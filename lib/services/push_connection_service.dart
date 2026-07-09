// lib/services/push_connection_service.dart
//
// Постоянный foreground-сервис доставки пушей БЕЗ Google/FCM.
//
// Зачем: после отказа от Firebase Cloud Messaging нужен собственный канал,
// который будит приложение из убитого состояния для входящих звонков и
// сообщений. Роль FCM теперь играет постоянный foreground-сервис
// (flutter_background_service, тип specialUse), держащий WebSocket-соединение
// в отдельном isolate и показывающий CallKit/локальные уведомления теми же
// функциями, что раньше вызывал FCM background handler (см. handleBackgroundPush).
//
// Координация с main-изолятом (без двух сокетов на один pubkey):
// main-изолят пишет heartbeat kPrefMainAliveTs, пока живёт его собственный WS.
// Пока heartbeat свежий — сервис МОЛЧИТ (не открывает свой сокет, UI сам всё
// показывает). Как только приложение убито и heartbeat протух — сервис
// подключается сам и становится каналом доставки. Пересечение (краткое окно
// перехода) снимается дедупом CallIdStorage / message_id, как раньше WS+FCM.
//
// Микрофон во время звонка: сервис его не трогает (тип specialUse нельзя
// boot-стартовать с microphone из-за while-in-use правил Android 14). Активный
// звонок обслуживает видимый CallScreen. Это задокументировано в отчёте.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/notification_service.dart';

/// Публичный ключ пользователя (НЕ секрет — распространяется через QR), чтобы
/// сервисный isolate мог собрать WS-URL без доступа к main-изоляту/секрет-хранилищу.
const String kPrefUserPubkey = 'push_user_pubkey';

/// Heartbeat main-изолята: миллисекунды последней «отметки жизни».
const String kPrefMainAliveTs = 'push_main_alive_ts';

/// Порог свежести heartbeat. Если main отметился позже (now - threshold) —
/// UI живо и сервис молчит; иначе приложение считается убитым.
const int _mainAliveThresholdMs = 12 * 1000;

/// Абстракция над плагинами (DI для unit-тестов, чтобы не дёргать MethodChannel).
abstract class PushServiceBackend {
  Future<void> createNotificationChannel({
    required String channelId,
    required String channelName,
    required String description,
  });

  Future<void> configure({
    required void Function(ServiceInstance service) onStart,
    required String notificationChannelId,
    required int notificationId,
  });

  Future<bool> isRunning();
  Future<void> startService();
  void invoke(String method, [Map<String, dynamic>? args]);
}

class PluginPushServiceBackend implements PushServiceBackend {
  PluginPushServiceBackend({
    FlutterBackgroundService? service,
    FlutterLocalNotificationsPlugin? notifications,
  })  : _service = service ?? FlutterBackgroundService(),
        _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  final FlutterBackgroundService _service;
  final FlutterLocalNotificationsPlugin _notifications;

  @override
  Future<void> createNotificationChannel({
    required String channelId,
    required String channelName,
    required String description,
  }) async {
    // Новый канал (id _v2) с showBadge=false: тихий постоянный сервис не должен вешать
    // отметку «непрочитано» на иконку. Старый 'orpheus_connection' (showBadge=true)
    // остаётся осиротевшим, но активного уведомления на нём не будет -> без отметки.
    final channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: description,
      importance: Importance.low, // тихое постоянное уведомление
      enableVibration: false,
      playSound: false,
      showBadge: false, // не бэйджить иконку постоянным уведомлением сервиса
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  @override
  Future<void> configure({
    required void Function(ServiceInstance service) onStart,
    required String notificationChannelId,
    required int notificationId,
  }) async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        // Постоянный сервис: стартуем при запуске приложения (foreground) и
        // восстанавливаемся после ребута через собственный boot-receiver плагина.
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Orpheus',
        initialNotificationContent: 'Protecting your connection',
        foregroundServiceNotificationId: notificationId,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );
  }

  @override
  Future<bool> isRunning() => _service.isRunning();

  @override
  Future<void> startService() => _service.startService();

  @override
  void invoke(String method, [Map<String, dynamic>? args]) =>
      _service.invoke(method, args);
}

/// Постоянный сервис доставки пушей (замена FCM).
class PushConnectionService {
  static bool _isInitialized = false;

  // v2: канал пересоздан с showBadge=false (старый 'orpheus_connection' вешал
  // постоянную отметку «непрочитано» на иконку — foreground-уведомление сервиса
  // всегда активно). Каналы Android неизменяемы, поэтому нужен новый id.
  static const String channelId = 'orpheus_connection_v2';
  static const String channelName = 'Connection';
  static const int _notificationId = 887;

  static const String _idleContent = 'Protecting your connection';

  static PushServiceBackend _backend = PluginPushServiceBackend();

  /// Для unit-тестов: подменить backend.
  static void debugSetBackendForTesting(PushServiceBackend? backend) {
    _backend = backend ?? PluginPushServiceBackend();
  }

  /// Для unit-тестов: сбросить инициализацию.
  static void debugResetForTesting() {
    _isInitialized = false;
  }

  /// Инициализация сервиса (один раз). Не бросает — best-effort.
  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _backend.createNotificationChannel(
        channelId: channelId,
        channelName: channelName,
        description: 'Keeps Orpheus reachable for calls and messages',
      );
      await _backend.configure(
        onStart: pushConnectionOnStart,
        notificationChannelId: channelId,
        notificationId: _notificationId,
      );
      _isInitialized = true;
      // ignore: avoid_print
      print("PushConnectionService initialized");
    } catch (e) {
      // ignore: avoid_print
      print("PushConnectionService init failed: $e");
    }
  }

  /// Запустить сервис, если ещё не запущен (autoStart уже поднимает его сам,
  /// но вызываем явно на старте приложения для гарантии из foreground-состояния).
  static Future<void> start() async {
    try {
      if (!_isInitialized) await initialize();
      if (!await _backend.isRunning()) {
        await _backend.startService();
        // ignore: avoid_print
        print("PushConnectionService started");
      }
    } catch (e) {
      // ignore: avoid_print
      print("PushConnectionService start failed: $e");
    }
  }

  /// Остановить сервис (например, после panic-wipe).
  static Future<void> stop() async {
    try {
      if (await _backend.isRunning()) {
        _backend.invoke('stopService');
      }
    } catch (e) {
      // ignore: avoid_print
      print("PushConnectionService stop failed: $e");
    }
  }

  /// Перевести уведомление сервиса в режим активного звонка.
  static void enterCallMode(String contactName) {
    try {
      _backend.invoke('enterCallMode', {
        'title': contactName,
        'content': 'In call',
      });
    } catch (_) {}
  }

  /// Обновить длительность звонка в уведомлении.
  static void updateCallNotification(String duration, String contactName) {
    try {
      _backend.invoke('enterCallMode', {
        'title': contactName,
        'content': duration,
      });
    } catch (_) {}
  }

  /// Вернуть уведомление сервиса в спокойный режим (звонок завершён).
  static void exitCallMode() {
    try {
      _backend.invoke('exitCallMode');
    } catch (_) {}
  }
}

/// Entry point сервисного isolate (должен быть top-level для AOT).
@pragma('vm:entry-point')
void pushConnectionOnStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  final runner = _ServicePushRunner();

  service.on('stopService').listen((event) async {
    await runner.stop();
    service.stopSelf();
  });

  service.on('enterCallMode').listen((event) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: (event?['title'] as String?) ?? 'Orpheus',
        content: (event?['content'] as String?) ?? 'In call',
      );
    }
  });

  service.on('exitCallMode').listen((event) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Orpheus',
        content: PushConnectionService._idleContent,
      );
    }
  });

  runner.start();
}

/// WS-слушатель в сервисном isolate. Подключается только когда main-изолят
/// не отвечает (приложение убито); иначе молчит.
class _ServicePushRunner {
  IOWebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _tick;
  Timer? _ping;
  bool _stopped = false;
  bool _connecting = false;
  int _hostIndex = 0;
  // Хост текущего живого сокета — чтобы заметить runtime-смену сервера (prod/test)
  // и переподключиться на новый.
  String? _connectedHost;

  // PoP: изолят должен доказать владение адресом (подписать challenge). Своя копия
  // CryptoService (отдельный процесс), инициализируется из secure storage лениво.
  final CryptoService _crypto = CryptoService();
  bool _authed = false;
  String? _connectedAddress;

  static List<int> _b64urlDecode(String s) {
    final pad = (4 - s.length % 4) % 4;
    return base64Url.decode(s + ('=' * pad));
  }

  static const _ignoredTypes = <String>{
    'error',
    'payment-confirmed',
    'license-status',
    'pong',
    'presence-state',
    'presence-update',
    'ice-candidate',
    'call-answer',
    'ice-restart',
    'ice-restart-answer',
    'delete-for-both',
  };

  void start() {
    _tick = Timer.periodic(const Duration(seconds: 4), (_) => _evaluate());
    _evaluate();
  }

  Future<void> stop() async {
    _stopped = true;
    _tick?.cancel();
    _ping?.cancel();
    await _closeSocket();
  }

  Future<void> _evaluate() async {
    if (_stopped) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Push-изолят — ОТДЕЛЬНЫЙ процесс со своим кэшем SharedPreferences. Без reload
      // он не видит изменений от main-изолята — в т.ч. wipe (prefs.clear()) и смену
      // pubkey. Из-за этого после стирания аккаунта сервис продолжал держать WS под
      // СТАРЫМ ключом и на телефон без аккаунта приходили звонки (зомби-сессия).
      // reload синхронизирует кэш с диском на каждом тике.
      await prefs.reload();
      // Активный API-хост (prod/test) из prefs. Изолят — ОТДЕЛЬНЫЙ процесс со своим
      // AppConfig, поэтому хидратим _activeHost здесь же (после reload); тогда и WS,
      // и фоновые httpUrls в этом изоляте идут на выбранный сервер. Если хост сменился
      // под живым сокетом — рвём его, чтобы редайл ушёл на новый сервер.
      final desiredHost = await AppConfig.reloadActiveHostFromPrefs(prefs);
      if (_channel != null && desiredHost != _connectedHost) {
        await _closeSocket();
        _hostIndex = 0;
      }
      final pubkey = prefs.getString(kPrefUserPubkey);
      if (pubkey == null || pubkey.isEmpty) {
        // Нет личности (не зарегистрирован или после wipe) — не подключаемся.
        await _closeSocket();
        return;
      }
      final mainTs = prefs.getInt(kPrefMainAliveTs) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final mainAlive = (now - mainTs) < _mainAliveThresholdMs;

      if (mainAlive) {
        // UI живо — main-WS сам обрабатывает входящие; сервис молчит.
        await _closeSocket();
      } else {
        await _ensureConnected(pubkey);
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _ensureConnected(String pubkey) async {
    if (_channel != null || _connecting || _stopped) return;
    _connecting = true;
    try {
      final host = AppConfig.apiHosts[_hostIndex % AppConfig.apiHosts.length];
      final uri = AppConfig.webSocketUrl(pubkey, host: host);
      final ws = await WebSocket.connect(uri)
          .timeout(const Duration(seconds: 20));
      if (_stopped) {
        try {
          await ws.close();
        } catch (_) {}
        return;
      }
      ws.pingInterval = const Duration(seconds: 10);
      _channel = IOWebSocketChannel(ws);
      _connectedHost = host;
      _connectedAddress = pubkey;
      _authed = false; // сначала обязательный PoP-хендшейк
      _sub = _channel!.stream.listen(
        (message) async {
          if (!_authed) {
            await _handlePopFrame(message);
          } else {
            await _onFrame(message);
          }
        },
        onDone: () => _onSocketClosed(),
        onError: (_) => _onSocketClosed(),
        cancelOnError: true,
      );
      _startPing();
      // ignore: avoid_print
      print("PushConnectionService WS connected");
    } catch (_) {
      _hostIndex++;
      await _closeSocket();
    } finally {
      _connecting = false;
    }
  }

  void _startPing() {
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 30), (_) {
      try {
        _channel?.sink.add(json.encode({'type': 'ping'}));
      } catch (_) {}
    });
  }

  Future<void> _onSocketClosed() async {
    _ping?.cancel();
    await _closeSocket();
    // Повторную попытку сделает следующий _evaluate по таймеру (если всё ещё
    // нужно — т.е. приложение по-прежнему убито).
  }

  Future<void> _closeSocket() async {
    _ping?.cancel();
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _connectedHost = null;
    _authed = false;
  }

  /// Обязательный PoP-хендшейк в изоляте: на challenge подписываем и шлём proof;
  /// на pop-ok переходим в рабочий режим. Иначе сервер закроет сокет (1008).
  Future<void> _handlePopFrame(dynamic message) async {
    try {
      final data = json.decode(message as String);
      if (data is! Map<String, dynamic>) return;
      final type = data['type'];
      if (type == 'pop-challenge') {
        if (_crypto.addressBase64 == null) {
          await _crypto.init(); // читает root_seed из secure storage, деривит ключи
        }
        if (_crypto.addressBase64 == null) {
          await _closeSocket();
          return;
        }
        final nonce = _b64urlDecode(data['nonce'] as String);
        final ts = data['ts'] as int;
        final sig = await _crypto.signPopProof(nonce, ts);
        _channel?.sink.add(json.encode({
          'type': 'pop-proof',
          'v': 1,
          'address': _connectedAddress,
          'sig': sig,
        }));
      } else if (type == 'pop-ok') {
        _authed = true;
      } else {
        await _closeSocket();
      }
    } catch (_) {
      await _closeSocket();
    }
  }

  Future<void> _onFrame(dynamic message) async {
    if (_stopped) return;
    try {
      final decoded = json.decode(message as String);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'] as String?;
      final senderKey = decoded['sender_pubkey'] as String?;
      if (type == null || _ignoredTypes.contains(type)) return;

      // support-reply приходит без sender_pubkey — общий информ-нотиф.
      if (type == 'support-reply') {
        await handleBackgroundPush({'type': 'support-reply'});
        return;
      }
      if (senderKey == null) return;

      if (type == 'call-offer' || type == 'incoming_call') {
        final data = decoded['data'];
        final offer = data is Map<String, dynamic> ? data : <String, dynamic>{};
        // Приводим WS-кадр к плоскому виду, который ждёт handleBackgroundPush
        // (тот же формат, что раньше слал FCM data).
        await handleBackgroundPush({
          'type': 'call-offer',
          'caller_key': senderKey,
          'sender_pubkey': senderKey,
          'call_id': _extractCallId(offer, senderKey),
          if (offer.isNotEmpty) 'offer_data': json.encode(offer),
          'recipient_pubkey': decoded['recipient_pubkey'],
        });
        return;
      }

      if (type == 'hang-up' || type == 'call-rejected' || type == 'call-ended') {
        await handleBackgroundPush({
          'type': type,
          'caller_key': senderKey,
          'sender_pubkey': senderKey,
        });
        return;
      }

      if (type == 'chat' ||
          type == 'new_message' ||
          type == 'room-message' ||
          type == 'room_message') {
        // Сервисный isolate не может расшифровать текст и достать имя из
        // зашифрованной БД — показываем обезличенное уведомление (это и есть
        // приватное поведение). Имя — префикс ключа.
        final display = senderKey.length >= 8
            ? senderKey.substring(0, 8)
            : senderKey;
        await handleBackgroundPush({
          // 'chat' у _handleBackgroundMessage нет — маппим на 'new_message'.
          'type': type == 'chat' ? 'new_message' : type,
          'sender_name': display,
          'caller_name': display,
          if (type == 'room-message' || type == 'room_message') ...{
            'room_id': decoded['room_id'],
            'room_name': decoded['room_name'],
            'author_type': decoded['author_type'],
          },
        });
        return;
      }
    } catch (_) {
      // Не роняем сервис на кривом кадре.
    }
  }

  static String _extractCallId(Map<String, dynamic> data, String callerKey) {
    final id = data['call_id'] ?? data['callId'] ?? data['id'];
    if (id != null && id.toString().isNotEmpty && id.toString() != 'null') {
      return id.toString();
    }
    final hash = callerKey.hashCode.abs();
    final window = DateTime.now().millisecondsSinceEpoch ~/ 15000;
    return 'call-${hash.toRadixString(16).padLeft(8, '0')}-$window';
  }
}
