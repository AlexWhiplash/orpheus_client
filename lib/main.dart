import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/license_screen.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/message_retention_policy.dart';
import 'package:orpheus_project/screens/lock_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';
import 'package:orpheus_project/services/incoming_message_handler.dart';
import 'package:orpheus_project/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orpheus_project/services/pending_call_storage.dart';
import 'package:orpheus_project/services/network_monitor_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/panic_wipe_service.dart';
import 'package:orpheus_project/services/message_cleanup_service.dart';
import 'package:orpheus_project/services/call_state_service.dart';
import 'package:orpheus_project/services/presence_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/services/telemetry_service.dart';
import 'package:orpheus_project/services/call_id_storage.dart';
import 'package:orpheus_project/services/push_connection_service.dart';
import 'package:orpheus_project/services/secure_storage_options.dart';
import 'package:orpheus_project/theme/app_theme.dart';
import 'package:orpheus_project/welcome_screen.dart';
import 'package:orpheus_project/screens/home_screen.dart';

part 'main_callkit.dart';

// Глобальные сервисы
final cryptoService = CryptoService.instance;
final websocketService = WebSocketService();
final presenceService = PresenceService(websocketService);
final notificationService = NotificationService();
final authService = AuthService.instance;
final panicWipeService = PanicWipeService.instance;
final messageCleanupService = MessageCleanupService.instance;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Потоки для обновлений UI
final StreamController<String> messageUpdateController = StreamController.broadcast();
final StreamController<Map<String, dynamic>> signalingStreamController = StreamController.broadcast();

/// Буфер входящих сигналов звонка (ICE candidates и т.п.)
final IncomingCallBuffer incomingCallBuffer = IncomingCallBuffer.instance;

bool _hasKeys = false;

/// Таймер heartbeat для координации с сервисным isolate (PushConnectionService).
Timer? _pushHeartbeatTimer;

/// Глобальный флаг: приложение в foreground (активно)?
bool isAppInForeground = true;

/// Pending call в RAM (для быстрого доступа в рамках одного isolate)
/// Для персистентного хранения используем PendingCallStorage
PendingCallData? _pendingCall;

/// Флаг: ожидается открытие CallScreen из CallKit (блокирует дубли из WebSocket)
bool _isProcessingCallKitAnswer = false;

/// Синхронный CLAIM навигации на экран звонка по call_id. Один и тот же звонок,
/// доставленный дважды (call-offer уходит и по WS, И по HTTP-fallback) или сразу
/// двумя путями (fullScreenIntent-уведомление + CallKit accept), должен открыть
/// ОДИН экран. Опираться на isCallActive нельзя: он ставится поздно, в
/// CallScreen.initState — кадром ПОЗЖЕ push, поэтому два вызова в одном кадре оба
/// видят false и оба пушат. Этот claim ставится СИНХРОННО на входе навигации, до
/// postFrame; Dart однопоточный и между проверкой и присвоением нет await, значит
/// конкурентные вызовы сериализуются: первый захватывает call_id, остальные
/// отклоняются. TTL самозаживляется (законный повторный звонок получает новый
/// call_id и не блокируется).
String? _navClaimedCallId;
int _navClaimedAtMs = 0;
const int _navClaimTtlMs = 15000;

bool _claimCallNavigation(String? callId) {
  if (callId == null || callId.isEmpty) return true;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (_navClaimedCallId == callId && (now - _navClaimedAtMs) < _navClaimTtlMs) {
    return false;
  }
  _navClaimedCallId = callId;
  _navClaimedAtMs = now;
  return true;
}

/// Освобождает claim (если Navigator оказался null в postFrame и звонок ушёл в
/// pending — чтобы повторная обработка смогла заново захватить и открыть экран).
void _resetCallNavigationClaim() => _navClaimedCallId = null;

/// Sentry DSN для мониторинга ошибок
const String _sentryDsn = 'https://7d6801508e29bc2e4f5b93b986147cdc@o4509485705265152.ingest.de.sentry.io/4510682122879056';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sentry — сторонний краш-репортер (ingest.de.sentry.io). Для privacy-мессенджера
  // отправка данных наружу должна быть строго opt-in: инициализируем Sentry только
  // если пользователь явно включил телеметрию (тот же флаг, что у TelemetryService).
  // По умолчанию (флаг выключен) наружу ничего не уходит.
  final telemetryEnabled = await _isTelemetryEnabled();

  if (!telemetryEnabled) {
    await _initializeApp();
    _runOrpheus();
    return;
  }

  // Sentry инициализация с перехватом всех ошибок
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      // Версия приложения для отслеживания регрессий
      options.release = 'orpheus@${AppConfig.appVersion}';
      options.environment = kReleaseMode ? 'production' : 'development';
      // Отслеживание производительности (10% транзакций)
      options.tracesSampleRate = 0.1;
      // Отключаем отправку PII (персональных данных)
      options.sendDefaultPii = false;
      // Фильтруем breadcrumbs от чувствительных данных
      options.beforeBreadcrumb = (Breadcrumb? breadcrumb, Hint _hint) {
        // Не логируем содержимое сообщений
        if (breadcrumb?.category == 'message' ||
            breadcrumb?.message?.contains('encrypted') == true) {
          return null;
        }
        return breadcrumb;
      };
    },
    appRunner: () async {
      await _initializeApp();
      _runOrpheus();
    },
  );
}

/// Запускает приложение в Zone, перехватывающей `print` (Dart) в DebugLogger —
/// иначе логи сервисов на `print` (WS/WebRTC) не попадали в файл/буфер (перехвачен
/// был только debugPrint). Ошибки Zone тоже логируются. Только для тест-сборок
/// (за флагом AppConfig.debugFileLogging).
void _runOrpheus() {
  if (!AppConfig.debugFileLogging) {
    runApp(const MyApp());
    return;
  }
  runZonedGuarded(
    () => runApp(const MyApp()),
    (error, stack) =>
        DebugLogger.error('ZONE', '$error', context: {'stack': '$stack'}),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        DebugLogger.info('PRINT', line);
        parent.print(zone, line);
      },
    ),
  );
}

/// Читает opt-in флаг телеметрии (по умолчанию выключено). Один и тот же флаг
/// управляет и Sentry, и фоновой телеметрией (см. [TelemetryService]).
Future<bool> _isTelemetryEnabled() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('telemetry_enabled') ?? false;
  } catch (_) {
    return false;
  }
}

/// Основная инициализация приложения
Future<void> _initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Перехват debugPrint (полная телеметрия жизненного цикла)
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    DebugLogger.info('PRINT', message);
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    DebugLogger.error('FLUTTER', details.exceptionAsString(),
        context: {'stack': details.stack.toString()});
    FlutterError.presentError(details);
  };
  
  // Персистентное файловое логирование (тест-сборки): все логи пишутся в файл,
  // переживают рестарт приложения и выгружаются кнопкой «Поделиться» в экране
  // отладки — не нужно подключать телефон к ПК.
  if (AppConfig.debugFileLogging) {
    await DebugLogger.enableFileLogging();
  }

  DebugLogger.info('APP', '🚀 Orpheus запускается...');

  // Инициализация сервиса локализации
  DebugLogger.info('APP', 'Инициализация LocaleService...');
  await LocaleService.instance.init();
  DebugLogger.info('APP', 'Локаль: ${LocaleService.instance.effectiveLocale.languageCode}');

  // Intl (DateFormat) требует инициализации таблиц локали.
  // Инициализируем обе поддерживаемые локали
  await initializeDateFormatting('ru');
  await initializeDateFormatting('en');
  
  // Устанавливаем локаль по умолчанию для Intl
  Intl.defaultLocale = LocaleService.instance.effectiveLocale.languageCode;

  try {
    // Уведомления (локальные, без Google/FCM)
    DebugLogger.info('APP', 'Инициализация уведомлений...');
    await notificationService.init();
    DebugLogger.success('APP', 'Уведомления инициализированы');
  } catch (e, stackTrace) {
    print("INIT ERROR: $e");
    DebugLogger.error('APP', 'INIT ERROR: $e');
    // Отправляем ошибку инициализации в Sentry (no-op, если Sentry выключен)
    await Sentry.captureException(e, stackTrace: stackTrace);
  }

  // 3.5. Одноразовый чистый сброс secure storage при переходе на
  // flutter_secure_storage v10 (новые шифры). ДО первого чтения ключей.
  await ensureSecureStorageMigrated();

  // 3.6. Активный API-хост (prod/test) из prefs — ДО любого сетевого сервиса,
  // чтобы первый WebSocket/HTTP шёл уже на выбранный сервер (тест-сборки).
  await AppConfig.loadActiveHost();

  // 4. Криптография
  DebugLogger.info('APP', 'Инициализация криптографии...');
  _hasKeys = await cryptoService.init();
  DebugLogger.info('APP', 'Ключи: ${_hasKeys ? "ЕСТЬ" : "НЕТ"}');

  // 5. Сервис авторизации (PIN, duress)
  DebugLogger.info('APP', 'Инициализация AuthService...');
  await authService.init();
  DebugLogger.info('APP', 'AuthService: PIN=${authService.config.isPinEnabled}, duress=${authService.config.isDuressEnabled}');

  // 5.5. Сервис автоочистки сообщений (зависит от AuthService)
  DebugLogger.info('APP', 'Инициализация MessageCleanupService...');
  await messageCleanupService.init();
  DebugLogger.info('APP', 'MessageCleanupService: retention=${authService.messageRetention.displayName}');

  // 6. Panic Wipe Service (тройное нажатие кнопки питания)
  panicWipeService.init();

  // 7. Network Monitor Service (мониторинг сети для реконнекта)
  DebugLogger.info('APP', 'Инициализация NetworkMonitorService.');
  await NetworkMonitorService.instance.init();
  DebugLogger.success('APP', 'NetworkMonitorService инициализирован');

  // 7.5 Телеметрия (полные логи в БД для анализа)
  await TelemetryService.instance.init();

  // 8. WebSocket подключение отложено до initState виджета,
  // чтобы _licenseSubscription был зарегистрирован до прихода license-status.

  // 9. Слушаем сообщения
  _listenForMessages();
  
  // 10. Инициализация CallKit для нативного UI звонков
  DebugLogger.info('APP', 'Инициализация CallKit...');
  _initCallKit();
  DebugLogger.success('APP', 'CallKit инициализирован');

  // Обработка клика по уведомлению о звонке (fallback)
  NotificationService.onIncomingCallFromNotification = (data) {
    final callerKey = data['caller_key'] ?? data['callerKey'];
    if (callerKey == null) return;
    Map<String, dynamic>? offerData;
    final offerJson = data['offer_data'] ?? data['offerData'];
    if (offerJson is String && offerJson.isNotEmpty) {
      try {
        offerData = json.decode(offerJson) as Map<String, dynamic>;
      } catch (_) {}
    } else if (offerJson is Map<String, dynamic>) {
      offerData = offerJson;
    }
    final callId = data['call_id'] ?? data['callId'] ?? data['id'];
    // ВАЖНО: тап/полноэкранный показ уведомления входящего != согласие ответить.
    // Открываем ЗВОНЯЩИЙ экран (рингтон + кнопка "Ответить") и ждём пользователя.
    // На локскрине fullScreenIntent сам запускает активити и дёргает этот колбэк
    // без реального нажатия — с autoAnswer:true это авто-поднимало трубку на
    // заблокированном телефоне (могли слушать). Реальный "Ответить" идёт отдельным
    // путём CallKit accept (main_callkit), там autoAnswer корректен.
    _navigateToCallScreen(
      callerKey.toString(),
      offerData,
      autoAnswer: false,
      callId: callId?.toString(),
    );
  };

  // Постоянный foreground-сервис доставки пушей (замена FCM). Поднимаем только
  // если у пользователя есть ключи (иначе показывать постоянное уведомление до
  // создания аккаунта незачем).
  _startPushConnectionAndHeartbeat();

  DebugLogger.success('APP', '✅ Приложение запущено');
}

/// Heartbeat main-изолята + публикация pubkey для сервисного isolate, плюс старт
/// постоянного сервиса. Пока main-изолят жив и пишет heartbeat, сервис молчит;
/// когда приложение убито и heartbeat протухает — сервис берёт доставку на себя.
void _startPushConnectionAndHeartbeat() {
  final pubkey = cryptoService.publicKeyBase64;
  if (!_hasKeys || pubkey == null || pubkey.isEmpty) return;

  Future<void> beat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Публичный ключ НЕ секрет (раздаётся через QR) — можно в SharedPreferences.
      await prefs.setString(kPrefUserPubkey, pubkey);
      await prefs.setInt(
          kPrefMainAliveTs, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  beat();
  _pushHeartbeatTimer?.cancel();
  _pushHeartbeatTimer =
      Timer.periodic(const Duration(seconds: 4), (_) => beat());

  PushConnectionService.start();
}

/// Переключить активный API-сервер (prod/test) и переподключить main-WS на новый
/// хост. Персист в prefs; push-изолят подхватит новый хост при следующем коннекте
/// (пока приложение живо, он держит сокет закрытым). Хост вне allowlist игнорируется.
Future<void> switchApiServer(String host) async {
  await AppConfig.setActiveHost(host);
  // disconnect ПЕРВЫМ: connect() — no-op, если сокет уже Connected/Connecting.
  try {
    websocketService.disconnect();
  } catch (_) {}
  final pubkey = cryptoService.publicKeyBase64;
  if (pubkey != null && pubkey.isNotEmpty) {
    websocketService.connect(pubkey);
  }
}

/// Инициализация CallKit для обработки нативного UI входящих звонков

void _listenForMessages() {
  final handler = IncomingMessageHandler(
    crypto: _IncomingCryptoAdapter(cryptoService),
    database: _IncomingDatabaseAdapter(DatabaseService.instance),
    notifications: _IncomingNotificationsAdapter(),
    callBuffer: incomingCallBuffer,
    openCallScreen: ({required contactPublicKey, required offer, String? callId}) {
      // ВАЖНО: используем централизованную навигацию с проверками
      // Если приложение в foreground, WebSocket может доставить call-offer
      // но если CallKit уже обрабатывает ответ - игнорируем дубль
      if (_isProcessingCallKitAnswer) {
        DebugLogger.info('CALL', '📞 Игнорирую call-offer из WS: CallKit уже обрабатывает');
        return;
      }
      if (CallStateService.instance.isCallActive.value) {
        DebugLogger.info('CALL', '📞 Игнорирую call-offer из WS: уже есть активный звонок');
        return;
      }
      // Тот же call_id, что уже захвачен другим путём (уведомление/CallKit или
      // дубль WS+HTTP) — не открываем второй экран.
      if (!_claimCallNavigation(callId)) {
        DebugLogger.info('CALL', '📞 Игнорирую дубль call-offer из WS по call_id');
        return;
      }
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (context) => CallScreen(
          contactPublicKey: contactPublicKey,
          offer: offer,
          callId: callId,
        ),
      ));
    },
    emitSignaling: (msg) => signalingStreamController.add(msg),
    emitChatUpdate: (senderKey) => messageUpdateController.add(senderKey),
    // Под локом (requiresUnlock) НЕ считаем приложение foreground для показа
    // входящего: иначе handler открыл бы CallScreen напрямую поверх/под локскрином
    // (недетерминированно, обходит лок). При locked -> ветка CallKit + pending,
    // а ответ обрабатывается после ввода PIN Orpheus (processPendingCallAfterUnlock).
    isAppInForeground: () => isAppInForeground && !authService.requiresUnlock,
    // КРИТИЧНО: передаём проверку активного звонка И обработки CallKit
    isCallActive: () => CallStateService.instance.isCallActive.value || _isProcessingCallKitAnswer,
  );

  websocketService.stream.listen((messageJson) async {
    try {
      await handler.handleRawMessage(messageJson);
    } catch (e, stackTrace) {
      DebugLogger.error('MAIN', 'Message Handler Error: $e');
      // Отправляем ошибку обработки сообщений в Sentry
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  });
}

class _IncomingCryptoAdapter implements IncomingMessageCrypto {
  _IncomingCryptoAdapter(this._crypto);
  final CryptoService _crypto;
  @override
  Future<String> decrypt(String senderPublicKeyBase64, String encryptedPayload) {
    return _crypto.decrypt(senderPublicKeyBase64, encryptedPayload);
  }
}

class _IncomingDatabaseAdapter implements IncomingMessageDatabase {
  _IncomingDatabaseAdapter(this._db);
  final DatabaseService _db;

  @override
  Future<void> addMessage(ChatMessage message, String contactPublicKey) {
    return _db.addMessage(message, contactPublicKey);
  }

  @override
  Future<void> addContactIfMissing(String publicKey) {
    return _db.addContactIfMissing(publicKey);
  }

  @override
  Future<String?> getContactName(String publicKey) async {
    try {
      final contact = await _db.getContact(publicKey);
      if (contact != null && contact.name.trim().isNotEmpty) {
        return contact.name;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<int> deleteMessagesByTimestamps(String contactKey, List<int> timestamps) {
    return _db.deleteMessagesByTimestamps(contactKey, timestamps);
  }

  @override
  Future<int> deleteMessagesByMessageIds(String contactKey, List<String> messageIds) {
    return _db.deleteMessagesByMessageIds(contactKey, messageIds);
  }

  @override
  Future<bool> messageExistsByMessageId(String contactKey, String messageId) {
    return _db.messageExistsByMessageId(contactKey, messageId);
  }
}

class _IncomingNotificationsAdapter implements IncomingMessageNotifications {
  @override
  Future<void> showCallNotification({required String callerName, String? payload}) {
    return NotificationService.showCallNotification(callerName: callerName, payload: payload);
  }

  @override
  Future<void> hideCallNotification() {
    return NotificationService.hideCallNotification();
  }

  @override
  Future<void> showMessageNotification({required String senderName}) {
    return NotificationService.showMessageNotification(senderName: senderName);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isLicensed = false;
  bool _isCheckCompleted = false;
  static const String _licenseCacheKey = 'license_active';

  /// Кэш последнего ПОДТВЕРЖДЁННОГО сервером статуса лицензии — без срока
  /// давности (аудит LOGIC-8). Модель простая: лицензия проверяется на сервере;
  /// если отозвана — WS-листенер мгновенно выставит `_isLicensed=false`, а если
  /// сети нет — приложение доступно по кэшу. Никакого учёта времени/grace-периода:
  /// не тратим ресурсы и батарею на постоянную слежку за возрастом кэша.
  Future<void> _loadCachedLicense() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final active = prefs.getBool(_licenseCacheKey) ?? false;
      if (active && mounted && !_isCheckCompleted) {
        setState(() {
          _isLicensed = true;
          _isCheckCompleted = true;
        });
      }
    } catch (_) {}
  }

  /// Сохраняет последний подтверждённый сервером статус лицензии (без отметки времени).
  Future<void> _persistLicense(bool active) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_licenseCacheKey, active);
    } catch (_) {}
  }
  late bool _keysExist;
  bool _isLocked = false;
  Timer? _inactivityTimer;
  DateTime _lastUserActivity = DateTime.now();
  StreamSubscription<String>? _licenseSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Начальное значение foreground-флага (приватность имени звонка): true только
    // если приложение реально стартует на переднем плане.
    DeviceSettingsService.setAppInForeground(
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
    _keysExist = _hasKeys;
    _isLocked = authService.requiresUnlock;
    RawKeyboard.instance.addListener(_handleRawKeyEvent);
    CallStateService.instance.isCallActive.addListener(_onCallActiveChanged);
    _registerUserActivity('init');
    
    // Подписываемся на изменения локали
    LocaleService.instance.addListener(_onLocaleChanged);
    
    // Останавливаем сеть В НАЧАЛЕ wipe: иначе входящее сообщение может
    // пересоздать БД+ключ во время очистки, а сокет остаться под стёртой личностью.
    AuthService.onWipeStarted = () {
      try {
        websocketService.disconnect();
      } catch (_) {}
      // Гасим heartbeat (иначе он перезапишет старый pubkey обратно в prefs
      // после prefs.clear() и сервис переподключится под стёртой личностью) и
      // останавливаем постоянный сервис доставки.
      try {
        _pushHeartbeatTimer?.cancel();
        _pushHeartbeatTimer = null;
      } catch (_) {}
      try {
        PushConnectionService.stop();
      } catch (_) {}
      // Panic-wipe/duress: возвращаем клиент на прод, чтобы стёртая личность не
      // пересоздавалась против тестового сервера.
      try {
        AppConfig.resetHostToProd();
      } catch (_) {}
    };

    // Central wipe handler — called from ALL wipe paths
    // (delete account, wipe code, auto-wipe, panic wipe)
    AuthService.onWipeCompleted = () {
      // Сеть уже остановлена в onWipeStarted; на всякий случай закрываем ещё раз.
      try {
        websocketService.disconnect();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _keysExist = false;
          _isLocked = false;
          _isLicensed = false;
          _isCheckCompleted = false;
        });
      }
    };
    
    // Не пишем в logcat префикс публичного ключа и состояние PIN (аудит QUAL-1/OPS-6).
    DebugLogger.info('APP', 'Keys exist: $_keysExist');
    DebugLogger.info('APP', 'Locked: $_isLocked');

    // Проверка лицензии (подписка на WS + 10с таймаут-фолбэк). Вынесено в метод,
    // чтобы пере-армить после создания аккаунта: иначе после wipe+создания в одной
    // сессии подписка уже отменена, а таймаут израсходован -> _isCheckCompleted
    // навсегда false -> приложение виснет на тёмном экране загрузки.
    _startLicenseCheck();

    // Подключаем WebSocket здесь, ПОСЛЕ регистрации _licenseSubscription,
    // чтобы не пропустить license-status из-за race condition с broadcast stream.
    if (_keysExist && !_isLocked && cryptoService.publicKeyBase64 != null) {
      websocketService.connect(cryptoService.publicKeyBase64!);
    }
  }

  /// Проверка лицензии: слушает license-status по WS + 10с таймаут-фолбэк на показ
  /// экрана лицензии. Идемпотентно (отменяет прошлую подписку). Вызывается при старте
  /// И после создания нового аккаунта — иначе после wipe+создания в одной сессии
  /// подписка уже отменена, а таймаут израсходован, и экран лицензии не показывается.
  void _startLicenseCheck() {
    _licenseSubscription?.cancel();
    _licenseSubscription = websocketService.stream.listen((message) {
      try {
        // Быстрый фильтр — не парсим JSON на каждом сообщении.
        if (!message.contains('license-status') && !message.contains('payment-confirmed')) return;

        final data = json.decode(message);
        if (data['type'] == 'license-status') {
          print("📋 License status received: ${data['status']}");
          setState(() {
            _isLicensed = (data['status'] == 'active');
            _isCheckCompleted = true;
          });
          _persistLicense(_isLicensed); // обновляем кэш для офлайн-запусков
          _licenseSubscription?.cancel();
          _licenseSubscription = null;
        } else if (data['type'] == 'payment-confirmed') {
          print("💳 Payment confirmed!");
          setState(() {
            _isLicensed = true;
            _isCheckCompleted = true;
          });
          _persistLicense(true);
          _licenseSubscription?.cancel();
          _licenseSubscription = null;
        }
      } catch (_) {}
    });

    // Если лицензия уже подтверждалась ранее — пускаем в приложение сразу
    // (не запирая офлайн-пользователя), онлайн-проверка идёт в фоне.
    _loadCachedLicense();

    // Таймаут на проверку лицензии (10 секунд)
    // Если за это время не получили ответ — показываем экран лицензии
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && !_isCheckCompleted) {
        print("⚠️ License check timeout - showing license screen");
        setState(() {
          _isCheckCompleted = true;
          _isLicensed = false;
        });
      }
    });
  }

  void _onAuthComplete() {
    // Delay state change to next frame to avoid duplicate GlobalKeys
    // when Navigator rebuilds during the same frame as WelcomeScreen disposal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _keysExist = true;
        // Свежий аккаунт: лицензии ещё нет — проверку надо начать заново.
        _isCheckCompleted = false;
        _isLicensed = false;
      });
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.connect(cryptoService.publicKeyBase64!);
      }
      // Пере-армить проверку лицензии — иначе после wipe экран лицензии не покажется
      // (подписка была отменена, таймаут израсходован) и экран зависнет чёрным.
      _startLicenseCheck();
    });
  }

  void _onUnlocked() {
    DebugLogger.info('APP', '🔓 App unlocked');
    setState(() => _isLocked = false);
    _registerUserActivity('unlock');

    // Подключаем основной WebSocket при разблокировке. Старт-подключение выше
    // гейтится на !_isLocked, а со строгим локом приложение часто СТАРТУЕТ
    // заблокированным; на холодном старте события resumed нет (уже resumed), так
    // что без этого основной WS не встаёт до ручного сворачивания-разворачивания
    // (не работают presence и исходящие звонки). forceReconnectIfStale поднимает
    // WS даже если он залип в Connecting после фона (частый кейс на Samsung).
    if (_keysExist && cryptoService.publicKeyBase64 != null) {
      websocketService.forceReconnectIfStale(cryptoService.publicKeyBase64!);
    }

    // Обработать отложенный звонок если есть
    // Используем небольшую задержку чтобы UI успел перестроиться
    Future.delayed(const Duration(milliseconds: 300), () {
      processPendingCallAfterUnlock();
    });
  }

  void _onDuressMode() {
    DebugLogger.warn('APP', '🔓 App unlocked in DURESS MODE');
    setState(() => _isLocked = false);
    // В duress mode приложение работает, но показывает пустой профиль
  }

  Future<void> _onWipe(WipeReason reason) async {
    final label = switch (reason) {
      WipeReason.wipeCode => 'WIPE CODE',
      WipeReason.autoWipe => 'AUTO WIPE',
    };
    DebugLogger.warn('APP', '⚠️ $label: выполняется полный WIPE');
    await authService.performWipe();
    // State reset is handled by AuthService.onWipeCompleted callback
  }

  void _onLocaleChanged() {
    // Обновляем Intl локаль при смене языка
    Intl.defaultLocale = LocaleService.instance.effectiveLocale.languageCode;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocaleService.instance.removeListener(_onLocaleChanged);
    _licenseSubscription?.cancel();
    _inactivityTimer?.cancel();
    RawKeyboard.instance.removeListener(_handleRawKeyEvent);
    CallStateService.instance.isCallActive.removeListener(_onCallActiveChanged);
    super.dispose();
  }

  /// Звонок на время своего показа снимает keyguard (enableCallMode -> дать
  /// ответить на заблокированном телефоне). По завершении звонка, если устройство
  /// всё ещё под системной блокировкой, лочим и приложение — иначе после звонка
  /// над локскрином мелькнёт интерфейс Orpheus (утечка). Если устройство уже
  /// разблокировано (пользователь сам ввёл PIN во время звонка) — не мешаем.
  Future<void> _onCallActiveChanged() async {
    if (CallStateService.instance.isCallActive.value) return; // звонок начался
    if (!authService.config.isPinEnabled || _isLocked) return;
    try {
      if (await DeviceSettingsService.isDeviceLocked()) {
        authService.lock();
        if (mounted) setState(() => _isLocked = true);
      }
    } catch (_) {}
  }

  void _handleRawKeyEvent(RawKeyEvent event) {
    _registerUserActivity('keyboard');
  }

  void _registerUserActivity(String source) {
    _lastUserActivity = DateTime.now();
    _resetInactivityTimer();
  }

  Duration? _getInactivityTimeout() {
    final seconds = authService.inactivityLockSeconds;
    if (seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    final timeout = _getInactivityTimeout();
    if (timeout == null) return;
    if (!authService.config.isPinEnabled || _isLocked) return;
    _inactivityTimer = Timer(timeout, () {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_lastUserActivity);
      if (elapsed >= timeout && authService.config.isPinEnabled && !_isLocked) {
        authService.lock();
        setState(() => _isLocked = true);
        DebugLogger.info('LIFECYCLE', '🔒 App locked by inactivity timeout');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Логируем изменение состояния
    DebugLogger.info('LIFECYCLE', 'State: $state');
    
    // Обновляем глобальный флаг состояния приложения
    isAppInForeground = (state == AppLifecycleState.resumed);
    // Дублируем в SharedPreferences: push-изолят читает это, чтобы решить, прятать
    // ли имя звонящего на входящем (приватность на локскрине).
    DeviceSettingsService.setAppInForeground(isAppInForeground);

    if (state == AppLifecycleState.resumed) {
      DebugLogger.info('LIFECYCLE', 'App in foreground, reconnecting WS...');
      // Reconnect WebSocket on return to app. forceReconnectIfStale вместо connect:
      // после фона сокет часто мёртв, а статус залип в Connecting -> connect() был бы
      // no-op и WS висел бы в Connecting; здесь форсируем свежий реконнект.
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.forceReconnectIfStale(cryptoService.publicKeyBase64!);
      }
      // Clear notification tray when user opens the app
      NotificationService.hideMessageNotifications();
      // Check message auto-cleanup on return to foreground
      messageCleanupService.onAppResumed();
      
      // КРИТИЧНО: Обработка отложенного звонка при возврате из background
      // Если пользователь принял звонок через CallKit, но Navigator был ещё не готов,
      // звонок сохранился в _pendingCall. Обрабатываем его сейчас.
      // Задержка даёт время Flutter engine полностью восстановить UI.
      if (_pendingCall != null && _pendingCall!.isValid && !_isLocked) {
        DebugLogger.info('LIFECYCLE', '📞 Найден pending call при resumed, обрабатываю');
        Future.delayed(const Duration(milliseconds: 300), () {
          processPendingCallAfterUnlock();
        });
      } else if (!_isLocked && !CallStateService.instance.isCallActive.value) {
        // Fallback: проверяем активные CallKit звонки
        // На случай если pending call был null, но пользователь принял звонок через CallKit
        // и приложение развернулось, но _handleCallKitAccept ещё не успел сработать
        Future.delayed(const Duration(milliseconds: 500), () {
          _checkActiveCallOnResumed();
        });
      }
      final timeout = _getInactivityTimeout();
      if (timeout != null &&
          authService.config.isPinEnabled &&
          !_isLocked &&
          DateTime.now().difference(_lastUserActivity) >= timeout) {
        authService.lock();
        setState(() => _isLocked = true);
        DebugLogger.info('LIFECYCLE', '🔒 App locked on resume (inactivity timeout)');
      } else {
        _resetInactivityTimer();
      }
    } else if (state == AppLifecycleState.paused) {
      DebugLogger.info('LIFECYCLE', 'Приложение в background');

      final hasActiveCall = CallStateService.instance.isCallActive.value;
      final hasPendingCall = _pendingCall != null && _pendingCall!.isValid;

      // ВАЖНО: сохраняем WebSocket в фоне, чтобы звонки доходили даже без CallKit/FCM.
      // Дедуп выполняется через call_id (CallIdStorage) в обработчике входящих сигналов.
      DebugLogger.info('LIFECYCLE', '📶 WebSocket остаётся подключённым в background');

      _inactivityTimer?.cancel();

      // Строгая блокировка: как только приложение уходит в фон / гаснет экран —
      // сразу лочим (при включённом PIN). Исключение — активный ИЛИ входящий
      // звонок: экран звонка и приём должны остаться доступными без PIN.
      if (authService.config.isPinEnabled &&
          !_isLocked &&
          !hasActiveCall &&
          !hasPendingCall) {
        authService.lock();
        setState(() => _isLocked = true);
        DebugLogger.info('LIFECYCLE', '🔒 App locked on background (immediate)');
      } else if (hasPendingCall) {
        DebugLogger.info('LIFECYCLE', '📞 Есть pending call');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      
      // Локализация
      locale: LocaleService.instance.selectedLocale,
      supportedLocales: LocaleService.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        // Если пользователь выбрал конкретную локаль — используем её
        if (LocaleService.instance.selectedLocale != null) {
          return LocaleService.instance.selectedLocale;
        }
        // Иначе ищем подходящую среди системных
        if (locale != null) {
          for (final supported in supportedLocales) {
            if (supported.languageCode == locale.languageCode) {
              return supported;
            }
          }
        }
        // Fallback на английский
        return const Locale('en');
      },
      
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _registerUserActivity('pointer'),
        onPointerMove: (_) => _registerUserActivity('pointer'),
        onPointerSignal: (_) => _registerUserActivity('pointer'),
        child: Stack(
          children: [
            child ?? const SizedBox.shrink(),
            // LockScreen рисуется ПОВЕРХ Navigator'а (всех запушенных маршрутов —
            // звонка, чата), а не как home. Иначе любой pushed-маршрут перекрывает
            // LockScreen-как-home и PIN приложения обходится (security). _buildHome
            // при этом отдаёт пустой чёрный экран, чтобы контент под локом не строился.
            if (_isLocked && _keysExist)
              Positioned.fill(
                child: LockScreen(
                  onUnlocked: _onUnlocked,
                  onDuressMode: _onDuressMode,
                  onWipe: _onWipe,
                ),
              ),
          ],
        ),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // 1. Нет ключей — экран приветствия
    if (!_keysExist) {
      return WelcomeScreen(onAuthComplete: _onAuthComplete);
    }
    
    // 2. Приложение заблокировано — контент НЕ строим (данные не грузим под локом).
    // Сам LockScreen рисуется оверлеем поверх всего в MaterialApp.builder выше,
    // чтобы перекрывать и запушенные маршруты (звонок/чат) — иначе PIN обходится.
    if (_isLocked) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    
    // 3. Проверка лицензии не завершена — загрузка
    if (!_isCheckCompleted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    // 4. Лицензия активна — главный экран
    if (_isLicensed) {
      return const HomeScreen();
    }
    
    // 5. Нет лицензии — экран лицензии
    return LicenseScreen(onLicenseConfirmed: () {
      setState(() => _isLicensed = true);
      _persistLicense(true);
      // После активации лицензии убеждаемся, что WS поднят свежей сессией — иначе
      // онлайн/presence мог не встать до перезапуска приложения (device-тест: у
      // некоторых Samsung после активации онлайн не поднимался до рестарта).
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.forceReconnectIfStale(cryptoService.publicKeyBase64!);
      }
    });
  }
}
