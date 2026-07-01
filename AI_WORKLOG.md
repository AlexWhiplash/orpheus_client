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
- `lib/services/notification_service.dart` — строки уведомлений (`incomingCall`, `newMessage`,
  `unknownCaller`) двуязычные через gen-l10n. Фоновый FCM-изолят без контекста → добавлен хелпер
  `notificationL10n()`: резолвит язык по сохранённому `app_locale` → системная локаль → `en`,
  затем `lookupL10n(Locale)`. RU-юзер получает RU, EN — EN.
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
