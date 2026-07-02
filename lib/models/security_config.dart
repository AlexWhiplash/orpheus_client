// lib/models/security_config.dart
// Модель конфигурации безопасности приложения

import 'package:orpheus_project/models/message_retention_policy.dart';

/// Конфигурация безопасности приложения
class SecurityConfig {
  /// Включена ли защита PIN-кодом
  final bool isPinEnabled;
  
  /// Длина PIN-кода (4 или 6 цифр). Default = 6 для обратной совместимости.
  final int pinLength;
  
  /// Хеш основного PIN-кода (Argon2id hash)
  final String? pinHash;
  
  /// Соль для хеширования PIN
  final String? pinSalt;
  
  /// Включен ли код принуждения (duress code)
  final bool isDuressEnabled;
  
  /// Хеш кода принуждения
  final String? duressHash;
  
  /// Соль для хеширования duress кода
  final String? duressSalt;
  
  /// Количество неудачных попыток ввода PIN
  final int failedAttempts;
  
  /// Время последней неудачной попытки (wall-clock; для отображения/fallback)
  final DateTime? lastFailedAttempt;

  /// Монотонное время (elapsedRealtime, мс с загрузки) последней неудачной
  /// попытки — тамперо-устойчивый источник для блокировки (аудит LOGIC-6).
  final int? lastFailedElapsedMs;

  /// Включена ли биометрия
  final bool isBiometricEnabled;
  
  /// Включён ли отдельный код удаления (panic wipe code)
  final bool isWipeCodeEnabled;

  /// Хеш кода удаления
  final String? wipeCodeHash;

  /// Соль для хеширования кода удаления
  final String? wipeCodeSalt;

  /// Включен ли автоматический wipe после N неудачных попыток
  final bool isAutoWipeEnabled;
  
  /// Количество попыток до автоматического wipe
  final int autoWipeAttempts;

  /// Включён ли жест экстренного удаления (3 быстрых ухода приложения в фон)
  /// ВАЖНО: это приближение, а не “перехват кнопки питания”.
  final bool isPanicGestureEnabled;

  /// Таймаут блокировки при неактивности (в секундах).
  /// 0 или меньше — отключено.
  final int inactivityLockSeconds;

  /// Политика автоудаления сообщений по времени
  final MessageRetentionPolicy messageRetention;
  
  /// Время последней очистки сообщений (для оптимизации — не чистить слишком часто)
  final DateTime? lastMessageCleanupAt;

  const SecurityConfig({
    this.isPinEnabled = false,
    this.pinLength = 6,
    this.pinHash,
    this.pinSalt,
    this.isDuressEnabled = false,
    this.duressHash,
    this.duressSalt,
    this.failedAttempts = 0,
    this.lastFailedAttempt,
    this.lastFailedElapsedMs,
    this.isBiometricEnabled = false,
    this.isWipeCodeEnabled = false,
    this.wipeCodeHash,
    this.wipeCodeSalt,
    this.isAutoWipeEnabled = false,
    this.autoWipeAttempts = 10,
    this.isPanicGestureEnabled = false,
    this.inactivityLockSeconds = 60,
    this.messageRetention = MessageRetentionPolicy.all,
    this.lastMessageCleanupAt,
  });

  /// Пустая конфигурация (без защиты)
  static const empty = SecurityConfig();

  /// Создать копию с изменёнными полями
  SecurityConfig copyWith({
    bool? isPinEnabled,
    int? pinLength,
    String? pinHash,
    String? pinSalt,
    bool? isDuressEnabled,
    String? duressHash,
    String? duressSalt,
    int? failedAttempts,
    DateTime? lastFailedAttempt,
    int? lastFailedElapsedMs,
    bool? isBiometricEnabled,
    bool? isWipeCodeEnabled,
    String? wipeCodeHash,
    String? wipeCodeSalt,
    bool? isAutoWipeEnabled,
    int? autoWipeAttempts,
    bool? isPanicGestureEnabled,
    int? inactivityLockSeconds,
    MessageRetentionPolicy? messageRetention,
    DateTime? lastMessageCleanupAt,
    bool clearPinHash = false,
    bool clearDuressHash = false,
    bool clearWipeCodeHash = false,
    bool clearLastFailedAttempt = false,
    bool clearLastMessageCleanupAt = false,
  }) {
    return SecurityConfig(
      isPinEnabled: isPinEnabled ?? this.isPinEnabled,
      pinLength: clearPinHash ? 6 : (pinLength ?? this.pinLength),
      pinHash: clearPinHash ? null : (pinHash ?? this.pinHash),
      pinSalt: clearPinHash ? null : (pinSalt ?? this.pinSalt),
      isDuressEnabled: isDuressEnabled ?? this.isDuressEnabled,
      duressHash: clearDuressHash ? null : (duressHash ?? this.duressHash),
      duressSalt: clearDuressHash ? null : (duressSalt ?? this.duressSalt),
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lastFailedAttempt: clearLastFailedAttempt ? null : (lastFailedAttempt ?? this.lastFailedAttempt),
      lastFailedElapsedMs: clearLastFailedAttempt ? null : (lastFailedElapsedMs ?? this.lastFailedElapsedMs),
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      isWipeCodeEnabled: isWipeCodeEnabled ?? this.isWipeCodeEnabled,
      wipeCodeHash: clearWipeCodeHash ? null : (wipeCodeHash ?? this.wipeCodeHash),
      wipeCodeSalt: clearWipeCodeHash ? null : (wipeCodeSalt ?? this.wipeCodeSalt),
      isAutoWipeEnabled: isAutoWipeEnabled ?? this.isAutoWipeEnabled,
      autoWipeAttempts: autoWipeAttempts ?? this.autoWipeAttempts,
      isPanicGestureEnabled: isPanicGestureEnabled ?? this.isPanicGestureEnabled,
      inactivityLockSeconds: inactivityLockSeconds ?? this.inactivityLockSeconds,
      messageRetention: messageRetention ?? this.messageRetention,
      lastMessageCleanupAt: clearLastMessageCleanupAt ? null : (lastMessageCleanupAt ?? this.lastMessageCleanupAt),
    );
  }

  /// Сериализация в Map для хранения
  Map<String, dynamic> toMap() {
    return {
      'isPinEnabled': isPinEnabled,
      'pinLength': pinLength,
      'pinHash': pinHash,
      'pinSalt': pinSalt,
      'isDuressEnabled': isDuressEnabled,
      'duressHash': duressHash,
      'duressSalt': duressSalt,
      'failedAttempts': failedAttempts,
      'lastFailedAttempt': lastFailedAttempt?.toIso8601String(),
      'lastFailedElapsedMs': lastFailedElapsedMs,
      'isBiometricEnabled': isBiometricEnabled,
      'isWipeCodeEnabled': isWipeCodeEnabled,
      'wipeCodeHash': wipeCodeHash,
      'wipeCodeSalt': wipeCodeSalt,
      'isAutoWipeEnabled': isAutoWipeEnabled,
      'autoWipeAttempts': autoWipeAttempts,
      'isPanicGestureEnabled': isPanicGestureEnabled,
      'inactivityLockSeconds': inactivityLockSeconds,
      'messageRetention': messageRetention.configValue,
      'lastMessageCleanupAt': lastMessageCleanupAt?.toIso8601String(),
    };
  }

  /// Десериализация из Map
  factory SecurityConfig.fromMap(Map<String, dynamic> map) {
    return SecurityConfig(
      isPinEnabled: map['isPinEnabled'] ?? false,
      // Default = 6 для обратной совместимости со старыми конфигурациями
      pinLength: map['pinLength'] ?? 6,
      pinHash: map['pinHash'],
      pinSalt: map['pinSalt'],
      isDuressEnabled: map['isDuressEnabled'] ?? false,
      duressHash: map['duressHash'],
      duressSalt: map['duressSalt'],
      failedAttempts: map['failedAttempts'] ?? 0,
      lastFailedAttempt: map['lastFailedAttempt'] != null
          ? DateTime.tryParse(map['lastFailedAttempt'])
          : null,
      lastFailedElapsedMs: map['lastFailedElapsedMs'] as int?,
      isBiometricEnabled: map['isBiometricEnabled'] ?? false,
      isWipeCodeEnabled: map['isWipeCodeEnabled'] ?? false,
      wipeCodeHash: map['wipeCodeHash'],
      wipeCodeSalt: map['wipeCodeSalt'],
      isAutoWipeEnabled: map['isAutoWipeEnabled'] ?? false,
      autoWipeAttempts: map['autoWipeAttempts'] ?? 10,
      isPanicGestureEnabled: map['isPanicGestureEnabled'] ?? false,
      inactivityLockSeconds: map['inactivityLockSeconds'] ?? 60,
      messageRetention: MessageRetentionPolicyExtension.fromConfigValue(map['messageRetention']),
      lastMessageCleanupAt: map['lastMessageCleanupAt'] != null 
          ? DateTime.tryParse(map['lastMessageCleanupAt']) 
          : null,
    );
  }

  /// Проверить, нужно ли показывать экран блокировки
  bool get requiresUnlock => isPinEnabled && pinHash != null;

  /// Проверить, заблокирован ли вход из-за превышения попыток
  bool get isLockedOut {
    if (lastFailedAttempt == null) return false;
    
    // Прогрессивная блокировка
    final lockDuration = _getLockDuration(failedAttempts);
    if (lockDuration == null) return false;
    
    final unlockTime = lastFailedAttempt!.add(lockDuration);
    return DateTime.now().isBefore(unlockTime);
  }

  /// Тамперо-устойчивая проверка блокировки (аудит LOGIC-6).
  ///
  /// Считает по МОНОТОННЫМ часам ([nowElapsedMs] = elapsedRealtime), которые
  /// нельзя сдвинуть сменой системного времени — поэтому блокировку нельзя
  /// «промотать», переведя часы вперёд. Если монотонная база недоступна
  /// ([nowElapsedMs] == null или после ребута, когда elapsedRealtime сбросился и
  /// стал меньше сохранённого) — откат на wall-clock [isLockedOut], т.е. поведение
  /// не хуже прежнего.
  bool isLockedOutMonotonic(int? nowElapsedMs) {
    if (lastFailedAttempt == null) return false;
    final lockDuration = _getLockDuration(failedAttempts);
    if (lockDuration == null) return false;

    if (nowElapsedMs != null &&
        lastFailedElapsedMs != null &&
        nowElapsedMs >= lastFailedElapsedMs!) {
      final elapsed = nowElapsedMs - lastFailedElapsedMs!;
      return elapsed < lockDuration.inMilliseconds;
    }
    // Нет монотонной базы / ребут → wall-clock fallback.
    return isLockedOut;
  }

  /// Получить время до разблокировки
  Duration? get timeUntilUnlock {
    if (!isLockedOut || lastFailedAttempt == null) return null;
    
    final lockDuration = _getLockDuration(failedAttempts);
    if (lockDuration == null) return null;
    
    final unlockTime = lastFailedAttempt!.add(lockDuration);
    final remaining = unlockTime.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  /// Получить длительность блокировки в зависимости от количества попыток
  Duration? _getLockDuration(int attempts) {
    // Контракт из ADR 0003:
    // 5 попыток  → 30 сек
    // 10 попыток → 1 мин
    // 15 попыток → 5 мин
    // 20 попыток → 30 мин
    //
    // Между порогами действует “последняя достигнутая ступень”.
    if (attempts < 5) return null;
    if (attempts < 10) return const Duration(seconds: 30);
    if (attempts < 15) return const Duration(minutes: 1);
    if (attempts < 20) return const Duration(minutes: 5);
    return const Duration(minutes: 30);
  }

  /// Проверить, нужен ли автоматический wipe
  bool get shouldAutoWipe => isAutoWipeEnabled && failedAttempts >= autoWipeAttempts;

  @override
  String toString() {
    return 'SecurityConfig(pin: $isPinEnabled, pinLength: $pinLength, duress: $isDuressEnabled, wipeCode: $isWipeCodeEnabled, bio: $isBiometricEnabled, panicGesture: $isPanicGestureEnabled, attempts: $failedAttempts, retention: $messageRetention)';
  }
}

/// Результат проверки PIN
enum PinVerifyResult {
  /// Успешная проверка основного PIN
  success,
  
  /// Успешная проверка duress кода — показать пустой профиль
  duress,

  /// Введён код удаления — требуется подтверждение wipe
  wipeCode,
  
  /// Неверный PIN
  invalid,
  
  /// Временная блокировка из-за превышения попыток
  lockedOut,
  
  /// Требуется автоматический wipe
  autoWipe,
}

