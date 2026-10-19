// Визуальное превью: Безопасность (этап 3) — настоящий SecuritySettingsScreen
// с тестовым AuthService (PIN + код принуждения), и он же под duress.
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/screens/security_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stage3_harness.dart';

void main() {
  setUpAll(loadStage3Fonts);

  Future<void> shoot(WidgetTester tester, String name, {bool duress = false}) async {
    SharedPreferences.setMockInitialValues({});
    final auth = await stage3Auth();
    await auth.setPin('123456');
    await auth.setDuressCode('123456', '654321');
    if (duress) auth.debugSetDuressMode(true);
    addTearDown(() => auth.debugSetDuressMode(false));

    setStage3Surface(tester, height: duress ? 1500 : 2000);
    await tester.pumpWidget(stage3App(SecuritySettingsScreen(auth: auth)));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(SecuritySettingsScreen), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('security', (tester) => shoot(tester, 'security'));
  testWidgets('security_duress',
      (tester) => shoot(tester, 'security_duress', duress: true));
}
