// lib/services/database_service.dart

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:orpheus_project/models/contact_model.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/models/ai_message_model.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  static const String _dbFileName = 'orpheus.db';
  // Ключ шифрования БД (SQLCipher). Хранится в Keystore-backed secure storage.
  static const String _dbKeyStoreKey = 'orpheus_db_key';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _isWiping = false;
  DatabaseService._init();

  /// Проверка: находимся ли мы в duress mode (показываем пустой профиль)
  bool get _isDuressMode => AuthService.instance.isDuressMode;

  // Метод для тестов: инициализация с готовой БД
  void initWithDatabase(Database db) {
    _database = db;
  }

  Future<Database> get database async {
    if (_isWiping) throw StateError('Database is being wiped');
    if (_database != null) return _database!;
    _database = await _initDB(_dbFileName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, filePath);

      // Ключ шифрования БД из Keystore (при первом запуске генерируется, а старая
      // НЕзашифрованная БД удаляется — перенос данных не требуется).
      final dbKey = await _getOrCreateDbKey();

      final db = await openDatabase(
        path,
        password: dbKey,
        version: 7,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
        singleInstance: true, // Важно для избежания блокировок
      );
      DebugLogger.success('DB', 'База данных (зашифрованная) открыта');
      return db;
    } catch (e) {
      DebugLogger.error('DB', 'КРИТИЧЕСКАЯ ОШИБКА инициализации: $e');
      rethrow;
    }
  }

  /// Возвращает ключ шифрования БД, генерируя его при первом запуске.
  /// Ключ — 256 случайных бит из [Random.secure], лежит в Keystore-backed
  /// secure storage. При первой генерации (переход на шифрование) удаляем
  /// возможную старую НЕзашифрованную БД: критичных данных в приложении нет,
  /// перенос не требуется (см. AUDIT_REPORT SEC-1).
  Future<String> _getOrCreateDbKey() async {
    final existing = await _secureStorage.read(key: _dbKeyStoreKey);
    if (existing != null && existing.isNotEmpty) return existing;

    await _deletePlainDbFilesIfAny();

    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final key = base64Url.encode(bytes);
    await _secureStorage.write(key: _dbKeyStoreKey, value: key);
    DebugLogger.info('DB', 'Сгенерирован новый ключ шифрования БД');
    return key;
  }

  /// Удаляет старый файл БД и его sidecar-файлы (journal/wal/shm), если есть.
  Future<void> _deletePlainDbFilesIfAny() async {
    try {
      final path = await _dbPath();
      for (final suffix in const ['', '-journal', '-wal', '-shm']) {
        final f = File('$path$suffix');
        if (await f.exists()) await f.delete();
      }
    } catch (_) {
      // best-effort: если удалить не удалось, открытие зашифрованной БД всё равно
      // пройдёт (или создаст новую), данные не критичны.
    }
  }

  Future<String> _dbPath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _dbFileName);
  }

  Future _createDB(Database db, int version) async {
    await _createContactsTable(db);
    await _createMessagesTable(db);
    await _createAiTables(db);
    await _createNotesTable(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    print("DB: Миграция с версии $oldVersion на $newVersion");
    try {
      if (oldVersion < 2) {
        print("DB: Создание таблицы messages...");
        await _createMessagesTable(db);
      }
      if (oldVersion < 3) {
        print("DB: Миграция до версии 3...");
        // Проверяем, существуют ли колонки перед добавлением
        try {
          await db.execute("ALTER TABLE messages ADD COLUMN status INTEGER DEFAULT 1");
          print("DB: Колонка status добавлена");
        } catch (e) {
          print("DB: Колонка status уже существует или ошибка: $e");
        }
        try {
          await db.execute("ALTER TABLE messages ADD COLUMN isRead INTEGER DEFAULT 1");
          print("DB: Колонка isRead добавлена");
        } catch (e) {
          print("DB: Колонка isRead уже существует или ошибка: $e");
        }
      }
      if (oldVersion < 4) {
        print("DB: Миграция до версии 4...");
        await _createAiTables(db);
      }
      if (oldVersion < 5) {
        print("DB: Миграция до версии 5...");
        await _createNotesTable(db);
      }
      if (oldVersion < 6) {
        print("DB: Миграция до версии 6 — UNIQUE индекс на messages...");
        try {
          await db.execute('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_message
            ON messages(contactPublicKey, timestamp, isSentByMe)
          ''');
          print("DB: UNIQUE индекс создан");
        } catch (e) {
          print("DB: Ошибка создания индекса: $e");
        }
      }
      if (oldVersion < 7) {
        // messageId — стабильный id сообщения для дедупа и «удалить у обоих».
        // Убираем старый UNIQUE-индекс по timestamp (мог молча терять сообщения
        // с одинаковой мс — аудит DB-4) и заменяем на индекс по messageId.
        DebugLogger.info('DB', 'Миграция до версии 7 — messageId');
        try {
          await db.execute("ALTER TABLE messages ADD COLUMN messageId TEXT");
        } catch (_) {}
        try {
          await db.execute("DROP INDEX IF EXISTS idx_unique_message");
        } catch (_) {}
        try {
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_messages_contact_ts
            ON messages(contactPublicKey, timestamp)
          ''');
          await db.execute('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_message_id
            ON messages(contactPublicKey, messageId)
          ''');
        } catch (e) {
          DebugLogger.warn('DB', 'Ошибка индексов v7: $e');
        }
      }
      print("DB: Миграция завершена");
    } catch (e) {
      print("DB: ОШИБКА миграции: $e");
      rethrow;
    }
  }

  Future<void> _createContactsTable(Database db) async {
    await db.execute('''
      CREATE TABLE contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        publicKey TEXT NOT NULL UNIQUE
      )
    ''');
  }

  Future<void> _createMessagesTable(Database db) async {
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
    // Индекс под горячий запрос чата и агрегат «последнее сообщение».
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_contact_ts
      ON messages(contactPublicKey, timestamp)
    ''');
    // Дедуп по стабильному messageId (NULL допускается многократно —
    // сообщения без id от старых клиентов не считаются дублями).
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_message_id
      ON messages(contactPublicKey, messageId)
    ''');
  }

  Future<void> _createAiTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_error INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_context (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _createNotesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        source_type TEXT NOT NULL,
        source_id TEXT,
        source_label TEXT
      )
    ''');
  }

  // --- Контакты ---
  Future<void> addContact(Contact contact) async {
    // В duress mode не добавляем контакты
    if (_isDuressMode) return;

    final db = await instance.database;
    await db.insert('contacts', contact.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Добавить контакт, ТОЛЬКО если его ещё нет. Нужно для авто-создания контакта
  /// при входящем сообщении от неизвестного отправителя: иначе сообщение
  /// сохраняется, но не появляется в списке чатов (аудит DB-6). Имя по умолчанию —
  /// префикс публичного ключа (пользователь может переименовать). Duress НЕ
  /// проверяем — как и addMessage, чтобы реальный набор данных был консистентен
  /// (в duress-режиме список контактов всё равно пуст на чтении).
  Future<void> addContactIfMissing(String publicKey) async {
    if (publicKey.isEmpty) return;
    final db = await instance.database;
    final existing = await db.query('contacts',
        columns: ['id'], where: 'publicKey = ?', whereArgs: [publicKey], limit: 1);
    if (existing.isNotEmpty) return;
    final name = publicKey.length >= 8 ? publicKey.substring(0, 8) : publicKey;
    await db.insert('contacts', {'name': name, 'publicKey': publicKey},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Contact>> getContacts() async {
    // В duress mode возвращаем пустой список
    if (_isDuressMode) return [];
    
    final db = await instance.database;
    
    // Сортировка по дате последнего сообщения (как в Telegram/WhatsApp):
    // 1. Контакты с недавними сообщениями — сверху
    // 2. Контакты без сообщений — снизу (по имени)
    final maps = await db.rawQuery('''
      SELECT c.id, c.name, c.publicKey,
             COALESCE(MAX(m.timestamp), 0) as lastMessageTime
      FROM contacts c
      LEFT JOIN messages m ON c.publicKey = m.contactPublicKey
      GROUP BY c.id, c.name, c.publicKey
      ORDER BY lastMessageTime DESC, c.name ASC
    ''');
    
    return List.generate(maps.length, (i) {
      return Contact(
        id: maps[i]['id'] as int,
        name: maps[i]['name'] as String,
        publicKey: maps[i]['publicKey'] as String,
      );
    });
  }

  /// Получить контакт по publicKey
  Future<Contact?> getContact(String publicKey) async {
    // В duress mode контакты "не существуют"
    if (_isDuressMode) return null;
    
    try {
      final db = await instance.database;
      final maps = await db.query(
        'contacts',
        where: 'publicKey = ?',
        whereArgs: [publicKey],
        limit: 1,
      );
      
      if (maps.isEmpty) {
        return null;
      }
      
      return Contact(
        id: maps[0]['id'] as int,
        name: maps[0]['name'] as String,
        publicKey: maps[0]['publicKey'] as String,
      );
    } catch (e) {
      print("DB ERROR: Failed to get contact by publicKey: $e");
      return null;
    }
  }

  Future<void> deleteContact(int id, String publicKey) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'contactPublicKey = ?', whereArgs: [publicKey]);
      await txn.delete('contacts', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Обновить имя контакта
  Future<void> updateContactName(int id, String newName) async {
    // В duress mode не обновляем
    if (_isDuressMode) return;
    
    final db = await instance.database;
    await db.update(
      'contacts',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Сообщения ---

  // Сохранить сообщение
  Future<void> addMessage(ChatMessage message, String contactKey) async {
    // В duress mode сообщения НЕ показываем, но входящие всё равно сохраняем,
    // чтобы пользователь не терял данные.
    
    final db = await instance.database;
    await db.insert('messages', message.toMap(contactKey),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Обновить статус сообщения (для исходящих/входящих).
  ///
  /// Контракт: обновляет строку по (contactPublicKey, timestamp, isSentByMe).
  /// Это достаточно детерминировано для наших сообщений, т.к. timestamp задаётся при создании.
  Future<void> updateMessageStatus({
    required String contactKey,
    required int timestampMs,
    required bool isSentByMe,
    required MessageStatus status,
  }) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'status': status.index},
      where: 'contactPublicKey = ? AND timestamp = ? AND isSentByMe = ?',
      whereArgs: [contactKey, timestampMs, isSentByMe ? 1 : 0],
    );
  }

  /// Обновить статус сообщения по стабильному messageId (точнее, чем по времени).
  Future<void> updateMessageStatusByMessageId(
    String contactKey,
    String messageId,
    MessageStatus status,
  ) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'status': status.index},
      where: 'contactPublicKey = ? AND messageId = ?',
      whereArgs: [contactKey, messageId],
    );
  }

  // Получить сообщения (с маппингом новых полей)
  Future<List<ChatMessage>> getMessagesForContact(String contactKey) async {
    // В duress mode возвращаем пустой список
    if (_isDuressMode) return [];
    
    final db = await instance.database;
    final maps = await db.query(
      'messages',
      where: 'contactPublicKey = ?',
      whereArgs: [contactKey],
      orderBy: 'timestamp ASC',
    );

    return maps.map(_rowToMessage).toList();
  }

  /// Сообщения контакта СТРОГО новее указанной метки времени (ASC).
  /// Для инкрементальной подгрузки новых сообщений без перечитывания всей
  /// истории на каждое входящее (аудит PERF-1).
  Future<List<ChatMessage>> getMessagesForContactAfter(
      String contactKey, int afterMs) async {
    if (_isDuressMode) return [];
    final db = await instance.database;
    final maps = await db.query(
      'messages',
      where: 'contactPublicKey = ? AND timestamp > ?',
      whereArgs: [contactKey, afterMs],
      orderBy: 'timestamp ASC',
    );
    return maps.map(_rowToMessage).toList();
  }

  ChatMessage _rowToMessage(Map<String, Object?> row) {
    return ChatMessage(
      id: row['id'] as int?,
      messageId: row['messageId'] as String?,
      text: row['text'] as String,
      isSentByMe: (row['isSentByMe'] as int) == 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      status: MessageStatus.values[(row['status'] as int?) ?? 1],
      isRead: ((row['isRead'] as int?) ?? 1) == 1,
    );
  }

  // --- AI Assistant ---

  Future<void> addAiMessage(AiMessage message, {int assistantLimit = 20}) async {
    final db = await instance.database;
    await db.insert('ai_messages', {
      'role': message.role.name,
      'content': message.content,
      'created_at': message.createdAt.millisecondsSinceEpoch,
      'is_error': message.isError ? 1 : 0,
    });
    await _trimAiMessages(db, assistantLimit);
  }

  Future<List<AiMessage>> getAiMessages({int assistantLimit = 20}) async {
    if (_isDuressMode) return [];
    final db = await instance.database;
    final rows = await db.query(
      'ai_messages',
      orderBy: 'created_at ASC',
    );
    return rows.map((row) {
      final role = AiMessageRole.values.firstWhere(
        (r) => r.name == row['role'],
        orElse: () => AiMessageRole.assistant,
      );
      return AiMessage(
        id: (row['id'] as int).toString(),
        role: role,
        content: row['content'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        isError: (row['is_error'] as int? ?? 0) == 1,
      );
    }).toList(growable: false);
  }

  Future<void> setAiParentMessageId(String? id) async {
    final db = await instance.database;
    if (id == null || id.isEmpty) {
      await db.delete('ai_context', where: 'key = ?', whereArgs: ['parent_message_id']);
      return;
    }
    await db.insert(
      'ai_context',
      {'key': 'parent_message_id', 'value': id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getAiParentMessageId() async {
    if (_isDuressMode) return null;
    final db = await instance.database;
    final rows = await db.query(
      'ai_context',
      where: 'key = ?',
      whereArgs: ['parent_message_id'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> clearAiChat() async {
    final db = await instance.database;
    await db.delete('ai_messages');
    await db.delete('ai_context', where: 'key = ?', whereArgs: ['parent_message_id']);
  }

  // --- Notes ---

  Future<void> addNote({
    required String text,
    required String sourceType,
    String? sourceId,
    String? sourceLabel,
    DateTime? createdAt,
  }) async {
    if (_isDuressMode) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final db = await instance.database;
    await db.insert('notes', {
      'text': trimmed,
      'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
      'source_type': sourceType,
      'source_id': sourceId,
      'source_label': sourceLabel,
    });
  }

  Future<List<Map<String, dynamic>>> getNotes() async {
    if (_isDuressMode) return [];
    final db = await instance.database;
    return db.query(
      'notes',
      orderBy: 'created_at DESC',
    );
  }

  Future<void> deleteNote(int id) async {
    if (_isDuressMode) return;
    final db = await instance.database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearNotes() async {
    if (_isDuressMode) return;
    final db = await instance.database;
    await db.delete('notes');
  }

  Future<void> _trimAiMessages(Database db, int assistantLimit) async {
    if (assistantLimit <= 0) return;
    final rows = await db.query(
      'ai_messages',
      columns: ['id', 'role'],
      orderBy: 'created_at ASC',
    );
    if (rows.isEmpty) return;

    final assistantIndices = <int>[];
    for (var i = 0; i < rows.length; i++) {
      if ((rows[i]['role'] as String?) == 'assistant') {
        assistantIndices.add(i);
      }
    }
    if (assistantIndices.length <= assistantLimit) return;

    final startAssistantIndex =
        assistantIndices[assistantIndices.length - assistantLimit];
    var keepStart = startAssistantIndex;
    for (var i = startAssistantIndex - 1; i >= 0; i--) {
      if ((rows[i]['role'] as String?) == 'user') {
        keepStart = i;
        break;
      }
    }

    final idsToDelete = <int>[];
    for (var i = 0; i < keepStart; i++) {
      final id = rows[i]['id'] as int;
      idsToDelete.add(id);
    }
    if (idsToDelete.isEmpty) return;
    await db.transaction((txn) async {
      for (final id in idsToDelete) {
        await txn.delete('ai_messages', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  // Пометить все сообщения от контакта как прочитанные
  Future<void> markMessagesAsRead(String contactKey) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'isRead': 1},
      where: 'contactPublicKey = ? AND isRead = 0',
      whereArgs: [contactKey],
    );
  }

  // Получить количество непрочитанных для контакта
  Future<int> getUnreadCount(String contactKey) async {
    final db = await instance.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) FROM messages WHERE contactPublicKey = ? AND isRead = 0',
        [contactKey]
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Получить непрочитанные счётчики сразу для списка контактов.
  ///
  /// Важно для UI: вместо `FutureBuilder` на каждый элемент списка — один запрос и один rebuild.
  Future<Map<String, int>> getUnreadCountsForContacts(List<String> contactKeys) async {
    // В duress mode ничего не показываем.
    if (_isDuressMode) return <String, int>{};
    if (contactKeys.isEmpty) return <String, int>{};

    final db = await instance.database;
    final placeholders = List.filled(contactKeys.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT contactPublicKey, COUNT(*) as cnt '
      'FROM messages '
      'WHERE isRead = 0 AND contactPublicKey IN ($placeholders) '
      'GROUP BY contactPublicKey',
      contactKeys,
    );

    final Map<String, int> result = <String, int>{};
    for (final row in rows) {
      final key = row['contactPublicKey'] as String?;
      final cnt = row['cnt'];
      if (key == null) continue;
      result[key] = (cnt is int) ? cnt : (cnt is num ? cnt.toInt() : 0);
    }
    return result;
  }

  Future<void> clearChatHistory(String contactKey) async {
    final db = await instance.database;
    await db.delete('messages', where: 'contactPublicKey = ?', whereArgs: [contactKey]);
  }

  Future<int> deleteMessagesByTimestamps(String contactKey, List<int> timestamps) async {
    if (_isDuressMode || timestamps.isEmpty) return 0;
    final db = await instance.database;
    final placeholders = List.filled(timestamps.length, '?').join(',');
    return await db.delete(
      'messages',
      where: 'contactPublicKey = ? AND timestamp IN ($placeholders)',
      whereArgs: [contactKey, ...timestamps],
    );
  }

  /// Удалить сообщения по стабильным messageId (для «удалить у обоих»).
  Future<int> deleteMessagesByMessageIds(String contactKey, List<String> messageIds) async {
    if (_isDuressMode || messageIds.isEmpty) return 0;
    final db = await instance.database;
    final placeholders = List.filled(messageIds.length, '?').join(',');
    return await db.delete(
      'messages',
      where: 'contactPublicKey = ? AND messageId IN ($placeholders)',
      whereArgs: [contactKey, ...messageIds],
    );
  }

  /// Есть ли уже сообщение с таким messageId от этого контакта (для дедупа входящих).
  Future<bool> messageExistsByMessageId(String contactKey, String messageId) async {
    final db = await instance.database;
    final rows = await db.query(
      'messages',
      columns: ['id'],
      where: 'contactPublicKey = ? AND messageId = ?',
      whereArgs: [contactKey, messageId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Удалить все сообщения старше указанной даты.
  /// 
  /// Используется для автоматической очистки сообщений по политике retention.
  /// Возвращает количество удалённых сообщений.
  Future<int> deleteMessagesOlderThan(DateTime cutoff) async {
    // В duress mode не удаляем — это может быть подозрительно
    // (пользователь под давлением не должен запускать необратимые действия)
    if (_isDuressMode) return 0;
    
    try {
      final db = await instance.database;
      final cutoffMs = cutoff.millisecondsSinceEpoch;
      
      final deletedCount = await db.delete(
        'messages',
        where: 'timestamp < ?',
        whereArgs: [cutoffMs],
      );
      
      print("DB: Удалено $deletedCount сообщений старше ${cutoff.toIso8601String()}");
      return deletedCount;
    } catch (e) {
      print("DB ERROR: Error deleting old messages: $e");
      return 0;
    }
  }

  /// Получить количество сообщений, которые будут удалены при данном cutoff.
  /// Используется для preview в UI перед включением политики.
  Future<int> countMessagesOlderThan(DateTime cutoff) async {
    if (_isDuressMode) return 0;
    
    try {
      final db = await instance.database;
      final cutoffMs = cutoff.millisecondsSinceEpoch;
      
      final result = await db.rawQuery(
        'SELECT COUNT(*) FROM messages WHERE timestamp < ?',
        [cutoffMs],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      print("DB ERROR: Error counting old messages: $e");
      return 0;
    }
  }

  Future close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Полное удаление локальной БД (для wipe).
  /// Блокирует повторное открытие БД до завершения удаления.
  Future<void> deleteDatabaseFile() async {
    _isWiping = true;
    try {
      // 1. Close open connection
      await close();

      final path = await _dbPath();

      // 2. Try sqflite deleteDatabase
      try {
        await deleteDatabase(path);
      } catch (_) {}

      // 3. Force delete file if still exists
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }

      // 4. Also delete journal/wal files
      for (final suffix in ['-journal', '-wal', '-shm']) {
        final f = File('$path$suffix');
        if (await f.exists()) await f.delete();
      }

      // 5. Delete the DB encryption key from secure storage, so any residual
      //    ciphertext is cryptographically unrecoverable and the next launch
      //    regenerates a fresh key + empty database.
      try {
        await _secureStorage.delete(key: _dbKeyStoreKey);
      } catch (_) {}

      // 6. Verify deletion
      if (await File(path).exists()) {
        DebugLogger.error('DB', 'Файл БД всё ещё существует после удаления!');
      } else {
        DebugLogger.success('DB', 'БД удалена и проверена');
      }
    } catch (e) {
      print("DB ERROR: Error deleting database: $e");
      rethrow;
    } finally {
      _isWiping = false;
    }
  }

  // --- Статистика для профиля ---

  /// Получить общее количество контактов
  Future<int> getTotalContactsCount() async {
    // В duress mode — 0
    if (_isDuressMode) return 0;
    
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM contacts');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Получить общее количество сообщений
  Future<int> getTotalMessagesCount() async {
    // В duress mode — 0
    if (_isDuressMode) return 0;
    
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM messages');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Получить количество отправленных сообщений
  Future<int> getSentMessagesCount() async {
    // В duress mode — 0
    if (_isDuressMode) return 0;
    
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM messages WHERE isSentByMe = 1');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Получить полную статистику профиля
  Future<Map<String, int>> getProfileStats() async {
    // В duress mode — всё по нулям
    if (_isDuressMode) {
      return {'contacts': 0, 'messages': 0, 'sent': 0};
    }
    
    final db = await instance.database;
    
    final contactsResult = await db.rawQuery('SELECT COUNT(*) FROM contacts');
    final messagesResult = await db.rawQuery('SELECT COUNT(*) FROM messages');
    final sentResult = await db.rawQuery('SELECT COUNT(*) FROM messages WHERE isSentByMe = 1');
    
    return {
      'contacts': Sqflite.firstIntValue(contactsResult) ?? 0,
      'messages': Sqflite.firstIntValue(messagesResult) ?? 0,
      'sent': Sqflite.firstIntValue(sentResult) ?? 0,
    };
  }
}