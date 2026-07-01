import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/models/chat_message_model.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    // Создаем in-memory БД
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    
    // Создаем таблицы вручную
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
    
    // Инициализируем сервис с тестовой БД
    DatabaseService.instance.initWithDatabase(db);
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  group('DatabaseService Tests', () {
    test('Singleton паттерн работает', () {
      final instance1 = DatabaseService.instance;
      final instance2 = DatabaseService.instance;

      expect(instance1, same(instance2));
    });

    test('Добавление контакта', () async {
      final contact = Contact(name: "Test User", publicKey: "TEST_KEY_123");

      await DatabaseService.instance.addContact(contact);

      final contacts = await DatabaseService.instance.getContacts();
      expect(contacts.length, 1);
      expect(contacts.any((c) => c.publicKey == "TEST_KEY_123"), isTrue);
    });

    test('Получение списка контактов', () async {
      final contacts = await DatabaseService.instance.getContacts();
      expect(contacts, isA<List<Contact>>());
    });

    test('updateMessageStatusByMessageId и deleteMessagesByMessageIds (LOGIC-2/3)', () async {
      const key = 'CONTACT_XYZ';
      await DatabaseService.instance.addMessage(
        ChatMessage(
          messageId: 'mid-1',
          text: 'привет',
          isSentByMe: true,
          status: MessageStatus.sending,
        ),
        key,
      );

      // Статус обновляется по стабильному messageId (LOGIC-3).
      await DatabaseService.instance
          .updateMessageStatusByMessageId(key, 'mid-1', MessageStatus.failed);
      var msgs = await DatabaseService.instance.getMessagesForContact(key);
      expect(msgs.length, 1);
      expect(msgs.first.messageId, 'mid-1');
      expect(msgs.first.status, MessageStatus.failed);

      // Удаление по messageId убирает сообщение (LOGIC-2).
      final deleted =
          await DatabaseService.instance.deleteMessagesByMessageIds(key, ['mid-1']);
      expect(deleted, 1);
      msgs = await DatabaseService.instance.getMessagesForContact(key);
      expect(msgs, isEmpty);
    });

    test('getMessagesForContactAfter возвращает только новые сообщения (PERF-1)', () async {
      const key = 'C_AFTER';
      await DatabaseService.instance.addMessage(
        ChatMessage(
          messageId: 'a',
          text: 'старое',
          isSentByMe: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
        key,
      );
      await DatabaseService.instance.addMessage(
        ChatMessage(
          messageId: 'b',
          text: 'новое',
          isSentByMe: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
        key,
      );

      final after =
          await DatabaseService.instance.getMessagesForContactAfter(key, 1000);
      expect(after.map((m) => m.text).toList(), ['новое']);
    });

    test('Добавление сообщения', () async {
      final message = ChatMessage(
        text: "Test message",
        isSentByMe: true,
        status: MessageStatus.sent,
      );

      await DatabaseService.instance.addMessage(message, "CONTACT_KEY");

      final messages = await DatabaseService.instance.getMessagesForContact("CONTACT_KEY");
      expect(messages.length, 1);
      expect(messages.any((m) => m.text == "Test message"), isTrue);
    });

    test('Получение сообщений для контакта', () async {
      final messages = await DatabaseService.instance.getMessagesForContact("CONTACT_KEY");
      expect(messages, isA<List<ChatMessage>>());
    });

    test('Пометить сообщения как прочитанные', () async {
      await DatabaseService.instance.markMessagesAsRead("CONTACT_KEY");
      // Метод не должен выбрасывать исключение
      expect(true, isTrue);
    });

    test('Получение количества непрочитанных сообщений', () async {
      final count = await DatabaseService.instance.getUnreadCount("CONTACT_KEY");
      expect(count, isA<int>());
      expect(count, greaterThanOrEqualTo(0));
    });

    test('Очистка истории чата', () async {
      // Сначала добавляем сообщение
      final message = ChatMessage(
        text: "Test",
        isSentByMe: true,
      );
      await DatabaseService.instance.addMessage(message, "CONTACT_KEY");
      
      // Затем очищаем
      await DatabaseService.instance.clearChatHistory("CONTACT_KEY");
      
      // Проверяем, что сообщения удалены
      final messages = await DatabaseService.instance.getMessagesForContact("CONTACT_KEY");
      expect(messages, isEmpty);
    });

    test('Удаление контакта', () async {
      // Сначала добавляем контакт
      final contact = Contact(name: "To Delete", publicKey: "DELETE_KEY");
      await DatabaseService.instance.addContact(contact);

      // Получаем ID контакта
      final contacts = await DatabaseService.instance.getContacts();
      final addedContact = contacts.firstWhere((c) => c.publicKey == "DELETE_KEY");

      // Удаляем контакт
      expect(addedContact.id, isNotNull);
      await DatabaseService.instance.deleteContact(addedContact.id!, addedContact.publicKey);
      
      // Проверяем, что контакт удален
      final contactsAfter = await DatabaseService.instance.getContacts();
      expect(contactsAfter.any((c) => c.publicKey == "DELETE_KEY"), isFalse);
    });
  });
}
