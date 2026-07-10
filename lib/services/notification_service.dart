// lib/services/notification_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/notification_prefs_service.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/services/call_id_storage.dart';
import 'package:orpheus_project/services/pending_call_storage.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Диспетчер входящего push-сообщения из фонового WS-слушателя
/// (см. PushConnectionService). Раньше эту роль играл FCM background handler
/// (`firebaseMessagingBackgroundHandler(RemoteMessage)`) — после отказа от Google
/// сообщения приходят по WebSocket из изолята постоянного foreground-сервиса.
///
/// КРИТИЧЕСКИ ВАЖНО: Этот код выполняется в ОТДЕЛЬНОМ isolate!
/// Нельзя использовать синглтоны или состояние из main isolate.
/// `data` — это раскодированный JSON WS-кадра (data-only, без notification payload).
@pragma('vm:entry-point')
Future<void> handleBackgroundPush(Map<String, dynamic> data) async {
  final type = data['type'];
  print("PUSH BACKGROUND type: $type");

  // Строгий mutual-add (фон): peer-звонки и peer-сообщения показываем ТОЛЬКО от
  // добавленных контактов. Проверка по allow-list из secure storage (в фоновом
  // изоляте зашифрованная БД ненадёжна). Комнаты (room-*) и support-reply не гейтим.
  final peerSender = (data['caller_key'] ?? data['sender_pubkey'])?.toString();
  final isPeerType = type == 'incoming_call' ||
      type == 'call-offer' ||
      type == 'new_message' ||
      type == 'chat';
  if (isPeerType && peerSender != null && peerSender.isNotEmpty) {
    final allow = await DatabaseService.loadContactAllowlist();
    if (!allow.contains(peerSender)) {
      print("PUSH BACKGROUND: drop $type from non-contact (strict mutual-add)");
      return;
    }
  }

  // === ВХОДЯЩИЙ ЗВОНОК ===
  // Показываем нативный UI звонка через flutter_callkit_incoming
  if (type == 'incoming_call' || type == 'call-offer') {
    await _sendBackgroundTelemetry(data, 'incoming_call_received');
    await _showNativeIncomingCall(data);
    return;
  }

  // === НОВОЕ СООБЩЕНИЕ ===
  // Показываем локальное уведомление (WS-кадр всегда data-only)
  if (type == 'new_message' ||
      type == 'chat' ||
      type == 'room-message' ||
      type == 'room_message' ||
      type == 'support-reply') {
    await NotificationService._handleBackgroundMessage(data);
    return;
  }

  // === ЗАВЕРШЕНИЕ ЗВОНКА ===
  // Скрываем нативный UI если звонок завершён
  if (type == 'hang-up' || type == 'call-rejected' || type == 'call-ended') {
    await _sendBackgroundTelemetry(data, 'call_end_received');
    final callerKey = data['caller_key'] ?? data['sender_pubkey'];
    if (callerKey != null) {
      // Завершаем все звонки от этого caller
      await FlutterCallkitIncoming.endAllCalls();
    }
    return;
  }
}

Future<void> _sendBackgroundTelemetry(Map<String, dynamic> data, String message) async {
  try {
    // Уважаем opt-in: фоновая телеметрия не уходит, пока пользователь явно не
    // включил её (тот же флаг, что у TelemetryService). Раньше этот путь слал
    // peer_pubkey и сырой payload в обход флага и санитизации (AUDIT_REPORT SEC-2).
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('telemetry_enabled') ?? false)) return;
    } catch (_) {
      return;
    }

    final recipientPubkey = data['recipient_pubkey']?.toString();
    if (recipientPubkey == null || recipientPubkey.isEmpty) return;

    final callId = data['call_id'] ?? data['callId'] ?? data['id'];

    final payload = {
      'source': 'client-bg',
      'entries': [
        {
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'info',
          'tag': 'BG',
          'category': 'BG',
          'message': message,
          // НЕ отправляем сырой data и peer_pubkey (граф общения контактов) — SEC-2.
          'call_id': callId,
          'app_state': 'background',
        },
      ],
    };

    final body = json.encode(payload);
    for (final url in AppConfig.httpUrls('/api/logs/batch')) {
      try {
        final response = await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'X-Pubkey': recipientPubkey,
          },
          body: body,
        ).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          break;
        }
      } catch (_) {
        // Игнорируем ошибки отправки из background
      }
    }
  } catch (_) {
    // Не ломаем background handler
  }
}

/// Извлекает call_id из данных FCM.
/// 
/// ПРИОРИТЕТ:
/// 1. call_id от сервера (уникальный для каждого звонка) — ЛУЧШИЙ вариант
/// 2. Fallback: генерируем на основе callerKey + timestamp (15 сек окно)
/// 
/// ВАЖНО: Сервер должен передавать call_id в FCM data!
/// Это единственный способ гарантировать что повторный звонок не будет проигнорирован.
String _extractOrGenerateCallId(Map<String, dynamic> data, String callerKey) {
  // 1. Пробуем получить call_id от сервера
  final serverCallId = data['call_id'] ?? data['callId'] ?? data['id'];
  if (serverCallId != null && 
      serverCallId.toString().isNotEmpty && 
      serverCallId.toString().toLowerCase() != 'null') {
    return serverCallId.toString();
  }
  
  // 2. Fallback: генерируем на основе callerKey
  // Используем 15-секундное окно — достаточно для дедупликации WS/FCM,
  // но не блокирует быстрый перезвон
  final hash = callerKey.hashCode.abs();
  final timeWindow = DateTime.now().millisecondsSinceEpoch ~/ 15000; // 15 секунд
  return 'call-${hash.toRadixString(16).padLeft(8, '0')}-$timeWindow';
}

/// Показать нативный UI входящего звонка
/// Работает даже когда приложение убито!
/// 
/// ВАЖНО: Этот код выполняется в ОТДЕЛЬНОМ isolate!
/// Нельзя использовать синглтоны из main isolate (включая IncomingCallBuffer).
/// Все данные передаём через CallKit extra.
/// 
/// АРХИТЕКТУРНОЕ ОГРАНИЧЕНИЕ (E2E encryption):
/// Сервер не хранит имена контактов — они только на устройстве клиента.
/// При killed app CallKit показывает первые 8 символов публичного ключа (caller_name из FCM).
/// После открытия CallScreen имя загружается из локальной БД (_resolveContactName).
Future<void> _showNativeIncomingCall(Map<String, dynamic> data) async {
  try {
    final callerKey = data['caller_key'] ?? data['sender_pubkey'] ?? '';
    // Резолвим ЛОКАЛЬНОЕ имя контакта (как пользователь его назвал), а не префикс
    // ключа. Best-effort с таймаутом: если приложение живо и БД доступна — покажем
    // имя сразу на экране входящего; при killed-app/закрытой БД — фолбэк на
    // caller_name/префикс (сервер имён не знает; имя всё равно подтянется при
    // открытии CallScreen).
    final fallbackName =
        (data['caller_name'] ?? data['sender_name'] ?? callerKey.toString().substring(0, 8))
            .toString();
    String callerName = fallbackName;
    try {
      final contact = await DatabaseService.instance
          .getContact(callerKey.toString())
          .timeout(const Duration(seconds: 1));
      final localName = contact?.name.trim();
      if (localName != null && localName.isNotEmpty) callerName = localName;
    } catch (_) {}

    // Приватность на локскрине: если устройство заблокировано и в настройках НЕ
    // включён показ имени на локскрине — прячем личность звонящего за нейтральной
    // подписью (без имени и без префикса ключа). Имя появится на экране звонка
    // после разблокировки Orpheus.
    bool hideCallerIdentity = false;
    try {
      if (await DeviceSettingsService.hideCallerIdentityOnIncoming()) {
        hideCallerIdentity = true;
        callerName =
            (await NotificationService.notificationL10n()).incomingEncryptedCall;
      }
    } catch (_) {}

    // Используем call_id от сервера если есть, иначе генерируем
    // КРИТИЧНО: сервер должен передавать уникальный call_id для каждого звонка!
    final callId = _extractOrGenerateCallId(data, callerKey.toString());

    final canShow = await CallIdStorage.tryShowCallKitForPush(callId: callId);
    if (!canShow) {
      print("📞 CALLKIT FCM: callId=$callId уже активен, пропускаю показ");
      return;
    }
    
    // Проверяем, нет ли уже активного звонка
    // ВАЖНО: FCM и WebSocket могут генерировать РАЗНЫЕ callId для одного звонка!
    // Поэтому проверяем по callerKey, а не только по callId.
    try {
      // activeCalls() теперь возвращает List<CallKitParams> (callkit 3.x).
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls.isNotEmpty) {
        for (final call in activeCalls) {
          // Проверяем по callId
          if (call.id == callId) {
            print("📞 CALLKIT PUSH: Звонок с id=$callId уже показан, пропускаю дубликат");
            return;
          }
          // Проверяем по callerKey в extra — если тот же caller, значит дубль!
          final extra = call.extra;
          if (extra != null && extra['callerKey'] == callerKey.toString()) {
            print("📞 CALLKIT PUSH: Звонок от $callerKey уже показан (WS?), пропускаю дубликат");
            return;
          }
        }
        // Есть активный звонок от ДРУГОГО caller — закрываем и показываем новый
        print("📞 CALLKIT FCM: Закрываю старые звонки от другого caller, показываю новый (id=$callId)");
        await FlutterCallkitIncoming.endAllCalls();
      }
    } catch (e) {
      print("📞 CALLKIT: Error checking active calls: $e");
    }
    
    // Получаем SDP offer если есть
    // КРИТИЧНО: передаём его в extra, чтобы main isolate получил при accept
    String? offerDataJson;
    if (data['offer_data'] != null) {
      offerDataJson = data['offer_data'].toString();
    }

    // Кладём offer на диск по callId. При ответе с ЗАБЛОКИРОВАННОГО экрана main-изолят
    // стартует «с нуля», и native `extra` CallKit часто не доносит offer до свежего
    // listener'а -> отвечающий создавал СВОЙ offer вместо answer (glare, звонок не
    // соединялся). Теперь main-изолят достанет offer отсюда (см. main_callkit).
    // Это НЕ авто-открытие звонка — только хранилище offer (TTL + сверка callId).
    if (offerDataJson != null) {
      try {
        await PendingCallStorage.instance.cacheOffer(
          callId: callId,
          offerData: json.decode(offerDataJson) as Map<String, dynamic>,
        );
      } catch (e) {
        print("📞 CALLKIT: cacheOffer error: $e");
      }
    }

    print("📞 CALLKIT: Показываю входящий звонок от $callerName (id=$callId), hasOffer=${offerDataJson != null}");
    
    final l10n = await NotificationService.notificationL10n();

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Orpheus',
      handle: hideCallerIdentity ? '' : callerKey.toString().substring(0, 8),
      type: 0, // Audio call
      missedCallNotification: NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: l10n.missedCall,
        callbackText: l10n.callBack,
      ),
      duration: 45000, // 45 seconds ringtone
      extra: <String, dynamic>{
        'callerKey': callerKey,
        'offerData': offerDataJson,
        'callId': callId,
      },
      headers: <String, dynamic>{},
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0D0D0D',
        actionColor: '#6AD394',
        textColor: '#FFFFFF',
        // callkit 3.x: textAccept/textDecline переехали из CallKitParams в AndroidParams.
        textAccept: l10n.answerCall,
        textDecline: l10n.decline,
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
        isShowCallID: false,
        // ПРИМЕЧАНИЕ: false (heads-up вместо полноэкранного ринга) не помог обойти
        // плагинный requestDismissKeyguard — PIN оставался. Вернули true.
        isShowFullLockedScreen: true,
      ),
      ios: IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    print("📞 CALLKIT: UI звонка показан");
  } catch (e) {
    print("📞 CALLKIT ERROR: $e");
    await _showFallbackLocalCallNotification(data);
  }
}

Future<void> _showFallbackLocalCallNotification(Map<String, dynamic> data) async {
  try {
    final callerKey = data['caller_key'] ?? data['sender_pubkey'] ?? '';
    final callerName = data['caller_name'] ?? data['sender_name'] ?? callerKey.toString().substring(0, 8);
    final l10n = await NotificationService.notificationL10n();
    final plugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await plugin.initialize(settings: initSettings);

    const androidDetails = AndroidNotificationDetails(
      'incoming_calls_fallback',
      'Incoming calls (fallback)',
      channelDescription: 'Fallback notifications if CallKit failed to show',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      ticker: 'incoming_call',
    );
    const details = NotificationDetails(android: androidDetails);

    await plugin.show(
      id: 9901,
      title: l10n.incomingCall,
      body: l10n.fromCaller(callerName.toString()),
      notificationDetails: details,
      payload: json.encode(data),
    );
  } catch (_) {
    // best-effort
  }
}

class NotificationService {
  // Singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // ===== Local notifications backend (DI for unit tests) =====
  static NotificationLocalBackend? _localBackend;
  static bool _localInitialized = false;

  @visibleForTesting
  static void debugSetLocalBackendForTesting(NotificationLocalBackend? backend) {
    _localBackend = backend;
    _localInitialized = false;
  }

  /// Callbacks для обработки событий
  static Function(Map<String, dynamic> data)? onIncomingCallFromNotification;

  // ID каналов уведомлений
  // Сервер указывает этот channel_id в AndroidNotification.channel_id
  static const String _incomingCallChannelId = 'orpheus_incoming_call';
  // Legacy: old client channel (keep to not break existing user settings)
  static const String _legacyCallChannelId = 'orpheus_calls';
  static const String _callChannelName = 'Incoming calls';
  static const String _messageChannelId = 'orpheus_messages';
  static const String _messageChannelName = 'Messages';
  static const String _orpheusRoomId = 'orpheus';

  /// Android small icon for notifications.
  ///
  /// Important: DON'T use `ic_launcher` (often adaptive) — it causes "white square".
  /// Need a monochrome icon in `res/drawable`.
  static const String _androidSmallIcon = 'ic_stat_orpheus';

  // Notification IDs
  static const int _callNotificationId = 1001;
  static const int _messageNotificationId = 1002;

  /// Инициализация сервиса (только локальные уведомления — без Google/FCM).
  ///
  /// Пуши доставляются по WebSocket из фонового сервиса (PushConnectionService),
  /// а показ на экране — через flutter_local_notifications / flutter_callkit_incoming.
  Future<void> init() async {
    // 1. Инициализация локальных уведомлений
    await _ensureLocalNotificationsInitialized();

    // 1.1 Android 13+: запрос runtime permission на уведомления (best-effort).
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final status = await Permission.notification.request();
        DebugLogger.info('NOTIF', 'Android notification permission: $status');
      } catch (e) {
        DebugLogger.warn('NOTIF', 'Notification permission request failed: $e');
      }
    }
  }

  /// Инициализация локальных уведомлений
  static Future<void> _ensureLocalNotificationsInitialized() async {
    if (_localBackend == null) {
      _localBackend = PluginNotificationLocalBackend();
    }
    if (_localInitialized) return;

    // Создаём каналы уведомлений
    await _localBackend!.createAndroidChannel(
      id: _incomingCallChannelId,
      name: _callChannelName,
      description: 'Incoming call notifications',
      importance: Importance.max,
      ledColor: const Color(0xFF6AD394),
    );

    // Legacy канал (оставляем, чтобы не “пропали” старые настройки/каналы у пользователей).
    await _localBackend!.createAndroidChannel(
      id: _legacyCallChannelId,
      name: _callChannelName,
      description: 'Incoming call notifications (legacy)',
      importance: Importance.max,
      ledColor: const Color(0xFF6AD394),
    );

    await _localBackend!.createAndroidChannel(
      id: _messageChannelId,
      name: _messageChannelName,
      description: 'New message notifications',
      importance: Importance.high,
    );

    await _localBackend!.initialize(onTap: _onNotificationTap);

    _localInitialized = true;
    print("🔔 Local notifications initialized");
  }

  /// Обработка фоновых data-only сообщений
  static Future<void> _handleBackgroundMessage(Map<String, dynamic> data) async {
    // Обеспечиваем инициализацию локальных уведомлений
    await _ensureLocalNotificationsInitialized();

    final type = data['type'];

    // Сервер (FastAPI) сейчас шлёт:
    // - incoming_call: caller_name/caller_key
    // - new_message: sender_name/sender_key
    //
    // Оставляем совместимость со старыми call/message.
    final l10n = await notificationL10n();
    final callerName = (data['caller_name'] ?? data['sender_name'] ?? l10n.unknownCaller).toString();
    final senderName = (data['sender_name'] ??
            data['caller_name'] ??
            data['sender'] ??
            data['from'] ??
            'Developer')
        .toString();

    if (type == 'incoming_call' || type == 'call') {
      await showCallNotification(
        callerName: callerName,
        payload: json.encode(data),
      );
    } else if (type == 'new_message' || type == 'message' || type == 'support-reply') {
      await showMessageNotification(senderName: senderName);
    } else if (type == 'room-message' || type == 'room_message') {
      final roomId = data['room_id']?.toString();
      final roomName = (data['room_name'] ?? 'Chat').toString();
      final authorType = data['author_type']?.toString();
      if (roomId == _orpheusRoomId && authorType == 'orpheus') {
        final enabled =
            await NotificationPrefsService.isOrpheusOfficialEnabled();
        if (!enabled) return;
        await showOrpheusOfficialNotification();
      } else {
        await showRoomMessageNotification(roomName: roomName);
      }
    }
  }

  @visibleForTesting
  static Future<void> debugHandleBackgroundMessageForTesting(Map<String, dynamic> data) {
    return _handleBackgroundMessage(data);
  }

  /// Решение: показывать ли локальное уведомление в background handler.
  ///
  /// Если FCM уже содержит `notification` payload — локальное не показываем (иначе теряется звук/дублируется).
  @visibleForTesting
  static bool shouldShowLocalNotification({
    required bool hasNotificationPayload,
    required Map<String, dynamic> data,
  }) {
    if (hasNotificationPayload) return false;
    final type = data['type'];
    return type == 'incoming_call' ||
        type == 'call' ||
        type == 'new_message' ||
        type == 'message' ||
        type == 'room-message' ||
        type == 'room_message' ||
        type == 'support-reply';
  }

  /// Обработка клика по локальному уведомлению
  static void _onNotificationTap(NotificationResponse response) {
    print('🔔 Local notification tap: ${response.payload}');
    try {
      if (response.payload == null || response.payload!.isEmpty) return;
      final data = json.decode(response.payload!) as Map<String, dynamic>;
      onIncomingCallFromNotification?.call(data);
    } catch (_) {}
  }

  // ==================== ПУБЛИЧНЫЕ МЕТОДЫ ====================

  /// Локализация для строк уведомлений.
  ///
  /// Уведомления показываются из фонового сервисного изолята, где нет `BuildContext`,
  /// поэтому язык резолвим по сохранённому выбору пользователя (`app_locale`,
  /// пишется `LocaleService`), с откатом на системную локаль, затем на английский.
  /// Так RU-пользователь получает русские уведомления, EN — английские.
  /// Нейтральная подпись входящего звонка для локскрина (без имени/ключа).
  /// Публичная обёртка над локализацией — чтобы другие сервисы (WS-путь показа
  /// CallKit) не лезли к @visibleForTesting notificationL10n напрямую.
  static Future<String> incomingEncryptedCallLabel() async =>
      (await notificationL10n()).incomingEncryptedCall;

  @visibleForTesting
  static Future<L10n> notificationL10n() async {
    String code;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('app_locale');
      if (saved != null && saved.isNotEmpty) {
        code = saved;
      } else {
        code = ui.PlatformDispatcher.instance.locale.languageCode == 'ru' ? 'ru' : 'en';
      }
    } catch (_) {
      code = 'en';
    }
    return lookupL10n(Locale(code));
  }

  /// Показать уведомление о входящем звонке
  /// Простое, без кнопок, со звуком и вибрацией
  static Future<void> showCallNotification({
    required String callerName,
    String? payload,
  }) async {
    try {
      await _ensureLocalNotificationsInitialized();
      final l10n = await notificationL10n();

      await _localBackend!.show(
        id: _callNotificationId,
        channelId: _incomingCallChannelId,
        channelName: _callChannelName,
        title: l10n.incomingCall,
        body: callerName,
        category: AndroidNotificationCategory.call,
        androidSmallIcon: _androidSmallIcon,
        fullScreenIntent: true,
        ongoing: true,
        payload: payload,
      );

      print("🔔 Call notification shown: $callerName");
      DebugLogger.success('NOTIF', '🔔 Call notification shown: $callerName');
    } catch (e) {
      print("🔔 showCallNotification error: $e");
      DebugLogger.error('NOTIF', 'showCallNotification error: $e');
    }
  }

  /// Скрыть уведомление о звонке
  static Future<void> hideCallNotification() async {
    try {
      await _localBackend?.cancel(_callNotificationId);
      print("🔔 Call notification hidden");
      DebugLogger.info('NOTIF', '🔔 Уведомление о звонке скрыто');
    } catch (e) {
      // ProGuard/R8 может вызывать ошибки с Gson TypeToken
      // Логируем но не бросаем исключение
      print("🔔 hideCallNotification error (ignored): $e");
      DebugLogger.warn('NOTIF', 'hideCallNotification ошибка (игнорируем): $e');
    }
  }

  /// Показать уведомление о новом сообщении
  /// Содержимое сообщения НЕ показывается для приватности
  static Future<void> showMessageNotification({
    required String senderName,
  }) async {
    try {
      await _ensureLocalNotificationsInitialized();
      final l10n = await notificationL10n();

      await _localBackend!.show(
        id: _messageNotificationId + senderName.hashCode % 1000, // Уникальный ID для разных отправителей
        channelId: _messageChannelId,
        channelName: _messageChannelName,
        title: senderName,
        body: l10n.newMessage, // Don't show content for privacy
        category: AndroidNotificationCategory.message,
        androidSmallIcon: _androidSmallIcon,
        groupKey: 'orpheus_messages_group',
        ongoing: false,
        fullScreenIntent: false,
      );

      print("🔔 Message notification shown: $senderName");
      DebugLogger.success('NOTIF', '📩 Показано уведомление: $senderName');
    } catch (e) {
      print("🔔 showMessageNotification error: $e");
      DebugLogger.error('NOTIF', 'showMessageNotification ошибка: $e');
    }
  }

  /// Показать уведомление о новом сообщении в чате.
  static Future<void> showRoomMessageNotification({
    required String roomName,
  }) async {
    try {
      await _ensureLocalNotificationsInitialized();
      final l10n = await notificationL10n();

      await _localBackend!.show(
        id: _messageNotificationId + roomName.hashCode % 1000,
        channelId: _messageChannelId,
        channelName: _messageChannelName,
        title: roomName,
        body: l10n.newMessageInChat,
        category: AndroidNotificationCategory.message,
        androidSmallIcon: _androidSmallIcon,
        groupKey: 'orpheus_messages_group',
        ongoing: false,
        fullScreenIntent: false,
      );

      DebugLogger.success('NOTIF', '💬 Чат-уведомление: $roomName');
    } catch (e) {
      DebugLogger.error('NOTIF', 'showRoomMessageNotification ошибка: $e');
    }
  }

  /// Show "Official Orpheus reply" notification.
  static Future<void> showOrpheusOfficialNotification() async {
    try {
      await _ensureLocalNotificationsInitialized();
      final l10n = await notificationL10n();

      await _localBackend!.show(
        id: _messageNotificationId + 999,
        channelId: _messageChannelId,
        channelName: _messageChannelName,
        title: 'Orpheus',
        body: l10n.officialOrpheusReply,
        category: AndroidNotificationCategory.message,
        androidSmallIcon: _androidSmallIcon,
        groupKey: 'orpheus_messages_group',
        ongoing: false,
        fullScreenIntent: false,
      );

      DebugLogger.success('NOTIF', '📩 Official Orpheus reply');
    } catch (e) {
      DebugLogger.error('NOTIF', 'showOrpheusOfficialNotification error: $e');
    }
  }

  /// Скрыть все уведомления о сообщениях
  static Future<void> hideMessageNotifications() async {
    try {
      await _localBackend?.cancelAll();
      print("🔔 All notifications hidden");
    } catch (e) {
      print("🔔 hideMessageNotifications error (ignored): $e");
      DebugLogger.warn('NOTIF', 'hideMessageNotifications ошибка: $e');
    }
  }

  /// Показать тестовое уведомление
  static Future<void> showTestNotification() async {
    await _ensureLocalNotificationsInitialized();
    final l10n = await notificationL10n();

    await _localBackend!.show(
      id: 9999,
      channelId: _messageChannelId,
      channelName: _messageChannelName,
      title: 'Orpheus',
      body: l10n.testNotificationWorks,
      category: AndroidNotificationCategory.message,
      androidSmallIcon: _androidSmallIcon,
      groupKey: null,
      ongoing: false,
      fullScreenIntent: false,
    );

    print("🔔 Test notification shown");
  }
}

/// Минимальный интерфейс для локальных уведомлений (DI для unit-тестов).
abstract class NotificationLocalBackend {
  Future<void> createAndroidChannel({
    required String id,
    required String name,
    required String description,
    required Importance importance,
    Color? ledColor,
  });

  Future<void> initialize({required void Function(NotificationResponse response) onTap});

  Future<void> show({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    required AndroidNotificationCategory category,
    required String androidSmallIcon,
    required bool fullScreenIntent,
    required bool ongoing,
    String? groupKey,
    String? payload,
  });

  Future<void> cancel(int id);
  Future<void> cancelAll();
}

class PluginNotificationLocalBackend implements NotificationLocalBackend {
  PluginNotificationLocalBackend({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> createAndroidChannel({
    required String id,
    required String name,
    required String description,
    required Importance importance,
    Color? ledColor,
  }) async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        id,
        name,
        description: description,
        importance: importance,
        playSound: true,
        enableVibration: true,
        enableLights: ledColor != null,
        ledColor: ledColor,
      ),
    );
  }

  @override
  Future<void> initialize({required void Function(NotificationResponse response) onTap}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(NotificationService._androidSmallIcon),
      ),
      onDidReceiveNotificationResponse: onTap,
    );
  }

  @override
  Future<void> show({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    required AndroidNotificationCategory category,
    required String androidSmallIcon,
    required bool fullScreenIntent,
    required bool ongoing,
    String? groupKey,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: category == AndroidNotificationCategory.call ? Importance.max : Importance.high,
      priority: category == AndroidNotificationCategory.call ? Priority.max : Priority.high,
      category: category,
      icon: androidSmallIcon,
      fullScreenIntent: fullScreenIntent,
      ongoing: ongoing,
      autoCancel: !ongoing,
      showWhen: category != AndroidNotificationCategory.call,
      enableVibration: true,
      playSound: true,
      groupKey: groupKey,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
