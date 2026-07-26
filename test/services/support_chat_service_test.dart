import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orpheus_project/models/support_message.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/support_chat_service.dart';

void main() {
  group('SupportMessage (модель)', () {
    test('fromJson парсит корректно', () {
      final json = {
        'id': 42,
        'direction': 'admin',
        'message': 'Hello!',
        'is_read': true,
        'created_at': '2025-01-04T12:00:00Z',
      };

      final msg = SupportMessage.fromJson(json);

      expect(msg.id, equals(42));
      expect(msg.direction, equals(MessageDirection.admin));
      expect(msg.message, equals('Hello!'));
      expect(msg.isRead, isTrue);
      expect(msg.createdAt.year, equals(2025));
    });

    test('fromJson с direction=user', () {
      final json = {
        'id': 1,
        'direction': 'user',
        'message': 'Hi',
        'is_read': false,
        'created_at': null,
      };

      final msg = SupportMessage.fromJson(json);

      expect(msg.direction, equals(MessageDirection.user));
      expect(msg.isRead, isFalse);
    });

    test('toJson сериализует корректно', () {
      final msg = SupportMessage(
        id: 10,
        direction: MessageDirection.user,
        message: 'Test',
        isRead: false,
        createdAt: DateTime(2025, 1, 1, 12, 0),
      );

      final json = msg.toJson();

      expect(json['id'], equals(10));
      expect(json['direction'], equals('user'));
      expect(json['message'], equals('Test'));
      expect(json['is_read'], isFalse);
    });

    test('isSystemMessage определяет системные сообщения', () {
      final normal = SupportMessage(
        id: 1,
        direction: MessageDirection.user,
        message: 'Hello',
        isRead: true,
        createdAt: DateTime.now(),
      );

      final system = SupportMessage(
        id: 2,
        direction: MessageDirection.user,
        message: '📎 Debug-логи отправлены (100 записей)',
        isRead: true,
        createdAt: DateTime.now(),
      );

      expect(normal.isSystemMessage, isFalse);
      expect(system.isSystemMessage, isTrue);
    });
  });

  group('SupportChatService (контракты)', () {
    late MockClient mockClient;
    late SupportChatService service;

    setUp(() {
      mockClient = MockClient((request) async {
        // Mock для /api/support/messages
        if (request.url.path.endsWith('/api/support/messages')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'id': 1,
                  'direction': 'user',
                  'message': 'Hello',
                  'is_read': true,
                  'created_at': '2025-01-04T12:00:00Z',
                },
                {
                  'id': 2,
                  'direction': 'admin',
                  'message': 'Hi!',
                  'is_read': false,
                  'created_at': '2025-01-04T12:01:00Z',
                },
              ],
            }),
            200,
          );
        }

        // Mock для /api/support/message (POST)
        if (request.url.path.endsWith('/api/support/message') &&
            request.method == 'POST') {
          return http.Response(
            jsonEncode({'id': 99, 'status': 'sent'}),
            200,
          );
        }

        // Mock для /api/support/logs (POST)
        if (request.url.path.endsWith('/api/support/logs') &&
            request.method == 'POST') {
          return http.Response(
            jsonEncode({'log_id': 5, 'status': 'received', 'lines_count': 50}),
            200,
          );
        }

        // Mock для /api/support/unread
        if (request.url.path.endsWith('/api/support/unread')) {
          return http.Response(
            jsonEncode({'unread_count': 3}),
            200,
          );
        }

        return http.Response('Not found', 404);
      });

      service = SupportChatService(httpClient: mockClient);
    });

    tearDown(() {
      service.dispose();
    });

    test('messages изначально пустой список', () {
      expect(service.messages, isEmpty);
      expect(service.isLoading, isFalse);
      expect(service.error, isNull);
    });

    test('handleIncomingReply добавляет сообщение от админа', () async {
      final events = <List<SupportMessage>>[];
      final sub = service.messagesStream.listen(events.add);

      service.handleIncomingReply({
        'text': 'Reply from support',
        'created_at': '2025-01-04T13:00:00Z',
      });

      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(service.messages, hasLength(1));
      expect(service.messages.first.direction, equals(MessageDirection.admin));
      expect(service.messages.first.message, equals('Reply from support'));
      expect(service.unreadCount, equals(1));
    });

    test('unreadStream эмитит при получении сообщения', () async {
      final counts = <int>[];
      final sub = service.unreadStream.listen(counts.add);

      service.handleIncomingReply({'text': 'msg1'});
      service.handleIncomingReply({'text': 'msg2'});

      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(counts, equals([1, 2]));
    });

    test('clear очищает сообщения и unread', () {
      service.handleIncomingReply({'text': 'test'});
      expect(service.messages, hasLength(1));
      expect(service.unreadCount, equals(1));

      service.clear();

      expect(service.messages, isEmpty);
      expect(service.unreadCount, equals(0));
    });
  });

  group('MessageDirection enum', () {
    test('user и admin различаются', () {
      expect(MessageDirection.user, isNot(equals(MessageDirection.admin)));
    });
  });

  // Переписка с разработчиком лежит на СЕРВЕРЕ, поэтому под принуждением её надо
  // гасить отдельно от гейта БД. Ставится последней группой: deriveFromSeedForTest
  // задаёт адрес на синглтоне CryptoService, а тесты выше рассчитаны на его
  // отсутствие.
  group('SupportChatService - duress mode', () {
    late List<Uri> requested;
    late SupportChatService service;

    setUp(() async {
      await CryptoService.instance
          .deriveFromSeedForTest(List<int>.filled(32, 9));
      expect(CryptoService.instance.addressBase64, isNotNull,
          reason: 'без адреса тест был бы пустым');
      requested = <Uri>[];
      service = SupportChatService(httpClient: MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          jsonEncode({
            'messages': [
              {
                'id': 1,
                'direction': 'user',
                'message': 'REAL-SUPPORT-HISTORY',
                'is_read': true,
                'created_at': '2025-01-04T12:00:00Z',
              },
            ],
          }),
          200,
        );
      }));
    });

    tearDown(() {
      AuthService.instance.debugSetDuressMode(false);
      service.dispose();
    });

    test('вне duress история грузится с сервера', () async {
      await service.loadMessages();

      expect(service.messages.single.message, equals('REAL-SUPPORT-HISTORY'));
      expect(requested, isNotEmpty);
    });

    test('в duress история пуста, на сервер не ходим и НЕТ ошибки на экране',
        () async {
      AuthService.instance.debugSetDuressMode(true);

      await service.loadMessages();

      expect(service.messages, isEmpty);
      expect(requested, isEmpty);
      // error != null отрисовался бы красной плашкой с текстом — это сам по себе
      // tell, поэтому duress-ветка обязана оставить error пустым.
      expect(service.error, isNull);
    });

    test('в duress уже загруженная реальная история вычищается из кеша',
        () async {
      await service.loadMessages();
      expect(service.messages, isNotEmpty);

      AuthService.instance.debugSetDuressMode(true);
      await service.loadMessages();

      expect(service.messages, isEmpty,
          reason: 'сервис — синглтон: кеш реальной сессии виден в duress');
      expect(service.error, isNull);
    });

    test('в duress живой ответ поддержки не появляется на экране', () async {
      AuthService.instance.debugSetDuressMode(true);

      service.handleIncomingReply({
        'text': 'LIVE-ADMIN-REPLY',
        'created_at': '2025-01-04T12:05:00Z',
      });

      expect(service.messages, isEmpty);
      expect(service.unreadCount, equals(0));
    });

    test('в duress отправка от лица жертвы не уходит', () async {
      AuthService.instance.debugSetDuressMode(true);

      expect(await service.sendMessage('written by the observer'), isFalse);
      expect(requested, isEmpty);
    });
  });
}




