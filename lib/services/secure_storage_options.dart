// lib/services/secure_storage_options.dart
//
// ЕДИНЫЙ источник опций flutter_secure_storage для ВСЕХ мест, где создаётся
// FlutterSecureStorage (CryptoService, AuthService, DatabaseService).
// КРИТИЧНО: опции идентичны везде — иначе часть секретов (X25519-ключи,
// хэши PIN/duress/wipe, ключ шифрования БД) станет нечитаемой.
//
// Апгрейд 9 -> 10: используем СОВРЕМЕННЫЕ шифры v10 по умолчанию
// (RSA/ECB/OAEP для ключа + AES/GCM для данных) — не deprecated, живут в v11.
//
// Данные v9 писались старыми шифрами (PKCS1 + CBC). Авто-миграцию v10 НЕ
// используем: она ненадёжна (может крашить/частично стирать — issues
// juliansteenbakker/flutter_secure_storage #1043, #1079). Вместо неё —
// детерминированный одноразовый `deleteAll()` ДО первого чтения
// (см. ensureSecureStorageMigrated). Данные v9 осознанно приносятся в жертву:
// существующие пользователи создают аккаунт заново (приложение в закрытой бете).
//
// resetOnError: false — не стираем аккаунт на транзиентной ошибке чтения
// (после сброса всё в новом формате, мигрировать нечего).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android-опции: современные шифры v10 (дефолт — OAEP + GCM), без авто-wipe и
/// без авто-миграции (старых данных после сброса не остаётся).
const AndroidOptions kAndroidSecureStorageOptions = AndroidOptions(
  resetOnError: false,
  migrateOnAlgorithmChange: false,
);

/// Единый экземпляр FlutterSecureStorage. Использовать ВЕЗДЕ вместо
/// `const FlutterSecureStorage()`.
const FlutterSecureStorage appSecureStorage =
    FlutterSecureStorage(aOptions: kAndroidSecureStorageOptions);

const String _resetFlagKey = 'secure_storage_v10_reset_done';

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
