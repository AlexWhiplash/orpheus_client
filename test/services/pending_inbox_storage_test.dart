import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orpheus_project/main.dart' show parkPersonalChatUntilRealSession;
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/pending_inbox_storage.dart';

// Очередь конвертов, доставленных push-изолятом при убитом приложении (сервер их
// не кладёт в оффлайн, т.к. считал нас онлайн по push-сокету). main-изолят сливает
// её при старте недеструктивно: удаляет ТОЛЬКО обработанное. Инцидент 13.07.2026:
// первое сообщение в спящий телефон терялось — уведомление было, а текста нет.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Map<String, dynamic> env(String id, {String sender = 'AAAA'}) => {
        'type': 'chat',
        'sender_pubkey': sender,
        'payload': 'ciphertext-$id',
        'message_id': id,
        'senc': 'enc',
        'ssig': 'sig',
      };

  test('append + peekAll возвращает конверты в порядке поступления', () async {
    final s = PendingInboxStorage.instance;
    await s.append(env('m1'));
    await s.append(env('m2'));

    final items = await s.peekAll();
    expect(items.map((e) => e.envelope['message_id']), ['m1', 'm2']);
    expect(items.first.envelope['payload'], 'ciphertext-m1');
  });

  test('peekAll недеструктивен: повторный peek возвращает то же', () async {
    final s = PendingInboxStorage.instance;
    await s.append(env('m1'));
    expect((await s.peekAll()).length, 1);
    expect((await s.peekAll()).length, 1); // не удалилось
  });

  test('removeProcessed убирает только обработанные, остальное сохраняется', () async {
    final s = PendingInboxStorage.instance;
    await s.append(env('m1'));
    await s.append(env('m2'));
    final items = await s.peekAll();

    // Обработали только первый.
    await s.removeProcessed({items.first.raw});

    final left = await s.peekAll();
    expect(left.map((e) => e.envelope['message_id']), ['m2']);
  });

  test('конверт, добавленный ПОСЛЕ peek, переживает removeProcessed (гонка изолятов)', () async {
    final s = PendingInboxStorage.instance;
    await s.append(env('m1'));
    final items = await s.peekAll(); // main прочитал снапшот [m1]

    // push-изолят добавил m2, пока main обрабатывал m1.
    await s.append(env('m2'));

    // main удаляет только обработанный m1 — m2 остаётся.
    await s.removeProcessed(items.map((e) => e.raw).toSet());

    final left = await s.peekAll();
    expect(left.map((e) => e.envelope['message_id']), ['m2']);
  });

  test('дедуп по message_id: повторный конверт не копится', () async {
    final s = PendingInboxStorage.instance;
    await s.append(env('dup'));
    await s.append(env('dup'));
    await s.append(env('other'));

    final items = await s.peekAll();
    expect(items.map((e) => e.envelope['message_id']), ['dup', 'other']);
  });

  test('протухшие по TTL конверты не отдаются в peekAll', () async {
    final old = DateTime.now().millisecondsSinceEpoch -
        PendingInboxStorage.maxAgeMs -
        1000;
    SharedPreferences.setMockInitialValues({
      'pending_inbox_envelopes': [
        '{"env":{"type":"chat","sender_pubkey":"A","message_id":"stale","payload":"x"},"ts":$old}',
      ],
    });
    final s = PendingInboxStorage.instance;
    await s.append(env('fresh'));

    final items = await s.peekAll();
    expect(items.map((e) => e.envelope['message_id']), ['fresh']);
  });

  test('пустая очередь -> пустой список без ошибок', () async {
    expect(await PendingInboxStorage.instance.peekAll(), isEmpty);
    await PendingInboxStorage.instance.removeProcessed({}); // no-op, без ошибок
  });

  // Личное сообщение, пришедшее в duress-сессию, раньше терялось НАВСЕГДА: строгий
  // mutual-add спрашивает isContact, а тот под duress отвечает false, и кадр дропался
  // до записи — при том что сервер уже считал его доставленным.
  group('duress: входящее откладывается, а не теряется', () {
    tearDown(() => AuthService.instance.debugSetDuressMode(false));

    test('личный chat уходит в очередь и НЕ обрабатывается сейчас', () async {
      AuthService.instance.debugSetDuressMode(true);

      final parked = await parkPersonalChatUntilRealSession(
          json.encode(env('m1', sender: 'REAL_CONTACT')));

      expect(parked, isTrue, reason: 'обработку надо остановить, кадр отложен');
      final items = await PendingInboxStorage.instance.peekAll();
      expect(items.single.envelope['message_id'], 'm1');
      expect(items.single.envelope['payload'], 'ciphertext-m1',
          reason: 'кладём конверт как есть, шифртекст не трогаем');
    });

    test('не-chat кадры не откладываются (звонки, служебное)', () async {
      AuthService.instance.debugSetDuressMode(true);

      for (final type in ['call-offer', 'hang-up', 'room-message', 'pong']) {
        final parked = await parkPersonalChatUntilRealSession(
            json.encode({'type': type, 'sender_pubkey': 'X'}));
        expect(parked, isFalse, reason: '$type откладывать нельзя');
      }
      expect(await PendingInboxStorage.instance.peekAll(), isEmpty);
    });

    test('битый JSON не роняет обработку входящих', () async {
      AuthService.instance.debugSetDuressMode(true);
      expect(await parkPersonalChatUntilRealSession('{не json'), isFalse);
      expect(await parkPersonalChatUntilRealSession('[]'), isFalse);
    });
  });
}
