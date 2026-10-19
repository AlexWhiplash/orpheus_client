// Визуальные превью экранов мессенджера (визуальная система Orpheus v1, этап 3).
//
// Не обычные тесты: рендерят экраны с фейковыми данными в PNG, чтобы смотреть
// оформление без сервера и телефона. В обычном `flutter test` пропускаются,
// работают только с --update-goldens:
//   flutter test test/visual_preview --update-goldens
// Картинки: test/visual_preview/goldens/*.png

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/chat_screen.dart';
import 'package:orpheus_project/contacts_screen.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart' show websocketService;
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/models/room_message_model.dart';
import 'package:orpheus_project/models/room_model.dart';
import 'package:orpheus_project/screens/home_screen.dart';
import 'package:orpheus_project/screens/room_chat_screen.dart';
import 'package:orpheus_project/screens/rooms_screen.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/theme/app_theme.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';
import 'package:orpheus_project/widgets/messenger_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Типичный Android: 412×915 dp.
const Size _screen = Size(412, 915);
const double _dpr = 2.0;

final bool _skip = !autoUpdateGoldenFiles;

Future<void> _loadFonts() async {
  final manifest = json.decode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    final loader = FontLoader(family.replaceFirst(RegExp(r'^packages/[^/]+/'), ''));
    for (final f in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(f['asset'] as String));
    }
    await loader.load();
  }
  // Текст без явного семейства (Material по умолчанию берёт Roboto) — тоже Inter.
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
  await roboto.load();
}

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: home,
    );

void _useScreen(WidgetTester tester, [Size size = _screen]) {
  tester.view.physicalSize = size * _dpr;
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);
}

DateTime _today(int h, int m) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, m);
}

const _keyA = 'PREVIEW_KEY_ALEXANDER';
const _keyV = 'PREVIEW_KEY_VADIM';
const _keyM = 'PREVIEW_KEY_METODEX';
const _keyL = 'PREVIEW_KEY_LITVA';

Future<Database> _openDb() async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE contacts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          publicKey TEXT NOT NULL UNIQUE,
          encryptionKey TEXT
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
      await db.execute('''
        CREATE TABLE outbox (
          messageId TEXT PRIMARY KEY NOT NULL,
          recipientKey TEXT NOT NULL,
          payload TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          lastAttemptAt INTEGER
        )
      ''');
    },
  );
  DatabaseService.instance.initWithDatabase(db);
  DatabaseService.instance.setDuressMode(false);
  return db;
}

Future<void> _seed() async {
  final db = DatabaseService.instance;
  await db.addContact(Contact(name: 'Александр', publicKey: _keyA));
  await db.addContact(Contact(name: 'Вадим', publicKey: _keyV));
  await db.addContact(Contact(name: 'Методекс · офис', publicKey: _keyM));
  await db.addContact(Contact(name: 'Литва', publicKey: _keyL));

  Future<void> msg(String key, String text, bool mine, DateTime at,
          {bool read = true}) =>
      db.addMessage(
        ChatMessage(
          text: text,
          isSentByMe: mine,
          timestamp: at,
          isRead: read,
          status: MessageStatus.delivered,
        ),
        key,
      );

  final yesterday = _today(19, 5).subtract(const Duration(days: 1));
  await msg(_keyA, 'Вчера проверил TURN, всё отвечает', false, yesterday);
  await msg(_keyA, 'Поднял сервер в нашей сети, можно пробовать', false,
      _today(17, 44));
  await msg(_keyA, 'Отлично. Звоню через минуту', true, _today(17, 45));
  await msg(_keyA, 'Жду. TURN тоже на месте', false, _today(17, 46),
      read: false);
  await msg(_keyA, 'Сервер поднят, проверим звонок', true, _today(17, 48));
  await msg(_keyA, 'Ок', false, _today(17, 49), read: false);
  await msg(_keyV, 'Посмотрел план, вечером отвечу', false, _today(16, 10));
  await msg(_keyM, 'Пропуск на завтра готов', false, yesterday);
  await msg(_keyL, 'Голосовое · 0:42', false,
      _today(11, 0).subtract(const Duration(days: 5)));
}

void _setOnline(Map<String, bool> states) {
  websocketService.debugHandlePostAuthFrame(
    json.encode({'type': 'presence-state', 'states': states}),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    EditableText.debugDeterministicCursor = true;
    await _loadFonts();
  });

  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await _openDb();
  });

  tearDown(() async {
    try {
      await DatabaseService.instance.close();
      await db.close();
    } catch (_) {}
  });

  testWidgets('contacts_list', skip: _skip, (tester) async {
    _useScreen(tester);
    await tester.runAsync(() async {
      await _seed();
      await tester.pumpWidget(_app(Scaffold(
        backgroundColor: AppColors.bg,
        body: const ContactsScreen(),
        bottomNavigationBar: HomeNavBar(
          selectedIndex: 1,
          onDestinationSelected: (_) {},
          hasContactUnread: true,
          hasRoomUnread: false,
          labels: const ['Система', 'Контакты', 'Комнаты', 'Профиль'],
        ),
      )));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    _setOnline({_keyA: true, _keyM: true});
    await _settle(tester);
    // Поиск — по кнопке в шапке, как в приложении.
    await tester.tap(find.byIcon(Icons.search));
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/contacts_list.png'),
    );
  });

  testWidgets('chat', skip: _skip, (tester) async {
    _useScreen(tester);
    final contact = Contact(name: 'Александр', publicKey: _keyA);
    await tester.runAsync(() async {
      await _seed();
      await tester.pumpWidget(_app(ChatScreen(contact: contact)));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    _setOnline({_keyA: true});
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chat.png'),
    );
  });

  testWidgets('rooms', skip: _skip, (tester) async {
    _useScreen(tester);
    final rooms = [
      Room(
        id: 'r1',
        name: 'Команда Orpheus',
        isOwner: true,
        membersCount: 6,
        lastMessageAt: _today(17, 30),
        lastMessagePreview: 'Сборка 1.1.9 ушла тестерам',
      ),
      Room(
        id: 'r2',
        name: 'Литва · связь',
        isOwner: false,
        membersCount: 3,
        lastMessageAt: _today(9, 12),
        lastMessagePreview: 'Канал стабилен, задержка 80 мс',
      ),
      Room(
        id: 'r3',
        name: 'Офис',
        isOwner: false,
        membersCount: 12,
        lastMessageAt: _today(12, 0).subtract(const Duration(days: 2)),
        lastMessagePreview: 'SYS:HISTORY_CLEARED',
      ),
    ];
    await tester.pumpWidget(_app(Builder(builder: (context) {
      final l10n = L10n.of(context);
      // Та же шапка, что у RoomsScreen; список — его же строками.
      return AppScaffold(
        safeArea: false,
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: AppSpacing.md,
          titleTextStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 21,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: 0.1,
          ),
          title: Text(l10n.rooms),
          actions: [
            HeaderIconButton(icon: Icons.refresh, onPressed: () {}),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, 100),
          itemCount: rooms.length + 1,
          separatorBuilder: (_, __) => const ListRowDivider(),
          itemBuilder: (context, i) => i == 0
              ? NotesVaultRow(onTap: () {})
              : RoomListRow(
                  room: rooms[i - 1], isOrpheus: false, onTap: () {}),
        ),
        bottomNavigationBar: HomeNavBar(
          selectedIndex: 2,
          onDestinationSelected: (_) {},
          hasContactUnread: true,
          hasRoomUnread: true,
          labels: [l10n.system, l10n.contacts, l10n.rooms, l10n.profile],
        ),
      );
    })));
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/rooms.png'),
    );
  });

  testWidgets('room_chat_bubbles', skip: _skip, (tester) async {
    _useScreen(tester);
    final msgs = [
      RoomMessage(
          id: '1',
          text: 'Всем привет, сборка 1.1.9 у тестеров',
          createdAt: _today(14, 2).toUtc(),
          senderKey: 'ABCD1234'),
      RoomMessage(
          id: '2',
          text: 'Ок',
          createdAt: _today(14, 3).toUtc(),
          senderKey: 'EFGH5678'),
      RoomMessage(
          id: '3',
          text: '',
          createdAt: _today(14, 5).toUtc(),
          isSystem: true,
          systemCode: 'invite_rotated'),
      RoomMessage(
          id: '4',
          text: 'Плановые работы на сервере в 23:00',
          createdAt: _today(14, 9).toUtc(),
          authorType: 'orpheus'),
    ];
    await tester.pumpWidget(_app(Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          children: [
            const ChatDaySeparator(label: 'Сегодня'),
            for (final m in msgs) RoomMessageBubble(message: m),
          ],
        ),
      ),
    )));
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/room_chat.png'),
    );
  });

  testWidgets('bottom_nav', skip: _skip, (tester) async {
    _useScreen(tester, const Size(412, 160));
    await tester.pumpWidget(_app(Scaffold(
      backgroundColor: AppColors.bg,
      body: const SizedBox.shrink(),
      bottomNavigationBar: HomeNavBar(
        selectedIndex: 1,
        onDestinationSelected: (_) {},
        hasContactUnread: false,
        hasRoomUnread: true,
        labels: const ['Система', 'Контакты', 'Комнаты', 'Профиль'],
      ),
    )));
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/bottom_nav.png'),
    );
  });
}
