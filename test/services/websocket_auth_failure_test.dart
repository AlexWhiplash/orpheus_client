import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/websocket_service.dart';

// Политика AuthFailed: серия подряд проваленных PoP-хендшейков (pop-error от
// сервера или закрытие сокета после отправленного proof без pop-ok) трактуется
// как отказ авторизации, а не сетевой сбой. Инцидент 13.07.2026: до-PoP клиенты
// после серверного деплоя показывали вечный Disconnected без намёка на причину.
void main() {
  group('WebSocketService AuthFailed policy', () {
    late WebSocketService service;

    setUp(() {
      service = WebSocketService();
    });

    tearDown(() {
      service.disconnect();
    });

    test('до порога — обычный Disconnected, isAuthFailed=false', () async {
      service.debugSimulateAuthFailure(popErrorCode: 'bad_signature');
      service.debugSimulateAuthFailure(popErrorCode: 'bad_signature');

      expect(service.isAuthFailed, isFalse);
      expect(service.currentStatus, ConnectionStatus.Disconnected);
      expect(service.lastPopErrorCode, 'bad_signature');
    });

    test('после порога (3 подряд) — статус AuthFailed', () async {
      for (var i = 0; i < 3; i++) {
        service.debugSimulateAuthFailure(popErrorCode: 'wrong_first_frame');
      }

      expect(service.isAuthFailed, isTrue);
      expect(service.currentStatus, ConnectionStatus.AuthFailed);
      expect(service.lastPopErrorCode, 'wrong_first_frame');
    });

    test('статус-стрим доносит AuthFailed до подписчиков (UI-баннер)', () async {
      final statuses = <ConnectionStatus>[];
      final sub = service.status.listen(statuses.add);

      for (var i = 0; i < 3; i++) {
        service.debugSimulateAuthFailure();
      }
      await Future.delayed(const Duration(milliseconds: 50));

      await sub.cancel();
      expect(statuses, contains(ConnectionStatus.AuthFailed));
    });

    test('намеренный disconnect в AuthFailed безопасен и завершает ретраи', () {
      for (var i = 0; i < 3; i++) {
        service.debugSimulateAuthFailure();
      }
      expect(() => service.disconnect(), returnsNormally);
      expect(service.currentStatus, ConnectionStatus.Disconnected);
    });
  });
}
