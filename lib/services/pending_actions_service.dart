// lib/services/pending_actions_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Минимальный интерфейс для хранилища pending-actions (для unit-тестов без плагинов).
abstract class PendingActionsPrefs {
  List<String>? getStringList(String key);
  Future<bool> setStringList(String key, List<String> value);
  Future<bool> remove(String key);
}

class SharedPrefsPendingActionsPrefs implements PendingActionsPrefs {
  SharedPrefsPendingActionsPrefs(this._prefs);
  final SharedPreferences _prefs;

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  @override
  Future<bool> setStringList(String key, List<String> value) => _prefs.setStringList(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);
}

/// Сервис для хранения и обработки отложенных действий (например, отклонение звонков, сообщения)
/// когда приложение закрыто и WebSocket не подключен
class PendingActionsService {
  static const String _pendingRejectionsKey = 'pending_call_rejections';
  static const String _pendingMessagesKey = 'pending_messages';

  static Future<PendingActionsPrefs> Function() _prefsProvider =
      () async => SharedPrefsPendingActionsPrefs(await SharedPreferences.getInstance());

  /// В unit-тестах можно подменить хранилище, чтобы проверять ошибки/краевые случаи.
  static void debugSetPrefsProviderForTesting(Future<PendingActionsPrefs> Function()? provider) {
    _prefsProvider = provider ??
        (() async => SharedPrefsPendingActionsPrefs(await SharedPreferences.getInstance()));
  }

  static Future<PendingActionsPrefs> _prefs() => _prefsProvider();
  
  /// Сохранить отклонение звонка для последующей отправки
  static Future<void> addPendingRejection(String callerKey) async {
    try {
      final prefs = await _prefs();
      final existing = prefs.getStringList(_pendingRejectionsKey) ?? [];
      
      // Добавляем только если еще нет
      if (!existing.contains(callerKey)) {
        existing.add(callerKey);
        await prefs.setStringList(_pendingRejectionsKey, existing);
        print("📞 Pending rejection сохранен для: $callerKey");
      }
    } catch (e) {
      print("📞 ERROR: Не удалось сохранить pending rejection: $e");
    }
  }
  
  /// Получить все pending rejections
  static Future<List<String>> getPendingRejections() async {
    try {
      final prefs = await _prefs();
      return prefs.getStringList(_pendingRejectionsKey) ?? [];
    } catch (e) {
      print("📞 ERROR: Не удалось получить pending rejections: $e");
      return [];
    }
  }
  
  /// Удалить pending rejection после отправки
  static Future<void> removePendingRejection(String callerKey) async {
    try {
      final prefs = await _prefs();
      final existing = prefs.getStringList(_pendingRejectionsKey) ?? [];
      existing.remove(callerKey);
      await prefs.setStringList(_pendingRejectionsKey, existing);
      print("📞 Pending rejection удален для: $callerKey");
    } catch (e) {
      print("📞 ERROR: Не удалось удалить pending rejection: $e");
    }
  }
  
  /// Очистить все pending rejections
  static Future<void> clearAllPendingRejections() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_pendingRejectionsKey);
      print("📞 Все pending rejections очищены");
    } catch (e) {
      print("📞 ERROR: Не удалось очистить pending rejections: $e");
    }
  }

  // ========== PENDING MESSAGES (Очередь сообщений для offline) ==========

  /// Добавить сообщение в очередь для отправки
  static Future<void> addPendingMessage({
    required String recipientKey,
    required String encryptedPayload,
    String? messageId,
  }) async {
    try {
      final prefs = await _prefs();
      final existing = prefs.getStringList(_pendingMessagesKey) ?? [];

      final messageData = json.encode({
        'recipientKey': recipientKey,
        'payload': encryptedPayload,
        'messageId': messageId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      existing.add(messageData);
      await prefs.setStringList(_pendingMessagesKey, existing);
      print("💬 Pending message добавлено для: ${recipientKey.substring(0, 8)}...");
    } catch (e) {
      print("💬 ERROR: Не удалось добавить pending message: $e");
    }
  }
  
  /// Получить все pending messages
  static Future<List<PendingMessage>> getPendingMessages() async {
    try {
      final prefs = await _prefs();
      final existing = prefs.getStringList(_pendingMessagesKey) ?? [];
      
      return existing.map((jsonStr) {
        try {
          final data = json.decode(jsonStr) as Map<String, dynamic>;
          return PendingMessage(
            recipientKey: data['recipientKey'] as String,
            encryptedPayload: data['payload'] as String,
            messageId: data['messageId'] as String?,
            timestamp: DateTime.tryParse(data['timestamp'] as String? ?? '') ?? DateTime.now(),
          );
        } catch (_) {
          return null;
        }
      }).whereType<PendingMessage>().toList();
    } catch (e) {
      print("💬 ERROR: Не удалось получить pending messages: $e");
      return [];
    }
  }
  
  /// Удалить все pending messages (после успешной отправки)
  static Future<void> clearPendingMessages() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_pendingMessagesKey);
      print("💬 Все pending messages очищены");
    } catch (e) {
      print("💬 ERROR: Не удалось очистить pending messages: $e");
    }
  }

  /// Удалить первые [count] pending messages, оставив остальные в очереди.
  /// Используется когда отправка прервалась на середине — удаляем только отправленные.
  static Future<void> removeFirstMessages(int count) async {
    if (count <= 0) return;
    try {
      final prefs = await _prefs();
      final existing = prefs.getStringList(_pendingMessagesKey) ?? [];
      if (count >= existing.length) {
        await prefs.remove(_pendingMessagesKey);
      } else {
        await prefs.setStringList(_pendingMessagesKey, existing.sublist(count));
      }
    } catch (e) {
      print("💬 ERROR: Не удалось удалить первые $count pending messages: $e");
    }
  }
  
  /// Количество pending messages
  static Future<int> getPendingMessagesCount() async {
    try {
      final prefs = await _prefs();
      final existing = prefs.getStringList(_pendingMessagesKey) ?? [];
      return existing.length;
    } catch (e) {
      return 0;
    }
  }
}

/// Модель pending сообщения
class PendingMessage {
  final String recipientKey;
  final String encryptedPayload;
  final String? messageId;
  final DateTime timestamp;

  PendingMessage({
    required this.recipientKey,
    required this.encryptedPayload,
    this.messageId,
    required this.timestamp,
  });
}

