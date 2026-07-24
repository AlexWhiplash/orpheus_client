import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _RecordingHttpClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final bodies = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Request) {
      bodies.add(request.body);
    }
    final bytes = utf8.encode('ok');
    return http.StreamedResponse(Stream.value(bytes), 200);
  }
}

class _RecordingWebSocketSink implements WebSocketSink {
  _RecordingWebSocketSink(this.sent);
  final List<dynamic> sent;

  @override
  void add(dynamic message) => sent.add(message);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // Для наших тестов достаточно, что метод существует.
  }

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

class _RecordingWebSocketChannel with StreamChannelMixin<dynamic> implements WebSocketChannel {
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

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('WebSocketService outgoing protocol', () {
    test('sendChatMessage формирует корректный JSON пакет (через outbox)',
        () async {
      // Chat теперь ходит через персистентный outbox (инцидент «лифт»).
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

      final sent = <dynamic>[];
      final ws = _RecordingWebSocketChannel(sent);

      final service = WebSocketService();
      service.debugAttachConnectedChannel(ws, currentPublicKey: 'ME');

      await service.sendChatMessage('RECIPIENT', 'PAYLOAD', messageId: 'mid-1');
      // Слив асинхронный — даём микротаскам и запросам к БД отработать.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Кадр chat + fence-ping вслед.
      expect(sent, hasLength(2));
      final decoded = json.decode(sent.first as String) as Map<String, dynamic>;
      expect(decoded['type'], equals('chat'));
      expect(decoded['recipient_pubkey'], equals('RECIPIENT'));
      expect(decoded['payload'], equals('PAYLOAD'));
      expect(decoded['message_id'], equals('mid-1'));
      final fence = json.decode(sent.last as String) as Map<String, dynamic>;
      expect(fence['type'], equals('ping'));

      await DatabaseService.instance.close();
    });

    test('sendSignalingMessage формирует корректный JSON пакет (call-offer)', () {
      final sent = <dynamic>[];
      final ws = _RecordingWebSocketChannel(sent);

      final service = WebSocketService();
      service.debugAttachConnectedChannel(ws, currentPublicKey: 'ME');

      service.sendSignalingMessage('RECIPIENT', 'call-offer', {'sdp': 'v=0', 'type': 'offer'});

      expect(sent, hasLength(1));
      final decoded = json.decode(sent.single as String) as Map<String, dynamic>;
      expect(decoded['type'], equals('call-offer'));
      expect(decoded['recipient_pubkey'], equals('RECIPIENT'));
      expect(decoded['data'], isA<Map>());
      expect((decoded['data'] as Map)['type'], equals('offer'));
    });

    test('hang-up всегда уходит по WS и дополнительно по HTTP (гарантия доставки)', () async {
      final sent = <dynamic>[];
      final ws = _RecordingWebSocketChannel(sent);
      final httpClient = _RecordingHttpClient();

      final service = WebSocketService(httpClient: httpClient);
      service.debugAttachConnectedChannel(ws, currentPublicKey: 'SENDER_PUBKEY');

      service.sendSignalingMessage('RECIPIENT', 'hang-up', {});

      // HTTP отправка внутри сервиса не await-ится — даём микротаскам отработать.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(sent, hasLength(1));
      final wsDecoded = json.decode(sent.single as String) as Map<String, dynamic>;
      expect(wsDecoded['type'], equals('hang-up'));

      expect(httpClient.requests, isNotEmpty);
      // Важно: в body есть sender_pubkey/recipient_pubkey/signal_type.
      // HTTP отправляется на ВСЕ хосты для гарантии доставки
      expect(httpClient.bodies, isNotEmpty);
      final bodyDecoded = json.decode(httpClient.bodies.first) as Map<String, dynamic>;
      expect(bodyDecoded['sender_pubkey'], equals('SENDER_PUBKEY'));
      expect(bodyDecoded['recipient_pubkey'], equals('RECIPIENT'));
      expect(bodyDecoded['signal_type'], equals('hang-up'));
    });
  });
}


