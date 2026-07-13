import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLocalBackend implements NotificationLocalBackend {
  final createdChannels = <({String id, String name, String description, Importance importance})>[];
  int initializeCalls = 0;
  final shown = <({
    int id,
    String channelId,
    String channelName,
    String title,
    String body,
    AndroidNotificationCategory category,
    String androidSmallIcon,
    bool fullScreenIntent,
    bool ongoing,
    String? groupKey,
  })>[];
  final cancelled = <int>[];
  int cancelAllCalls = 0;

  Object? throwOnShow;
  Object? throwOnCancel;
  Object? throwOnCancelAll;

  @override
  Future<void> createAndroidChannel({
    required String id,
    required String name,
    required String description,
    required Importance importance,
    Color? ledColor,
  }) async {
    createdChannels.add((id: id, name: name, description: description, importance: importance));
  }

  @override
  Future<void> initialize({required void Function(NotificationResponse response) onTap}) async {
    initializeCalls += 1;
  }

  @override
  Future<void> show({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    required AndroidNotificationCategory category,
    required String androidSmallIcon,
    required bool fullScreenIntent,
    required bool ongoing,
    String? groupKey,
    String? payload,
  }) async {
    if (throwOnShow != null) throw throwOnShow!;
    shown.add((
      id: id,
      channelId: channelId,
      channelName: channelName,
      title: title,
      body: body,
      category: category,
      androidSmallIcon: androidSmallIcon,
      fullScreenIntent: fullScreenIntent,
      ongoing: ongoing,
      groupKey: groupKey,
    ));
  }

  @override
  Future<void> cancel(int id) async {
    if (throwOnCancel != null) throw throwOnCancel!;
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async {
    if (throwOnCancelAll != null) throw throwOnCancelAll!;
    cancelAllCalls += 1;
  }
}

void main() {
  group('NotificationService (контракты локальных уведомлений)', () {
    late _FakeLocalBackend backend;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Уведомления резолвят язык по сохранённому app_locale (фоновый изолят без контекста).
      SharedPreferences.setMockInitialValues({'app_locale': 'ru'});
      backend = _FakeLocalBackend();
      NotificationService.debugSetLocalBackendForTesting(backend);
    });

    tearDown(() {
      NotificationService.debugSetLocalBackendForTesting(null);
    });

    test('showCallNotification: обезличено — title=Входящий звонок, body=Закрытая связь (без имени)', () async {
      await NotificationService.showCallNotification(callerName: 'Alice');

      // каналы должны быть созданы при первой инициализации
      expect(
        backend.createdChannels.map((c) => c.id),
        containsAll(['orpheus_incoming_call', 'orpheus_calls', 'orpheus_messages']),
      );
      expect(backend.initializeCalls, equals(1));

      expect(backend.shown, hasLength(1));
      final s = backend.shown.single;
      expect(s.id, equals(1001));
      expect(s.channelId, equals('orpheus_incoming_call'));
      expect(s.title, equals('Входящий звонок'));
      expect(s.body, equals('Закрытая связь')); // не имя звонящего
      expect(s.category, equals(AndroidNotificationCategory.call));
      expect(s.androidSmallIcon, equals('ic_stat_orpheus'));
      expect(s.ongoing, isTrue);
      expect(s.fullScreenIntent, isTrue);
    });

    test('hideCallNotification: cancel(1001), ошибки игнорируются (best-effort)', () async {
      backend.throwOnCancel = StateError('boom');
      await NotificationService.hideCallNotification();
      // не падает
    });

    test('showMessageNotification: обезличено — title=Orpheus, без отправителя, body=Новое сообщение', () async {
      await NotificationService.showMessageNotification();

      expect(backend.shown, hasLength(1));
      final s = backend.shown.single;
      expect(s.channelId, equals('orpheus_messages'));
      expect(s.title, equals('Orpheus')); // не отправитель
      expect(s.body, equals('Новое сообщение'));
      expect(s.category, equals(AndroidNotificationCategory.message));
      expect(s.androidSmallIcon, equals('ic_stat_orpheus'));
      expect(s.groupKey, equals('orpheus_messages_group'));
    });

    test('hideMessageNotifications: cancelAll, ошибки игнорируются (best-effort)', () async {
      backend.throwOnCancelAll = StateError('boom');
      await NotificationService.hideMessageNotifications();
      // не падает
    });

    test('background message mapping: type=incoming_call/new_message + legacy call/message', () async {
      // новый протокол сервера
      await NotificationService.debugHandleBackgroundMessageForTesting({'type': 'incoming_call', 'caller_name': 'Carol'});
      await NotificationService.debugHandleBackgroundMessageForTesting({'type': 'new_message', 'sender_name': 'Dan'});
      // legacy
      await NotificationService.debugHandleBackgroundMessageForTesting({'type': 'call', 'sender_name': 'Eve'});
      await NotificationService.debugHandleBackgroundMessageForTesting({'type': 'message', 'sender_name': 'Frank'});
      await NotificationService.debugHandleBackgroundMessageForTesting({'type': 'incoming_call'}); // дефолт имя

      expect(backend.shown.where((s) => s.channelId == 'orpheus_incoming_call').length, equals(3));
      expect(backend.shown.where((s) => s.channelId == 'orpheus_messages').length, equals(2));
      // Обезличено: звонки — «Закрытая связь» (без имени), сообщения — «Новое сообщение».
      expect(backend.shown.where((s) => s.channelId == 'orpheus_incoming_call')
          .every((s) => s.body == 'Закрытая связь'), isTrue);
      expect(backend.shown.where((s) => s.channelId == 'orpheus_messages')
          .every((s) => s.body == 'Новое сообщение'), isTrue);
    });

    test('background handler policy: если есть notification payload — локальное уведомление не показываем', () {
      expect(
        NotificationService.shouldShowLocalNotification(
          hasNotificationPayload: true,
          data: {'type': 'incoming_call'},
        ),
        isFalse,
      );
      expect(
        NotificationService.shouldShowLocalNotification(
          hasNotificationPayload: true,
          data: {'type': 'new_message'},
        ),
        isFalse,
      );
    });

    test('background handler policy: data-only — локальное уведомление показываем для call/message типов', () {
      expect(
        NotificationService.shouldShowLocalNotification(
          hasNotificationPayload: false,
          data: {'type': 'incoming_call'},
        ),
        isTrue,
      );
      expect(
        NotificationService.shouldShowLocalNotification(
          hasNotificationPayload: false,
          data: {'type': 'new_message'},
        ),
        isTrue,
      );
      expect(
        NotificationService.shouldShowLocalNotification(
          hasNotificationPayload: false,
          data: {'type': 'call'},
        ),
        isTrue,
      );
      expect(
        NotificationService.shouldShowLocalNotification(
          hasNotificationPayload: false,
          data: {'type': 'message'},
        ),
        isTrue,
      );
      expect(
        NotificationService.shouldShowLocalNotification(
          hasNotificationPayload: false,
          data: {'type': 'something_else'},
        ),
        isFalse,
      );
    });

    test('ошибки backend.show не должны пробрасываться наружу (best-effort)', () async {
      backend.throwOnShow = StateError('boom');
      await NotificationService.showMessageNotification();
      await NotificationService.showCallNotification(callerName: 'Mallory');
    });
  });
}


