// lib/services/call_session_controller.dart

import 'package:flutter/foundation.dart';
import 'package:orpheus_project/services/websocket_service.dart' show ConnectionStatus;
import 'package:orpheus_project/services/network_monitor_service.dart' show NetworkState;

/// Состояние звонка.
///
/// Вынесено из `call_screen.dart` (аудит ARCH-3 / вариант #1): домен-тип звонка
/// живёт рядом с контроллером логики, а не внутри виджета.
enum CallState {
  Dialing,
  Incoming,
  Connecting,
  Connected,
  Rejected,
  Failed,
  Reconnecting,
}

/// Внешние операции звонка, которые нужны контроллеру от WebRTC/сигналинга.
///
/// Держим интерфейс УЗКИМ, чтобы `CallSessionController` был юнит-тестируемым:
/// в тестах подставляется fake, в проде (шаг 2 рефакторинга) — реализация поверх
/// `WebRTCService` + `websocketService`. Это и есть инъектируемый peer-интерфейс,
/// которого не хватало для тестов звонков (аудит TEST-4).
abstract class CallOps {
  /// Инициировать ICE-restart: создать renegotiation-offer, отправить сигнал
  /// `ice-restart` и ICE-кандидаты собеседнику. Возвращает true, если рестарт
  /// успешно инициирован.
  Future<bool> restartIce();
}

/// Планировщик отложенных повторов. В проде — `Future.delayed`, в тестах —
/// управляемый фейк (чтобы гонять ретраи без реального ожидания).
typedef RetryScheduler = void Function(Duration delay, VoidCallback action);

/// Источник текущего времени (для дебаунса ICE-restart). В тестах управляемый.
typedef NowFn = DateTime Function();

/// Машина состояний звонка + политика реконнекта, вынесенная из `_CallScreenState`.
///
/// Отвечает ТОЛЬКО за логику (состояние, переходы, ICE-restart/реконнект). UI,
/// анимации, рендереры и нативные вызовы остаются в виджете, который слушает
/// этот контроллер (`ChangeNotifier`) и прокидывает в него события сети/WS и
/// действия пользователя. Не зависит от Flutter-виджетов и глобальных синглтонов
/// напрямую — поэтому проверяется юнит-тестами.
class CallSessionController extends ChangeNotifier {
  CallSessionController({
    required CallOps ops,
    RetryScheduler? scheduler,
    NowFn? now,
    VoidCallback? onFatal,
    CallState initialState = CallState.Dialing,
  })  : _ops = ops,
        _schedule = scheduler ?? _defaultScheduler,
        _now = now ?? DateTime.now,
        _onFatal = onFatal,
        _callState = initialState;

  final CallOps _ops;
  final RetryScheduler _schedule;
  final NowFn _now;

  /// Вызывается при переходе в терминальный Failed (в т.ч. когда исчерпаны
  /// попытки реконнекта) — виджет по нему авто-закрывает экран звонка. Раньше
  /// закрытие делал `_onError` виджета, но внутренний max-attempts путь его
  /// обходил (аудит ревью Stage B, регресс #2).
  final VoidCallback? _onFatal;

  /// Максимум попыток ICE-restart перед тем как признать звонок упавшим.
  static const int maxReconnectAttempts = 5;

  /// Минимальный интервал между попытками ICE-restart (дебаунс дубликатов).
  static const Duration iceRestartDebounce = Duration(seconds: 3);

  CallState _callState;
  CallState get callState => _callState;

  String _debugStatus = 'Init';
  String get debugStatus => _debugStatus;

  NetworkState _networkState = NetworkState.online;
  NetworkState get networkState => _networkState;

  ConnectionStatus _wsStatus = ConnectionStatus.Connected;
  ConnectionStatus get wsStatus => _wsStatus;

  bool _isReconnecting = false;
  bool get isReconnecting => _isReconnecting;

  int _reconnectAttempts = 0;
  int get reconnectAttempts => _reconnectAttempts;

  DateTime? _lastIceRestartTime;
  bool _isClosed = false;
  // Идёт ли попытка ICE-restart прямо сейчас (в т.ч. await restartIce). Не даёт
  // внешнему триггеру и запланированному повтору совпасть и запустить две
  // параллельные цепочки реконнекта (аудит ревью Stage B, новый race).
  bool _iceRestartInFlight = false;

  static void _defaultScheduler(Duration delay, VoidCallback action) {
    Future.delayed(delay, action);
  }

  /// Начальное состояние из параметров звонка (мирроринг initState):
  /// autoAnswer+offer -> Connecting (принят через CallKit), offer -> Incoming,
  /// иначе -> Dialing (исходящий).
  static CallState initialStateFor({
    required bool autoAnswer,
    required bool hasOffer,
  }) {
    if (autoAnswer && hasOffer) return CallState.Connecting;
    if (hasOffer) return CallState.Incoming;
    return CallState.Dialing;
  }

  /// Текст статуса для UI (мирроринг `_getStatusText`). Для Connected — пусто
  /// (там показывается таймер).
  String get statusText {
    switch (_callState) {
      case CallState.Dialing:
        return 'Calling...';
      case CallState.Incoming:
        return 'Incoming call';
      case CallState.Connecting:
        return 'Connecting...';
      case CallState.Reconnecting:
        return 'Reconnecting...';
      case CallState.Rejected:
        return 'Ended';
      case CallState.Failed:
        return 'Failed';
      case CallState.Connected:
        return '';
    }
  }

  /// Обновить состояние сети (из подписки NetworkMonitor во виджете).
  void updateNetworkState(NetworkState state) {
    _networkState = state;
    _notify();
  }

  /// Обновить статус WebSocket (из подписки во виджете). Если WS восстановился
  /// во время реконнекта — пробуем ICE-restart (мирроринг wsStatusSubscription).
  void updateWsStatus(ConnectionStatus status) {
    final previous = _wsStatus;
    _wsStatus = status;
    _notify();
    if (previous != ConnectionStatus.Connected &&
        status == ConnectionStatus.Connected &&
        _isReconnecting) {
      attemptIceRestart();
    }
  }

  /// Потеря связи/пира во время активного звонка -> уходим в Reconnecting.
  /// Срабатывает только из Connected (мирроринг `_handleNetworkLost`).
  void onNetworkLost() {
    if (_callState == CallState.Connected) {
      _isReconnecting = true;
      _reconnectAttempts = 0;
      _callState = CallState.Reconnecting;
      _debugStatus = 'Connection lost...';
      _notify();
    }
  }

  /// Переход в Connecting: offer отправлен (исходящий) либо звонок принят
  /// (входящий). Мирроринг `setState(() => _callState = Connecting)`.
  void onConnecting() {
    _callState = CallState.Connecting;
    _notify();
  }

  /// Обновить отображаемый статус (напр. "Answer received", "ICE restart...").
  /// Не меняет `callState` — только подпись для UI.
  void setDebugStatus(String status) {
    _debugStatus = status;
    _notify();
  }

  /// Восстановление сети -> пробуем ICE-restart, если мы в реконнекте
  /// (мирроринг `_handleNetworkRestored`).
  void onNetworkRestored() {
    if (_isReconnecting || _callState == CallState.Reconnecting) {
      attemptIceRestart();
    }
  }

  /// ВНЕШНЯЯ точка входа реконнекта (события сети/WS): с дебаунсом, чтобы
  /// близкие по времени триггеры не запускали несколько параллельных цепочек
  /// (мирроринг `_attemptIceRestart`).
  Future<void> attemptIceRestart() async {
    if (_isClosed) return;

    // Дебаунс: не чаще одного раза в iceRestartDebounce.
    final now = _now();
    if (_lastIceRestartTime != null &&
        now.difference(_lastIceRestartTime!) < iceRestartDebounce) {
      return;
    }
    await _runIceRestart();
  }

  /// Одна попытка ICE-restart + планирование повтора. Запланированные повторы
  /// зовут ЭТОТ метод НАПРЯМУЮ, в обход дебаунса: иначе повтор с задержкой меньше
  /// дебаунса всегда съедался бы и реконнект умирал после одной попытки
  /// (аудит ревью Stage B, регресс #1).
  Future<void> _runIceRestart() async {
    // Гвард от параллельных цепочек: пока попытка в полёте (включая await
    // restartIce), второй запуск не стартуем.
    if (_isClosed || _iceRestartInFlight) return;
    _iceRestartInFlight = true;
    try {
      _lastIceRestartTime = _now();

      if (_reconnectAttempts >= maxReconnectAttempts) {
        onError('Failed to restore connection');
        return;
      }

      _reconnectAttempts++;
      _debugStatus = 'Reconnecting... ($_reconnectAttempts)';
      _notify();

      // Ждём восстановления WebSocket, иначе рестарт-offer не уйдёт.
      if (_wsStatus != ConnectionStatus.Connected) {
        _scheduleRetry(const Duration(seconds: 2));
        return;
      }

      try {
        final ok = await _ops.restartIce();
        if (!ok) {
          _scheduleRetry(const Duration(seconds: 3));
        }
      } catch (_) {
        _scheduleRetry(const Duration(seconds: 3));
      }
    } finally {
      _iceRestartInFlight = false;
    }
  }

  void _scheduleRetry(Duration delay) {
    _schedule(delay, () {
      if (!_isClosed && _isReconnecting) {
        _runIceRestart(); // намеренный повтор — минуя дебаунс
      }
    });
  }

  /// Звонок соединён (первично или после успешного реконнекта): выходим из
  /// режима реконнекта.
  void onConnected() {
    _isReconnecting = false;
    _reconnectAttempts = 0;
    _callState = CallState.Connected;
    _notify();
  }

  /// Собеседник положил трубку: терминальное состояние Rejected (навигацию/поп
  /// делает виджет по уведомлению).
  void onRemoteHangup() {
    _isReconnecting = false;
    _callState = CallState.Rejected;
    _notify();
  }

  /// Неустранимая ошибка (в т.ч. исчерпаны попытки реконнекта) -> Failed.
  /// Дёргает [_onFatal], чтобы виджет авто-закрыл экран — в т.ч. на внутреннем
  /// max-attempts пути, который раньше `_safePop` не вызывал (регресс #2).
  void onError(String message) {
    _isReconnecting = false;
    _callState = CallState.Failed;
    _debugStatus = message;
    _notify();
    _onFatal?.call();
  }

  /// notify с гуардом на закрытие: после dispose асинхронный сигналинг-колбэк
  /// мог бы дёрнуть мутатор и уронить `notifyListeners` на disposed-объекте в
  /// debug (аудит ревью Stage B). При _isClosed просто ничего не делаем.
  void _notify() {
    if (_isClosed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _isClosed = true;
    super.dispose();
  }
}
