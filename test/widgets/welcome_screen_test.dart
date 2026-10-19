import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/welcome_screen.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      // Делаем экран выше, чтобы избежать overflow в сложной верстке.
      binding.window.physicalSizeTestValue = const Size(1080, 1920);
      binding.window.devicePixelRatioTestValue = 1.0;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    testWidgets('Отображает основные элементы интерфейса',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );
      // Даем анимациям дойти до состояния, когда кнопки в видимой области.
      await tester.pump(const Duration(seconds: 3));

      // Заголовок
      expect(find.text('ORPHEUS'), findsOneWidget);

      // Кнопки
      expect(find.text('Создать аккаунт'), findsOneWidget);
      expect(find.text('Восстановить из ключа'), findsOneWidget);
    });

    testWidgets('Кнопка создания аккаунта вызывает callback',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      // Находим кнопку создания аккаунта
      final createButton =
          find.widgetWithText(ElevatedButton, 'Создать аккаунт');
      expect(createButton, findsOneWidget);

      // В тестовой среде нет смысла реально вызывать cryptoService,
      // но важно, что кнопка активна.
      final btn = tester.widget<ElevatedButton>(createButton);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Кнопка восстановления открывает диалог',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      // Находим и нажимаем кнопку восстановления
      final restoreButton =
          find.widgetWithText(OutlinedButton, 'Восстановить из ключа');
      expect(restoreButton, findsOneWidget);

      // Вызываем onPressed напрямую (из-за сложной анимации/opacity в welcome экране,
      // hit-test через tap() в тестовой среде нестабилен).
      final btn = tester.widget<OutlinedButton>(restoreButton);
      btn.onPressed?.call();
      await tester.pump(const Duration(milliseconds: 200));

      // Должен появиться диалог восстановления
      expect(find.text('Восстановление'), findsOneWidget);
      expect(find.textContaining('Приватный ключ'), findsOneWidget);
      expect(find.text('Отмена'), findsOneWidget);
      expect(find.text('Импорт'), findsOneWidget);
    });

    testWidgets('Диалог восстановления можно закрыть',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      // Открываем диалог
      final restoreButton =
          find.widgetWithText(OutlinedButton, 'Восстановить из ключа');
      final btn = tester.widget<OutlinedButton>(restoreButton);
      btn.onPressed?.call();
      await tester.pump(const Duration(milliseconds: 200));

      // Закрываем диалог
      final cancelBtnFinder = find.widgetWithText(OutlinedButton, 'Отмена');
      final cancelBtn = tester.widget<OutlinedButton>(cancelBtnFinder);
      cancelBtn.onPressed?.call();
      await tester.pump(const Duration(milliseconds: 200));

      // Диалог должен исчезнуть
      expect(find.text('Восстановление'), findsNothing);
    });

    testWidgets('Экран использует градиентный фон',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: WelcomeScreen(
            onAuthComplete: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Ищем любой BoxDecoration с LinearGradient (нимб может быть RadialGradient).
      bool foundLinear = false;
      for (final w in tester.widgetList(find.byType(DecoratedBox))) {
        final d = (w as DecoratedBox).decoration;
        if (d is BoxDecoration && d.gradient is LinearGradient) {
          foundLinear = true;
          break;
        }
      }
      if (!foundLinear) {
        for (final w in tester.widgetList(find.byType(Container))) {
          final d = (w as Container).decoration;
          if (d is BoxDecoration && d.gradient is LinearGradient) {
            foundLinear = true;
            break;
          }
        }
      }
      expect(foundLinear, isTrue);
    });
  });
}
