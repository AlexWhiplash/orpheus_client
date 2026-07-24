import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/presence_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:rxdart/rxdart.dart';

class _TestWebSocketService extends WebSocketService {
  _TestWebSocketService() : super();

  final StreamController<String> _inbound = StreamController<String>.broadcast();
  final BehaviorSubject<ConnectionStatus> _status =
      BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.Disconnected);

  final List<String> sentRawMessages = <String>[];

  @override
  Stream<String> get stream => _inbound.stream;

  @override
  Stream<ConnectionStatus> get status => _status.stream;

  @override
  ConnectionStatus get currentStatus => _status.value;

  void setStatus(ConnectionStatus status) => _status.add(status);

  void emitJson(Map<String, dynamic> jsonObject) {
    _inbound.add(json.encode(jsonObject));
  }

  void emitRaw(String raw) {
    _inbound.add(raw);
  }

  @override
  void sendRawMessage(String jsonString) {
    sentRawMessages.add(jsonString);
  }

  Future<void> disposeTest() async {
    await _inbound.close();
    await _status.close();
  }
}

void main() {
  group('PresenceService', () {
    test('не шлёт subscribe пока WS не Connected; затем resubscribe', () async {
      final ws = _TestWebSocketService();
      final service = PresenceService(ws);

      service.setWatchedPubkeys([' a ', 'b', '']);
      expect(ws.sentRawMessages, isEmpty);

      ws.setStatus(ConnectionStatus.Connected);
      await Future<void>.delayed(Duration.zero);

      expect(ws.sentRawMessages, hasLength(1));
      final msg = json.decode(ws.sentRawMessages.single) as Map<String, dynamic>;
      expect(msg['type'], 'presence-subscribe');
      expect((msg['pubkeys'] as List).toSet(), {'a', 'b'});

      service.dispose();
      await ws.disposeTest();
    });

    test('обрыв соединения сбрасывает презенс (нет залипшего «онлайн»)', () async {
      final ws = _TestWebSocketService()..setStatus(ConnectionStatus.Connected);
      final service = PresenceService(ws);
      await Future<void>.delayed(Duration.zero);

      service.setWatchedPubkeys(['a']);
      ws.emitJson({
        'type': 'presence-update',
        'pubkey': 'a',
        'online': true,
      });
      await Future<void>.delayed(Duration.zero);
      expect(service.isOnline('a'), isTrue);

      // Сеть умерла: без соединения презенс неизвестен — «онлайн» не показываем.
      ws.setStatus(ConnectionStatus.Disconnected);
      await Future<void>.delayed(Duration.zero);
      expect(service.isOnline('a'), isFalse);

      // Реконнект: полная переподписка, состояние вернёт presence-state.
      ws.setStatus(ConnectionStatus.Connected);
      await Future<void>.delayed(Duration.zero);
      expect(
        ws.sentRawMessages
            .map((m) => json.decode(m) as Map<String, dynamic>)
            .where((m) => m['type'] == 'presence-subscribe')
            .length,
        greaterThanOrEqualTo(2),
      );

      service.dispose();
      await ws.disposeTest();
    });

    test('шлёт unsubscribe и subscribe diff-ом', () async {
      final ws = _TestWebSocketService()..setStatus(ConnectionStatus.Connected);
      final service = PresenceService(ws, maxPubkeysPerMessage: 50);

      service.setWatchedPubkeys(['a', 'b', 'c']);
      await Future<void>.delayed(Duration.zero);
      ws.sentRawMessages.clear();

      service.setWatchedPubkeys(['b', 'c', 'd']);
      await Future<void>.delayed(Duration.zero);

      expect(ws.sentRawMessages, hasLength(2));

      final msg0 = json.decode(ws.sentRawMessages[0]) as Map<String, dynamic>;
      expect(msg0['type'], 'presence-unsubscribe');
      expect((msg0['pubkeys'] as List).toSet(), {'a'});

      final msg1 = json.decode(ws.sentRawMessages[1]) as Map<String, dynamic>;
      expect(msg1['type'], 'presence-subscribe');
      expect((msg1['pubkeys'] as List).toSet(), {'d'});

      service.dispose();
      await ws.disposeTest();
    });

    test('chunking по maxPubkeysPerMessage', () async {
      final ws = _TestWebSocketService();
      final service = PresenceService(ws, maxPubkeysPerMessage: 2);

      // Важно: сначала даём сервису увидеть статус Connected, чтобы resubscribe не продублировал subscribe позже.
      ws.setStatus(ConnectionStatus.Connected);
      await Future<void>.delayed(Duration.zero);
      ws.sentRawMessages.clear();

      service.setWatchedPubkeys(['a', 'b', 'c', 'd', 'e']);
      await Future<void>.delayed(Duration.zero);

      expect(ws.sentRawMessages, hasLength(3));

      final decoded = ws.sentRawMessages
          .map((e) => json.decode(e) as Map<String, dynamic>)
          .toList(growable: false);

      expect(decoded[0]['type'], 'presence-subscribe');
      expect((decoded[0]['pubkeys'] as List).length, 2);

      expect(decoded[1]['type'], 'presence-subscribe');
      expect((decoded[1]['pubkeys'] as List).length, 2);

      expect(decoded[2]['type'], 'presence-subscribe');
      expect((decoded[2]['pubkeys'] as List).length, 1);

      service.dispose();
      await ws.disposeTest();
    });

    test('обрабатывает presence-state и presence-update', () async {
      final ws = _TestWebSocketService();
      final service = PresenceService(ws);

      ws.emitJson({
        'type': 'presence-state',
        'states': {
          'a': true,
          'b': false,
          'bad': 'nope',
        },
      });

      final s1 = await service.stream.firstWhere((m) => m['a'] == true && m['b'] == false);
      expect(s1.containsKey('bad'), isFalse);

      ws.emitJson({
        'type': 'presence-update',
        'pubkey': 'b',
        'online': true,
      });

      final s2 = await service.stream.firstWhere((m) => m['b'] == true);
      expect(s2['a'], isTrue);

      service.dispose();
      await ws.disposeTest();
    });

    test('игнорирует некорректные payload и JSON', () async {
      final ws = _TestWebSocketService();
      final service = PresenceService(ws);

      // Некорректный JSON
      ws.emitRaw('not-json');

      // Некорректные типы
      ws.emitJson({'type': 'presence-update', 'pubkey': 123, 'online': true});
      ws.emitJson({'type': 'presence-update', 'pubkey': 'a', 'online': 'yes'});
      ws.emitJson({'type': 'presence-state', 'states': 'nope'});

      // Дадим событийному циклу пройти.
      await Future<void>.delayed(Duration.zero);

      // Состояние не должно измениться (остаётся пустым)
      expect(service.isOnline('a'), isFalse);

      service.dispose();
      await ws.disposeTest();
    });
  });
}

