import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Контракт надёжной отправки chat (инцидент «лифт» 23.07.2026):
// 1) персист в outbox ДО касания сокета;
// 2) запись в сокет НЕ удаляет из очереди;
// 3) удаление только по подтверждению: pong-fence (старый сервер) или chat-ack;
// 4) смерть сокета до подтверждения -> ресенд в новой сессии;
// 5) duress не отправляет и не пополняет очередь реального профиля.

class _RecordingWebSocketSink implements WebSocketSink {
  _RecordingWebSocketSink(this.sent);
  final List<dynamic> sent;

  @override
  void add(dynamic message) => sent.add(message);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final v in stream) {
      add(v);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Future.value();
}

class _RecordingWebSocketChannel
    with StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _RecordingWebSocketChannel(this.sent) : sink = _RecordingWebSocketSink(sent);

  final List<dynamic> sent;

  @override
  final WebSocketSink sink;

  final _in = StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get stream => _in.stream;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();
}

Future<Database> _openTestDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      contactPublicKey TEXT NOT NULL,
      messageId TEXT,
      text TEXT NOT NULL,
      isSentByMe INTEGER NOT NULL,
      timestamp INTEGER NOT NULL,
      status INTEGER DEFAULT 1,
      isRead INTEGER DEFAULT 1
    )
  ''');
  await db.execute('''
    CREATE TABLE outbox (
      messageId TEXT PRIMARY KEY,
      recipientKey TEXT NOT NULL,
      payload TEXT NOT NULL,
      createdAt INTEGER NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      lastAttemptAt INTEGER
    )
  ''');
  return db;
}

List<Map<String, dynamic>> _framesOfType(List<dynamic> sent, String type) => sent
    .map((raw) => json.decode(raw as String) as Map<String, dynamic>)
    .where((f) => f['type'] == type)
    .toList();

// Слив/подтверждение внутри сервиса асинхронные (fire-and-forget) — даём
// микротаскам и запросам к БД отработать.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await _openTestDb();
    DatabaseService.instance.setDuressMode(false);
    DatabaseService.instance.initWithDatabase(db);
  });

  tearDown(() async {
    DatabaseService.instance.setDuressMode(false);
    await DatabaseService.instance.close();
  });

  group('Outbox: персист до сокета', () {
    test('без соединения сообщение лежит в outbox и никуда не пишется',
        () async {
      final service = WebSocketService();
      await service.sendChatMessage('RECIPIENT', 'PAYLOAD', messageId: 'mid-1');

      final batch = await DatabaseService.instance.getOutboxBatch();
      expect(batch, hasLength(1));
      expect(batch.single.messageId, 'mid-1');
      expect(batch.single.recipientKey, 'RECIPIENT');
    });

    test('null messageId получает сгенерированный id', () async {
      final service = WebSocketService();
      await service.sendChatMessage('RECIPIENT', 'PAYLOAD');

      final batch = await DatabaseService.instance.getOutboxBatch();
      expect(batch, hasLength(1));
      expect(batch.single.messageId, isNotEmpty);
    });

    test('слишком большой payload -> ArgumentError, очередь пуста', () async {
      final service = WebSocketService();
      final huge = 'x' * 1000000;
      await expectLater(
        service.sendChatMessage('RECIPIENT', huge, messageId: 'mid-big'),
        throwsArgumentError,
      );
      expect(await DatabaseService.instance.outboxCount(), 0);
    });
  });

  group('Outbox: слив и подтверждение (pong-fence, старый сервер)', () {
    test('запись в сокет НЕ удаляет из очереди; pong подтверждает', () async {
      final sent = <dynamic>[];
      final ws = _RecordingWebSocketChannel(sent);
      final service = WebSocketService();
      service.debugAttachConnectedChannel(ws, currentPublicKey: 'ME');

      final events = <OutgoingStatusEvent>[];
      final sub = service.outgoingStatus.listen(events.add);

      await DatabaseService.instance.addMessage(
        ChatMessage(
            messageId: 'mid-f1',
            text: 'hi',
            isSentByMe: true,
            status: MessageStatus.sending),
        'RECIPIENT',
      );
      await service.sendChatMessage('RECIPIENT', 'PAYLOAD', messageId: 'mid-f1');
      await _settle();

      // Кадр chat записан + fence-ping, но очередь НЕ пуста (нет подтверждения).
      final chats = _framesOfType(sent, 'chat');
      expect(chats, hasLength(1));
      expect(chats.single['message_id'], 'mid-f1');
      expect(chats.single['payload'], 'PAYLOAD');
      expect(_framesOfType(sent, 'ping'), hasLength(1));
      expect(await DatabaseService.instance.outboxCount(), 1);

      // Pong (fence-режим) подтверждает: очередь пуста, статус sent, событие UI.
      service.debugHandlePostAuthFrame(json.encode({'type': 'pong'}));
      await _settle();

      expect(await DatabaseService.instance.outboxCount(), 0);
      final msgs =
          await DatabaseService.instance.getMessagesForContact('RECIPIENT');
      expect(msgs.single.status, MessageStatus.sent);
      expect(events, hasLength(1));
      expect(events.single.messageId, 'mid-f1');
      expect(events.single.status, MessageStatus.sent);
      await sub.cancel();
    });

    test('смерть сокета до pong -> ресенд в новой сессии с тем же id', () async {
      final sentA = <dynamic>[];
      final service = WebSocketService();
      service.debugAttachConnectedChannel(_RecordingWebSocketChannel(sentA));

      await service.sendChatMessage('RECIPIENT', 'PAYLOAD', messageId: 'mid-r1');
      await _settle();
      expect(_framesOfType(sentA, 'chat'), hasLength(1));
      expect(await DatabaseService.instance.outboxCount(), 1);

      // «Реконнект»: новая сессия (pong старой не пришёл) -> повторная запись.
      final sentB = <dynamic>[];
      service.debugAttachConnectedChannel(_RecordingWebSocketChannel(sentB));
      service.triggerOutboxDrain();
      await _settle();

      final chats = _framesOfType(sentB, 'chat');
      expect(chats, hasLength(1));
      expect(chats.single['message_id'], 'mid-r1');
      expect(await DatabaseService.instance.outboxCount(), 1); // всё ещё ждёт
    });

    test('pong подтверждает только записанное ДО его пинга (FIFO)', () async {
      final sent = <dynamic>[];
      final service = WebSocketService();
      service.debugAttachConnectedChannel(_RecordingWebSocketChannel(sent));

      await service.sendChatMessage('RECIPIENT', 'P1', messageId: 'mid-o1');
      await _settle();
      await service.sendChatMessage('RECIPIENT', 'P2', messageId: 'mid-o2');
      await _settle();
      expect(_framesOfType(sent, 'ping'), hasLength(2));

      // Один pong -> подтверждена только первая пачка.
      service.debugHandlePostAuthFrame(json.encode({'type': 'pong'}));
      await _settle();
      expect(await DatabaseService.instance.outboxCount(), 1);

      service.debugHandlePostAuthFrame(json.encode({'type': 'pong'}));
      await _settle();
      expect(await DatabaseService.instance.outboxCount(), 0);
    });
  });

  group('Outbox: строгий режим chat-ack', () {
    test('pong НЕ подтверждает; подтверждает chat-ack', () async {
      final sent = <dynamic>[];
      final service = WebSocketService();
      service.debugAttachConnectedChannel(_RecordingWebSocketChannel(sent),
          serverAcksChat: true);

      await service.sendChatMessage('RECIPIENT', 'PAYLOAD', messageId: 'mid-a1');
      await _settle();
      expect(await DatabaseService.instance.outboxCount(), 1);

      service.debugHandlePostAuthFrame(json.encode({'type': 'pong'}));
      await _settle();
      expect(await DatabaseService.instance.outboxCount(), 1,
          reason: 'pong в строгом режиме не подтверждает');

      service.debugHandlePostAuthFrame(
          json.encode({'type': 'chat-ack', 'message_id': 'mid-a1', 'queued': true}));
      await _settle();
      expect(await DatabaseService.instance.outboxCount(), 0);
    });
  });

  group('Outbox: duress', () {
    test('в duress очередь не пополняется и не сливается', () async {
      // Очередь реального профиля, накопленная ДО duress.
      await DatabaseService.instance.enqueueOutbox(
          recipientKey: 'RECIPIENT', payload: 'REAL', messageId: 'mid-d1');

      DatabaseService.instance.setDuressMode(true);

      final sent = <dynamic>[];
      final service = WebSocketService();
      service.debugAttachConnectedChannel(_RecordingWebSocketChannel(sent));
      await service.sendChatMessage('RECIPIENT', 'DURESS', messageId: 'mid-d2');
      await _settle();

      // Ничего не записано в сокет; duress-сообщение не легло в очередь.
      expect(_framesOfType(sent, 'chat'), isEmpty);
      DatabaseService.instance.setDuressMode(false);
      final batch = await DatabaseService.instance.getOutboxBatch();
      expect(batch.map((m) => m.messageId), ['mid-d1']);
    });
  });

  group('Reconcile', () {
    test('sending без outbox-строки -> failed; с outbox-строкой — не трогаем',
        () async {
      // Timestamp старше 2-минутного фильтра: свежие sending reconcile не
      // трогает (окно живой отправки между addMessage и enqueueOutbox).
      final old = DateTime.now().subtract(const Duration(minutes: 5));
      await DatabaseService.instance.addMessage(
        ChatMessage(
            messageId: 'mid-orphan',
            text: 'потерян при крэше',
            isSentByMe: true,
            timestamp: old,
            status: MessageStatus.sending),
        'RECIPIENT',
      );
      await DatabaseService.instance.addMessage(
        ChatMessage(
            messageId: 'mid-queued',
            text: 'ждёт отправки',
            isSentByMe: true,
            timestamp: old,
            status: MessageStatus.sending),
        'RECIPIENT',
      );
      // Свежая живая отправка (окно до enqueueOutbox) — трогать нельзя.
      await DatabaseService.instance.addMessage(
        ChatMessage(
            messageId: 'mid-fresh',
            text: 'отправляется прямо сейчас',
            isSentByMe: true,
            status: MessageStatus.sending),
        'RECIPIENT',
      );
      await DatabaseService.instance.enqueueOutbox(
          recipientKey: 'RECIPIENT', payload: 'X', messageId: 'mid-queued');

      final failed =
          await DatabaseService.instance.failOrphanedSendingMessages();
      expect(failed, [('RECIPIENT', 'mid-orphan')]);

      final msgs =
          await DatabaseService.instance.getMessagesForContact('RECIPIENT');
      expect(
          msgs.firstWhere((m) => m.messageId == 'mid-orphan').status,
          MessageStatus.failed);
      expect(
          msgs.firstWhere((m) => m.messageId == 'mid-queued').status,
          MessageStatus.sending);
      expect(
          msgs.firstWhere((m) => m.messageId == 'mid-fresh').status,
          MessageStatus.sending);
    });
  });

  group('Миграция v9 -> v10', () {
    test('создаёт таблицу outbox, существующие данные не тронуты', () async {
      // Закрываем БД из setUp: singleInstance-кэш иначе вернёт её же (с уже
      // созданными таблицами) вместо свежей in-memory.
      await DatabaseService.instance.close();
      // «Старая» БД v9: те же таблицы, БЕЗ outbox.
      final oldDb =
          await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await oldDb.execute('''
        CREATE TABLE contacts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          publicKey TEXT NOT NULL UNIQUE,
          encryptionKey TEXT
        )
      ''');
      await oldDb.execute('''
        CREATE TABLE messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          contactPublicKey TEXT NOT NULL,
          messageId TEXT,
          text TEXT NOT NULL,
          isSentByMe INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          status INTEGER DEFAULT 1,
          isRead INTEGER DEFAULT 1
        )
      ''');
      await oldDb.insert('messages', {
        'contactPublicKey': 'C1',
        'messageId': 'old-1',
        'text': 'старое сообщение',
        'isSentByMe': 1,
        'timestamp': 1000,
        'status': 1,
        'isRead': 1,
      });

      await DatabaseService.instance.debugRunUpgrade(oldDb, 9, 10);

      // outbox появился и работает.
      DatabaseService.instance.initWithDatabase(oldDb);
      await DatabaseService.instance.enqueueOutbox(
          recipientKey: 'C1', payload: 'P', messageId: 'new-1');
      expect(await DatabaseService.instance.outboxCount(), 1);

      // Старые данные целы.
      final rows = await oldDb.query('messages');
      expect(rows, hasLength(1));
      expect(rows.single['messageId'], 'old-1');
    });
  });
}
