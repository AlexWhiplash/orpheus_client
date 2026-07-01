import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/screens/settings_screen.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Чтобы SettingsScreen не ловил MissingPluginException от package_info_plus.
    PackageInfo.setMockInitialValues(
      appName: 'Orpheus',
      packageName: 'orpheus_project',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
  });

  group('SettingsScreen widget tests', () {
    late Database testDb;

    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.physicalSizeTestValue = const Size(1080, 1920);
      binding.window.devicePixelRatioTestValue = 1.0;
    });

    setUp(() async {
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

    tearDown(() async {
      try {
        await DatabaseService.instance.close();
        await testDb.close();
      } catch (_) {}
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    testWidgets('Smoke: открывается и показывает основные пункты меню', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('ru'),
              home: SettingsScreen(),
            ));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pump();

      expect(find.text('Профиль'), findsOneWidget);
      expect(find.text('Безопасность'), findsOneWidget);
      expect(find.text('Поддержка'), findsOneWidget);
      expect(find.text('Как пользоваться'), findsOneWidget);
      expect(find.text('История обновлений'), findsOneWidget);
    });

    testWidgets('Тап по "Безопасность" открывает SecuritySettingsScreen', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('ru'),
              home: SettingsScreen(),
            ));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pump();

      await tester.tap(find.text('Безопасность'));
      await tester.pumpAndSettle();

      expect(find.text('БЕЗОПАСНОСТЬ'), findsOneWidget);
    });

    testWidgets('Секретные 5 тапов по заголовку открывают DebugLogsScreen', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('ru'),
              home: SettingsScreen(),
            ));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pump();

      // Заголовок AppBar содержит текст "Профиль" внутри GestureDetector.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Профиль'));
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.pumpAndSettle();
      expect(find.text('DEBUG LOGS'), findsOneWidget);
    });
  });
}






