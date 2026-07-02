# Orpheus Client (Flutter)

Клиентское приложение на Flutter для проекта Orpheus.

## Быстрый старт

### Требования
- Flutter SDK 3.44.x (проект разрабатывается на 3.44.4, канал stable). В `pubspec.yaml` → `environment`
  зафиксирован только Dart SDK.
- Android SDK / Android Studio (для Android)

> **Без сервисов Google:** клиент не использует Firebase/FCM/ML Kit — сборка идёт сразу после
> `flutter pub get`, никаких `google-services.json` или секретов Google не нужно. Пуши доставляет
> собственный постоянный foreground-сервис поверх WebSocket (см. `PushConnectionService`).
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

> Подпись release: если создан `android/key.properties` (см. `android/key.properties.example`), сборка
> подписывается **вашим keystore**; если файла нет — фолбэк на debug-ключ, чтобы сборка работала без секретов
> (`OPS-1`). Для публичной раздачи сгенерируйте свой keystore и заполните `key.properties` (инструкция — в примере).

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
