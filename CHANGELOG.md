# CHANGELOG

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/)  
Версионирование: SemVer (привязка к `pubspec.yaml` при релизе)

## [Unreleased]
### Added
- CI (GitHub Actions): `flutter analyze` (жёсткий гейт на ошибки) + `flutter test` на пуш в ветки `wl/**` и на pull request.

### Changed
- JDK для Gradle резолвится через flutter/JAVA_HOME, без жёстко прописанного пути.

### Fixed
- Компиляция на актуальном Flutter (3.44.x): `CupertinoPageTransitionsBuilder` импортируется из `package:flutter/cupertino.dart` (перестал реэкспортироваться из `material`).

### Removed
- Машинно-специфичный `org.gradle.java.home` из `android/gradle.properties` (был жёстко прописан путь другого разработчика, ломал сборку на других машинах).

## [1.1.1] - 2026-01-05
### Added
- Профиль: добавлен “Чат с разработчиком” (поддержка) с отправкой сообщений и debug-логов.
-

### Changed
-

### Fixed
- UI: исправлен перенос текста в диалогах добавления и удаления контакта — добавлен `SingleChildScrollView` и `softWrap: true` для корректного отображения длинных текстов на устройствах с большими экранами (например, Samsung S25 Ultra).
-

### Removed
-

## [1.1.0] - 2025-12-12
### Added
- Безопасность: PIN (6 цифр), duress PIN и wipe/auto-wipe (опционально), экран блокировки (биометрия — опционально).
- UI: экран “Как пользоваться”, улучшения чата (карточки событий звонков).
- Android: `BootReceiver` (автозапуск после перезагрузки) + splash ресурсы для Android 12+.
- Стабильность/сеть: fallback по хостам для WebSocket (переезд на `api.orpheus.click`).
- Процесс/документация: восстановлены `.cursor/rules`/`.cursor/commands`/`.githooks`, добавлены docs и скрипты авто-коммита; release notes ведём в `OPHEUS_ADMIN` → “Версии”.

### Changed
- Профиль: версия берётся из платформы (`version+buildNumber`), а не из хардкода.
- `main.dart`: входящие WS-сообщения обработаны через `IncomingMessageHandler` (тонкая обвязка).

### Fixed
- Тесты/стабильность: убраны pending timers и флейки в widget-тестах.
- Звонки: ICE candidate не теряется (даже если приходит до `call-offer`), порядок действий для `hang-up`/`call-rejected` стабилизирован.
- Настройки: устранён `setState() called after dispose()`, автолок не мешает активному звонку.

### Removed
- UI: убраны баннеры/надписи про “Сквозное шифрование” в списке контактов и чате (меньше визуального шума).
- Процесс: убраны дублирующие документы по тестам (перенос в `docs/testing/README.md`).
