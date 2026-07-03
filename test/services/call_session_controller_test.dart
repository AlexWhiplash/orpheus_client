import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/call_session_controller.dart';
import 'package:orpheus_project/services/websocket_service.dart' show ConnectionStatus;

/// Фейковый peer: считает вызовы restartIce и отдаёт заданный результат.
class _FakeOps implements CallOps {
  int restartIceCalls = 0;
  bool result = true;

  @override
  Future<bool> restartIce() async {
    restartIceCalls++;
    return result;
  }
}

void main() {
  group('CallSessionController.initialStateFor', () {
    test('autoAnswer + offer -> Connecting', () {
      expect(
        CallSessionController.initialStateFor(autoAnswer: true, hasOffer: true),
        CallState.Connecting,
      );
    });

    test('offer без autoAnswer -> Incoming', () {
      expect(
        CallSessionController.initialStateFor(autoAnswer: false, hasOffer: true),
        CallState.Incoming,
      );
    });

    test('без offer -> Dialing (исходящий)', () {
      expect(
        CallSessionController.initialStateFor(autoAnswer: false, hasOffer: false),
        CallState.Dialing,
      );
    });

    test('autoAnswer без offer -> Dialing', () {
      expect(
        CallSessionController.initialStateFor(autoAnswer: true, hasOffer: false),
        CallState.Dialing,
      );
    });
  });

  group('CallSessionController.statusText', () {
    CallSessionController make(CallState s) =>
        CallSessionController(ops: _FakeOps(), initialState: s);

    test('маппинг состояний', () {
      expect(make(CallState.Dialing).statusText, 'Calling...');
      expect(make(CallState.Incoming).statusText, 'Incoming call');
      expect(make(CallState.Connecting).statusText, 'Connecting...');
      expect(make(CallState.Reconnecting).statusText, 'Reconnecting...');
      expect(make(CallState.Rejected).statusText, 'Ended');
      expect(make(CallState.Failed).statusText, 'Failed');
      // Connected -> пусто (показывается таймер)
      expect(make(CallState.Connected).statusText, '');
    });
  });

  group('CallSessionController — переходы', () {
    test('onNetworkLost переводит в Reconnecting ТОЛЬКО из Connected', () {
      final connected =
          CallSessionController(ops: _FakeOps(), initialState: CallState.Connected);
      connected.onNetworkLost();
      expect(connected.callState, CallState.Reconnecting);
      expect(connected.isReconnecting, isTrue);
      expect(connected.reconnectAttempts, 0);

      // Из не-Connected — no-op
      for (final s in [CallState.Dialing, CallState.Incoming, CallState.Connecting]) {
        final c = CallSessionController(ops: _FakeOps(), initialState: s);
        c.onNetworkLost();
        expect(c.callState, s, reason: 'onNetworkLost не должен трогать состояние $s');
        expect(c.isReconnecting, isFalse);
      }
    });

    test('onConnected сбрасывает режим реконнекта', () {
      final c = CallSessionController(ops: _FakeOps(), initialState: CallState.Connected);
      c.onNetworkLost(); // -> Reconnecting, isReconnecting=true
      c.onConnected();
      expect(c.callState, CallState.Connected);
      expect(c.isReconnecting, isFalse);
      expect(c.reconnectAttempts, 0);
    });

    test('onRemoteHangup -> Rejected', () {
      final c = CallSessionController(ops: _FakeOps(), initialState: CallState.Connected);
      c.onRemoteHangup();
      expect(c.callState, CallState.Rejected);
      expect(c.isReconnecting, isFalse);
    });

    test('onError -> Failed с сообщением', () {
      final c = CallSessionController(ops: _FakeOps(), initialState: CallState.Connected);
      c.onError('boom');
      expect(c.callState, CallState.Failed);
      expect(c.debugStatus, 'boom');
      expect(c.isReconnecting, isFalse);
    });

    test('notifyListeners срабатывает на переходе', () {
      final c = CallSessionController(ops: _FakeOps(), initialState: CallState.Connected);
      var notified = 0;
      c.addListener(() => notified++);
      c.onNetworkLost();
      expect(notified, greaterThan(0));
    });
  });

  group('CallSessionController — политика ICE-restart', () {
    /// Создаёт контроллер в состоянии Reconnecting с управляемыми часами/планировщиком.
    ({
      CallSessionController c,
      _FakeOps ops,
      List<void Function()> scheduled,
      void Function(Duration) advance,
    }) makeReconnecting({bool wsConnected = true}) {
      var now = DateTime(2024, 1, 1);
      final scheduled = <void Function()>[];
      final ops = _FakeOps();
      final c = CallSessionController(
        ops: ops,
        now: () => now,
        scheduler: (delay, action) => scheduled.add(action),
        initialState: CallState.Connected,
      );
      if (!wsConnected) {
        c.updateWsStatus(ConnectionStatus.Disconnected);
      }
      c.onNetworkLost(); // -> Reconnecting, isReconnecting=true, attempts=0
      return (c: c, ops: ops, scheduled: scheduled, advance: (d) => now = now.add(d));
    }

    test('attemptIceRestart инкрементит попытки и зовёт restartIce (ws Connected)', () async {
      final h = makeReconnecting();
      await h.c.attemptIceRestart();
      expect(h.c.reconnectAttempts, 1);
      expect(h.ops.restartIceCalls, 1);
    });

    test('дебаунс: повтор в пределах 3с игнорируется', () async {
      final h = makeReconnecting();
      await h.c.attemptIceRestart();
      expect(h.c.reconnectAttempts, 1);
      // Повтор без сдвига часов — дебаунс
      await h.c.attemptIceRestart();
      expect(h.c.reconnectAttempts, 1, reason: 'должен быть задебаунсен');
      expect(h.ops.restartIceCalls, 1);
      // После 4с — новая попытка проходит
      h.advance(const Duration(seconds: 4));
      await h.c.attemptIceRestart();
      expect(h.c.reconnectAttempts, 2);
      expect(h.ops.restartIceCalls, 2);
    });

    test('исчерпание попыток -> onError(Failed)', () async {
      final h = makeReconnecting();
      // 5 успешных попыток (attempts 1..5), между ними сдвигаем часы за дебаунс
      for (var i = 0; i < CallSessionController.maxReconnectAttempts; i++) {
        await h.c.attemptIceRestart();
        h.advance(const Duration(seconds: 4));
      }
      expect(h.c.reconnectAttempts, CallSessionController.maxReconnectAttempts);
      // Следующая попытка: attempts(5) >= max(5) -> Failed
      await h.c.attemptIceRestart();
      expect(h.c.callState, CallState.Failed);
      expect(h.c.debugStatus, 'Failed to restore connection');
    });

    test('ws не Connected: restartIce НЕ зовётся, планируется повтор', () async {
      final h = makeReconnecting(wsConnected: false);
      await h.c.attemptIceRestart();
      expect(h.ops.restartIceCalls, 0, reason: 'без WS offer не отправить');
      expect(h.scheduled, isNotEmpty, reason: 'должен запланировать повтор');
    });

    test('неудачный restartIce планирует повтор', () async {
      final h = makeReconnecting();
      h.ops.result = false;
      await h.c.attemptIceRestart();
      expect(h.ops.restartIceCalls, 1);
      expect(h.scheduled, isNotEmpty, reason: 'при неуспехе — повтор');
    });

    test('восстановление WS во время реконнекта запускает ICE-restart', () async {
      final h = makeReconnecting(wsConnected: false);
      // WS восстановился -> триггерит attemptIceRestart
      h.c.updateWsStatus(ConnectionStatus.Connected);
      // attemptIceRestart async; дождёмся микротасков
      await Future<void>.delayed(Duration.zero);
      expect(h.c.reconnectAttempts, 1);
      expect(h.ops.restartIceCalls, 1);
    });

    test('onNetworkRestored вне реконнекта — no-op', () async {
      final ops = _FakeOps();
      final c = CallSessionController(ops: ops, initialState: CallState.Connected);
      c.onNetworkRestored(); // не в реконнекте
      await Future<void>.delayed(Duration.zero);
      expect(ops.restartIceCalls, 0);
      expect(c.reconnectAttempts, 0);
    });
  });
}
