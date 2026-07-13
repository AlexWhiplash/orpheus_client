import 'dart:convert';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/call_id_storage.dart';
import 'package:orpheus_project/services/device_settings_service.dart';
import 'package:orpheus_project/services/notification_service.dart';

abstract interface class IncomingMessageCrypto {
  /// Расшифровка: [senderEncKeyBase64] — X25519 enc-ключ отправителя (НЕ адрес!).
  Future<String> decrypt(String senderEncKeyBase64, String encryptedPayload);

  /// Проверка самоподписи связки адрес<->enc отправителя (Ed25519).
  Future<bool> verifyIdentityBundle(String address, String enc, String sig);
}

abstract interface class IncomingMessageDatabase {
  Future<void> addMessage(ChatMessage message, String contactPublicKey);
  Future<void> addContactIfMissing(String publicKey, {String? encryptionKey});
  Future<bool> isContact(String publicKey);
  Future<String?> getContactEncryptionKey(String publicKey);
  Future<String?> getContactName(String publicKey);
  Future<int> deleteMessagesByTimestamps(String contactKey, List<int> timestamps);
  Future<int> deleteMessagesByMessageIds(String contactKey, List<String> messageIds);
  Future<bool> messageExistsByMessageId(String contactKey, String messageId);
}

abstract interface class IncomingMessageNotifications {
  Future<void> showCallNotification({required String callerName, String? payload});
  Future<void> hideCallNotification();
  Future<void> showMessageNotification();
}

typedef OpenCallScreen = void Function({
  required String contactPublicKey,
  required Map<String, dynamic> offer,
  String? callId,
});

/// Единая точка обработки входящих WS сообщений.
///
/// Цель: чтобы поведение было зафиксировано тестами, а `main.dart` был тонкой обвязкой.
class IncomingMessageHandler {
  IncomingMessageHandler({
    required IncomingMessageCrypto crypto,
    required IncomingMessageDatabase database,
    required IncomingMessageNotifications notifications,
    required IncomingCallBuffer callBuffer,
    required OpenCallScreen openCallScreen,
    required void Function(Map<String, dynamic> msg) emitSignaling,
    required void Function(String senderPublicKey) emitChatUpdate,
    required bool Function() isAppInForeground,
    bool Function()? isCallActive,
    int Function()? nowMs,
  })  : _crypto = crypto,
        _db = database,
        _notif = notifications,
        _callBuffer = callBuffer,
        _openCallScreen = openCallScreen,
        _emitSignaling = emitSignaling,
        _emitChatUpdate = emitChatUpdate,
        _isAppInForeground = isAppInForeground,
        _isCallActive = (isCallActive ?? (() => false)),
        _nowMs = (nowMs ?? (() => DateTime.now().millisecondsSinceEpoch));

  final IncomingMessageCrypto _crypto;
  final IncomingMessageDatabase _db;
  final IncomingMessageNotifications _notif;
  final IncomingCallBuffer _callBuffer;
  final OpenCallScreen _openCallScreen;
  final void Function(Map<String, dynamic> msg) _emitSignaling;
  final void Function(String senderPublicKey) _emitChatUpdate;
  final bool Function() _isAppInForeground;
  final bool Function() _isCallActive;
  final int Function() _nowMs;

  // Анти-спам/анти-дубликаты для call-offer: на некоторых сетях/устройствах возможны повторы.
  final Map<String, int> _lastCallOfferHandledAtMsBySender = {};
  static const int _callOfferDebounceMs = 2500;
  static const int _callOfferTtlMs = 60 * 1000;

  // Анти-дубликаты для chat: защита от повторной доставки при reconnect/offline delivery.
  final Map<String, int> _lastChatTimestampBySender = {};
  static const int _chatDedupeWindowMs = 5000;

  static const _ignoredTypes = <String>{
    'error',
    'payment-confirmed',
    'license-status',
    'pong',
    'presence-state',
    'presence-update',
  };

  // Teardown-сигналы завершения звонка — НЕ гейтим строгим mutual-add (см. handleDecoded):
  // без payload, звонок не поднимают, только завершают; гарантируют, что активный
  // звонок всегда можно закрыть быстро (иначе — zombie-call до ICE-таймаута).
  static const _callTeardownTypes = <String>{'hang-up', 'call-rejected'};

  Future<void> handleRawMessage(String messageJson) async {
    final dynamic decoded = json.decode(messageJson);
    if (decoded is! Map<String, dynamic>) return;
    await handleDecoded(decoded);
  }

  Future<void> handleDecoded(Map<String, dynamic> messageData) async {
    final type = messageData['type'] as String?;
    final senderKey = messageData['sender_pubkey'] as String?;

    if (type == 'support-reply') {
      if (!_isAppInForeground()) {
        await _notif.showMessageNotification();
      }
      return;
    }

    // Пропускаем служебные сообщения и любые пакеты без sender_pubkey.
    if (type == null || senderKey == null || _ignoredTypes.contains(type)) return;

    // Строгий mutual-add: сообщения/звонки принимаем ТОЛЬКО от добавленных контактов.
    // Не-контакты дропаем целиком (без расшифровки, без показа, без авто-добавления).
    // Исключение — teardown-сигналы завершения звонка (_callTeardownTypes): их пропускаем,
    // чтобы активный звонок всегда можно было закрыть (реальное закрытие всё равно
    // фильтруется по пиру в CallScreen). Комнаты/Оракул сюда не приходят (свои пути).
    if (!_callTeardownTypes.contains(type) && !await _db.isContact(senderKey)) {
      DebugLogger.info('SECURITY', 'Дроп $type от не-контакта (строгий mutual-add)');
      return;
    }

    // === ЗВОНКИ ===
    if (type == 'call-offer') {
      final data = messageData['data'];
      if (data is! Map<String, dynamic>) return;

      // 1) TTL (backward-compatible): если сервер прислал server_ts_ms и он слишком старый — игнорируем.
      final now = _nowMs();
      final dynamic tsRaw = messageData['server_ts_ms'] ?? data['server_ts_ms'];
      final int? serverTsMs = tsRaw is int ? tsRaw : int.tryParse(tsRaw?.toString() ?? '');
      if (serverTsMs != null && (now - serverTsMs) > _callOfferTtlMs) {
        return;
      }

      // 2) Если уже есть активный звонок/экран — не поднимаем второй входящий (иначе "пачка" экранов).
      if (_isCallActive()) {
        return;
      }

      // 3) Дедуп по sender (короткое окно): защита от дублей при выходе из оффлайна/повторной доставке.
      final last = _lastCallOfferHandledAtMsBySender[senderKey];
      if (last != null && (now - last) < _callOfferDebounceMs) {
        return;
      }
      _lastCallOfferHandledAtMsBySender[senderKey] = now;

      // ВАЖНО: не очищаем уже пришедшие кандидаты (если они пришли раньше offer).
      _callBuffer.ensure(senderKey);

      final contactName = (await _db.getContactName(senderKey))?.trim();
      final displayName = (contactName != null && contactName.isNotEmpty)
          ? contactName
          : senderKey.substring(0, 8);

      // Единый call_id для корреляции
      final callId = CallIdStorage.extractCallId(data, senderKey);

      // Дедуп по call_id (особенно важно при WS+FCM в фоне)
      final canShow = await CallIdStorage.trySetActiveCall(
        callId: callId,
        source: CallIdStorage.sourceWebSocket,
      );
      if (!canShow) {
        DebugLogger.info('CALL', '📞 call_id уже активен, пропускаю WS звонок',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
        return;
      }

      // Сохраняем данные звонка в буфер (fallback для CallKit)
      _callBuffer.setLastIncomingCall(senderKey, data);
      
      // Если приложение в foreground — открываем CallScreen напрямую
      // Если в background — показываем нативный CallKit UI
      if (_isAppInForeground()) {
        DebugLogger.info('CALL', '📞 Foreground: открываю CallScreen напрямую',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
        _openCallScreen(contactPublicKey: senderKey, offer: data, callId: callId);
      } else {
        DebugLogger.info('CALL', '📞 Background: показываю CallKit UI',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
        // Показываем ТОЛЬКО нативный CallKit-входящий. Раньше здесь ДОПОЛНИТЕЛЬНО
        // показывалось fullScreenIntent-уведомление как "фолбек" — но на локскрине
        // оно само запускало активити и открывало ВТОРОЙ экран звонка (задвоение),
        // да ещё и с реальным именем в обход приват-гейта. CallKit показывает
        // входящий надёжно (в т.ч. поверх локскрина) и применяет приват-подпись.
        await _showCallKitIncoming(
          callerName: displayName,
          callerKey: senderKey,
          offerData: data,
        );
      }
      return;
    }

    if (type == 'ice-candidate') {
      // Всегда буферизуем (кандидаты могут прийти раньше offer).
      _callBuffer.add(senderKey, messageData);
      final callId = CallIdStorage.extractCallId(
          messageData['data'] is Map<String, dynamic>
              ? (messageData['data'] as Map<String, dynamic>)
              : messageData,
          senderKey);
      DebugLogger.info('CALL', '📥 ICE candidate', context: {
        'call_id': callId,
        'peer_pubkey': senderKey,
      });
      _emitSignaling(messageData);
      return;
    }

    if (type == 'call-answer') {
      final callId = CallIdStorage.extractCallId(
          messageData['data'] is Map<String, dynamic>
              ? (messageData['data'] as Map<String, dynamic>)
              : messageData,
          senderKey);
      DebugLogger.info('CALL', '📥 call-answer', context: {
        'call_id': callId,
        'peer_pubkey': senderKey,
      });
      _emitSignaling(messageData);
      return;
    }

    // ICE restart signals - пробрасываем в CallScreen для renegotiation
    if (type == 'ice-restart' || type == 'ice-restart-answer') {
      final callId = CallIdStorage.extractCallId(
          messageData['data'] is Map<String, dynamic>
              ? (messageData['data'] as Map<String, dynamic>)
              : messageData,
          senderKey);
      DebugLogger.info('CALL', '📥 ICE restart signal', context: {
        'call_id': callId,
        'peer_pubkey': senderKey,
        'type': type,
      });
      _emitSignaling(messageData);
      return;
    }

    if (type == 'hang-up' || type == 'call-rejected') {
      _callBuffer.clear(senderKey);
      _lastCallOfferHandledAtMsBySender.remove(senderKey);
      final callId = CallIdStorage.extractCallId(
          messageData['data'] is Map<String, dynamic>
              ? (messageData['data'] as Map<String, dynamic>)
              : messageData,
          senderKey);
      DebugLogger.info('CALL', '📥 $type', context: {
        'call_id': callId,
        'peer_pubkey': senderKey,
      });

      // КРИТИЧНО: сначала сообщаем в CallScreen, затем пытаемся спрятать уведомления.
      _emitSignaling(messageData);
      await _notif.hideCallNotification();
      
      // Скрываем нативный UI звонка (CallKit) если он был показан
      try {
        await FlutterCallkitIncoming.endAllCalls();
        DebugLogger.info('CALL', 'CallKit UI скрыт (hang-up/rejected)',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
      } catch (e) {
        DebugLogger.warn('CALL', 'Error hiding CallKit: $e',
            context: {'call_id': callId, 'peer_pubkey': senderKey});
      }
      // Освобождаем активный call_id: звонок завершён собеседником ДО ответа
      // (CallScreen мог не открыться, dispose не сработает) — иначе следующий
      // звонок отклонится как "занято" до истечения TTL 15с.
      await CallIdStorage.clear();
      return;
    }

    // === DELETE FOR BOTH ===
    if (type == 'delete-for-both') {
      // Предпочитаем стабильные messageId; timestamps_ms — fallback для старых клиентов
      // (по времени приёма матч не срабатывал у получателя — аудит LOGIC-2).
      final ids = messageData['message_ids'];
      if (ids is List && ids.isNotEmpty) {
        final idList = ids.map((e) => '$e').where((s) => s.isNotEmpty).toList();
        if (idList.isNotEmpty) {
          await _db.deleteMessagesByMessageIds(senderKey, idList);
          _emitChatUpdate(senderKey);
          return;
        }
      }
      final timestamps = messageData['timestamps_ms'];
      if (timestamps is List && timestamps.isNotEmpty) {
        final tsInts = timestamps.map((e) => e is int ? e : int.tryParse('$e') ?? 0).where((t) => t > 0).toList();
        if (tsInts.isNotEmpty) {
          await _db.deleteMessagesByTimestamps(senderKey, tsInts.cast<int>());
          _emitChatUpdate(senderKey);
        }
      }
      return;
    }

    // === ЧАТ ===
    if (type == 'chat') {
      final payload = messageData['payload'] as String?;
      if (payload == null) return;

      final messageId = messageData['message_id'] as String?;

      if (messageId != null && messageId.isNotEmpty) {
        // Точный дедуп по стабильному id: пропускаем только НАСТОЯЩИЙ дубль
        // (двойная доставка WS + offline), а не любое сообщение в 5-сек окне,
        // из-за чего терялись быстрые подряд сообщения (аудит LOGIC-1).
        if (await _db.messageExistsByMessageId(senderKey, messageId)) {
          return;
        }
      } else {
        // Старый клиент без message_id — fallback на прежнее окно дедупа
        // от двойной доставки WS + offline_messages на реконнекте.
        final now = _nowMs();
        final lastTs = _lastChatTimestampBySender[senderKey];
        if (lastTs != null && (now - lastTs) < _chatDedupeWindowMs) {
          return;
        }
        _lastChatTimestampBySender[senderKey] = now;
      }

      // senderKey — это Ed25519-АДРЕС; для ECDH нужен X25519 enc-ключ отправителя.
      // Берём inline-bundle из сообщения (senc/ssig, verified) или сохранённый у контакта.
      final senc = messageData['senc'] as String?;
      final ssig = messageData['ssig'] as String?;
      String? encKey;
      if (senc != null && senc.isNotEmpty && ssig != null && ssig.isNotEmpty) {
        if (await _crypto.verifyIdentityBundle(senderKey, senc, ssig)) {
          encKey = senc;
        } else {
          DebugLogger.warn('CHAT', 'inline-bundle отправителя не прошёл проверку подписи');
        }
      }
      encKey ??= await _db.getContactEncryptionKey(senderKey);
      if (encKey == null || encKey.isEmpty) {
        DebugLogger.warn('CHAT', 'Нет enc-ключа отправителя — сообщение не расшифровать');
        return;
      }

      final decryptedMessage = await _crypto.decrypt(encKey, payload);

      final receivedMessage = ChatMessage(
        messageId: messageId,
        text: decryptedMessage,
        isSentByMe: false,
        status: MessageStatus.delivered,
        isRead: false,
      );

      // Авто-добавляем неизвестного отправителя в контакты (и запоминаем его enc-ключ),
      // иначе сообщение сохранится, но не появится в списке чатов (аудит DB-6).
      await _db.addContactIfMissing(senderKey, encryptionKey: encKey);
      await _db.addMessage(receivedMessage, senderKey);
      _emitChatUpdate(senderKey);

      final isCallStatusMessage = _isCallStatusMessage(decryptedMessage);
      if (!_isAppInForeground() && !isCallStatusMessage) {
        // Обезличенное уведомление — без отправителя (приватность на локскрине).
        await _notif.showMessageNotification();
      }
    }
  }

  static bool _isCallStatusMessage(String message) {
    const callStatusMessages = [
      'Outgoing call',
      'Incoming call',
      'Missed call',
      // Legacy Russian (backward compatibility with older clients)
      'Исходящий звонок',
      'Входящий звонок',
      'Пропущен звонок',
    ];
    return callStatusMessages.contains(message);
  }

  static const String _supportSenderLabel = 'Developer';

  /// Показать нативный CallKit UI для входящего звонка
  /// 
  /// ВАЖНО: Когда приложение свёрнуто, Flutter engine может быть suspended.
  /// Для надёжной работы сервер также отправляет FCM push параллельно.
  Future<void> _showCallKitIncoming({
    required String callerName,
    required String callerKey,
    required Map<String, dynamic> offerData,
  }) async {
    // Используем call_id от сервера если есть, иначе генерируем
    // КРИТИЧНО: сервер передаёт уникальный call_id для каждого звонка!
    final callId = _extractOrGenerateCallId(offerData, callerKey);
    
    // Проверяем, нет ли уже активного звонка
    // ВАЖНО: FCM и WebSocket могут генерировать РАЗНЫЕ callId для одного звонка!
    // Поэтому проверяем по callerKey, а не по callId.
    try {
      // activeCalls() теперь возвращает List<CallKitParams> (callkit 3.x).
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls.isNotEmpty) {
        for (final call in activeCalls) {
          // Проверяем по callId
          if (call.id == callId) {
            DebugLogger.info('CALL', '📞 CallKit с id=$callId уже показан, пропускаю дубликат',
                context: {'call_id': callId, 'peer_pubkey': callerKey});
            return;
          }
          // Проверяем по callerKey в extra — если тот же caller, значит дубль!
          final extra = call.extra;
          if (extra != null && extra['callerKey'] == callerKey) {
            DebugLogger.info('CALL', '📞 CallKit для $callerKey уже показан, пропускаю WS дубликат',
                context: {'call_id': callId, 'peer_pubkey': callerKey});
            return;
          }
        }
        // Есть активный звонок от ДРУГОГО caller — закрываем и показываем новый
        DebugLogger.info('CALL', '📞 Закрываю старые CallKit звонки от другого caller, показываю новый (id=$callId)',
            context: {'call_id': callId, 'peer_pubkey': callerKey});
        await FlutterCallkitIncoming.endAllCalls();
      }
    } catch (e) {
      DebugLogger.warn('CALL', 'Error checking active calls: $e',
          context: {'call_id': callId, 'peer_pubkey': callerKey});
    }
    
    // Приватность на локскрине: заблокировано + флаг выключен -> нейтральная
    // подпись без имени/ключа (имя появится на экране звонка после разблокировки).
    String displayName = callerName;
    bool hideCallerIdentity = false;
    try {
      if (await DeviceSettingsService.hideCallerIdentityOnIncoming()) {
        hideCallerIdentity = true;
        displayName = await NotificationService.incomingEncryptedCallLabel();
      }
    } catch (_) {}

    final params = CallKitParams(
      id: callId,
      nameCaller: displayName,
      appName: 'Orpheus',
      handle: hideCallerIdentity ? '' : callerKey.substring(0, 8),
      type: 0, // Audio call
      duration: 45000, // 45 секунд рингтон (больше времени на ответ)
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      extra: <String, dynamic>{
        'callerKey': callerKey,
        'offerData': json.encode(offerData),
        'callId': callId,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0D0D0D',
        actionColor: '#6AD394',
        textColor: '#FFFFFF',
        // callkit 3.x: textAccept/textDecline теперь в AndroidParams.
        textAccept: 'Answer',
        textDecline: 'Decline',
        // ПРИМЕЧАНИЕ: пробовали false (heads-up вместо полноэкранного ринга, чтобы
        // обойти плагинный requestDismissKeyguard) — не помогло, PIN оставался на
        // обоих устройствах, а UX входящего стал хуже. Вернули true. Ответ на
        // заблокированном телефоне остаётся нерешённым на уровне плагина/keyguard.
        isShowFullLockedScreen: true,
        // КРИТИЧНО для пробуждения устройства:
        isImportant: true,
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
      ),
    );
    
    await FlutterCallkitIncoming.showCallkitIncoming(params);
    DebugLogger.info('CALL', '📱 CallKit UI показан для $callerName (id=$callId)');
  }
  
  /// Извлекает call_id из данных или генерирует стабильный callId.
  /// 
  /// ПРИОРИТЕТ:
  /// 1. call_id от сервера (уникальный для каждого звонка) — ЛУЧШИЙ вариант
  /// 2. Fallback: генерируем на основе callerKey + timestamp (15 сек окно)
  static String _extractOrGenerateCallId(Map<String, dynamic> data, String callerKey) {
    // 1. Пробуем получить call_id от сервера
    final serverCallId = data['call_id'] ?? data['callId'] ?? data['id'];
    if (serverCallId != null && 
        serverCallId.toString().isNotEmpty && 
        serverCallId.toString().toLowerCase() != 'null') {
      return serverCallId.toString();
    }
    
    // 2. Fallback: генерируем на основе callerKey
    final hash = callerKey.hashCode.abs();
    final timeWindow = DateTime.now().millisecondsSinceEpoch ~/ 15000; // 15 секунд
    return 'call-${hash.toRadixString(16).padLeft(8, '0')}-$timeWindow';
  }
}


