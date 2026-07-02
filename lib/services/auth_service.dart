// lib/services/auth_service.dart
// Сервис авторизации: PIN-код, duress code, блокировка

import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as kdf;
import 'package:flutter/foundation.dart' show kDebugMode;
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

  /// Полная очистка secure storage (для исчерпывающего panic-wipe — аудит SEC-5).
  Future<void> deleteAll();
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

  @override
  Future<void> deleteAll() => _inner.deleteAll();
}

class AuthService {
  static final AuthService instance = AuthService._();

  /// Callback for notifying _AppState that wipe completed.
  /// Set by _AppState.initState() to reset navigation state.
  static VoidCallback? onWipeCompleted;

  /// Вызывается в САМОМ начале wipe (до удаления данных), чтобы _AppState мог
  /// остановить сетевой конвейер (websocket): иначе входящее сообщение может
  /// пересоздать БД + ключ во время очистки, а сокет остаться подключённым под
  /// стёртой личностью.
  static VoidCallback? onWipeStarted;

  /// Создать отдельный экземпляр (в тестах), чтобы не трогать singleton и не зависеть от плагинов.
  ///
  /// [fastHash] — использовать быстрый синхронный хэш вместо Argon2id. Нужен
  /// ТОЛЬКО виджет-тестам: реальный Argon2id async не завершается под fake-clock
  /// `WidgetTester.pump`. Прод и обычные (await) тесты используют Argon2id.
  static AuthService createForTesting({
    required AuthSecureStorage secureStorage,
    DateTime Function()? now,
    bool fastHash = false,
  }) {
    return AuthService._(
        secureStorage: secureStorage, now: now, fastHashForTesting: fastHash);
  }

  AuthService._({
    AuthSecureStorage? secureStorage,
    DateTime Function()? now,
    bool fastHashForTesting = false,
  })  : _secureStorage =
            secureStorage ?? FlutterAuthSecureStorage(const FlutterSecureStorage()),
        _now = now ?? DateTime.now,
        // Сим fastHash действует ТОЛЬКО в debug (тесты): в release всегда Argon2id,
        // даже если кто-то по ошибке создаст сервис через createForTesting.
        _fastHashForTesting = fastHashForTesting && kDebugMode;

  final AuthSecureStorage _secureStorage;
  final DateTime Function() _now;
  final bool _fastHashForTesting;
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
    final hash = await _computeHash(pin, salt);

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
    final result = await verifyPin(currentPin);
    if (result != PinVerifyResult.success) {
      return false;
    }
    
    // Сохраняем текущую длину PIN при изменении
    await setPin(newPin, pinLength: _config.pinLength);
    return true;
  }

  /// Отключить PIN-код (требует текущий PIN)
  Future<bool> disablePin(String currentPin) async {
    final result = await verifyPin(currentPin);
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
  Future<PinVerifyResult> verifyPin(String pin) async {
    if (!_config.isPinEnabled || _config.pinHash == null) {
      _isUnlocked = true;
      return PinVerifyResult.success;
    }

    // Проверка блокировки
    if (_config.isLockedOut) {
      DebugLogger.warn('AUTH', 'Login attempt during lockout');
      return PinVerifyResult.lockedOut;
    }

    // Проверка основного PIN
    if (await _verifyHash(pin, _config.pinSalt!, _config.pinHash!)) {
      await _resetFailedAttempts();
      _isUnlocked = true;
      _isDuressMode = false;
      // legacy → Argon2id при первом входе
      await _maybeUpgradeLegacyHash(pin, _config.pinSalt, _config.pinHash,
          (h) => _config.copyWith(pinHash: h));
      DebugLogger.info('AUTH', 'PIN correct, unlocked');
      return PinVerifyResult.success;
    }

    // Проверка кода удаления (wipe code)
    // ВАЖНО: возвращаем wipeCode без инкремента попыток — это сознательное действие.
    if (_config.isWipeCodeEnabled && _config.wipeCodeHash != null && _config.wipeCodeSalt != null) {
      if (await _verifyHash(pin, _config.wipeCodeSalt!, _config.wipeCodeHash!)) {
        await _resetFailedAttempts();
        DebugLogger.warn('AUTH', 'Wipe code entered — confirmation required');
        return PinVerifyResult.wipeCode;
      }
    }

    // Проверка duress кода
    if (_config.isDuressEnabled && _config.duressHash != null && _config.duressSalt != null) {
      if (await _verifyHash(pin, _config.duressSalt!, _config.duressHash!)) {
        await _resetFailedAttempts();
        _isUnlocked = true;
        _isDuressMode = true;
        await _maybeUpgradeLegacyHash(pin, _config.duressSalt, _config.duressHash,
            (h) => _config.copyWith(duressHash: h));
        DebugLogger.warn('AUTH', 'Duress code entered, empty profile activated');
        return PinVerifyResult.duress;
      }
    }

    // Неверный PIN
    // Счётчик попыток пишем durable ДО реакции UI, иначе force-kill сбрасывает
    // прогресс блокировки/авто-wipe (аудит LOGIC-5).
    await _incrementFailedAttempts();

    // Проверка автоматического wipe
    if (_config.shouldAutoWipe) {
      DebugLogger.warn('AUTH', 'Attempt limit exceeded, auto-wipe required');
      return PinVerifyResult.autoWipe;
    }

    return PinVerifyResult.invalid;
  }

  /// Апгрейд legacy SHA-256 хэша в Argon2id при первом удачном вводе кода —
  /// чтобы старые PIN/коды принуждения не оставались слабо захэшированными
  /// (аудит SEC-8). [code] — введённый (правильный) код, [apply] проставляет
  /// новый Argon2id-хэш в конфиг.
  Future<void> _maybeUpgradeLegacyHash(String code, String? salt,
      String? stored, SecurityConfig Function(String newHash) apply) async {
    if (_fastHashForTesting) return; // в тестах хэш и так legacy — не переписываем
    if (stored == null || salt == null || stored.startsWith(_argon2Prefix)) {
      return;
    }
    try {
      final upgraded = await _computeHash(code, salt);
      _config = apply(upgraded);
      await _saveConfig();
      DebugLogger.info('AUTH', 'Legacy hash upgraded to Argon2id');
    } catch (_) {
      // Апгрейд не критичен: при неудаче код продолжит работать по legacy-пути.
    }
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
    if (_config.pinHash == null || _config.pinSalt == null) return false;
    if (!await _verifyHash(mainPin, _config.pinSalt!, _config.pinHash!)) {
      return false;
    }

    // Duress код не должен совпадать с основным PIN
    if (mainPin == duressCode) {
      return false;
    }

    final salt = _generateSalt();
    final duressHash = await _computeHash(duressCode, salt);
    
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
    if (_config.pinHash == null || _config.pinSalt == null) return false;
    if (!await _verifyHash(mainPin, _config.pinSalt!, _config.pinHash!)) {
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

    if (!await _verifyHash(mainPin, _config.pinSalt!, _config.pinHash!)) return false;

    // Код удаления не должен совпадать с основным PIN
    if (wipeCode == mainPin) return false;

    final salt = _generateSalt();
    final wipeHash = await _computeHash(wipeCode, salt);

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

    if (!await _verifyHash(mainPin, _config.pinSalt!, _config.pinHash!)) return false;

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

  // === БИОМЕТРИЯ (вход по отпечатку/лицу) ===

  Future<void> setBiometricEnabled(bool enabled) async {
    _config = _config.copyWith(isBiometricEnabled: enabled);
    await _saveConfig();
    print("AUTH: Biometric ${enabled ? 'enabled' : 'disabled'}");
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
    final result = await verifyPin(mainPin);
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

  /// Полный wipe — удаление всех данных.
  ///
  /// Best-effort: каждый шаг в своём try/catch, чтобы сбой одного не отменял
  /// остальные (аудит LOGIC-7). Secure storage чистится ПОЛНОСТЬЮ (`deleteAll`),
  /// а не по списку ключей, чтобы не оставить desktop-link сессию, ключ БД и
  /// любые будущие ключи (аудит SEC-5). Состояние и `onWipeCompleted`
  /// сбрасываются всегда, даже при частичных ошибках.
  Future<void> performWipe() async {
    DebugLogger.warn('AUTH', 'Performing full wipe');
    // Останавливаем сеть ДО деструктивных шагов (см. onWipeStarted).
    onWipeStarted?.call();
    final errors = <String>[];

    // 1. Криптоключи — на ЖИВОМ синглтоне, чтобы очистились и ключи в памяти,
    //    и reconnect не поднялся под стёртой личностью (publicKeyBase64 → null).
    try {
      await CryptoService.instance.deleteAccount();
    } catch (e) {
      errors.add('crypto: $e');
    }

    // 2. База данных (в т.ч. удаляет ключ шифрования БД)
    try {
      await DatabaseService.instance.deleteDatabaseFile();
    } catch (e) {
      errors.add('db: $e');
    }

    // 3. ВСЁ secure storage: крипто-ключи, security-config, desktop-link сессия,
    //    ключ БД и любые будущие ключи — исчерпывающе (аудит SEC-5).
    try {
      await _secureStorage.deleteAll();
    } catch (e) {
      errors.add('secure_storage: $e');
    }

    // 4. Локальные настройки
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      errors.add('prefs: $e');
    }

    // 5. Сброс состояния (всегда)
    _config = SecurityConfig.empty;
    _isUnlocked = false;
    _isDuressMode = false;

    // 6. Всегда уведомляем UI (даже при частичных ошибках), чтобы навигация
    //    сбросилась и не осталась на «полу-стёртом» состоянии (аудит LOGIC-7).
    onWipeCompleted?.call();

    if (errors.isEmpty) {
      DebugLogger.success('AUTH', 'Wipe completed');
    } else {
      DebugLogger.error('AUTH', 'Wipe finished with errors: ${errors.join('; ')}');
    }
  }

  // === УТИЛИТЫ ===

  /// Генерация случайной соли
  String _generateSalt() {
    final random = Random.secure();
    final saltBytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64.encode(saltBytes);
  }

  /// Параметры Argon2id для хэширования PIN/кодов (memory-hard — аудит SEC-8).
  /// `memory` — число 1 КБ-блоков (≈19 МБ) = минимум OWASP (m=19456, t=2, p=1).
  /// Для 4–6-значного PIN вся стойкость к перебору украденного конфига держится
  /// на цене KDF, поэтому берём рекомендованный минимум. Значения — тюнингуемы:
  /// при заметной задержке разблокировки на слабом устройстве уменьшить memory
  /// или нарастить iterations (замерять на реальном железе).
  static final kdf.Argon2id _argon2id = kdf.Argon2id(
    parallelism: 1,
    memory: 19456,
    iterations: 2,
    hashLength: 32,
  );

  /// Префикс-тег нового формата хэша. Legacy-хэши (10000×SHA-256) его не имеют,
  /// по этому и различаем формат при проверке.
  static const String _argon2Prefix = 'argon2id\$';

  /// Хэширует PIN/код через Argon2id. Соль — base64 (как и раньше).
  Future<String> _computeHash(String pin, String salt) async {
    // Тест-режим: быстрый синхронный хэш (untagged) — verify пойдёт по legacy-пути.
    if (_fastHashForTesting) return _hashPinLegacy(pin, salt);
    final key = await _argon2id.deriveKey(
      secretKey: kdf.SecretKey(utf8.encode(pin)),
      nonce: base64.decode(salt),
    );
    final bytes = await key.extractBytes();
    return '$_argon2Prefix${base64.encode(bytes)}';
  }

  /// Проверяет PIN/код против сохранённого хэша, поддерживая ОБА формата:
  /// новый Argon2id и legacy SHA-256 — иначе PIN, заданные до обновления,
  /// заблокировались бы (аудит SEC-8).
  Future<bool> _verifyHash(String pin, String salt, String storedHash) async {
    if (storedHash.startsWith(_argon2Prefix)) {
      final computed = await _computeHash(pin, salt);
      return computed == storedHash;
    }
    return _hashPinLegacy(pin, salt) == storedHash;
  }

  /// LEGACY-хэш (10000×SHA-256). Оставлен ТОЛЬКО для проверки PIN/кодов,
  /// заданных до перехода на Argon2id; все новые хэши считаются через
  /// [_computeHash] и при первой удачной проверке апгрейдятся (см. verifyPin).
  String _hashPinLegacy(String pin, String salt) {
    final saltBytes = base64.decode(salt);
    var data = [...saltBytes, ...utf8.encode(pin), ...saltBytes];
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

