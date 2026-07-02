// lib/services/secure_storage_options.dart
//
// ЕДИНЫЙ источник опций flutter_secure_storage для ВСЕХ мест, где создаётся
// FlutterSecureStorage (CryptoService, AuthService, DatabaseService).
// КРИТИЧНО: опции должны быть идентичны везде — иначе часть секретов (X25519-ключи,
// хэши PIN/duress/wipe, ключ шифрования БД) станет нечитаемой у части кода.
//
// Апгрейд 9 -> 10: v10 сменил ДЕФОЛТНЫЕ Android-шифры (ключ: RSA PKCS1 -> OAEP,
// данные: AES-CBC -> AES-GCM) и по умолчанию при сбое авто-миграции БЕЗВОЗВРАТНО
// стирает хранилище (`resetOnError: true` + `migrateWithBackup: false`).
// Для приложения с НЕвосстановимыми ключами (изъять их заново неоткуда) это
// задокументированная потеря данных у существующих пользователей
// (juliansteenbakker/flutter_secure_storage issues #1043, #1079).
//
// Поэтому здесь — БЕЗОПАСНЫЙ МОСТ: остаёмся на «старых» шифрах v9 (PKCS1 + CBC),
// значит алгоритм не меняется и миграция не запускается; и отключаем авто-wipe.
// Существующие данные читаются как есть, риск потери — нулевой.
//
// ВАЖНО: это ВРЕМЕННЫЙ мост. Старые шифры помечены @Deprecated в v10 и удалены
// в v11. Полноценный переход на новые шифры делать ТОЛЬКО после того, как в
// приложении появится экспорт/импорт ключа (чтобы сбой миграции был переживаем),
// затем с `migrateOnAlgorithmChange: true` + `migrateWithBackup: true` +
// `resetOnError: false`. См. девайс-чеклист в docs/.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android-опции: точное совпадение с тем, что записал v9 (никакой миграции),
/// авто-wipe при ошибке ОТКЛЮЧЁН.
const AndroidOptions kAndroidSecureStorageOptions = AndroidOptions(
  keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
  storageCipherAlgorithm: StorageCipherAlgorithm.AES_CBC_PKCS7Padding,
  migrateOnAlgorithmChange: false,
  resetOnError: false,
);

/// Единый экземпляр FlutterSecureStorage. Использовать ВЕЗДЕ вместо
/// `const FlutterSecureStorage()`.
const FlutterSecureStorage appSecureStorage =
    FlutterSecureStorage(aOptions: kAndroidSecureStorageOptions);
