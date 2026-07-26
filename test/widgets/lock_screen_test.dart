import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/lock_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

void main() {
  group('LockScreen widget tests', () {
    late AuthService auth;

    setUp(() async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.physicalSizeTestValue = const Size(1080, 1920);
      binding.window.devicePixelRatioTestValue = 1.0;
      // AuthService держит best-effort маркер PIN в SharedPreferences; без
      // мока getInstance() виснет под fake-async виджет-тестов.
      SharedPreferences.setMockInitialValues({});

      auth = AuthService.createForTesting(
          secureStorage: _MemSecureStorage(),
          fastHash: true,
          monotonicNow: () async => 0);
      await auth.init();
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    testWidgets('Правильный PIN вызывает onUnlocked (и не duress/wipe)', (tester) async {
      await auth.setPin('123456');

      var unlocked = 0;
      var duress = 0;
      var wiped = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: LockScreen.forTesting(
            auth: auth,
            onUnlocked: () => unlocked++,
            onDuressMode: () => duress++,
            onWipe: (_) async => wiped++,
          ),
        ),
      );
      await tester.pump();

      await _enterPin(tester, '123456');
      // Внутри есть delay(300ms) перед verifyPin
      await tester.pump(const Duration(milliseconds: 350));

      expect(unlocked, 1);
      expect(duress, 0);
      expect(wiped, 0);
    });

    testWidgets('Duress PIN вызывает onDuressMode', (tester) async {
      await auth.setPin('111111');
      final ok = await auth.setDuressCode('111111', '222222');
      expect(ok, isTrue);

      var unlocked = 0;
      var duress = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: LockScreen.forTesting(
            auth: auth,
            onUnlocked: () => unlocked++,
            onDuressMode: () => duress++,
            onWipe: (_) async {},
          ),
        ),
      );
      await tester.pump();

      await _enterPin(tester, '222222');
      await tester.pump(const Duration(milliseconds: 350));

      expect(unlocked, 0);
      expect(duress, 1);
    });

    testWidgets('Wipe code показывает диалог и wipe выполняется только после удержания', (tester) async {
      await auth.setPin('111111');
      final ok = await auth.setWipeCode('111111', '333333');
      expect(ok, isTrue);

      var wiped = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: LockScreen.forTesting(
            auth: auth,
            onUnlocked: () {},
            onDuressMode: () {},
            onWipe: (_) async => wiped++,
          ),
        ),
      );
      await tester.pump();

      await _enterPin(tester, '333333');
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('УДАЛИТЬ ВСЕ ДАННЫЕ?'), findsOneWidget);
      expect(wiped, 0);

      // Удерживаем кнопку 2s (в диалоге она обрабатывает onLongPressStart/End),
      // поэтому делаем "настоящий" press-and-hold.
      final holdTarget = find.ancestor(
        of: find.text('УДЕРЖИВАТЬ'),
        matching: find.byType(GestureDetector),
      );
      expect(holdTarget, findsOneWidget);

      final center = tester.getCenter(holdTarget);
      final gesture = await tester.startGesture(center);
      // В диалоге прогресс держания считается через DateTime.now(),
      // а тик прогресса идёт через Timer.periodic (который в widget-тестах живёт во "времени pump()").
      // Поэтому двигаем оба времени синхронно: реальный sleep + tester.pump(step).
      await tester.runAsync(() async {
        const step = Duration(milliseconds: 50);
        const total = Duration(seconds: 3);
        final ticks = total.inMilliseconds ~/ step.inMilliseconds;
        for (var i = 0; i < ticks; i++) {
          await Future<void>.delayed(step);
          await tester.pump(step);
        }
      });
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));

      expect(wiped, 1);
    });

    testWidgets('Неверный PIN показывает ошибку', (tester) async {
      await auth.setPin('123456');

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: LockScreen.forTesting(
            auth: auth,
            onUnlocked: () {},
            onDuressMode: () {},
            onWipe: (_) async {},
          ),
        ),
      );
      await tester.pump();

      await _enterPin(tester, '000000');
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Неверный PIN'), findsOneWidget);
    });
  });

  // Группа поднимает лок ТАК ЖЕ, КАК В ПРОДЕ — оверлеем в `MaterialApp.builder`
  // поверх Navigator, а не через `home:`. Разница принципиальна: у контекста внутри
  // builder нет Navigator в предках (MaterialApp создаёт Navigator и лишь ПОТОМ
  // заворачивает его в builder), поэтому всё, что дергает Navigator из LockScreen,
  // в проде падает, а в тестах с `home:` — работает. Именно так и было пропущено,
  // что код удаления с локскрина не срабатывает никогда.
  group('LockScreen как оверлей (структура прода)', () {
    late AuthService auth;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      auth = AuthService.createForTesting(
          secureStorage: _MemSecureStorage(),
          fastHash: true,
          monotonicNow: () async => 0);
      await auth.init();
    });

    Future<int> pumpLockOverlay(
      WidgetTester tester, {
      required List<WipeReason> wipes,
    }) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              Positioned.fill(
                child: LockScreen.forTesting(
                  auth: auth,
                  onUnlocked: () {},
                  onDuressMode: () {},
                  onWipe: (reason) async => wipes.add(reason),
                ),
              ),
            ],
          ),
          home: const Scaffold(backgroundColor: Colors.black),
        ),
      );
      await tester.pump();
      return 0;
    }

    testWidgets('код удаления открывает подтверждение и удержание запускает wipe',
        (tester) async {
      await auth.setPin('123456');
      expect(await auth.setWipeCode('123456', '333333'), isTrue);

      final wipes = <WipeReason>[];
      await pumpLockOverlay(tester, wipes: wipes);

      await _enterPin(tester, '333333');
      await tester.pump(const Duration(milliseconds: 350));

      // Подтверждение должно ПОЯВИТЬСЯ: раньше здесь летел FlutterError
      // «Navigator operation requested with a context that does not include a
      // Navigator», и до onWipe дело не доходило никогда.
      expect(find.text('УДАЛИТЬ ВСЕ ДАННЫЕ?'), findsOneWidget);
      expect(wipes, isEmpty, reason: 'без удержания стирать нельзя');

      // Удержание 2 секунды -> wipe.
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('УДЕРЖИВАТЬ')));
      await tester.pump(const Duration(milliseconds: 600)); // порог long-press
      expect(wipes, isEmpty, reason: 'полсекунды удержания ещё не стирают');

      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pump();

      expect(wipes, equals([WipeReason.wipeCode]));
    });

    testWidgets('отмена в подтверждении не стирает и убирает окно',
        (tester) async {
      await auth.setPin('123456');
      expect(await auth.setWipeCode('123456', '333333'), isTrue);

      final wipes = <WipeReason>[];
      await pumpLockOverlay(tester, wipes: wipes);

      await _enterPin(tester, '333333');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('УДАЛИТЬ ВСЕ ДАННЫЕ?'), findsOneWidget);

      await tester.tap(find.text('Отмена'));
      await tester.pump();

      expect(wipes, isEmpty);
      expect(find.text('УДАЛИТЬ ВСЕ ДАННЫЕ?'), findsNothing);
      // Пин-пад снова доступен — пользователь может ввести настоящий PIN.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('авто-wipe с оверлея работает (регресс-страховка)',
        (tester) async {
      await auth.setPin('123456');
      await auth.setAutoWipe(true, attempts: 3);

      final wipes = <WipeReason>[];
      await pumpLockOverlay(tester, wipes: wipes);

      for (var i = 0; i < 3; i++) {
        await _enterPin(tester, '000000');
        await tester.pump(const Duration(milliseconds: 350));
      }

      expect(wipes, equals([WipeReason.autoWipe]));
    });
  });
}


