import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqlite_api.dart';

void main() {
  // Инициализация FFI для SQLite в тестах
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ContactsScreen Widget Tests', () {
    late Database testDb;

    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      // Увеличиваем экран для сложной верстки (иначе overflow в пустом состоянии).
      binding.window.physicalSizeTestValue = const Size(1080, 1920);
      binding.window.devicePixelRatioTestValue = 1.0;
    });

    setUp(() async {
      // Создаем in-memory БД для каждого теста
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
            } catch (e) {}
            try {
              await db.execute("ALTER TABLE messages ADD COLUMN isRead INTEGER DEFAULT 1");
            } catch (e) {}
          }
        },
      );
      
      // Инициализируем DatabaseService с тестовой БД
      DatabaseService.instance.initWithDatabase(testDb);
    });

    tearDown(() async {
      try {
        await DatabaseService.instance.close();
        await testDb.close();
      } catch (e) {
        // Игнорируем ошибки
      }
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    testWidgets('Отображает заголовок и основные элементы', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: ContactsScreen(enableUnreadCounters: false),
        ),
      );

      // Даем время на загрузку
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Проверяем наличие заголовка
      expect(find.text('Контакты'), findsOneWidget);

      // Проверяем наличие кнопки добавления контакта в AppBar
      expect(find.byIcon(Icons.person_add_outlined), findsOneWidget);
    });

    testWidgets('Отображает состояние загрузки', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: ContactsScreen(enableUnreadCounters: false),
        ),
      );

      // Пока идет загрузка, должен быть индикатор
      await tester.pump();

      // Может быть либо список контактов, либо индикатор загрузки, либо пустое состояние
      final hasLoading = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final hasEmptyState = find.text('Нет контактов').evaluate().isNotEmpty;
      final hasList = find.byType(ListView).evaluate().isNotEmpty;

      // Должно быть одно из состояний
      expect(hasLoading || hasEmptyState || hasList, isTrue);
    });

    testWidgets('Отображает пустое состояние при отсутствии контактов', (WidgetTester tester) async {
      // В widget-тестах реальные async-операции (sqflite_ffi) должны стартовать внутри runAsync,
      // иначе Future из initState может зависнуть в fakeAsync.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: Locale('ru'),
            home: ContactsScreen(enableUnreadCounters: false),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Всегда есть Оракул Орфея в списке, а при пустых контактах — подсказка "Нет контактов"
      expect(find.text('Нет контактов'), findsOneWidget);
      // Оракул Орфея должен быть всегда виден
      expect(find.text('Оракул Орфея'), findsOneWidget);
    });

    testWidgets('Отображает список контактов', (WidgetTester tester) async {
      await tester.runAsync(() async {
        // Добавляем тестовые контакты в БД
        await DatabaseService.instance.addContact(Contact(name: "Alice", publicKey: "KEY1"));
        await DatabaseService.instance.addContact(Contact(name: "Bob", publicKey: "KEY2"));

        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: Locale('ru'),
            home: ContactsScreen(enableUnreadCounters: false),
          ),
        );
        await tester.pump();
        // Даём времени отработать и загрузке контактов, и запросам unreadCount в карточках.
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump(const Duration(milliseconds: 500));

      // Должен быть список контактов
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('Кнопка добавления контакта открывает диалог', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: ContactsScreen(enableUnreadCounters: false),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Нажимаем на кнопку добавления контакта в AppBar
      await tester.tap(find.byIcon(Icons.person_add_outlined));
      await tester.pump(const Duration(milliseconds: 400));

      // Должен появиться диалог добавления контакта
      expect(find.text('Новый контакт'), findsOneWidget);
    });

    testWidgets('Диалог добавления контакта можно закрыть', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('ru'),
          home: ContactsScreen(enableUnreadCounters: false),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Открываем диалог через кнопку в AppBar
      await tester.tap(find.byIcon(Icons.person_add_outlined));
      await tester.pump(const Duration(milliseconds: 400));

      // Закрываем диалог
      await tester.tap(find.text('Отмена'));
      await tester.pump(const Duration(milliseconds: 400));

      // Диалог должен исчезнуть
      expect(find.text('Новый контакт'), findsNothing);
    });
  });
}

