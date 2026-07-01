// lib/services/auth_service.dart
// Сервис авторизации: PIN-код, duress code, блокировка

import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:orpheus_project/models/security_config.dart';
import 'package:orpheus_project/models/message_retention_policy.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Абстракция для secure storage (нужна для unit-тестов без MethodChannel).
abstract class AuthSecureStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

/// Прод-реализация secure storage через `flutter_secure_storage`.
class FlutterAuthSecureStorage implements AuthSecureStorage {
  FlutterAuthSecureStorage(this._inner);
  final FlutterSecureStorage _inner;

  @override
  Future<String?> read({required String key}) => _inner.read(key: key);

  @override
  Future<void> write({required String key, required String value}) => _inner.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _inner.delete(key: key);
}

class AuthService {
  static final AuthService instance = AuthService._();

  /// Callback for notifying _AppState that wipe completed.
  /// Set by _AppState.initState() to reset navigation state.
  static VoidCallback? onWipeCompleted;

  /// Создать отдельный экземпляр (в тестах), чтобы не трогать singleton и не зависеть от плагинов.
  static AuthService createForTesting({
    required AuthSecureStorage secureStorage,
    DateTime Function()? now,
  }) {
    return AuthService._(secureStorage: secureStorage, now: now);
  }

  AuthService._({
    AuthSecureStorage? secureStorage,
    DateTime Function()? now,
  })  : _secureStorage =
            secureStorage ?? FlutterAuthSecureStorage(const FlutterSecureStorage()),
        _now = now ?? DateTime.now;

  final AuthSecureStorage _secureStorage;
  final DateTime Function() _now;
  static const _configKey = 'orpheus_security_config';

  /// Текущая конфигурация безопасности
  SecurityConfig _config = SecurityConfig.empty;
  SecurityConfig get config => _config;

  /// Флаг: приложение сейчас в duress mode (показывает пустой профиль)
  bool _isDuressMode = false;
  bool get isDuressMode => _isDuressMode;

  /// Флаг: приложение разблокировано
  bool _isUnlocked = false;
  bool get isUnlocked => _isUnlocked;

  /// Инициализация сервиса — загрузка конфигурации
  Future<void> init() async {
    try {
      final configJson = await _secureStorage.read(key: _configKey);
      if (configJson != null) {
        final map = json.decode(configJson) as Map<String, dynamic>;
        _config = SecurityConfig.fromMap(map);
        DebugLogger.info('AUTH', 'Config loaded'); // без дампа конфига (хэши/соль)
      } else {
        _config = SecurityConfig.empty;
        print("AUTH: Config not found, using empty");
      }
      
      // Если PIN не настроен — приложение автоматически разблокировано
      if (!_config.requiresUnlock) {
        _isUnlocked = true;
      }
    } catch (e) {
      print("AUTH ERROR: Config load error: $e");
      _config = SecurityConfig.empty;
      _isUnlocked = true;
    }
  }

  /// Сохранить конфигурацию
  Future<void> _saveConfig() async {
    final configJson = json.encode(_config.toMap());
    await _secureStorage.write(key: _configKey, value: configJson);
  }

  /// Проверить, нужна ли разблокировка
  bool get requiresUnlock => _config.requiresUnlock && !_isUnlocked;

  // === УПРАВЛЕНИЕ PIN ===

  /// Установить новый PIN-код
  /// [pinLength] — длина PIN-кода (4 или 6), используется для UI и валидации
  Future<void> setPin(String pin, {int pinLength = 6}) async {
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    
    _config = _config.copyWith(
      isPinEnabled: true,
      pinLength: pinLength,
      pinHash: hash,
      pinSalt: salt,
      failedAttempts: 0,
      clearLastFailedAttempt: true,
    );
    
    await _saveConfig();
    _isUnlocked = true;
    print("AUTH: PIN set (length: $pinLength)");
  }

  /// Изменить PIN-код (требует текущий PIN)
  /// При изменении PIN сохраняется текущая длина
  Future<bool> changePin(String currentPin, String newPin) async {
    final result = verifyPin(currentPin);
    if (result != PinVerifyResult.success) {
      return false;
    }
    
    // Сохраняем текущую длину PIN при изменении
    await setPin(newPin, pinLength: _config.pinLength);
    return true;
  }

  /// Отключить PIN-код (требует текущий PIN)
  Future<bool> disablePin(String currentPin) async {
    final result = verifyPin(currentPin);
    if (result != PinVerifyResult.success) {
      return false;
    }
    
    _config = _config.copyWith(
      isPinEnabled: false,
      clearPinHash: true,
      isDuressEnabled: false,
      clearDuressHash: true,
      isWipeCodeEnabled: false,
      clearWipeCodeHash: true,
      isPanicGestureEnabled: false,
      failedAttempts: 0,
      clearLastFailedAttempt: true,
    );
    
    await _saveConfig();
    _isUnlocked = true;
    print("AUTH: PIN disabled");
    return true;
  }

  /// Проверить PIN-код
  PinVerifyResult verifyPin(String pin) {
    if (!_config.isPinEnabled || _config.pinHash == null) {
      _isUnlocked = true;
      return PinVerifyResult.success;
    }

    // Проверка блокировки
    if (_config.isLockedOut) {
      print("AUTH: ⛔ Login attempt during lockout (pinLength: ${_config.pinLength})");
      return PinVerifyResult.lockedOut;
    }

    // Проверка основного PIN
    final hash = _hashPin(pin, _config.pinSalt!);
    if (hash == _config.pinHash) {
      _resetFailedAttempts();
      _isUnlocked = true;
      _isDuressMode = false;
      print("AUTH: ✅ PIN correct (${_config.pinLength}-digit), unlocked");
      return PinVerifyResult.success;
    }

    // Проверка кода удаления (wipe code)
    // ВАЖНО: возвращаем wipeCode без инкремента попыток — это сознательное действие.
    if (_config.isWipeCodeEnabled && _config.wipeCodeHash != null && _config.wipeCodeSalt != null) {
      final wipeHash = _hashPin(pin, _config.wipeCodeSalt!);
      if (wipeHash == _config.wipeCodeHash) {
        _resetFailedAttempts();
        DebugLogger.warn('AUTH', 'Wipe code entered — confirmation required');
        return PinVerifyResult.wipeCode;
      }
    }

    // Проверка duress кода
    if (_config.isDuressEnabled && _config.duressHash != null) {
      final duressHash = _hashPin(pin, _config.duressSalt!);
      if (duressHash == _config.duressHash) {
        _resetFailedAttempts();
        _isUnlocked = true;
        _isDuressMode = true;
        DebugLogger.warn('AUTH', 'Duress code entered, empty profile activated');
        return PinVerifyResult.duress;
      }
    }

    // Неверный PIN
    _incrementFailedAttempts();
    
    // Проверка автоматического wipe
    if (_config.shouldAutoWipe) {
      DebugLogger.warn('AUTH', 'Attempt limit exceeded, auto-wipe required');
      return PinVerifyResult.autoWipe;
    }

    return PinVerifyResult.invalid;
  }

  /// Сбросить счётчик неудачных попыток
  Future<void> _resetFailedAttempts() async {
    _config = _config.copyWith(
      failedAttempts: 0,
      clearLastFailedAttempt: true,
    );
    await _saveConfig();
  }

  /// Увеличить счётчик неудачных попыток
  Future<void> _incrementFailedAttempts() async {
    _config = _config.copyWith(
      failedAttempts: _config.failedAttempts + 1,
      lastFailedAttempt: _now(),
    );
    await _saveConfig();
    DebugLogger.warn('AUTH', 'Wrong PIN attempt');
  }

  // === УПРАВЛЕНИЕ DURESS CODE ===

  /// Установить код принуждения (требует основной PIN)
  Future<bool> setDuressCode(String mainPin, String duressCode) async {
    // Проверяем основной PIN
    final hash = _hashPin(mainPin, _config.pinSalt!);
    if (hash != _config.pinHash) {
      return false;
    }

    // Duress код не должен совпадать с основным PIN
    if (mainPin == duressCode) {
      return false;
    }

    final salt = _generateSalt();
    final duressHash = _hashPin(duressCode, salt);
    
    _config = _config.copyWith(
      isDuressEnabled: true,
      duressHash: duressHash,
      duressSalt: salt,
    );
    
    await _saveConfig();
    DebugLogger.info('AUTH', 'Duress code set');
    return true;
  }

  /// Отключить код принуждения (требует основной PIN)
  Future<bool> disableDuressCode(String mainPin) async {
    final hash = _hashPin(mainPin, _config.pinSalt!);
    if (hash != _config.pinHash) {
      return false;
    }
    
    _config = _config.copyWith(
      isDuressEnabled: false,
      clearDuressHash: true,
    );
    
    await _saveConfig();
    _isDuressMode = false;
    print("AUTH: Duress code disabled");
    return true;
  }

  // === УПРАВЛЕНИЕ КОДОМ УДАЛЕНИЯ ===

  /// Установить код удаления (требует основной PIN)
  Future<bool> setWipeCode(String mainPin, String wipeCode) async {
    if (_config.pinHash == null || _config.pinSalt == null) return false;

    final hash = _hashPin(mainPin, _config.pinSalt!);
    if (hash != _config.pinHash) return false;

    // Код удаления не должен совпадать с основным PIN
    if (wipeCode == mainPin) return false;

    final salt = _generateSalt();
    final wipeHash = _hashPin(wipeCode, salt);

    _config = _config.copyWith(
      isWipeCodeEnabled: true,
      wipeCodeHash: wipeHash,
      wipeCodeSalt: salt,
    );

    await _saveConfig();
    DebugLogger.info('AUTH', 'Wipe code set');
    return true;
  }

  /// Отключить код удаления (требует основной PIN)
  Future<bool> disableWipeCode(String mainPin) async {
    if (_config.pinHash == null || _config.pinSalt == null) return false;

    final hash = _hashPin(mainPin, _config.pinSalt!);
    if (hash != _config.pinHash) return false;

    _config = _config.copyWith(
      isWipeCodeEnabled: false,
      clearWipeCodeHash: true,
    );

    await _saveConfig();
    print("AUTH: Wipe code disabled");
    return true;
  }

  // === PANIC GESTURE (3x уход в фон) ===

  Future<void> setPanicGestureEnabled(bool enabled) async {
    _config = _config.copyWith(isPanicGestureEnabled: enabled);
    await _saveConfig();
    print("AUTH: Panic gesture ${enabled ? 'enabled' : 'disabled'}");
  }

  // === БЛОКИРОВКА ПО ТАЙМАУТУ НЕАКТИВНОСТИ ===

  int get inactivityLockSeconds => _config.inactivityLockSeconds;

  Future<void> setInactivityLockSeconds(int seconds) async {
    _config = _config.copyWith(inactivityLockSeconds: seconds);
    await _saveConfig();
    print("AUTH: Inactivity lock timeout = ${seconds}s");
  }

  // === АВТОУДАЛЕНИЕ СООБЩЕНИЙ ===

  /// Текущая политика хранения сообщений
  MessageRetentionPolicy get messageRetention => _config.messageRetention;

  /// Время последней очистки сообщений
  DateTime? get lastMessageCleanupAt => _config.lastMessageCleanupAt;

  /// Установить политику хранения сообщений
  Future<void> setMessageRetention(MessageRetentionPolicy policy) async {
    _config = _config.copyWith(messageRetention: policy);
    await _saveConfig();
    print("AUTH: Message retention set to: ${policy.displayName}");
  }

  /// Обновить время последней очистки сообщений
  Future<void> updateLastMessageCleanup([DateTime? time]) async {
    _config = _config.copyWith(lastMessageCleanupAt: time ?? _now());
    await _saveConfig();
  }

  /// Проверить, нужна ли очистка сообщений
  /// Возвращает true если:
  /// 1. Политика != all (есть ограничение)
  /// 2. Прошло больше часа с последней очистки (или очистка не выполнялась)
  bool get shouldRunMessageCleanup {
    if (_config.messageRetention == MessageRetentionPolicy.all) {
      return false; // Храним всё — очистка не нужна
    }
    
    final lastCleanup = _config.lastMessageCleanupAt;
    if (lastCleanup == null) {
      return true; // Очистка ни разу не выполнялась
    }
    
    // Не чистить чаще чем раз в час (оптимизация)
    const cleanupInterval = Duration(hours: 1);
    return _now().difference(lastCleanup) >= cleanupInterval;
  }

  // === БЛОКИРОВКА И РАЗБЛОКИРОВКА ===

  /// Заблокировать приложение (например, при сворачивании)
  void lock() {
    if (_config.requiresUnlock) {
      _isUnlocked = false;
      _isDuressMode = false;
      print("AUTH: 🔒 App locked (requires ${_config.pinLength}-digit PIN)");
    }
  }

  /// Выйти из duress mode (требует основной PIN)
  Future<bool> exitDuressMode(String mainPin) async {
    final result = verifyPin(mainPin);
    if (result == PinVerifyResult.success) {
      _isDuressMode = false;
      return true;
    }
    return false;
  }

  // === AUTO-WIPE ===

  /// Включить/выключить auto-wipe
  Future<void> setAutoWipe(bool enabled, {int attempts = 10}) async {
    _config = _config.copyWith(
      isAutoWipeEnabled: enabled,
      autoWipeAttempts: attempts,
    );
    await _saveConfig();
    print("AUTH: Auto-wipe ${enabled ? 'enabled ($attempts attempts)' : 'disabled'}");
  }

  /// Полный wipe — удаление всех данных
  Future<void> performWipe() async {
    DebugLogger.warn('AUTH', 'Performing full wipe');
    
    try {
      // 1. Удаляем криптоключи
      final cryptoService = CryptoService();
      await cryptoService.deleteAccount();
      
      // 2. Закрываем и удаляем базу данных
      await DatabaseService.instance.deleteDatabaseFile();
      
      // 3. Удаляем локальные настройки (SharedPreferences)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      } catch (_) {}

      // 4. Удаляем конфигурацию безопасности
      await _secureStorage.delete(key: _configKey);
      
      // 5. Сбрасываем состояние
      _config = SecurityConfig.empty;
      _isUnlocked = false;
      _isDuressMode = false;

      // 6. Notify _AppState to reset navigation
      onWipeCompleted?.call();

      DebugLogger.success('AUTH', 'Wipe completed');
    } catch (e) {
      DebugLogger.error('AUTH', 'Wipe error: $e');
      rethrow;
    }
  }

  // === УТИЛИТЫ ===

  /// Генерация случайной соли
  String _generateSalt() {
    final random = Random.secure();
    final saltBytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64.encode(saltBytes);
  }

  /// Хеширование PIN с солью (PBKDF2-like с SHA-256)
  String _hashPin(String pin, String salt) {
    // Простая схема: SHA-256(salt + pin + salt) повторенная несколько раз
    // Для production рекомендуется Argon2id, но для мобильного приложения это достаточно
    final saltBytes = base64.decode(salt);
    var data = [...saltBytes, ...utf8.encode(pin), ...saltBytes];
    
    // 10000 итераций для замедления brute-force
    for (var i = 0; i < 10000; i++) {
      data = sha256.convert(data).bytes;
    }
    
    return base64.encode(data);
  }

  /// Получить время до разблокировки (для UI)
  Duration? get timeUntilUnlock => _config.timeUntilUnlock;

  /// Получить количество оставшихся попыток до wipe
  int? get attemptsUntilWipe {
    if (!_config.isAutoWipeEnabled) return null;
    final remaining = _config.autoWipeAttempts - _config.failedAttempts;
    return remaining > 0 ? remaining : 0;
  }
}

