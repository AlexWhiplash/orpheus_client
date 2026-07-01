# Orpheus Client (Flutter)

Клиентское приложение на Flutter для проекта Orpheus.

## Быстрый старт

### Требования
- Flutter SDK 3.44.x (проект разрабатывается на 3.44.4, канал stable). В `pubspec.yaml` → `environment`
  зафиксирован только Dart SDK.
- Android SDK / Android Studio (для Android)

> **Firebase настраивать не нужно:** `android/app/google-services.json` уже закоммичен, поэтому
> debug-сборка собирается сразу после `flutter pub get`, без дополнительных секретов.
>
> **Ветка:** активная разработка этого клиента идёт в изолированном треке `wl/dev` (форк
> `AlexWhiplash/orpheus_client`); ветку `master` не трогаем.

### Установка зависимостей
```powershell
flutter pub get
```

### Запуск
```powershell
flutter run
```

### Сборка APK (релиз)
```powershell
flutter build apk --release
```
Готовый файл: `build/app/outputs/flutter-apk/app-release.apk`.

> Примечание: сейчас release подписывается debug-ключом — для публичной раздачи нужен собственный
> keystore (см. `AUDIT_REPORT.md`, находка `OPS-1`).

## Тесты и отчёты

См. `docs/testing/README.md`.

Основные команды:
```powershell
flutter test
```

Или с генерацией отчётов:
```powershell
.\test_runner.ps1
```

## Документация
- Основная: `docs/README.md`
- Архитектура: `docs/ARCHITECTURE.md`
- Решения (ADR): `docs/DECISIONS/`

## Процесс изменений (чтобы ничего не забыть)
- Обновить `CHANGELOG.md` (секция `Unreleased`)
- Добавить запись в `AI_WORKLOG.md`
- Обновить `docs/*` при необходимости

### Cursor
- Правила: `.cursor/rules/`
- Команды-шаблоны: `.cursor/commands/` (например: `update-artifacts`, `update-changelog`, `log-work`, `commit-ready`)

### Git hooks (рекомендуется)
Чтобы коммит нельзя было сделать без `CHANGELOG.md` и `AI_WORKLOG.md`:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1
```
