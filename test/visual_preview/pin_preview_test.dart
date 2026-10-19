// Визуальное превью: блокировка и настройка PIN (этап 3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/screens/lock_screen.dart';
import 'package:orpheus_project/screens/pin_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stage3_harness.dart';

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final ch in digits.split('')) {
    await tester.tap(find.text(ch));
    await tester.pump();
  }
}

void main() {
  setUpAll(loadStage3Fonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lock', (tester) async {
    final auth = await stage3Auth();
    await auth.setPin('123456');
    await auth.setBiometricEnabled(true);
    setStage3Surface(tester);
    await tester.pumpWidget(stage3App(LockScreen.forTesting(
      auth: auth,
      onUnlocked: () {},
      onDuressMode: () {},
      onWipe: (_) async {},
    )));
    await precacheStage3Assets(tester);
    await _tapDigits(tester, '123');
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/lock.png'));
  });

  testWidgets('lock_wipe_confirm', (tester) async {
    final auth = await stage3Auth();
    await auth.setPin('123456');
    await auth.setWipeCode('123456', '999999');
    setStage3Surface(tester);
    await tester.pumpWidget(stage3App(LockScreen.forTesting(
      auth: auth,
      onUnlocked: () {},
      onDuressMode: () {},
      onWipe: (_) async {},
    )));
    await precacheStage3Assets(tester);
    await tester.runAsync(() async {
      for (final ch in '999999'.split('')) {
        await tester.tap(find.text(ch));
        await tester.pump();
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/lock_wipe_confirm.png'));
  });

  testWidgets('pin_setup_length', (tester) async {
    final auth = await stage3Auth();
    setStage3Surface(tester);
    await tester.pumpWidget(stage3App(
        PinSetupScreen(mode: PinSetupMode.setPin, auth: auth)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/pin_setup_length.png'));
  });

  testWidgets('pin_setup_duress', (tester) async {
    final auth = await stage3Auth();
    await auth.setPin('123456');
    setStage3Surface(tester);
    await tester.pumpWidget(stage3App(
        PinSetupScreen(mode: PinSetupMode.setDuress, auth: auth)));
    await tester.pumpAndSettle();
    await _tapDigits(tester, '12');
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/pin_setup_duress.png'));
  });
}
