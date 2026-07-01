import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/security_settings_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';

class _MemSecureStorage implements AuthSecureStorage {
  final Map<String, String> _m = {};

  @override
  Future<void> delete({required String key}) async {
    _m.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _m.clear();
  }

  @override
  Future<String?> read({required String key}) async {
    return _m[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    _m[key] = value;
  }
}

void main() {
  group('SecuritySettingsScreen widget tests', () {
    late AuthService auth;

    setUp(() async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.physicalSizeTestValue = const Size(1080, 1920);
      binding.window.devicePixelRatioTestValue = 1.0;

      auth = AuthService.createForTesting(secureStorage: _MemSecureStorage());
      await auth.init();
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    testWidgets('Когда PIN не установлен — предлагает "Установить PIN-код"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: SecuritySettingsScreen(auth: auth),
        ),
      );
      await tester.pump();

      expect(find.text('БЕЗОПАСНОСТЬ'), findsOneWidget);
      expect(find.text('Установить PIN-код'), findsOneWidget);
      expect(find.text('Изменить PIN-код'), findsNothing);
      expect(find.text('Отключить PIN-код'), findsNothing);
    });

    testWidgets('Когда PIN установлен — показывает "Изменить/Отключить PIN-код" и секции duress/wipe', (tester) async {
      await auth.setPin('123456');

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: SecuritySettingsScreen(auth: auth),
        ),
      );
      await tester.pump();

      expect(find.text('Изменить PIN-код'), findsOneWidget);
      expect(find.text('Отключить PIN-код'), findsOneWidget);

      // Duress
      expect(find.text('КОД ПРИНУЖДЕНИЯ'), findsOneWidget);
      expect(find.text('Установить код принуждения'), findsOneWidget);

      // Wipe code
      expect(find.text('КОД УДАЛЕНИЯ'), findsOneWidget);
      expect(find.text('Установить код удаления'), findsOneWidget);
    });
  });
}






