import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/home_screen.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqlite_api.dart';

void main() {
  // Инициализация FFI для SQLite в widget-тестах (HomeScreen по умолчанию открывает ContactsScreen).
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Beta disclaimer (one-time) widget tests', () {
    late Database testDb;

    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      // Увеличиваем экран, чтобы избежать overflow в сложной верстке.
      binding.window.physicalSizeTestValue = const Size(1080, 1920);
      binding.window.devicePixelRatioTestValue = 1.0;

      // Чтобы не всплывал DeviceSettings диалог во время тестов.
      SharedPreferences.setMockInitialValues({
        'setup_dialog_dismissed': true,
      });
    });

    setUp(() async {
      // In-memory БД, чтобы ContactsScreen не падал на DatabaseService.instance.database.
      testDb = await openDatabase(
        inMemoryDatabasePath,
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE contacts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              publicKey TEXT NOT NULL UNIQUE
            )
          ''');
          await db.execute('''
            CREATE TABLE messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              contactPublicKey TEXT NOT NULL,
              messageId TEXT, 
              text TEXT NOT NULL,
              isSentByMe INTEGER NOT NULL,
              timestamp INTEGER NOT NULL,
              status INTEGER DEFAULT 1,
              isRead INTEGER DEFAULT 1
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 3) {
            try {
              await db.execute("ALTER TABLE messages ADD COLUMN status INTEGER DEFAULT 1");
            } catch (_) {}
            try {
              await db.execute("ALTER TABLE messages ADD COLUMN isRead INTEGER DEFAULT 1");
            } catch (_) {}
          }
        },
      );
      DatabaseService.instance.initWithDatabase(testDb);
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    tearDown(() async {
      try {
        await DatabaseService.instance.close();
        await testDb.close();
      } catch (_) {}
    });

    testWidgets('Показывается на первом запуске и сохраняет флаг после подтверждения', (tester) async {
      // В widget-тестах sqflite_ffi должен выполняться внутри runAsync,
      // иначе Future из ContactsScreen/initState может зависнуть и оставить pending timers.
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('ru'),
              home: HomeScreen(),
            ));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await tester.pump();

        expect(find.text('Бета-версия'), findsOneWidget);
        expect(find.textContaining('закрытое тестирование'), findsOneWidget);

        await tester.tap(find.text('Больше не показывать'));
        await tester.pump();
        await tester.tap(find.text('Понятно'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Бета-версия'), findsNothing);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('beta_disclaimer_dismissed_v1'), isTrue);

        // Даем отработать delay(2s) из _checkDeviceSettings(), чтобы не было pending timers.
        await Future<void>.delayed(const Duration(seconds: 3));
        await tester.pump();

        // Проверяем, что при повторном построении экрана дисклеймер уже не появляется.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await tester.pumpWidget(const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('ru'),
              home: HomeScreen(),
            ));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await tester.pump();

        expect(find.text('Бета-версия'), findsNothing);

        await Future<void>.delayed(const Duration(seconds: 3));
        await tester.pump();
      });
    });

    testWidgets('Не показывается, если флаг уже установлен', (tester) async {
      SharedPreferences.setMockInitialValues({
        'setup_dialog_dismissed': true,
        'beta_disclaimer_dismissed_v1': true,
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('ru'),
              home: HomeScreen(),
            ));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await tester.pump();

        expect(find.text('Бета-версия'), findsNothing);
        expect(find.textContaining('закрытое тестирование'), findsNothing);

        // Даем отработать delay(2s) из _checkDeviceSettings(), чтобы не было pending timers.
        await Future<void>.delayed(const Duration(seconds: 3));
        await tester.pump();
      });
    });
  });
}

