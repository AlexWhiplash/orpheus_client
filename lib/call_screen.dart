import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/background_call_service.dart';
import 'package:orpheus_project/services/call_native_ui_service.dart';
import 'package:orpheus_project/services/call_state_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/call_id_storage.dart';
import 'package:orpheus_project/services/network_monitor_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/sound_service.dart';
import 'package:orpheus_project/services/webrtc_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/widgets/call/background_painters.dart';
import 'package:orpheus_project/widgets/call/control_panel.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';
import 'package:orpheus_project/services/call_session_controller.dart';

// CallState и логика звонка (машина состояний, реконнект) вынесены в
// CallSessionController (аудит ARCH-3 / вариант #1). Здесь остаётся UI-виджет,
// который слушает контроллер и прокидывает в него события сети/WS/действия.

class CallScreen extends StatefulWidget {
  final String contactPublicKey;
  final Map<String, dynamic>? offer;
  final String? callId;
  /// Если true — звонок принимается автоматически (ответ через CallKit)
  final bool autoAnswer;

  const CallScreen({
    super.key,
    required this.contactPublicKey,
    this.offer,
    this.callId,
    this.autoAnswer = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

/// Реализация [CallOps] поверх WebRTCService/сигналинга конкретного экрана.
/// Контроллер знает только про этот узкий интерфейс; фактический ICE-restart
/// делегируется виджету (где живут WebRTC, WS и ключ собеседника).
class _WebRtcCallOps implements CallOps {
  _WebRtcCallOps(this._state);
  final _CallScreenState _state;

  @override
  Future<bool> restartIce() => _state._performIceRestart();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  // Сервисы
  final _webrtcService = WebRTCService();
  final _renderer = RTCVideoRenderer();

  // Подписки
  StreamSubscription? _signalingSubscription;
  StreamSubscription? _webrtcLogSubscription;
  StreamSubscription? _networkSubscription;
  StreamSubscription? _wsStatusSubscription;
  StreamSubscription? _iceRestartSubscription;

  // Состояние звонка — владелец логики: CallSessionController (вынос ARCH-3/#1).
  // Виджет ЧИТАЕТ состояние через геттеры-делегаты и слушает контроллер (перерисовка).
  late final CallSessionController _controller;
  CallState get _callState => _controller.callState;
  String get _debugStatus => _controller.debugStatus;
  NetworkState get _networkState => _controller.networkState;
  ConnectionStatus get _wsStatus => _controller.wsStatus;
  bool get _isReconnecting => _controller.isReconnecting;
  int get _reconnectAttempts => _controller.reconnectAttempts;
  static const int _maxReconnectAttempts = CallSessionController.maxReconnectAttempts;

  String _displayName = "Anonymous";
  String _durationText = "00:00";
  late final String _callId;

  // Debounce для ВХОДЯЩЕГО ICE restart (исходящий дебаунс живёт в контроллере).
  DateTime? _lastIceRestartReceivedTime;
  static const Duration _iceRestartDebounce = CallSessionController.iceRestartDebounce;

  // Управление устройствами
  bool _isSpeakerOn = false;
  bool _isMicMuted = false;

  // Флаги жизненного цикла
  bool _isDisposed = false;
  bool _messagesSent = false;

  // Логирование
  bool _showDebugLogs = false;
  final List<String> _debugLogs = [];
  final ScrollController _logScrollController = ScrollController();

  // Анимации
  late AnimationController _pulseController;
  late AnimationController _particlesController;
  late AnimationController _waveController;

  // Таймеры
  Timer? _durationTimer;
  final Stopwatch _stopwatch = Stopwatch();

  // Визуализация аудио
  final List<double> _audioWaveData = List.generate(20, (_) => 0.0);
  Timer? _waveTimer;

  /// Watchdog: если после ОТВЕТА звонок не соединился — ICE-restart (отложенный
  /// ответ на локе теряет ранние кандидаты звонящего). См. _scheduleAnswerConnectWatchdog.
  Timer? _answerConnectWatchdog;
  // Таймаут исходящего звонка: если абонент не ответил за отведённое время —
  // авто-отбой, чтобы не звонить бесконечно (в т.ч. когда на той стороне нет
  // аккаунта и она даже не может отклонить).
  Timer? _outgoingRingWatchdog;

  @override
  void initState() {
    super.initState();

    // Гарантия: пока открыт CallScreen, автолок приложения не должен мешать ответу/разговору.
    CallStateService.instance.setCallActive(true);
    // Android: разрешаем показывать поверх lockscreen и включать экран во время звонка.
    // Best-effort: если нативная часть недоступна — звонок всё равно должен работать.
    CallNativeUiService.enableCallMode();

    _displayName = widget.contactPublicKey.substring(0, 8);
    // Поднимаем микрофонный foreground-сервис из видимого CallScreen — тогда
    // микрофон переживёт сворачивание приложения во время разговора (Android 14).
    CallNativeUiService.startCallAudio(title: _displayName);
    _resolveContactName();

    // Единый call_id для корреляции логов.
    // Исходящий (offer == null) -> УНИКАЛЬНЫЙ id на каждый звонок (иначе быстрые
    // перезвоны в пределах 30с получали одинаковый id и CallKit не показывал
    // новый ринг). Входящий -> берём id из offer.
    _callId = widget.callId
        ?? (widget.offer != null
            ? CallIdStorage.extractCallId(widget.offer!, widget.contactPublicKey)
            : CallIdStorage.generateUniqueCallId(
                cryptoService.addressBase64 ?? widget.contactPublicKey,
              ));

    // Контроллер логики звонка (машина состояний + реконнект/ICE-restart).
    // Начальное состояние: autoAnswer+offer -> Connecting (принят через CallKit),
    // offer -> Incoming, иначе Dialing (исходящий).
    _controller = CallSessionController(
      ops: _WebRtcCallOps(this),
      // Терминальный Failed (в т.ч. исчерпаны попытки реконнекта) -> авто-закрытие.
      onFatal: () => Future.delayed(const Duration(seconds: 2), _safePop),
      initialState: CallSessionController.initialStateFor(
        autoAnswer: widget.autoAnswer,
        hasOffer: widget.offer != null,
      ),
    );

    // 1. Запуск foreground service для звонка
    _startBackgroundMode();

    // 2. Скрываем уведомление о входящем звонке и CallKit UI (экран уже открыт)
    NotificationService.hideCallNotification();
    FlutterCallkitIncoming.endAllCalls(); // Гарантированно скрываем CallKit

    // 3. Анимации
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: false);

    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // 4. Подписка на состояние сети и WebSocket
    _initNetworkMonitoring();

    // 5. Старт WebRTC
    _initCallSequence();

    // Слушаем контроллер ПОСЛЕДНИМ: синхронные правки состояния выше (нач.
    // значения сети/WS) не должны дёргать setState во время initState.
    _controller.addListener(_onControllerChanged);

    // BT-priming один раз, с задержкой — после того как отработает запрос
    // микрофона (иначе диалоги стекаются).
    Future.delayed(const Duration(seconds: 3), _maybePrimeBluetooth);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Инициализация мониторинга сети для индикации и реконнекта
  void _initNetworkMonitoring() {
    // Начальное состояние сети/WS проталкиваем в контроллер (слушатель ещё не
    // подключён -> setState не дёргается).
    _controller.updateNetworkState(NetworkMonitorService.instance.currentState);
    _controller.updateWsStatus(websocketService.currentStatus);

    // Подписка на изменения сети -> прокидываем в контроллер
    _networkSubscription = NetworkMonitorService.instance.onNetworkChange.listen((event) {
      if (_isDisposed) return;

      _addLog("🌐 Network: ${event.type.name}");
      DebugLogger.info('CALL', 'Network event: ${event.type}');

      _controller.updateNetworkState(NetworkMonitorService.instance.currentState);

      if (event.type == NetworkChangeType.disconnected) {
        // Потеря связи во время звонка -> режим реконнекта
        _controller.onNetworkLost();
      } else if (event.type == NetworkChangeType.reconnected ||
                 event.type == NetworkChangeType.networkSwitch) {
        // Восстановление связи -> ICE restart
        _controller.onNetworkRestored();
      }
    });

    // Подписка на статус WebSocket. Контроллер сам инициирует ICE restart, если
    // WS восстановился во время реконнекта.
    _wsStatusSubscription = websocketService.status.listen((status) {
      if (_isDisposed) return;
      _addLog("📡 WS: ${status.name}");
      _controller.updateWsStatus(status);
    });

    // Подписка на автоматический ICE restart от WebRTC при Disconnected/Failed
    _iceRestartSubscription = _webrtcService.onIceRestartNeeded.listen((_) {
      if (_isDisposed) return;

      // Только если звонок был активен
      if (_callState == CallState.Connected) {
        _addLog("🔄 ICE restart нужен (автоопределение)");
        _controller.onNetworkLost(); // Переводим в режим реконнекта
      }
    });
  }

  /// Обработка входящего ICE restart от собеседника
  Future<void> _handleIncomingIceRestart(Map<String, dynamic> offer) async {
    // Debounce - игнорируем дубликаты ice-restart
    final now = DateTime.now();
    if (_lastIceRestartReceivedTime != null && 
        now.difference(_lastIceRestartReceivedTime!) < _iceRestartDebounce) {
      _addLog("⏳ Incoming ICE restart debounced (duplicate)");
      return;
    }
    _lastIceRestartReceivedTime = now;
    
    _addLog("🔄 Обработка входящего ICE restart...");

    _controller.setDebugStatus("ICE restart...");

    try {
      final success = await _webrtcService.handleIceRestartOffer(
        offer: offer,
        onAnswerCreated: (answer) {
          _addLog("📤 ICE restart answer");
          websocketService.sendSignalingMessage(
            widget.contactPublicKey,
            'ice-restart-answer',
            _attachCallId(answer),
          );
        },
        onCandidateCreated: (cand) {
          _addLog("📤 ICE restart candidate");
          websocketService.sendSignalingMessage(
            widget.contactPublicKey,
            'ice-candidate',
            _attachCallId(cand),
          );
        },
      );
      
      if (success) {
        _addLog("✅ ICE restart обработан успешно");
      } else {
        _addLog("⚠️ ICE restart не удался");
      }
    } catch (e) {
      _addLog("❌ Ошибка обработки ICE restart: $e");
    }
  }

  /// Реализация CallOps.restartIce: выполняет WebRTC ICE-restart и шлёт сигнал
  /// 'ice-restart' + кандидаты собеседнику. Дебаунс/лимит попыток/повторы —
  /// теперь в CallSessionController, здесь только сама WebRTC-операция.
  Future<bool> _performIceRestart() {
    return _webrtcService.restartIce(
      onOfferCreated: (offer) {
        _addLog("📤 ICE restart offer (ice-restart signal)");
        // ВАЖНО: 'ice-restart', а не 'call-offer', чтобы получатель знал что это
        // renegotiation, а не новый звонок.
        websocketService.sendSignalingMessage(
          widget.contactPublicKey,
          'ice-restart',
          _attachCallId(offer),
        );
      },
      onCandidateCreated: (cand) {
        websocketService.sendSignalingMessage(
          widget.contactPublicKey,
          'ice-candidate',
          _attachCallId(cand),
        );
      },
    );
  }

  Future<void> _startBackgroundMode() async {
    await BackgroundCallService.startCallService();
  }

  static const String _btPrimeKey = 'bt_call_audio_primed';

  /// Разовый поясняющий экран ПЕРЕД системным запросом BLUETOOTH_CONNECT.
  /// Системный диалог «устройства поблизости» звучит пугающе (упоминает
  /// «относительное положение»), хотя разрешение нужно ТОЛЬКО для вывода звука
  /// звонка в BT-гарнитуру — без сканирования устройств и геолокации. Праймим один
  /// раз, только когда микрофон уже выдан (чтобы диалоги не стекались).
  Future<void> _maybePrimeBluetooth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_btPrimeKey) ?? false) return;
      if (await Permission.bluetoothConnect.isGranted) return;
      if (!await Permission.microphone.isGranted) return;
      if (!mounted) return;

      final isRu = Localizations.localeOf(context).languageCode == 'ru';
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(
            isRu ? 'Звук звонка в Bluetooth' : 'Bluetooth call audio',
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            isRu
                ? 'Чтобы выводить звук звонка в вашу Bluetooth-гарнитуру, Android '
                    'сейчас попросит разрешение «Устройства поблизости». Orpheus '
                    'использует его ТОЛЬКО для подключения к гарнитуре — не сканирует '
                    'устройства и не определяет ваше местоположение. Можно пропустить: '
                    'звонки работают и через динамик/наушники.'
                : 'To play call audio through your Bluetooth headset, Android will now '
                    'ask for the "Nearby devices" permission. Orpheus uses it ONLY to '
                    'connect to your headset — it does not scan for devices or track your '
                    'location. You can skip this; calls still work via the speaker/earpiece.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isRu ? 'Пропустить' : 'Skip'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isRu ? 'Продолжить' : 'Continue'),
            ),
          ],
        ),
      );
      await prefs.setBool(_btPrimeKey, true);
      if (proceed == true) {
        await Permission.bluetoothConnect.request();
      }
    } catch (_) {}
  }

  Future<void> _resolveContactName() async {
    try {
      final contacts = await DatabaseService.instance.getContacts();
      final found = contacts.firstWhere(
        (c) => c.publicKey == widget.contactPublicKey,
        orElse: () => null as dynamic,
      );

      if (found.toString() != 'null' && mounted) {
        setState(() {
          _displayName = found.name;
        });
      }
    } catch (_) {}
  }

  Future<void> _initCallSequence() async {
    await _renderer.initialize();

    // Явно выключаем громкую связь при старте звонка
    // чтобы синхронизировать состояние UI (_isSpeakerOn = false) с реальным устройством
    Helper.setSpeakerphoneOn(false);

    // Подписка на логи WebRTC
    _webrtcLogSubscription = _webrtcService.onDebugLog.listen((log) {
      _addLog(log);

      if (log.contains("Connected")) {
        if (_callState != CallState.Connected) _onConnected();
      } else if (log.contains("Failed")) {
        if (!_isDisposed) _onError("Failed (ICE)");
      }

      if (log.contains("REMOTE TRACK RECEIVED") || log.contains("Remote stream assigned")) {
        _attachRemoteStream();
      }
    });

    // Подписка на сигналы WebSocket
    _signalingSubscription = signalingStreamController.stream.listen((signal) async {
      if (_isDisposed || signal['sender_pubkey'] != widget.contactPublicKey) {
        return;
      }

      final type = signal['type'];
      final data = signal['data'];

      if (type == 'call-answer') {
        _controller.setDebugStatus("Answer received");
        await _webrtcService.handleAnswer(data);
        if (_callState != CallState.Connected) {
          _controller.onConnecting();
        }
      } else if (type == 'ice-restart-answer') {
        // Ответ на наш ICE restart
        _addLog("📥 ICE restart answer received");
        _controller.setDebugStatus("ICE restart answer");
        await _webrtcService.handleAnswer(data);
      } else if (type == 'ice-restart') {
        // Входящий ICE restart от собеседника
        _addLog("📥 ICE restart offer received");
        await _handleIncomingIceRestart(data);
      } else if (type == 'ice-candidate') {
        await _webrtcService.addCandidate(data);
      } else if (type == 'hang-up' || type == 'call-rejected') {
        // Проверяем call_id: устаревший hang-up/reject от ПРЕДЫДУЩЕГО захода
        // (например, тайаут-reject старого звонка, долетевший поздно по
        // HTTP-fallback) не должен завершать ТЕКУЩИЙ соединённый звонок.
        // Если call_id нет (старые клиенты) — обрабатываем как раньше.
        final signalCallId = data is Map ? data['call_id'] : null;
        if (signalCallId != null && signalCallId != _callId) {
          _addLog("📞 Игнорирую устаревший $type (call_id=$signalCallId ≠ $_callId)");
        } else {
          _addLog("📞 Получен $type - завершаем звонок");
          _onRemoteHangup();
        }
      }
    });

    // Применяем буферизованные ICE кандидаты
    if (_callState == CallState.Incoming) {
      final bufferedCandidates = incomingCallBuffer.takeAll(widget.contactPublicKey);
      if (bufferedCandidates.isNotEmpty) {
        _addLog("📦 Применение ${bufferedCandidates.length} буферизованных кандидатов");
        for (final candidateMsg in bufferedCandidates) {
          final data = candidateMsg['data'] as Map<String, dynamic>;
          await _webrtcService.addCandidate(data);
        }
      }
    }

    if (widget.autoAnswer) {
      // Экран открыт, чтобы ОТВЕТИТЬ на входящий (CallKit/автоответ). Отвечающий
      // НИКОГДА не должен инициировать свой offer.
      if (widget.offer != null) {
        // Автоответ через CallKit — сразу принимаем без рингтона
        DebugLogger.info('CALL', '📞 AutoAnswer: принимаю звонок автоматически');
        _acceptCall();
      } else {
        // Offer потерян (напр. ответ с заблокированного экрана при cold-start, когда
        // offer не доехал). НЕ создаём свой offer — это дало бы glare (обе стороны
        // «звонящие»), и звонок бы не соединился. Обрываем чисто.
        DebugLogger.error('CALL', '📞 AutoAnswer без offer — обрыв (защита от glare)');
        _onError("Call Error");
      }
    } else if (_callState == CallState.Dialing) {
      SoundService.instance.playDialingSound();
      _startOutgoingCall();
    } else {
      // Обычный входящий (не автоответ) — рингтон, ждём ручного ответа
      SoundService.instance.playIncomingRingtone();
    }
  }

  // --- ЛОГИКА ЗВОНКА ---

  Future<void> _startOutgoingCall() async {
    try {
      await _webrtcService.initiateCall(
        onOfferCreated: (offer) {
          _addLog("📤 call-offer");
          websocketService.sendSignalingMessage(
            widget.contactPublicKey,
            'call-offer',
            _attachCallId(offer),
          );
        },
        onCandidateCreated: (cand) {
          _addLog("📤 ice-candidate");
          websocketService.sendSignalingMessage(
            widget.contactPublicKey,
            'ice-candidate',
            _attachCallId(cand),
          );
        },
      );
      _startOutgoingRingWatchdog();
    } catch (e) {
      _addLog("ERROR: $e");
      _onError("Mic Error");
    }
  }

  /// Авто-отбой исходящего звонка при отсутствии ответа. Иначе экран «Calling…»
  /// звонит бесконечно, пока пользователь сам не сбросит — особенно когда на той
  /// стороне нет аккаунта (после wipe) и она не может даже отклонить.
  void _startOutgoingRingWatchdog() {
    _outgoingRingWatchdog?.cancel();
    _outgoingRingWatchdog = Timer(const Duration(seconds: 45), () {
      if (!mounted || _isDisposed) return;
      if (_callState == CallState.Connected) return;
      _addLog("⏱️ Нет ответа 45с — авто-отбой исходящего");
      _endCallButton();
    });
  }

  void _acceptCall() async {
    SoundService.instance.stopAllSounds();
    _controller.onConnecting();

    try {
      await _webrtcService.answerCall(
        offer: widget.offer!,
        onAnswerCreated: (ans) {
          _addLog("📤 call-answer");
          websocketService.sendSignalingMessage(
            widget.contactPublicKey,
            'call-answer',
            _attachCallId(ans),
          );
        },
        onCandidateCreated: (cand) {
          _addLog("📤 ice-candidate");
          websocketService.sendSignalingMessage(
            widget.contactPublicKey,
            'ice-candidate',
            _attachCallId(cand),
          );
        },
      );
      _scheduleAnswerConnectWatchdog();
    } catch (e) {
      _onError("Connect Error");
    }
  }

  /// Watchdog после ОТВЕТА. Если за отведённое время звонок не соединился —
  /// инициируем ICE-restart (пере-обмен кандидатами). Нужен для ОТЛОЖЕННОГО
  /// ответа (звонок принят на заблокированном телефоне после ввода PIN): ранние
  /// ICE-кандидаты звонящего теряются, пока приёмник ещё не готов/не подключён к
  /// WS, и обычный обмен не связывается. Для нормального (быстрого) ответа звонок
  /// успевает стать Connected раньше — тогда watchdog просто ничего не делает.
  void _scheduleAnswerConnectWatchdog() {
    _answerConnectWatchdog?.cancel();
    // 4с: быстрый ответ (обычный звонок) успевает Connected раньше -> no-op; для
    // отложенного ответа на локе (кандидаты потеряны) чем раньше ICE-restart, тем
    // быстрее соединение. Меньше не берём — дать шанс штатному ICE на медленной сети.
    _answerConnectWatchdog = Timer(const Duration(seconds: 4), () {
      if (!mounted || _isDisposed) return;
      if (_callState == CallState.Connected) return;
      _addLog("⏱️ Нет коннекта через 4с после ответа — ICE-restart");
      _performIceRestart();
      // Вторая попытка, если и после restart не связалось.
      _answerConnectWatchdog = Timer(const Duration(seconds: 6), () {
        if (!mounted || _isDisposed) return;
        if (_callState == CallState.Connected) return;
        _addLog("⏱️ Всё ещё нет коннекта — повторный ICE-restart");
        _performIceRestart();
      });
    });
  }

  void _endCallButton() async {
    if (_messagesSent) return;  // Предотвращаем повторные вызовы
    _messagesSent = true;

    // Скрываем CallKit UI сразу
    FlutterCallkitIncoming.endAllCalls();

    final currentState = _callState;
    String signal = currentState == CallState.Incoming ? 'call-rejected' : 'hang-up';

    // СНАЧАЛА отправляем hang-up сигнал
    print("📞 Отправка $signal к ${widget.contactPublicKey.substring(0, 8)}...");
    websocketService.sendSignalingMessage(
      widget.contactPublicKey,
      signal,
      _attachCallId({}),
    );

    // Небольшая задержка чтобы WebSocket успел отправить сообщение
    await Future.delayed(const Duration(milliseconds: 100));

    // System messages to chat (English for consistent DB storage)
    if (currentState == CallState.Connected) {
      _saveCallStatusMessageLocally("Outgoing call", true);
      _sendCallStatusMessageToContact("Incoming call");
    } else if (currentState == CallState.Incoming) {
      _saveCallStatusMessageLocally("Missed call", false);
    } else if (currentState == CallState.Dialing) {
      _saveCallStatusMessageLocally("Outgoing call", true);
      _sendCallStatusMessageToContact("Missed call");
    }

    _safePop();
  }

  void _onRemoteHangup() {
    if (_isDisposed || _messagesSent) return;
    _messagesSent = true;
    SoundService.instance.stopAllSounds();
    SoundService.instance.playDisconnectedSound();

    final wasConnected = _callState == CallState.Connected;
    _controller.onRemoteHangup();

    if (wasConnected) {
      _saveCallStatusMessageLocally("Incoming call", false);
      _sendCallStatusMessageToContact("Outgoing call");
    }
    // Non-connected calls: remote hung up / rejected — no local message needed,
    // the remote side already saved and sent their status message to us.

    Future.delayed(const Duration(seconds: 1), _safePop);
  }

  void _onConnected() {
    _answerConnectWatchdog?.cancel();
    _outgoingRingWatchdog?.cancel();
    SoundService.instance.stopAllSounds();
    SoundService.instance.playConnectedSound();

    if (_isReconnecting) {
      _addLog("✅ Соединение восстановлено!");
    }
    // Контроллер: Connected + сброс флагов реконнекта (+ notify -> перерисовка).
    _controller.onConnected();

    if (mounted) {
      _waveController.repeat();
      _attachRemoteStream();
    }

    // Анимация волн
    _waveTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _isDisposed || _callState != CallState.Connected) {
        timer.cancel();
        return;
      }
      setState(() {
        for (int i = 0; i < _audioWaveData.length; i++) {
          _audioWaveData[i] = (0.2 + (i % 3) * 0.1) +
              (DateTime.now().millisecondsSinceEpoch % 1000) / 1000 * 0.3;
        }
      });
    });

    // Таймер длительности
    _stopwatch.start();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final elapsed = _stopwatch.elapsed;
      final min = elapsed.inMinutes.toString().padLeft(2, '0');
      final sec = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      setState(() => _durationText = "$min:$sec");
      
      // Обновляем уведомление foreground service
      BackgroundCallService.updateCallDuration(_durationText, _displayName);
    });
  }

  void _onError(String msg) {
    if (_isDisposed) return;
    // Авто-закрытие теперь через controller.onError -> onFatal (единый путь для
    // прямых ошибок И внутреннего max-attempts, регресс #2).
    _controller.onError(msg);
  }

  void _safePop() {
    incomingCallBuffer.takeAll(widget.contactPublicKey);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // --- УПРАВЛЕНИЕ МЕДИА ---

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  void _toggleMic() {
    final tracks = _webrtcService.localStream?.getAudioTracks();
    if (tracks != null && tracks.isNotEmpty) {
      setState(() => _isMicMuted = !_isMicMuted);
      tracks[0].enabled = !_isMicMuted;
    }
  }

  void _attachRemoteStream() {
    final remoteStream = _webrtcService.remoteStream;
    if (remoteStream != null && mounted) {
      if (_renderer.srcObject != remoteStream) {
        _renderer.srcObject = remoteStream;
      }
    }
  }

  // --- СИСТЕМНЫЕ СООБЩЕНИЯ ---

  Future<void> _saveCallStatusMessageLocally(String messageText, bool isSentByMe) async {
    try {
      final callMessage = ChatMessage(
        text: messageText,
        isSentByMe: isSentByMe,
        status: MessageStatus.sent,
        isRead: true,
      );
      await DatabaseService.instance.addMessage(callMessage, widget.contactPublicKey);
      messageUpdateController.add(widget.contactPublicKey);
    } catch (e) {
      DebugLogger.error('CALL', 'Error saving local message: $e',
          context: _callContext());
    }
  }

  Future<void> _sendCallStatusMessageToContact(String messageText) async {
    try {
      final payload = await cryptoService.encrypt(widget.contactPublicKey, messageText);
      websocketService.sendChatMessage(widget.contactPublicKey, payload);
    } catch (e) {
      DebugLogger.error('CALL', 'Error sending message to peer: $e',
          context: _callContext());
    }
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _debugLogs.add("${DateTime.now().toString().substring(11, 19)} $message");
    });
    if (_showDebugLogs) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_logScrollController.hasClients) {
          _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
        }
      });
    }
    DebugLogger.info('CALL', message, context: _callContext());
  }

  Map<String, dynamic> _callContext({Map<String, dynamic>? extra}) {
    final ctx = <String, dynamic>{
      'call_id': _callId,
      'peer_pubkey': widget.contactPublicKey,
      'state': _callState.name,
      'ws_status': _wsStatus.name,
      'network': _networkState.name,
    };
    if (extra != null && extra.isNotEmpty) {
      ctx.addAll(extra);
    }
    return ctx;
  }

  Map<String, dynamic> _attachCallId(Map<String, dynamic> data) {
    if (data.containsKey('call_id')) return data;
    return {
      ...data,
      'call_id': _callId,
    };
  }

  String _getStatusText() {
    switch (_callState) {
      case CallState.Dialing:
        return "Calling...";
      case CallState.Incoming:
        return "Incoming call";
      case CallState.Connecting:
        return "Connecting...";
      case CallState.Reconnecting:
        return "Reconnecting...";
      case CallState.Rejected:
        return "Ended";
      case CallState.Failed:
        return "Failed";
      default:
        return "";
    }
  }

  /// Виджет предупреждения о проблемах с соединением
  Widget _buildConnectionWarning() {
    String message;
    Color color;
    IconData icon;

    if (_networkState == NetworkState.offline) {
      message = "No network";
      color = Colors.red;
      icon = Icons.signal_wifi_off;
    } else if (_wsStatus == ConnectionStatus.Connecting) {
      message = "Reconnecting...";
      color = Colors.orange;
      icon = Icons.sync;
    } else if (_wsStatus == ConnectionStatus.Disconnected) {
      message = "Connection lost";
      color = Colors.red;
      icon = Icons.cloud_off;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            message,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  /// Статус/таймер под именем контакта: таймер (Connected), спиннер реконнекта
  /// (Reconnecting) или текст статуса (остальные состояния).
  Widget _buildStatusSection() {
    if (_callState == CallState.Connected) {
      return Column(
        children: [
          Text(
            _durationText,
            style: const TextStyle(
              color: Color(0xFF6AD394),
              fontSize: 24,
              fontFamily: "monospace",
            ),
          ),
          // Показываем предупреждение при проблемах с сетью
          if (_networkState == NetworkState.offline ||
              _wsStatus != ConnectionStatus.Connected)
            _buildConnectionWarning(),
        ],
      );
    } else if (_callState == CallState.Reconnecting) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _getStatusText(),
                style: const TextStyle(color: Colors.orange, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _debugStatus,
            style: const TextStyle(color: Colors.orange, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            "Attempt $_reconnectAttempts of $_maxReconnectAttempts",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          Text(
            _getStatusText(),
            style: const TextStyle(color: Colors.grey, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            _debugStatus,
            style: const TextStyle(color: Colors.red, fontSize: 10),
          ),
        ],
      );
    }
  }

  /// Аватар контакта с пульсирующими кольцами (кроме Failed/Rejected).
  Widget _buildAvatar() {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_callState != CallState.Failed && _callState != CallState.Rejected)
          ...List.generate(3, (index) {
            return ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.8 + index * 0.3).animate(
                CurvedAnimation(
                  parent: _pulseController,
                  curve: Interval(index * 0.2, 1.0, curve: Curves.easeOut),
                ),
              ),
              child: FadeTransition(
                opacity: Tween(begin: 0.4 - index * 0.1, end: 0.0).animate(
                  CurvedAnimation(
                    parent: _pulseController,
                    curve: Interval(index * 0.2, 1.0, curve: Curves.easeOut),
                  ),
                ),
                child: Container(
                  width: 150 + index * 30,
                  height: 150 + index * 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF6AD394).withOpacity(0.3 - index * 0.1),
                      width: 2 - index * 0.3,
                    ),
                  ),
                ),
              ),
            );
          }),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: _callState == CallState.Connected
                ? [
                    BoxShadow(
                      color: const Color(0xFF6AD394).withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ]
                : [],
          ),
          child: CircleAvatar(
            radius: 60,
            backgroundColor: _callState == CallState.Connected
                ? const Color(0xFF6AD394).withOpacity(0.2)
                : Colors.grey[800],
            child: Text(
              _displayName.isNotEmpty ? _displayName[0].toUpperCase() : "?",
              style: TextStyle(
                fontSize: 40,
                color: _callState == CallState.Connected
                    ? const Color(0xFF6AD394)
                    : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Визуализатор звука (полоски), показывается только в состоянии Connected.
  Widget _buildAudioVisualizer() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 30),
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_audioWaveData.length, (index) {
              final height = _audioWaveData[index] * 50;
              return Container(
                width: 3,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6AD394),
                  borderRadius: BorderRadius.circular(2),
                ),
                height: height.clamp(5.0, 50.0),
              );
            }),
          ),
        ),
      ],
    );
  }

  /// Оверлей debug-логов (только в debug, аудит UI-9).
  Widget _buildDebugOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        padding: const EdgeInsets.only(top: 50, bottom: 20, left: 10, right: 10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "DEBUG LOGS",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => setState(() => _showDebugLogs = false),
                )
              ],
            ),
            Expanded(
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: _debugLogs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _debugLogs[index],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    CallStateService.instance.setCallActive(false);
    // Освобождаем активный call_id в межизолятном хранилище. Раньше clear() был
    // мёртвым кодом -> активный id висел до TTL 15с, и быстрый повторный звонок
    // (уже с НОВЫМ id) отклонялся trySetActiveCall как "занято, другой активен".
    CallIdStorage.clear();
    CallNativeUiService.disableCallMode();
    // Останавливаем микрофонный сервис — звонок завершён.
    CallNativeUiService.stopCallAudio();

    // 0. Скрываем CallKit UI если он был показан
    FlutterCallkitIncoming.endAllCalls();

    // 1. Останавливаем foreground service
    BackgroundCallService.stopCallService();

    // 2. Чистим буфер
    incomingCallBuffer.takeAll(widget.contactPublicKey);

    // 3. Отправляем HangUp если закрыли свайпом (не через кнопку)
    if (!_messagesSent) {
      final finalState = _callState;
      print("📞 Dispose: отправка hang-up (state=$finalState)");
      
      if (finalState == CallState.Connected || finalState == CallState.Dialing) {
        websocketService.sendSignalingMessage(
          widget.contactPublicKey,
          'hang-up',
          _attachCallId({}),
        );

        if (finalState == CallState.Connected) {
          _saveCallStatusMessageLocally("Outgoing call", true);
          _sendCallStatusMessageToContact("Incoming call");
        } else if (finalState == CallState.Dialing) {
          _saveCallStatusMessageLocally("Outgoing call", true);
          _sendCallStatusMessageToContact("Missed call");
        }
      } else if (finalState == CallState.Incoming) {
        websocketService.sendSignalingMessage(
          widget.contactPublicKey,
          'call-rejected',
          _attachCallId({}),
        );
        _saveCallStatusMessageLocally("Missed call", false);
      }
    }

    _isDisposed = true;
    _pulseController.dispose();
    _particlesController.dispose();
    _waveController.dispose();
    _renderer.srcObject = null;
    _renderer.dispose();
    _stopwatch.stop();
    _durationTimer?.cancel();
    _waveTimer?.cancel();
    _answerConnectWatchdog?.cancel();
    _outgoingRingWatchdog?.cancel();
    _signalingSubscription?.cancel();
    _webrtcLogSubscription?.cancel();
    _networkSubscription?.cancel();
    _wsStatusSubscription?.cancel();
    _iceRestartSubscription?.cancel();
    SoundService.instance.stopAllSounds();

    _controller.removeListener(_onControllerChanged);
    _controller.dispose();

    _webrtcService.hangUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Анимированный фон
          CallBackground(controller: _particlesController),

          // 2. Частицы
          CustomPaint(
            painter: ParticlesPainter(_particlesController.value),
            child: Container(),
          ),

          // 3. Волны (только если Connected)
          if (_callState == CallState.Connected)
            AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) => CustomPaint(
                painter: WavePainter(_waveController.value),
                child: Container(),
              ),
            ),

          // Скрытый VideoView для аудио
          SizedBox(height: 0, width: 0, child: RTCVideoView(_renderer)),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),

                // Скрытая кнопка логов — только в debug (аудит UI-9)
                GestureDetector(
                  onTap: kDebugMode
                      ? () => setState(() => _showDebugLogs = !_showDebugLogs)
                      : null,
                  child: const Text(
                    "Secure Call",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Имя контакта
                Text(
                  _displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                
                // Бейдж пользователя
                AnimatedUserBadge(pubkey: widget.contactPublicKey),
                const SizedBox(height: 4),

                // Статус или Таймер
                _buildStatusSection(),

                const Spacer(),

                // Аватар с анимацией пульсации
                _buildAvatar(),

                // Визуализатор звука
                if (_callState == CallState.Connected) _buildAudioVisualizer(),

                const Spacer(),

                // Панель управления
                CallControlPanel(
                  isIncoming: _callState == CallState.Incoming,
                  isMicMuted: _isMicMuted,
                  isSpeakerOn: _isSpeakerOn,
                  onToggleMic: _toggleMic,
                  onToggleSpeaker: _toggleSpeaker,
                  onEndCall: _endCallButton,
                  onAcceptCall: _acceptCall,
                ),

                const SizedBox(height: 60),
              ],
            ),
          ),

          // Оверлей с логами — только в debug (в release не показываем, аудит UI-9)
          if (kDebugMode && _showDebugLogs) _buildDebugOverlay(),
        ],
      ),
    );
  }
}
