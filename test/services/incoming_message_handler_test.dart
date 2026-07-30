import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';
import 'package:orpheus_project/services/incoming_message_handler.dart';

class _FakeCrypto implements IncomingMessageCrypto {
  _FakeCrypto(this._decryptFn);
  final Future<String> Function(String sender, String payload) _decryptFn;

  @override
  Future<String> decrypt(String senderEncKeyBase64, String encryptedPayload) {
    return _decryptFn(senderEncKeyBase64, encryptedPayload);
  }

  @override
  Future<bool> verifyIdentityBundle(String address, String enc, String sig) async => true;
}

class _FakeDb implements IncomingMessageDatabase {
  final Map<String, String> contactNames = {};
  final Map<String, String> contactEncKeys = {};
  final List<(ChatMessage message, String contactKey)> saved = [];

  final Set<String> ensuredContacts = {};

  // Строгий mutual-add: по умолчанию считаем всех контактами (чтобы прежние тесты
  // работали); отдельные тесты выставляют contactsAllowAll=false + contacts.
  bool contactsAllowAll = true;
  final Set<String> contacts = {};

  @override
  Future<bool> isContact(String publicKey) async =>
      contactsAllowAll || contacts.contains(publicKey);

  @override
  Future<void> addMessage(ChatMessage message, String contactPublicKey) async {
    saved.add((message, contactPublicKey));
  }

  @override
  Future<void> addContactIfMissing(String publicKey, {String? encryptionKey}) async {
    ensuredContacts.add(publicKey);
    contacts.add(publicKey);
    if (encryptionKey != null) contactEncKeys[publicKey] = encryptionKey;
  }

  @override
  Future<String?> getContactEncryptionKey(String publicKey) async {
    // Возвращаем не-null, чтобы chat-декрипт в тестах проходил (fake decrypt ключ игнорирует).
    return contactEncKeys[publicKey] ?? 'fake-enc';
  }

  /// Запросы имени: под duress-гейтом их быть не должно вообще (имя резолвится
  /// только ПОСЛЕ строгого mutual-add).
  final List<String> nameLookups = [];

  @override
  Future<String?> getContactName(String publicKey) async {
    nameLookups.add(publicKey);
    return contactNames[publicKey];
  }

  @override
  Future<int> deleteMessagesByTimestamps(String contactKey, List<int> timestamps) async {
    return timestamps.length;
  }

  @override
  Future<int> deleteMessagesByMessageIds(String contactKey, List<String> messageIds) async {
    return messageIds.length;
  }

  @override
  Future<bool> messageExistsByMessageId(String contactKey, String messageId) async {
    return saved.any((e) => e.$1.messageId == messageId && e.$2 == contactKey);
  }
}

class _FakeNotif implements IncomingMessageNotifications {
  final List<String> calls = [];

  @override
  Future<void> showCallNotification({required String callerName, String? payload}) async {
    calls.add('showCall:$callerName');
  }

  @override
  Future<void> hideCallNotification() async {
    calls.add('hideCall');
  }

  @override
  Future<void> showMessageNotification() async {
    calls.add('showMsg');
  }
}

void main() {
  group('IncomingMessageHandler', () {
    setUp(() {
      IncomingCallBuffer.instance.clearAll();
    });

    test('игнорирует пакеты без sender_pubkey и служебные типы', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb();
      final notif = _FakeNotif();
      final signaling = <Map<String, dynamic>>[];
      final chatUpdates = <String>[];

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'x'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {
          fail('openCallScreen не должен вызываться');
        },
        emitSignaling: signaling.add,
        emitChatUpdate: chatUpdates.add,
        isAppInForeground: () => true,
      );

      await handler.handleDecoded({'type': 'pong'});
      await handler.handleDecoded({'type': 'license-status', 'status': 'active'});
      await handler.handleDecoded({'type': 'chat', 'payload': 'p'}); // sender_pubkey отсутствует

      expect(signaling, isEmpty);
      expect(chatUpdates, isEmpty);
      expect(notif.calls, isEmpty);
      expect(db.saved, isEmpty);
    });

    test('строгий mutual-add: сообщение и звонок от не-контакта дропаются', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb()
        ..contactsAllowAll = false
        ..contacts.add('FRIEND');
      final notif = _FakeNotif();
      final signaling = <Map<String, dynamic>>[];
      final chatUpdates = <String>[];
      var openedCall = false;

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, payload) async => payload),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {
          openedCall = true;
        },
        emitSignaling: signaling.add,
        emitChatUpdate: chatUpdates.add,
        isAppInForeground: () => true,
      );

      // Не-контакт: и chat, и call-offer дропаются целиком (без сохранения/показа/авто-добавления).
      await handler.handleDecoded(
          {'type': 'chat', 'sender_pubkey': 'STRANGER', 'payload': 'hi', 'message_id': 'm1'});
      await handler.handleDecoded(
          {'type': 'call-offer', 'sender_pubkey': 'STRANGER', 'data': {'call_id': 'c1'}});
      expect(db.saved, isEmpty);
      expect(chatUpdates, isEmpty);
      expect(openedCall, isFalse);
      expect(db.ensuredContacts, isEmpty);

      // Контакт: сообщение проходит.
      await handler.handleDecoded(
          {'type': 'chat', 'sender_pubkey': 'FRIEND', 'payload': 'yo', 'message_id': 'm2'});
      expect(db.saved.length, 1);
      expect(chatUpdates, ['FRIEND']);
    });

    // Режим принуждения: `DatabaseService.isContact` под duress отвечает false для
    // ЛЮБОГО адреса (закреплено в database_service_test), поэтому входящий звонок от
    // РЕАЛЬНОГО контакта обязан умереть в том же гейте — до резолва имени, до буфера
    // и до показа CallKit. Проверяем обе ветки показа: foreground (CallScreen) и
    // background (нативный CallKit). Фоновая ветка тут ещё и сама себе детектор: если
    // гейт пропустит кадр, вызов плагина в тестах бросит MissingPluginException.
    test('duress: входящий звонок от реального контакта не поднимает ни экран, ни CallKit',
        () async {
      // Контрольная ветка доходит до CallIdStorage (дедуп по call_id живёт в
      // SharedPreferences — это IPC с push-изолятом), поэтому нужен мок хранилища.
      SharedPreferences.setMockInitialValues({});
      final buffer = IncomingCallBuffer.instance;
      // Ровно то, что видит хендлер под duress: контактов «нет».
      final db = _FakeDb()..contactsAllowAll = false;
      final notif = _FakeNotif();
      final signaling = <Map<String, dynamic>>[];
      var openedCall = false;
      var foreground = true;

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, payload) async => payload),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {
          openedCall = true;
        },
        emitSignaling: signaling.add,
        emitChatUpdate: (_) {},
        isAppInForeground: () => foreground,
      );

      const offer = {'type': 'call-offer', 'sender_pubkey': 'CALLER_PUBKEY_BASE64_AA', 'data': {'call_id': 'c1'}};

      await handler.handleDecoded(offer);
      foreground = false;
      await handler.handleDecoded({...offer, 'data': {'call_id': 'c2'}});

      expect(openedCall, isFalse);
      expect(notif.calls, isEmpty);
      // Имя не резолвилось: наблюдатель не увидит его ни на экране, ни в шторке.
      expect(db.nameLookups, isEmpty);
      // Буфер сигналинга по этому пиру не создан — ICE-кандидатам некуда лечь.
      expect(buffer.takeAll('CALLER_PUBKEY_BASE64_AA'), isEmpty);
      expect(signaling, isEmpty);

      // КОНТРОЛЬ: вне duress тот же кадр звонок поднимает (иначе тест вакуумен).
      db.contactsAllowAll = true;
      foreground = true;
      await handler.handleDecoded({...offer, 'data': {'call_id': 'c3'}});
      expect(openedCall, isTrue);
      expect(db.nameLookups, ['CALLER_PUBKEY_BASE64_AA']);
    });

    // Маркер пропущенного звонка: его кладёт в очередь main-изолят, когда звонок
    // пришёл в duress-сессию (сам offer протухает за минуту, поднимать его нельзя).
    // После входа настоящим PIN из маркера появляется запись в переписке.
    group('маркер пропущенного звонка из очереди', () {
      ({
        IncomingMessageHandler handler,
        _FakeDb db,
        _FakeNotif notif,
        List<String> chatUpdates,
      }) build({bool allowAll = true}) {
        final db = _FakeDb()..contactsAllowAll = allowAll;
        final notif = _FakeNotif();
        final chatUpdates = <String>[];
        return (
          handler: IncomingMessageHandler(
            crypto: _FakeCrypto((_, payload) async => payload),
            database: db,
            notifications: notif,
            callBuffer: IncomingCallBuffer.instance,
            openCallScreen: ({required contactPublicKey, required offer, callId}) {
              fail('маркер не должен открывать экран звонка');
            },
            emitSignaling: (_) {},
            emitChatUpdate: chatUpdates.add,
            isAppInForeground: () => true,
          ),
          db: db,
          notif: notif,
          chatUpdates: chatUpdates,
        );
      }

      Map<String, dynamic> marker({String id = 'missed-c1', int ts = 1700000000000}) => {
            'type': IncomingMessageHandler.missedCallType,
            'sender_pubkey': 'CALLER_PUBKEY_BASE64_AA',
            'message_id': id,
            'server_ts_ms': ts,
          };

      test('пишет непрочитанную запись «Missed call» со временем звонка', () async {
        final t = build();

        await t.handler.handleDecoded(marker(), fromPendingQueue: true);

        expect(t.db.saved.length, 1);
        final (message, contactKey) = t.db.saved.single;
        expect(contactKey, 'CALLER_PUBKEY_BASE64_AA');
        expect(message.text, 'Missed call');
        expect(message.isSentByMe, isFalse);
        // Непрочитанное: иначе жертва не заметит, что звонок был.
        expect(message.isRead, isFalse);
        expect(message.timestamp.millisecondsSinceEpoch, 1700000000000);
        // Текст-маркер должен попадать в набор системных записей звонка, иначе
        // статистика профиля посчитает его перепиской.
        expect(ChatMessage.isCallEvent(message.text), isTrue);
        // Экран чата/список обновляются, уведомление НЕ показываем (разбор идёт
        // сразу после входа настоящим PIN — человек уже в приложении).
        expect(t.chatUpdates, ['CALLER_PUBKEY_BASE64_AA']);
        expect(t.notif.calls, isEmpty);
      });

      test('повторный разбор той же очереди не двоит запись', () async {
        final t = build();

        await t.handler.handleDecoded(marker(), fromPendingQueue: true);
        await t.handler.handleDecoded(marker(), fromPendingQueue: true);

        expect(t.db.saved.length, 1);
      });

      test('из СЕТИ такой кадр игнорируется (нельзя дописывать чужую историю)', () async {
        final t = build();

        await t.handler.handleDecoded(marker()); // fromPendingQueue: false

        expect(t.db.saved, isEmpty);
        expect(t.chatUpdates, isEmpty);
      });

      test('маркер от не-контакта отсекает строгий mutual-add', () async {
        final t = build(allowAll: false);

        await t.handler.handleDecoded(marker(), fromPendingQueue: true);

        expect(t.db.saved, isEmpty);
      });
    });

    test('строгий mutual-add: teardown (hang-up/call-rejected) от не-контакта НЕ дропается', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb()..contactsAllowAll = false; // в контактах никого нет
      final notif = _FakeNotif();
      final signaling = <Map<String, dynamic>>[];

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, payload) async => payload),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {},
        emitSignaling: signaling.add,
        emitChatUpdate: (_) {},
        isAppInForeground: () => true,
      );

      // Сигналы завершения звонка проходят даже от не-контакта: активный звонок
      // всегда должен закрываться (фильтрация по пиру — уже в CallScreen).
      await handler.handleDecoded(
          {'type': 'hang-up', 'sender_pubkey': 'STRANGER', 'data': {'call_id': 'c1'}});
      await handler.handleDecoded(
          {'type': 'call-rejected', 'sender_pubkey': 'STRANGER', 'data': {'call_id': 'c2'}});

      expect(signaling.map((s) => s['type']).toList(), ['hang-up', 'call-rejected']);
    });

    test('chat: разные message_id в окне не теряются, одинаковый id — дубль отбрасывается (LOGIC-1)', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb();
      final notif = _FakeNotif();
      var now = 1000;

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, payload) async => payload), // "расшифровка" = payload
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {},
        emitSignaling: (_) {},
        emitChatUpdate: (_) {},
        isAppInForeground: () => true,
        nowMs: () => now, // время не двигаем: оба сообщения "в одну мс"
      );

      const sender = 'SENDER_KEY';

      // Два РАЗНЫХ сообщения в одну и ту же миллисекунду (внутри старого 5-сек окна).
      await handler.handleDecoded(
          {'type': 'chat', 'sender_pubkey': sender, 'payload': 'привет', 'message_id': 'id-1'});
      await handler.handleDecoded(
          {'type': 'chat', 'sender_pubkey': sender, 'payload': 'ты тут?', 'message_id': 'id-2'});

      // Оба сохранились (старое 5-сек окно теряло второе — аудит LOGIC-1).
      expect(db.saved.length, 2);
      expect(db.saved.map((e) => e.$1.text), containsAll(['привет', 'ты тут?']));
      expect(db.saved.first.$1.messageId, 'id-1');

      // Повторная доставка того же id (WS + offline) — настоящий дубль, не сохраняется.
      await handler.handleDecoded(
          {'type': 'chat', 'sender_pubkey': sender, 'payload': 'привет', 'message_id': 'id-1'});
      expect(db.saved.length, 2);

      // Неизвестный отправитель авто-добавлен в контакты, иначе сообщение
      // сохранилось бы, но не показалось в списке чатов (аудит DB-6).
      expect(db.ensuredContacts, contains(sender));
    });

    test('ICE до offer не теряется: буферизуется и сохраняется при приходе offer', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb()..contactNames['SENDER_KEY'] = 'Alice';
      final notif = _FakeNotif();
      final signaling = <Map<String, dynamic>>[];

      Map<String, dynamic>? openedOffer;
      String? openedKey;

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'x'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {
          openedKey = contactPublicKey;
          openedOffer = offer;
        },
        emitSignaling: signaling.add,
        emitChatUpdate: (_) {},
        isAppInForeground: () => true, // foreground → openCallScreen, НЕ showCallNotification
      );

      await handler.handleDecoded({
        'type': 'ice-candidate',
        'sender_pubkey': 'SENDER_KEY',
        'data': {'candidate': 'c', 'sdpMid': '0', 'sdpMLineIndex': 0},
      });

      expect(signaling.length, 1);
      expect(buffer.sizeFor('SENDER_KEY'), 1);

      await handler.handleDecoded({
        'type': 'call-offer',
        'sender_pubkey': 'SENDER_KEY',
        'data': {'sdp': 'v=0...', 'type': 'offer'},
      });

      // В foreground режиме вызывается openCallScreen, а НЕ showCallNotification
      // showCallNotification вызывается только в background режиме (устаревший fallback)
      expect(openedKey, equals('SENDER_KEY'));
      expect(openedOffer?['type'], equals('offer'));
      // ключевое: pre-offer ICE не должен очищаться при обработке offer
      expect(buffer.sizeFor('SENDER_KEY'), 1);
    });

    test('call-offer: дедуп по sender в коротком окне (не открывает 2 CallScreen подряд)', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb()..contactNames['SENDER_KEY'] = 'Alice';
      final notif = _FakeNotif();

      var now = 1000000;
      int openCalls = 0;

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'x'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {
          openCalls += 1;
        },
        emitSignaling: (_) {},
        emitChatUpdate: (_) {},
        isAppInForeground: () => true, // foreground → openCallScreen
        isCallActive: () => false,
        nowMs: () => now,
      );

      final offerMsg = {
        'type': 'call-offer',
        'sender_pubkey': 'SENDER_KEY',
        'data': {'sdp': 'v=0...', 'type': 'offer'},
      };

      await handler.handleDecoded(offerMsg);
      await handler.handleDecoded(offerMsg); // тот же момент времени -> должен быть проигнорирован

      // В foreground вызывается openCallScreen
      expect(openCalls, equals(1));

      // После окна дедупа следующий offer принимается.
      now += 3000;
      await handler.handleDecoded(offerMsg);
      expect(openCalls, equals(2));
    });

    test('call-offer: TTL по server_ts_ms (слишком старый offer игнорируется)', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb();
      final notif = _FakeNotif();

      var now = 1000000;
      int openCalls = 0;

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'x'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {
          openCalls += 1;
        },
        emitSignaling: (_) {},
        emitChatUpdate: (_) {},
        isAppInForeground: () => true,
        isCallActive: () => false,
        nowMs: () => now,
      );

      await handler.handleDecoded({
        'type': 'call-offer',
        'sender_pubkey': 'SENDER_KEY',
        'server_ts_ms': now - 61 * 1000,
        'data': {'sdp': 'old', 'type': 'offer'},
      });

      expect(openCalls, equals(0));
      expect(notif.calls, isEmpty);
    });

    test('call-offer: если звонок уже активен — offer игнорируется', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb();
      final notif = _FakeNotif();

      int openCalls = 0;
      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'x'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {
          openCalls += 1;
        },
        emitSignaling: (_) {},
        emitChatUpdate: (_) {},
        isAppInForeground: () => true,
        isCallActive: () => true,
        nowMs: () => 1000000,
      );

      await handler.handleDecoded({
        'type': 'call-offer',
        'sender_pubkey': 'SENDER_KEY',
        'data': {'sdp': 'v=0...', 'type': 'offer'},
      });

      expect(openCalls, equals(0));
      expect(notif.calls, isEmpty);
    });

    test('hang-up/call-rejected: сначала signaling, затем hideCallNotification', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb();
      final notif = _FakeNotif();
      final order = <String>[];

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'x'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {},
        emitSignaling: (msg) => order.add('signaling:${msg['type']}'),
        emitChatUpdate: (_) {},
        isAppInForeground: () => true,
      );

      await handler.handleDecoded({
        'type': 'hang-up',
        'sender_pubkey': 'SENDER_KEY',
        'data': {},
      });

      // notif.calls содержит только hideCall, а порядок проверяем через order + notif.calls
      expect(order, equals(['signaling:hang-up']));
      expect(notif.calls, equals(['hideCall']));
    });

    test('chat: сохраняет сообщение, шлёт update; нотификация только в фоне и без текста', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb()..contactNames['SENDER_KEY'] = 'Bob';
      final notif = _FakeNotif();
      final chatUpdates = <String>[];

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'hello'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {},
        emitSignaling: (_) {},
        emitChatUpdate: chatUpdates.add,
        isAppInForeground: () => false,
      );

      await handler.handleDecoded({
        'type': 'chat',
        'sender_pubkey': 'SENDER_KEY',
        'payload': '{"cipherText":"..."}',
      });

      expect(db.saved, hasLength(1));
      expect(db.saved.first.$1.text, equals('hello'));
      expect(db.saved.first.$1.isSentByMe, isFalse);
      expect(db.saved.first.$1.isRead, isFalse);
      expect(db.saved.first.$1.status, equals(MessageStatus.delivered));

      expect(chatUpdates, equals(['SENDER_KEY']));
      // Приватность: уведомление полностью обезличено — ни содержания, ни отправителя.
      expect(notif.calls, equals(['showMsg']));
    });

    test('chat: системные call-status сообщения не должны поднимать уведомление', () async {
      final buffer = IncomingCallBuffer.instance;
      final db = _FakeDb()..contactNames['SENDER_KEY'] = 'Bob';
      final notif = _FakeNotif();

      final handler = IncomingMessageHandler(
        crypto: _FakeCrypto((_, __) async => 'Пропущен звонок'),
        database: db,
        notifications: notif,
        callBuffer: buffer,
        openCallScreen: ({required contactPublicKey, required offer, callId}) {},
        emitSignaling: (_) {},
        emitChatUpdate: (_) {},
        isAppInForeground: () => false,
      );

      await handler.handleDecoded({
        'type': 'chat',
        'sender_pubkey': 'SENDER_KEY',
        'payload': 'enc',
      });

      expect(db.saved, hasLength(1));
      expect(notif.calls, isEmpty);
    });
  });
}


