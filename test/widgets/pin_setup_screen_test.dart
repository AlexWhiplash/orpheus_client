import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/pin_setup_screen.dart';
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

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final ch in pin.split('')) {
    await tester.tap(find.text(ch));
    await tester.pump();
  }
  // Внутри есть delay(200ms) перед обработкой
  await tester.pump(const Duration(milliseconds: 250));
}

/// Выбирает длину PIN на экране выбора (для setPin)
Future<void> _selectPinLength(WidgetTester tester, int length) async {
  final title = length == 4 ? '4 цифры' : '6 цифр';
  await tester.tap(find.text(title));
  await tester.pump();
}

void main() {
  group('PinSetupScreen widget tests', () {
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

    testWidgets('setPin: mismatch на подтверждении показывает ошибку и сбрасывает шаг', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: PinSetupScreen(
            mode: PinSetupMode.setPin,
            auth: auth,
          ),
        ),
      );
      await tester.pump();

      // Сначала выбираем длину PIN (новый шаг)
      expect(find.text('ВЫБЕРИТЕ ДЛИНУ PIN'), findsOneWidget);
      await _selectPinLength(tester, 6);
      await tester.pump();

      // Первый ввод
      await _enterPin(tester, '123456');
      expect(find.text('ПОДТВЕРДИТЕ PIN'), findsOneWidget);

      // Подтверждение неверное
      await _enterPin(tester, '000000');
      expect(find.text('PIN-коды не совпадают'), findsOneWidget);

      // Должны вернуться на шаг "НОВЫЙ PIN"
      expect(find.text('НОВЫЙ PIN'), findsOneWidget);
    });

    testWidgets('setPin: успешная установка вызывает onSuccess и выставляет config.isPinEnabled', (tester) async {
      var success = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: PinSetupScreen(
            mode: PinSetupMode.setPin,
            auth: auth,
            onSuccess: () => success++,
          ),
        ),
      );
      await tester.pump();

      // Сначала выбираем длину PIN (новый шаг)
      expect(find.text('ВЫБЕРИТЕ ДЛИНУ PIN'), findsOneWidget);
      await _selectPinLength(tester, 6);
      await tester.pump();

      await _enterPin(tester, '123456');
      expect(find.text('ПОДТВЕРДИТЕ PIN'), findsOneWidget);
      await _enterPin(tester, '123456');

      // Даем UI время показать snackbar/поп и вызвать callback.
      await tester.pump(const Duration(milliseconds: 300));

      expect(success, 1);
      expect(auth.config.isPinEnabled, isTrue);
      expect(auth.config.pinLength, equals(6));
    });

    testWidgets('changePin: неверный текущий PIN показывает ошибку', (tester) async {
      await auth.setPin('111111');

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: PinSetupScreen(
            mode: PinSetupMode.changePin,
            auth: auth,
          ),
        ),
      );
      await tester.pump();

      await _enterPin(tester, '000000');
      expect(find.text('Неверный PIN-код'), findsOneWidget);
      expect(find.text('ТЕКУЩИЙ PIN'), findsOneWidget);
    });

    testWidgets('setPin: 4-значный PIN успешно устанавливается', (tester) async {
      var success = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: PinSetupScreen(
            mode: PinSetupMode.setPin,
            auth: auth,
            onSuccess: () => success++,
          ),
        ),
      );
      await tester.pump();

      // Выбираем 4-значный PIN
      expect(find.text('ВЫБЕРИТЕ ДЛИНУ PIN'), findsOneWidget);
      await _selectPinLength(tester, 4);
      await tester.pump();

      // Вводим 4-значный PIN
      await _enterPin(tester, '1234');
      expect(find.text('ПОДТВЕРДИТЕ PIN'), findsOneWidget);
      await _enterPin(tester, '1234');

      await tester.pump(const Duration(milliseconds: 300));

      expect(success, 1);
      expect(auth.config.isPinEnabled, isTrue);
      expect(auth.config.pinLength, equals(4));
    });
  });
}






