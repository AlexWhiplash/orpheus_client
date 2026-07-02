import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // После отказа от Google/FCM иконка малых уведомлений задаётся программно
  // (flutter_local_notifications: AndroidInitializationSettings('ic_stat_orpheus')
  // и icon в AndroidNotificationDetails), а не через firebase-meta-data в манифесте.
  test('Монохромная иконка уведомления (drawable ic_stat_orpheus) существует', () async {
    final icon = File('android/app/src/main/res/drawable/ic_stat_orpheus.xml');
    expect(await icon.exists(), isTrue,
        reason: 'ic_stat_orpheus нужна как small icon, иначе в шторке "белый квадрат"');
  });

  test('Манифест больше не тянет firebase-messaging meta-data (де-гуглизация)', () async {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    expect(await manifest.exists(), isTrue);
    final xml = await manifest.readAsString();
    expect(xml, isNot(contains('com.google.firebase')));
  });
}






