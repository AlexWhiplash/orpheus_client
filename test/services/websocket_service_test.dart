import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('WebSocketService Tests', () {
    late WebSocketService service;

    setUp(() {
      service = WebSocketService();
    });

    tearDown(() {
      service.disconnect();
    });

    test('Инициализация сервиса', () {
      expect(service, isNotNull);
      expect(service.stream, isNotNull);
      expect(service.status, isNotNull);
    });

    test('Начальное состояние - Disconnected', () async {
      final status = await service.status.first;
      expect(status, equals(ConnectionStatus.Disconnected));
    });

    test('Попытка отправки сообщения без подключения', () async {
      // Не бросает: сообщение персистится в outbox и ждёт соединения
      // (инцидент «лифт» — раньше уходило в prefs-очередь).
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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
      DatabaseService.instance.setDuressMode(false);
      DatabaseService.instance.initWithDatabase(db);

      await expectLater(
          service.sendChatMessage('recipient_key', 'payload'), completes);
      expect(await DatabaseService.instance.outboxCount(), 1);

      await DatabaseService.instance.close();
    });

    test('Попытка отправки сигнального сообщения без подключения', () {
      expect(() {
        service.sendSignalingMessage('recipient_key', 'call-offer', {'sdp': 'test'});
      }, returnsNormally);
    });

    test('Попытка отправки сырого сообщения без подключения', () {
      expect(() {
        service.sendRawMessage('{"type":"test"}');
      }, returnsNormally);
    });

    test('Множественные вызовы disconnect безопасны', () {
      expect(() {
        service.disconnect();
        service.disconnect();
        service.disconnect();
      }, returnsNormally);
    });

    test('Поток статуса работает корректно', () async {
      final statuses = <ConnectionStatus>[];
      final subscription = service.status.listen((status) {
        statuses.add(status);
      });

      // Даем время на получение начального статуса
      await Future.delayed(const Duration(milliseconds: 100));

      subscription.cancel();
      expect(statuses, isNotEmpty);
      expect(statuses.first, equals(ConnectionStatus.Disconnected));
    });

    test('Поток сообщений работает корректно', () async {
      final messages = <String>[];
      final subscription = service.stream.listen((message) {
        messages.add(message);
      });

      // Даем время на инициализацию
      await Future.delayed(const Duration(milliseconds: 100));

      subscription.cancel();
      // Поток должен быть создан, даже если сообщений нет
      expect(service.stream, isNotNull);
    });
  });
}

