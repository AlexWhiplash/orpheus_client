import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:orpheus_project/services/background_call_service.dart';
import 'package:orpheus_project/services/push_connection_service.dart';

/// Фейковый backend постоянного сервиса (PushConnectionService), чтобы не дёргать
/// MethodChannel. BackgroundCallService теперь тонкий фасад над ним.
class _FakeBackend implements PushServiceBackend {
  int createChannelCalls = 0;
  int configureCalls = 0;
  int isRunningCalls = 0;
  int startCalls = 0;
  final invoked = <({String method, Map<String, dynamic>? args})>[];

  bool running = false;

  Object? throwOnCreateChannel;
  Object? throwOnConfigure;
  Object? throwOnIsRunning;
  Object? throwOnStart;
  Object? throwOnInvoke;

  @override
  Future<void> createNotificationChannel({
    required String channelId,
    required String channelName,
    required String description,
  }) async {
    createChannelCalls += 1;
    if (throwOnCreateChannel != null) throw throwOnCreateChannel!;
  }

  @override
  Future<void> configure({
    required void Function(ServiceInstance service) onStart,
    required String notificationChannelId,
    required int notificationId,
  }) async {
    configureCalls += 1;
    if (throwOnConfigure != null) throw throwOnConfigure!;
  }

  @override
  Future<bool> isRunning() async {
    isRunningCalls += 1;
    if (throwOnIsRunning != null) throw throwOnIsRunning!;
    return running;
  }

  @override
  Future<void> startService() async {
    startCalls += 1;
    if (throwOnStart != null) throw throwOnStart!;
    running = true;
  }

  @override
  void invoke(String method, [Map<String, dynamic>? args]) {
    if (throwOnInvoke != null) throw throwOnInvoke!;
    invoked.add((method: method, args: args));
  }
}

void main() {
  group('PushConnectionService / BackgroundCallService (фасад)', () {
    late _FakeBackend backend;

    setUp(() {
      backend = _FakeBackend();
      PushConnectionService.debugSetBackendForTesting(backend);
      PushConnectionService.debugResetForTesting();
    });

    tearDown(() {
      PushConnectionService.debugSetBackendForTesting(null);
      PushConnectionService.debugResetForTesting();
    });

    test('initialize идемпотентен: channel+configure вызываются один раз', () async {
      await PushConnectionService.initialize();
      await PushConnectionService.initialize();

      expect(backend.createChannelCalls, equals(1));
      expect(backend.configureCalls, equals(1));
    });

    test('start: если не running — инициализирует и стартует сервис', () async {
      backend.running = false;
      await PushConnectionService.start();

      expect(backend.createChannelCalls, equals(1));
      expect(backend.configureCalls, equals(1));
      expect(backend.startCalls, equals(1));
      expect(backend.running, isTrue);
    });

    test('start: если уже running — не стартует повторно', () async {
      backend.running = true;
      await PushConnectionService.start();

      expect(backend.startCalls, equals(0));
      expect(backend.configureCalls, equals(1));
    });

    test('фасад startCallService: поднимает сервис и входит в call mode', () async {
      backend.running = false;
      await BackgroundCallService.startCallService(contactName: 'Alice');

      expect(backend.startCalls, equals(1));
      final enter = backend.invoked.where((e) => e.method == 'enterCallMode');
      expect(enter, hasLength(1));
      expect(enter.single.args?['title'], equals('Alice'));
    });

    test('фасад stopCallService: НЕ останавливает сервис, только exitCallMode', () async {
      backend.running = true;
      await BackgroundCallService.stopCallService();

      expect(backend.invoked.where((e) => e.method == 'stopService'), isEmpty);
      expect(backend.invoked.where((e) => e.method == 'exitCallMode'), hasLength(1));
    });

    test('updateCallDuration шлёт enterCallMode с длительностью', () async {
      BackgroundCallService.updateCallDuration('00:12', 'Alice');
      final enter = backend.invoked.where((e) => e.method == 'enterCallMode');
      expect(enter, hasLength(1));
      expect(enter.single.args, equals({'title': 'Alice', 'content': '00:12'}));
    });

    test('stop: если running — вызывает stopService', () async {
      backend.running = true;
      await PushConnectionService.stop();
      expect(backend.invoked.where((e) => e.method == 'stopService'), hasLength(1));
    });

    test('ошибки backend не должны пробрасываться наружу (best-effort)', () async {
      backend.throwOnCreateChannel = StateError('boom:create');
      backend.throwOnConfigure = StateError('boom:configure');
      backend.throwOnIsRunning = StateError('boom:isRunning');
      backend.throwOnStart = StateError('boom:start');
      backend.throwOnInvoke = StateError('boom:invoke');

      await PushConnectionService.initialize();
      await PushConnectionService.start();
      await PushConnectionService.stop();
      await BackgroundCallService.startCallService();
      await BackgroundCallService.stopCallService();
      BackgroundCallService.updateCallDuration('00:01', 'Bob');
    });
  });
}
