// test/widgets/duress_navigator_test.dart
// Вход по коду принуждения не должен отдавать наблюдателю UI реальной сессии.
//
// Лок в приложении — ОВЕРЛЕЙ поверх Navigator'а (main.dart, MaterialApp.builder),
// поэтому маршруты, открытые до лока, остаются смонтированными вместе со своим
// State и уже расшифрованными данными. Здесь проверяется прод-механизм сброса:
// dropRoutesAboveHome() + pushedRouteTracker из main.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/chat_screen.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/screens/lock_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _secret = 'TOP-SECRET-PLAINTEXT';
const String _mainPin = '111111';
const String _duressPin = '222222';

class _MemSecureStorage implements AuthSecureStorage {
  final Map<String, String> _m = {};
  @override
  Future<void> delete({required String key}) async => _m.remove(key);
  @override
  Future<void> deleteAll() async => _m.clear();
  @override
  Future<String?> read({required String key}) async => _m[key];
  @override
  Future<void> write({required String key, required String value}) async {
    _m[key] = value;
  }
}

/// Повторяет структуру MyApp: лок рисуется оверлеем в MaterialApp.builder поверх
/// Navigator'а, home под локом — чёрный Scaffold. Колбэки лока дергают ровно те же
/// прод-функции и в том же порядке, что _onDuressMode/_onUnlocked/onWipeCompleted.
class _AppHarness extends StatefulWidget {
  const _AppHarness({required this.auth, required this.locked});

  final AuthService auth;
  final ValueNotifier<bool> locked;

  @override
  State<_AppHarness> createState() => _AppHarnessState();
}

class _AppHarnessState extends State<_AppHarness> {
  bool _duressUiActive = false;

  @override
  void initState() {
    super.initState();
    widget.locked.addListener(_onLockChanged);
  }

  @override
  void dispose() {
    widget.locked.removeListener(_onLockChanged);
    super.dispose();
  }

  void _onLockChanged() {
    if (mounted) setState(() {});
  }

  void _onDuressMode() {
    _duressUiActive = true;
    dropRoutesAboveHome();
    widget.locked.value = false;
  }

  void _onUnlocked() {
    if (_duressUiActive) {
      _duressUiActive = false;
      dropRoutesAboveHome();
    }
    widget.locked.value = false;
  }

  Future<void> _onWipe(WipeReason reason) async {
    dropRoutesAboveHome();
    _duressUiActive = false;
    widget.locked.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked.value;
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: appNavigatorObservers,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
          if (locked)
            Positioned.fill(
              child: LockScreen.forTesting(
                auth: widget.auth,
                onUnlocked: _onUnlocked,
                onDuressMode: _onDuressMode,
                onWipe: _onWipe,
              ),
            ),
        ],
      ),
      home: locked
          ? const Scaffold(backgroundColor: Colors.black)
          : const Scaffold(body: Center(child: Text('HOME-STUB'))),
    );
  }
}

/// Экран телефона: на дефолтных 800x600 пин-пад и чат не помещаются.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
  // LockScreen._verifyPin ждёт 300 мс перед проверкой (UX-задержка).
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Duress unlock drops the real-session UI', () {
    late Database testDb;
    late AuthService auth;
    late ValueNotifier<bool> locked;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      // Трекер маршрутов — глобал; не даём тестам протекать друг в друга.
      pushedRouteTracker.debugClear();

      testDb = await openDatabase(
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
      DatabaseService.instance.initWithDatabase(testDb);
      DatabaseService.instance.setDuressMode(false);

      auth = AuthService.createForTesting(
        secureStorage: _MemSecureStorage(),
        fastHash: true,
        monotonicNow: () async => 0,
      );
      await auth.init();
      await auth.setPin(_mainPin);
      expect(await auth.setDuressCode(_mainPin, _duressPin), isTrue);

      locked = ValueNotifier<bool>(false);
    });

    tearDown(() async {
      DatabaseService.instance.setDuressMode(false);
      try {
        await DatabaseService.instance.close();
        await testDb.close();
      } catch (_) {}
    });

    /// Реальная сессия с открытым чатом, в котором уже загружена расшифрованная
    /// история; затем лок.
    Future<void> openChatThenLock(WidgetTester tester) async {
      _useTallSurface(tester);
      final contact = Contact(name: 'Alice', publicKey: 'KEY1');
      await tester.runAsync(() async {
        await DatabaseService.instance.addContact(contact);
        await DatabaseService.instance.addMessage(
          ChatMessage(text: _secret, isSentByMe: false),
          'KEY1',
        );
        await tester.pumpWidget(_AppHarness(auth: auth, locked: locked));
        await tester.pump();
        navigatorKey.currentState!.push(MaterialPageRoute(
          builder: (_) => ChatScreen(contact: contact),
        ));
        await tester.pump();
        // Реальное время внутри runAsync: иначе sqflite_ffi из initState зависает
        // в fakeAsync (та же грабля, что в contacts_screen_test.dart:129-130), и
        // недоделанные запросы всплывают после закрытия БД в tearDown.
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(_secret), findsOneWidget,
          reason: 'чат должен успеть загрузить историю до лока');

      auth.lock();
      locked.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('duress-код убирает открытый чат вместе с расшифрованным текстом',
        (tester) async {
      await openChatThenLock(tester);
      await _enterPin(tester, _duressPin);
      await tester.pumpAndSettle();

      expect(auth.isDuressMode, isTrue);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text(_secret), findsNothing);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('HOME-STUB'), findsOneWidget);
    });

    testWidgets(
        'расшифрованный текст не виден НИ В ОДНОМ кадре после снятия лока',
        (tester) async {
      await openChatThenLock(tester);
      await _enterPin(tester, _duressPin);

      // Ключевая проверка: пока лок нарисован, чат под ним допустим (оверлей
      // непрозрачен), но в первом же кадре БЕЗ лока его быть не должно. Именно
      // здесь removeRoute отличается от popUntil: тот доигрывает анимацию выхода
      // уже после того, как лок исчез.
      var framesWithoutLock = 0;
      for (var i = 0; i < 40; i++) {
        if (find.byType(LockScreen).evaluate().isEmpty) {
          framesWithoutLock++;
          expect(find.text(_secret), findsNothing,
              reason: 'кадр $i: расшифрованный текст видно без лока');
          expect(find.byType(ChatScreen), findsNothing,
              reason: 'кадр $i: маршрут чата ещё в дереве без лока');
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(framesWithoutLock, greaterThan(0),
          reason: 'лок так и не снялся — проверка была бы пустой');
    });

    testWidgets('обычный PIN после авто-лока оставляет открытый чат на месте',
        (tester) async {
      await openChatThenLock(tester);
      await _enterPin(tester, _mainPin);
      await tester.pumpAndSettle();

      expect(auth.isDuressMode, isFalse);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text(_secret), findsOneWidget);
    });

    testWidgets('duress -> лок -> настоящий PIN: маршруты duress-сессии тоже уходят',
        (tester) async {
      await openChatThenLock(tester);
      await _enterPin(tester, _duressPin);
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);

      // Внутри duress-сессии наблюдатель что-то открыл.
      navigatorKey.currentState!.push(MaterialPageRoute(
        builder: (_) =>
            const Scaffold(body: Center(child: Text('DURESS-ROUTE'))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('DURESS-ROUTE'), findsOneWidget);

      auth.lock();
      locked.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await _enterPin(tester, _mainPin);
      await tester.pumpAndSettle();

      expect(auth.isDuressMode, isFalse);
      expect(find.text('DURESS-ROUTE'), findsNothing);
      expect(find.text('HOME-STUB'), findsOneWidget);
    });

    testWidgets('диалог с секретом (экспорт ключа) тоже уходит со стека',
        (tester) async {
      const fakeSeed = 'FAKE-ROOT-SEED-BASE64';
      _useTallSurface(tester);
      await tester.runAsync(() async {
        await tester.pumpWidget(_AppHarness(auth: auth, locked: locked));
        await tester.pump();
      });
      // showDialog по умолчанию пушит DialogRoute на КОРНЕВОЙ Navigator.
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text(fakeSeed)),
      );
      await tester.pumpAndSettle();
      expect(find.text(fakeSeed), findsOneWidget);

      auth.lock();
      locked.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await _enterPin(tester, _duressPin);
      await tester.pumpAndSettle();

      expect(find.text(fakeSeed), findsNothing);
    });

    testWidgets('auto-wipe с локскрина тоже сбрасывает стек (лок уходит с PIN)',
        (tester) async {
      // Идём РЕАЛЬНЫМ путём LockScreen: неверный PIN -> PinVerifyResult.autoWipe ->
      // widget.onWipe(...). Прямой вызов dropRoutesAboveHome() здесь был бы
      // тавтологией и не проверял бы, что сброс висит на wipe-колбэке.
      await auth.setAutoWipe(true, attempts: 3);
      await openChatThenLock(tester);

      for (var i = 0; i < 3; i++) {
        await _enterPin(tester, '000000');
      }
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text(_secret), findsNothing);
    });

    testWidgets('dropRoutesAboveHome безопасен на пустом стеке и при повторе',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_AppHarness(auth: auth, locked: locked));
      await tester.pump();

      dropRoutesAboveHome();
      dropRoutesAboveHome();
      await tester.pumpAndSettle();
      expect(find.text('HOME-STUB'), findsOneWidget);
    });

    // Гард обвязки. Тесты выше поднимают КОПИЮ структуры MyApp (запампить сам MyApp
    // нельзя — initState тянет плагины), поэтому они проверяют механизм, но НЕ то,
    // что прод его зовёт: удалить вызов из main.dart и они останутся зелёными
    // (проверено мутацией). Читаем исходник и держим четыре точки подключения.
    test('main.dart подключает сброс во всех четырёх точках', () {
      final source = File('lib/main.dart').readAsStringSync();

      // Обсервер зарегистрирован — без него трекер пуст и сбрасывать нечего.
      expect(source, contains('navigatorObservers: appNavigatorObservers'));

      for (final anchor in <String>[
        'void _onDuressMode()',
        'void _onUnlocked()',
        'AuthService.onWipeCompleted =',
      ]) {
        final start = source.indexOf(anchor);
        expect(start, greaterThan(-1), reason: 'не найден якорь: $anchor');
        // Тело метода/колбэка: до конца следующего блока верхнего уровня хватает
        // окна в ~2500 символов — все три сейчас существенно короче.
        final body = source.substring(
            start, (start + 2500).clamp(0, source.length));
        expect(body, contains('dropRoutesAboveHome()'),
            reason: 'в $anchor потерялся сброс стека — утечка реальной сессии '
                'вернётся, а виджет-тесты этого не заметят');
      }
    });

    testWidgets('PushedRouteTracker отпускает маршруты (иначе сам станет утечкой)',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_AppHarness(auth: auth, locked: locked));
      await tester.pump();

      final routeA = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('A')));
      final routeB = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('B')));
      navigatorKey.currentState!.push(routeA);
      navigatorKey.currentState!.push(routeB);
      await tester.pumpAndSettle();
      expect(pushedRouteTracker.topDown(), [routeB, routeA]);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(pushedRouteTracker.topDown(), [routeA]);

      dropRoutesAboveHome();
      await tester.pumpAndSettle();
      expect(pushedRouteTracker.topDown(), isEmpty);
    });
  });
}
