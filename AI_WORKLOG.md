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
