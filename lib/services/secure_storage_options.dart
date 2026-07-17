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

import 'package:orpheus_project/services/debug_logger_service.dart';

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
/// Ретраится и `null`: осечка Keystore может проявляться как "успешное" чтение
/// без данных (ложный null), а не только как исключение — цена лишь ~450мс на
/// первом запуске/после wipe, когда ключа действительно нет. При неустранимой
/// ошибке чтения — пробрасывает исключение, чтобы вызывающий не принял сбой
/// за пустоту. Гарантировать, что финальный `null` не ложный, невозможно —
/// поэтому безвозвратные действия по `null` дополнительно страхуются на месте
/// (см. `_deleteDbFilesIfAny` в DatabaseService: файл откладывается, не удаляется).
Future<String?> readSecureWithRetry(
  FlutterSecureStorage storage,
  String key, {
  int attempts = 3,
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final value = await storage.read(key: key);
      if (value != null || attempt >= attempts) {
        if (value != null && attempt > 1) {
          DebugLogger.warn('STORAGE',
              'Ключ "$key" прочитан с попытки $attempt (ложный null Keystore)');
        }
        return value;
      }
    } catch (_) {
      if (attempt >= attempts) rethrow;
    }
    await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
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
///
/// КРИТИЧНО: любой код, стирающий SharedPreferences (performWipe -> prefs.clear),
/// ОБЯЗАН восстановить флаг через [markSecureStorageMigrated] — иначе следующий
/// холодный старт выполнит deleteAll поверх заново созданного аккаунта. Именно
/// так 17.07.2026 за ночь «слетел» аккаунт: wipe 15.07 стёр флаг, аккаунт
/// восстановили в той же сессии, а первый же холодный старт молча снёс seed и
/// ключ БД. Каждая ветка логируется — молчаливый deleteAll стоил двух суток отладки.
Future<void> ensureSecureStorageMigrated() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_resetFlagKey) ?? false) {
      DebugLogger.info('STORAGE', 'Миграция v10: флаг на месте, сброс не требуется');
      return;
    }
    DebugLogger.warn(
        'STORAGE', 'Флаг миграции v10 отсутствует — одноразовый deleteAll secure storage');
    await appSecureStorage.deleteAll();
    await prefs.setBool(_resetFlagKey, true);
    DebugLogger.success('STORAGE', 'Secure storage сброшен, флаг миграции выставлен');
  } catch (e) {
    // best-effort: даже если сброс не удался, resetOnError:false не даст стереть
    // данные молча, а следующий запуск повторит попытку (флаг не выставлен).
    DebugLogger.error('STORAGE', 'Сбой миграции secure storage: $e');
  }
}

/// Выставить флаг миграции БЕЗ deleteAll.
///
/// Для мест, где хранилище заведомо уже в актуальном формате (PKCS1+AES/GCM) и
/// сбрасывать нечего: сразу после performWipe (deleteAll там уже выполнен, а
/// prefs.clear стёр флаг) и после записи свежего seed при создании/импорте
/// аккаунта. Best-effort: при сбое следующий холодный старт выполнит deleteAll
/// по пустому/свежему хранилищу — это потеря аккаунта, поэтому сбой логируется.
Future<void> markSecureStorageMigrated() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_resetFlagKey, true);
  } catch (e) {
    DebugLogger.error('STORAGE', 'Не удалось выставить флаг миграции: $e');
  }
}
