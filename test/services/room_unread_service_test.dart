import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/room_model.dart';
import 'package:orpheus_project/services/room_unread_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = RoomUnreadService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc.debugResetForTesting();
  });

  test('noteIncoming помечает комнату непрочитанной', () {
    expect(svc.hasUnread.value, isFalse);
    svc.noteIncoming('r1');
    expect(svc.hasUnread.value, isTrue);
  });

  test('noteIncoming игнорирует открытую (активную) комнату', () {
    svc.activeRoomId = 'r1';
    svc.noteIncoming('r1');
    expect(svc.hasUnread.value, isFalse);
  });

  test('markSeen очищает непрочитанное для комнаты', () async {
    svc.noteIncoming('r1');
    expect(svc.hasUnread.value, isTrue);
    await svc.markSeen('r1');
    expect(svc.hasUnread.value, isFalse);
  });

  test('syncWithRooms: первый запуск не подсвечивает существующую историю', () async {
    await svc.syncWithRooms([
      Room(
        id: 'r1',
        name: 'R1',
        lastMessageAt: DateTime.fromMillisecondsSinceEpoch(5000),
      ),
    ]);
    expect(svc.hasUnread.value, isFalse);
  });

  test('syncWithRooms: сообщение новее last-seen -> непрочитано', () async {
    SharedPreferences.setMockInitialValues({
      'room_last_seen_v1': json.encode({'r1': 1000}),
    });
    svc.debugResetForTesting();
    await svc.syncWithRooms([
      Room(
        id: 'r1',
        name: 'R1',
        lastMessageAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ),
    ]);
    expect(svc.hasUnread.value, isTrue);
  });
}
