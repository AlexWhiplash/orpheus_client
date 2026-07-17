// lib/services/secure_storage_options.dart
//
// ЕДИНЫЙ источник опций flutter_secure_storage для ВСЕХ мест, где создаётся
// FlutterSecureStorage (CryptoService, AuthService, DatabaseService).
// КРИТИЧНО: опции идентичны везде — иначе часть секретов (X25519-ключи,
// хэши PIN/duress/wipe, ключ шифрования БД) станет нечитаемой.
//
// Апгрейд 9 -> 10 + фикс потери данных на рестарте: key-шифр PKCS1 (см. подробный
// разбор бага OAEP/MGF1 у kAndroidSecureStorageOptions ниже) + AES/GCM для данных.
// Дефолтный OAEP v10 теряет доступ к данным после перезапуска на строгом KeyMint
// (Pixel/Samsung) — подтверждено на устройстве device-тестом.
//
// Авто-миграцию v10 НЕ используем (ненадёжна — issues juliansteenbakker/
// flutter_secure_storage #1043, #1079). Вместо неё — детерминированный одноразовый
// `deleteAll()` ДО первого чтения (см. ensureSecureStorageMigrated), флаг бампается
// при смене шифра. Старые данные осознанно приносятся в жертву: пользователи создают
// аккаунт заново (закрытая бета).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android-опции secure storage.
///
/// key-шифр: PKCS1 вместо дефолтного v10 OAEP. Дефолт
/// `RSA_ECB_OAEPwithSHA_256andMGF1Padding` генерит RSA-ключ, авторизованный ТОЛЬКО
/// на digest SHA-256, но расшифровывает с MGF1=SHA-1. Строгий KeyMint (Pixel
/// Titan M2, Samsung Knox и др.) отклоняет unwrap ПРИВАТНЫМ ключом на новом
/// процессе (`INCOMPATIBLE_MGF_DIGEST` → "decryption failed"), тогда как запись
/// ПУБЛИЧНЫМ ключом идёт софтверно и проходит. Итог: данные пишутся, но не читаются
/// после перезапуска → аккаунт слетал каждый рестарт (баг подтверждён на устройстве,
/// не GrapheneOS-специфика). PKCS1 не использует MGF1/OAEP-параметры и багом не задет,
/// и он ТИХИЙ (без biometric-prompt) — критично для чтения ключа БД из push-изолята
/// при заблокированном экране. Для ЛОКАЛЬНОГО key-wrapping padding-oracle не применим
/// (приватный ключ невыгружаем из Keystore, оракула расшифровки нет).
const AndroidOptions kAndroidSecureStorageOptions = AndroidOptions(
  keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
  storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  // Пинуем алгоритм: не даём плагину авто-мигрировать PKCS1 -> OAEP (вернуло бы баг).
  migrateOnAlgorithmChange: false,
  // НЕ включать resetOnError. С ним ОДНА ошибка чтения (в т.ч. разовая осечка
  // Keystore) молча стирает ВСЁ хранилище и возвращает null — а null неотличим от
  // "ключа нет". Итог, подтверждённый на Samsung: после рестарта root seed читается
  // как отсутствующий -> экран приветствия поверх живого аккаунта, ключ БД пропадает
  // -> генерируется новый -> база не открывается. Пусть ошибка чтения будет ошибкой:
  // её ретраит вызывающий (см. readWithRetry), а не маскирует уничтожением данных.
  resetOnError: false,
);

/// Чтение secure storage с ретраями.
///
/// Осечка Keystore на строгом KeyMint (Samsung Knox, Pixel Titan M2) — разовая и
/// лечится повтором. Без ретрая любой сбой означает "данных нет", а это худший из
/// возможных ответов: приложение предложит создать аккаунт поверх существующего.
/// Возвращает `null` ТОЛЬКО если ключа действительно нет; при неустранимой ошибке
/// чтения — пробрасывает исключение, чтобы вызывающий не принял сбой за пустоту.
Future<String?> readSecureWithRetry(
  FlutterSecureStorage storage,
  String key, {
  int attempts = 3,
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await storage.read(key: key);
    } catch (_) {
      if (attempt >= attempts) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
    }
  }
}

/// Единый экземпляр FlutterSecureStorage. Использовать ВЕЗДЕ вместо
/// `const FlutterSecureStorage()`.
const FlutterSecureStorage appSecureStorage =
    FlutterSecureStorage(aOptions: kAndroidSecureStorageOptions);

// Флаг бампнут при смене key-шифра OAEP -> PKCS1: нужен новый одноразовый
// deleteAll, чтобы стереть старые нечитаемые OAEP-данные под новый шифр.
const String _resetFlagKey = 'secure_storage_reset_v10_pkcs1';

/// Одноразовый чистый сброс secure storage при переходе на v10.
///
/// Вызывать ОДИН РАЗ на старте приложения, ДО первого чтения ключей
/// (до CryptoService/AuthService/DatabaseService). Идемпотентно: реальный
/// `deleteAll` выполняется только на первом запуске после апгрейда (флаг в
/// SharedPreferences), дальше — no-op. `deleteAll` не расшифровывает данные,
/// поэтому старый формат v9 стирается без риска краша авто-миграции.
Future<void> ensureSecureStorageMigrated() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_resetFlagKey) ?? false) return;
    await appSecureStorage.deleteAll();
    await prefs.setBool(_resetFlagKey, true);
  } catch (_) {
    // best-effort: даже если сброс не удался, resetOnError:false не даст стереть
    // данные молча, а следующий запуск повторит попытку (флаг не выставлен).
  }
}
