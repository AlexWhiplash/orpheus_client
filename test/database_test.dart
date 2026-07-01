import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/contact_model.dart';
// ВАЖНО: Нам придется немного подхачить DatabaseService для тестов,
// либо инициализировать фабрику FFI глобально.

void main() {
  // Инициализация FFI для SQLite в тестах
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    // Создаем чистую БД в памяти перед каждым тестом
    db = await openDatabase(inMemoryDatabasePath, version: 1,
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
        });
  });

  tearDown(() async {
    await db.close();
  });

  group('Database Logic Tests', () {
    test('CRUD Контактов', () async {
      final contact = Contact(name: "Elon", publicKey: "KEY123");

      // Insert
      await db.insert('contacts', contact.toMap());

      // Read
      final List<Map<String, dynamic>> maps = await db.query('contacts');
      expect(maps.length, 1);
      expect(maps.first['name'], "Elon");
      expect(maps.first['publicKey'], "KEY123");
    });

    test('Уникальность publicKey в контактах', () async {
      final contact1 = Contact(name: "Elon", publicKey: "KEY123");
      final contact2 = Contact(name: "Musk", publicKey: "KEY123"); // Тот же ключ

      await db.insert('contacts', contact1.toMap());

      // Попытка вставить контакт с тем же ключом должна вызвать ошибку
      expect(() async {
        await db.insert('contacts', contact2.toMap());
      }, throwsA(anything));
    });

    test('Множественные контакты', () async {
      final contacts = [
        Contact(name: "Alice", publicKey: "KEY1"),
        Contact(name: "Bob", publicKey: "KEY2"),
        Contact(name: "Charlie", publicKey: "KEY3"),
      ];

      for (final contact in contacts) {
        await db.insert('contacts', contact.toMap());
      }

      final maps = await db.query('contacts', orderBy: 'name');
      expect(maps.length, 3);
      expect(maps[0]['name'], "Alice");
      expect(maps[1]['name'], "Bob");
      expect(maps[2]['name'], "Charlie");
    });

    test('Сохранение и чтение сообщений', () async {
      final msg = ChatMessage(
          text: "Hello Mars",
          isSentByMe: true,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
          isRead: true
      );

      // Сохраняем (эмуляция метода addMessage)
      await db.insert('messages', msg.toMap("KEY123"));

      // Читаем
      final List<Map<String, dynamic>> maps = await db.query('messages');
      expect(maps.length, 1);

      final savedMsg = maps.first;
      expect(savedMsg['text'], "Hello Mars");
      expect(savedMsg['contactPublicKey'], "KEY123");
      expect(savedMsg['isSentByMe'], 1);
      expect(savedMsg['status'], MessageStatus.sent.index);
      expect(savedMsg['isRead'], 1);
    });

    test('Сообщения с разными статусами', () async {
      final messages = [
        ChatMessage(text: "Sending", isSentByMe: true, status: MessageStatus.sending),
        ChatMessage(text: "Sent", isSentByMe: true, status: MessageStatus.sent),
        ChatMessage(text: "Delivered", isSentByMe: false, status: MessageStatus.delivered),
        ChatMessage(text: "Read", isSentByMe: false, status: MessageStatus.read),
        ChatMessage(text: "Failed", isSentByMe: true, status: MessageStatus.failed),
      ];

      for (final msg in messages) {
        await db.insert('messages', msg.toMap("KEY123"));
      }

      final maps = await db.query('messages');
      expect(maps.length, 5);

      // Проверяем статусы
      expect(maps[0]['status'], MessageStatus.sending.index);
      expect(maps[1]['status'], MessageStatus.sent.index);
      expect(maps[2]['status'], MessageStatus.delivered.index);
      expect(maps[3]['status'], MessageStatus.read.index);
      expect(maps[4]['status'], MessageStatus.failed.index);
    });

    test('Фильтрация сообщений по контакту', () async {
      final msg1 = ChatMessage(text: "Msg1", isSentByMe: true);
      final msg2 = ChatMessage(text: "Msg2", isSentByMe: true);
      final msg3 = ChatMessage(text: "Msg3", isSentByMe: true);

      await db.insert('messages', msg1.toMap("KEY1"));
      await db.insert('messages', msg2.toMap("KEY1"));
      await db.insert('messages', msg3.toMap("KEY2"));

      final maps = await db.query(
        'messages',
        where: 'contactPublicKey = ?',
        whereArgs: ['KEY1'],
      );

      expect(maps.length, 2);
      expect(maps[0]['text'], "Msg1");
      expect(maps[1]['text'], "Msg2");
    });

    test('Сортировка сообщений по timestamp', () async {
      final now = DateTime.now();
      final msg1 = ChatMessage(text: "First", isSentByMe: true, timestamp: now);
      final msg2 = ChatMessage(text: "Second", isSentByMe: true, timestamp: now.add(const Duration(seconds: 1)));
      final msg3 = ChatMessage(text: "Third", isSentByMe: true, timestamp: now.add(const Duration(seconds: 2)));

      // Вставляем в обратном порядке
      await db.insert('messages', msg3.toMap("KEY1"));
      await db.insert('messages', msg1.toMap("KEY1"));
      await db.insert('messages', msg2.toMap("KEY1"));

      final maps = await db.query('messages', orderBy: 'timestamp ASC');
      expect(maps.length, 3);
      expect(maps[0]['text'], "First");
      expect(maps[1]['text'], "Second");
      expect(maps[2]['text'], "Third");
    });

    test('Пустые и длинные тексты сообщений', () async {
      final emptyMsg = ChatMessage(text: "", isSentByMe: true);
      final longMsg = ChatMessage(text: "A" * 10000, isSentByMe: true);

      await db.insert('messages', emptyMsg.toMap("KEY1"));
      await db.insert('messages', longMsg.toMap("KEY1"));

      final maps = await db.query('messages');
      expect(maps.length, 2);
      expect(maps[0]['text'] as String, isEmpty);
      final longText = maps[1]['text'] as String?;
      expect(longText, isNotNull);
      expect(longText!.length, 10000);
    });
  });
}