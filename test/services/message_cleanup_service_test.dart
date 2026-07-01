// test/services/message_cleanup_service_test.dart
// Тесты для MessageCleanupService

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/message_retention_policy.dart';
import 'package:orpheus_project/models/security_config.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/message_cleanup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Инициализация FFI для sqflite в тестах
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('MessageCleanupService', () {
    late _MockAuthStorage mockStorage;
    late AuthService authService;
    late DatabaseService databaseService;
    late MessageCleanupService cleanupService;
    late DateTime fixedNow;

    setUp(() async {
      fixedNow = DateTime(2024, 1, 15, 12, 0, 0);
      
      // Создаём mock storage
      mockStorage = _MockAuthStorage();
      
      // Создаём AuthService для тестов
      authService = AuthService.createForTesting(
        secureStorage: mockStorage,
        now: () => fixedNow,
      );
      await authService.init();
      
      // Создаём in-memory БД с уникальным именем для каждого теста
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
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
        ),
      );
      
      // Очищаем таблицы перед каждым тестом
      await db.delete('messages');
      await db.delete('contacts');
      
      databaseService = DatabaseService.instance;
      databaseService.initWithDatabase(db);
      
      // Создаём CleanupService
      cleanupService = MessageCleanupService.createForTesting(
        authService: authService,
        databaseService: databaseService,
        now: () => fixedNow,
      );
    });

    group('shouldRunMessageCleanup', () {
      test('returns false when policy is all', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.all);
        expect(authService.shouldRunMessageCleanup, isFalse);
      });

      test('returns true when policy is not all and no previous cleanup', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.day);
        expect(authService.shouldRunMessageCleanup, isTrue);
      });

      test('returns false when last cleanup was less than 1 hour ago', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.day);
        
        // Устанавливаем время последней очистки 30 минут назад
        final recentTime = fixedNow.subtract(const Duration(minutes: 30));
        await authService.updateLastMessageCleanup(recentTime);
        
        expect(authService.shouldRunMessageCleanup, isFalse);
      });

      test('returns true when last cleanup was more than 1 hour ago', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.day);
        
        // Устанавливаем время последней очистки 2 часа назад
        final oldTime = fixedNow.subtract(const Duration(hours: 2));
        await authService.updateLastMessageCleanup(oldTime);
        
        expect(authService.shouldRunMessageCleanup, isTrue);
      });
    });

    group('performCleanup', () {
      test('skips when policy is all', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.all);
        
        final result = await cleanupService.performCleanup();
        
        expect(result.status, equals(CleanupStatus.skipped));
        expect(result.message, contains('хранить всё'));
      });

      test('deletes old messages when policy is day', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.day);
        
        // Добавляем сообщения: одно старое (2 дня), одно свежее (1 час)
        final db = await databaseService.database;
        
        // Старое сообщение (2 дня назад)
        await db.insert('messages', {
          'contactPublicKey': 'contact1',
          'text': 'old message',
          'isSentByMe': 1,
          'timestamp': fixedNow.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          'status': 1,
          'isRead': 1,
        });
        
        // Свежее сообщение (1 час назад)
        await db.insert('messages', {
          'contactPublicKey': 'contact1',
          'text': 'new message',
          'isSentByMe': 1,
          'timestamp': fixedNow.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          'status': 1,
          'isRead': 1,
        });
        
        final result = await cleanupService.performCleanup();
        
        expect(result.status, equals(CleanupStatus.success));
        expect(result.deletedCount, equals(1)); // Удалено 1 старое сообщение
        
        // Проверяем, что осталось только свежее сообщение
        final remaining = await db.query('messages');
        expect(remaining.length, equals(1));
        expect(remaining.first['text'], equals('new message'));
      });

      test('deletes messages older than week when policy is week', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.week);
        
        final db = await databaseService.database;
        
        // Сообщение 10 дней назад (должно удалиться)
        await db.insert('messages', {
          'contactPublicKey': 'contact1',
          'text': 'very old',
          'isSentByMe': 1,
          'timestamp': fixedNow.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
          'status': 1,
          'isRead': 1,
        });
        
        // Сообщение 3 дня назад (должно остаться)
        await db.insert('messages', {
          'contactPublicKey': 'contact1',
          'text': 'recent',
          'isSentByMe': 1,
          'timestamp': fixedNow.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
          'status': 1,
          'isRead': 1,
        });
        
        final result = await cleanupService.performCleanup();
        
        expect(result.status, equals(CleanupStatus.success));
        expect(result.deletedCount, equals(1));
        
        final remaining = await db.query('messages');
        expect(remaining.length, equals(1));
        expect(remaining.first['text'], equals('recent'));
      });

      test('updates lastMessageCleanupAt after successful cleanup', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.day);
        
        expect(authService.lastMessageCleanupAt, isNull);
        
        await cleanupService.performCleanup();
        
        expect(authService.lastMessageCleanupAt, equals(fixedNow));
      });
    });

    group('performCleanupIfNeeded', () {
      test('skips when shouldRunMessageCleanup is false', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.all);
        
        final result = await cleanupService.performCleanupIfNeeded();
        
        expect(result.status, equals(CleanupStatus.skipped));
      });

      test('runs cleanup when shouldRunMessageCleanup is true', () async {
        await authService.setMessageRetention(MessageRetentionPolicy.day);
        
        final result = await cleanupService.performCleanupIfNeeded();
        
        // Даже без сообщений — должен быть success с 0 удалённых
        expect(result.status, equals(CleanupStatus.success));
      });
    });

    group('getCleanupPreview', () {
      test('returns 0 for policy all', () async {
        final count = await cleanupService.getCleanupPreview(MessageRetentionPolicy.all);
        expect(count, equals(0));
      });

      test('returns count of messages to be deleted', () async {
        final db = await databaseService.database;
        
        // Добавляем 3 старых и 2 новых сообщения
        for (var i = 0; i < 3; i++) {
          await db.insert('messages', {
            'contactPublicKey': 'contact1',
            'text': 'old $i',
            'isSentByMe': 1,
            'timestamp': fixedNow.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
            'status': 1,
            'isRead': 1,
          });
        }
        
        for (var i = 0; i < 2; i++) {
          await db.insert('messages', {
            'contactPublicKey': 'contact1',
            'text': 'new $i',
            'isSentByMe': 1,
            'timestamp': fixedNow.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
            'status': 1,
            'isRead': 1,
          });
        }
        
        final preview = await cleanupService.getCleanupPreview(MessageRetentionPolicy.week);
        expect(preview, equals(3)); // 3 старых сообщения будут удалены
      });
    });

    group('onRetentionPolicyChanged', () {
      test('performs immediate cleanup', () async {
        final db = await databaseService.database;
        
        // Добавляем старое сообщение
        await db.insert('messages', {
          'contactPublicKey': 'contact1',
          'text': 'old',
          'isSentByMe': 1,
          'timestamp': fixedNow.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
          'status': 1,
          'isRead': 1,
        });
        
        // Устанавливаем политику через authService
        await authService.setMessageRetention(MessageRetentionPolicy.day);
        
        // Вызываем обработчик изменения политики
        final result = await cleanupService.onRetentionPolicyChanged(MessageRetentionPolicy.day);
        
        expect(result.status, equals(CleanupStatus.success));
        expect(result.deletedCount, equals(1));
      });
    });
  });
}

/// Мок для secure storage
class _MockAuthStorage implements AuthSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read({required String key}) async => _storage[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _storage.clear();
  }
}
