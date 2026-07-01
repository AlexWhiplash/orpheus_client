# AI Worklog

Журнал действий по изолированному треку `wl/dev` (независимая версия клиента,
работаем на актуальном Flutter; upstream `master` не трогаем).

---

## 2026-07-01 — Bootstrap среды и guardrails (Фаза 0–1)

**Задача:** поднять рабочую среду для нового участника, собрать/запустить клиент,
поставить guardrails против поломок. Трек изолированный (ветка `wl/dev`).

**Сделано:**
- Установлен Flutter 3.44.4 (stable), связан с Android SDK (Android Studio уже стоял).
- Проект собран (`app-debug.apk`) и запущен на эмуляторе — полная инициализация без
  ошибок (Firebase, FCM, крипто, сеть, CallKit).
- Решение по стеку: работаем на **актуальном** Flutter, код патчим под него.

**Изменения кода/конфига:**
- `android/gradle.properties` — удалён машинно-специфичный `org.gradle.java.home`
  (был жёстко прописан путь другого разработчика → сборка падала на других машинах).
- `lib/theme/app_theme.dart` — добавлен импорт `package:flutter/cupertino.dart`
  (`CupertinoPageTransitionsBuilder` перестал реэкспортироваться из `material` в
  новом Flutter). Это была единственная ошибка компиляции (`flutter analyze` → 0 errors).
- `.github/workflows/ci.yml` — CI: `flutter analyze` (гейт на ошибки) + `flutter test`.

**Статус тестов:** 303 passed / 20 failed. Падения — version-skew на Flutter 3.44
(локаль EN vs RU в тестах уведомлений; семантика поиска виджетов; fallback update_service).
Помечены как следующая задача; в CI `flutter test` пока не блокирующий.

**Команды:** `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d emulator-5554`.

---

## 2026-07-01 — Зелёные тесты: разбор 20 падений (Фаза 2)

**Задача:** довести тест-сьют до зелёного на Flutter 3.44. Было 303 passed / 20 failed
(version-skew, помеченный ранее как следующая задача).

**Диагностика (мульти-агентный разбор по каждому падению):** причины оказались смешанными —
не единый version-skew:
- устаревшие RU-литералы в ассертах после миграции на gen-l10n (`СКАНИРОВАНИЕ QR` → фактически
  `СКАНИРОВАТЬ QR-КОД`; `Неверный PIN-код` → `Неверный PIN`; неразрывный дефис U+2011 в `PIN‑код`);
- забытая локаль в `pumpWidget` (contacts, диалог обновления) → `L10n.of(context)!` кидал null-check;
- строки, захардкоженные по-английски (уведомления, панель звонка, заголовок «История обновлений»);
- диалоги, читавшие язык из глобального синглтона `LocaleService` вместо виджет-дерева;
- реальный дефект каркаса Flutter 3.44 (ListTile без Material-предка) на экране настроек;
- самопротиворечивый тест `getWithFallback` (писан под 2 хоста, а остался один).

**Изменения кода:**
- `lib/services/notification_service.dart` — ВСЕ строки уведомлений двуязычные через gen-l10n
  (звонок, сообщение, чат-сообщение, официальный ответ, тестовое, дефолтное имя, а также CallKit:
  Ответить/Отклонить/Пропущенный/Перезвонить и fallback-уведомление звонка). Фоновый FCM-изолят
  без контекста → добавлен хелпер `notificationL10n()`: резолвит язык по сохранённому `app_locale`
  → системная локаль → `en`, затем `lookupL10n(Locale)`. RU-юзер получает RU, EN — EN.
  (Системные названия Android-каналов не трогаем — регистрируются один раз.)
- `lib/widgets/call/control_panel.dart` — подписи кнопок звонка через `L10n.of(context)`
  (`decline`/`answerCall`/`microphone`/`speaker`/`endCall`).
- `lib/l10n/app_{en,ru}.arb` — добавлены ключи `answerCall`, `microphone`, `newMessage`,
  `unknownCaller` (обе локали); перегенерён `app_localizations*.dart`.
- `lib/updates_screen.dart` — заголовок через `L10n.of(context).updateHistory.toUpperCase()`
  (переиспользован существующий ключ; EN-визуал сохранён).
- `lib/screens/settings_screen.dart` — `_MenuCard`: Column обёрнут в `Material(transparency)`
  (фикс debug-ассерта Flutter 3.44 + видимый ripple).
- `lib/screens/home_screen.dart`, `lib/screens/lock_screen.dart` — язык диалога бета-дисклеймера
  и диалога wipe берётся из `Localizations.localeOf(context)` (в проде эквивалентно синглтону).

**Изменения тестов:** обновлены устаревшие литералы (help/qr/lock), добавлена локаль+делегаты в
pump'ы (contacts, диалог обновления), переписан `getWithFallback` под один хост (+тест на `null`).

**Статус:** `flutter analyze` → 0 errors; `flutter test` → **324 passed / 0 failed**.

**Команды:** `flutter analyze`, `flutter test`.

---

## 2026-07-01 — Шифрование локальной БД (аудит SEC-1) [ветка wl/db-encryption]

**Задача:** первый заход по ремедиации аудита (`AUDIT_REPORT.md`) — закрыть критическую находку
`SEC-1`: локальная БД хранилась в открытом виде, из-за чего PIN/duress/panic-wipe были косметикой.
Директива пользователя: потеря данных допустима (критичных данных нет) → миграцию не делаем.

**Сделано:**
- `pubspec.yaml`: `sqflite` → `sqflite_sqlcipher ^3.4.0` (drop-in API + пароль/PRAGMA key).
- `lib/services/database_service.dart`: ключ шифрования БД — 256 случайных бит (`Random.secure`),
  хранится в Keystore-backed `flutter_secure_storage` (`orpheus_db_key`). `openDatabase(..., password:)`.
  При первом запуске (нет ключа) старая НЕзашифрованная БД удаляется, создаётся свежая зашифрованная.
  В `deleteDatabaseFile()` (panic-wipe) ключ БД тоже удаляется → остаточный шифртекст невосстановим,
  следующий запуск создаёт новый ключ + пустую БД. Логи переведены на `DebugLogger`.
- `android/app/src/main/AndroidManifest.xml`: `allowBackup="false"` + `dataExtractionRules`.
- `android/app/src/main/res/xml/data_extraction_rules.xml`: исключить всё из cloud-backup и
  device-transfer (SEC-7 / DB-2 / OPS-3).
- `test/services/database_service_test.dart`: убран импорт удалённого `package:sqflite/sqflite.dart`
  (типы/фабрика берутся из `sqflite_common_ffi`).

**Дизайн-решение:** ключ БД — случайный в Keystore, НЕ из PIN. Причина: приложение принимает и пишет
сообщения, пока заблокировано (WebSocket под экраном PIN) и в фоне; ключ из PIN там недоступен →
входящие терялись бы. Компромисс: PIN остаётся UI-замком, данные защищает Keystore-ключ (это огромный
шаг от plaintext). PIN-деривация — отдельное продуктовое решение (жертва приёмом в фоне).

**Статус:** `flutter analyze` → 0 errors; `flutter test` → **324 passed / 0 failed**.
Реальная проверка SQLCipher/манифеста — сборка `flutter build apk --debug` (нативные libs + resources).

**Команды:** `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug`.

---

## 2026-07-01 - Телеметрия opt-in + без метаданных (аудит SEC-2) [ветка wl/audit-fixes]

**Задача:** закрыть SEC-2 - телеметрия была включена по умолчанию и слала на сервер публичные
ключи контактов (граф общения) и отпечаток устройства.

**Сделано (lib/services/telemetry_service.dart, переписан):**
- `_enabled = false` по умолчанию; флаг persist в SharedPreferences; `setEnabled()` + `isEnabled`.
- Из выгрузки убраны `peer_pubkey` и `device_info` (отпечаток); `device_info_plus` больше не
  используется в телеметрии. `os` оставлен грубым (android/ios).
- `_sanitizeContext()` вырезает из context ключи-личности контактов перед отправкой.
- Тумблер включения добавлен в скрытый экран отладочных логов (lib/screens/debug_logs_screen.dart).
- `X-Pubkey` оставлен: телеметрия теперь opt-in, владелец включает её для отладки СВОЕГО устройства.

**Статус:** analyze 0 errors; test 324 passed / 0 failed.

---

## 2026-07-01 - Стабильный message_id: дедуп + удалить у обоих (аудит LOGIC-1/2) [ветка wl/audit-fixes]

**Задача:** LOGIC-1 (тихая потеря быстрых входящих из-за 5-сек окна дедупа) и LOGIC-2 («удалить
у обоих» не срабатывало у получателя из-за матча по метке времени). Решение: стабильный `message_id`
(UUID) в конверте, одинаковый у обеих сторон.

**Сделано (8 файлов lib + тесты):**
- `models/chat_message_model.dart`: поле `messageId` (+toMap).
- `services/database_service.dart`: колонка `messageId`; версия 6->7; убран UNIQUE-индекс по timestamp
  (DB-4), добавлены индекс `(contactPublicKey,timestamp)` и UNIQUE `(contactPublicKey,messageId)`;
  методы `deleteMessagesByMessageIds`, `messageExistsByMessageId`; чтение messageId в mapping.
- `services/incoming_message_handler.dart`: дедуп по `message_id` (точный) с fallback на окно для
  старых клиентов; delete-for-both по `message_ids` (fallback timestamps_ms); +2 метода в интерфейс.
- `services/websocket_service.dart`: `message_id` в конверте chat, `message_ids` в delete-for-both,
  проброс через pending-очередь на реконнекте.
- `services/pending_actions_service.dart`: `messageId` в PendingMessage/сериализации.
- `chat_screen.dart`: генерация UUID при отправке (пакет `uuid`, был неиспользуем - DEP-10);
  delete-for-both/self по id.
- `main.dart`: адаптер IncomingMessageDatabase - 2 новых метода.
- Тесты: тест-схемы messages + `messageId`; фейк `_FakeDb` +2 метода; новый тест на LOGIC-1
  (разные id в окне не теряются, одинаковый id - дубль).

**Обратная совместимость:** message_id в открытом виде рядом с зашифрованным payload; старые клиенты
игнорируют лишнее поле; без id - прежнее окно дедупа.

**Статус:** analyze 0 errors; test 325 passed / 0 failed; flutter build apk --debug OK.

---

## 2026-07-01 - Реальный статус исходящих сообщений (аудит LOGIC-3/LOGIC-4/UI-8) [ветка wl/msg-status]

**Задача:** сообщение всегда показывало двойную галку «доставлено», даже при сбое шифрования/
отправки (ошибка молча проглатывалась) - баг доверия.

**Сделано:**
- `chat_screen.dart`: `_sendMessage` теперь стартует со статусом `sending`, при успехе -> `sent`,
  при ошибке (encrypt/send) -> `failed` (раньше `catch (_)` глотал ошибку). Иконка статуса через
  `_buildStatusIcon`: часы/одиночная галка/красный error (двойная галка delivered/read пока не
  используется - сервер релей без квитанций).
- `database_service.dart`: добавлен `updateMessageStatusByMessageId` (обновление по стабильному id).
- Тест: DB-тест на `updateMessageStatusByMessageId` + `deleteMessagesByMessageIds`.

**Статус:** analyze 0 errors; test 326 passed / 0 failed.

---

## 2026-07-01 - Экран приветствия: loading/guard при создании аккаунта (аудит UI-5)

**Сделано (welcome_screen.dart):** `_createNewAccount` - guard от двойного тапа (иначе перегенерация
ключей поверх созданных), `isLoading` на кнопке + блокировка кнопок на время генерации, обработка
ошибки со SnackBar (раньше без loading и без обработки). Импорт-ключа уже закрывал диалог до await
и показывал ошибку - не трогал.

**Статус:** analyze 0 errors; test 326 passed / 0 failed.
