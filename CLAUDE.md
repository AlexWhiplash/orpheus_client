# Orpheus Client - Инструкции для Claude

## Workspace Structure
Этот проект является частью multi-component workspace Orpheus. Полная структура проекта описана в [WORKSPACE_STRUCTURE.md](WORKSPACE_STRUCTURE.md).

**Компоненты проекта**:
- **Orpheus Client** (текущий) - Flutter мобильное приложение
- **Orpheus Desktop** - C# WinUI 3 desktop приложение
- **Orpheus Backend** - Python FastAPI сервер
- **Orpheus Mailer Relay** - Go SMTP relay сервис
- **Orpheus Site** - React + TypeScript сайт

Каждый компонент имеет свой CLAUDE.md с инструкциями для соответствующей технологии.

## Стиль кода
- Используй Dart 3.0+ синтаксис
- Все сервисы — singleton с `.instance`
- Async операции через Future/Stream, никаких callbacks
- Комментарии на английском, UI тексты через l10n (английский приоритет)
- Избегай использования emojis в коде и комментариях

## Архитектурные правила
- Криптография ТОЛЬКО через CryptoService, никаких прямых вызовов
- Все DB операции через DatabaseService.instance
- WebSocket сообщения через WebSocketService
- UI обновления через setState() или Provider
- Тяжелые операции (шифрование, хэширование) через compute() для избежания UI lag
- Следуй layered architecture: Presentation -> Services -> Data

## Сервисы
- AuthService - аутентификация, PIN, duress mode, auto-lock
- CryptoService - E2E шифрование (X25519 + ChaCha20-Poly1305)
- WebSocketService - real-time messaging с автореконнектом
- DatabaseService - SQLite (SQLCipher), версия 10, поддержка duress mode, таблица outbox для исходящих chat
- NotificationService - локальные уведомления + CallKit (без Google/FCM)
- PushConnectionService - постоянный foreground-сервис (specialUse) с WebSocket в отдельном isolate; заменяет FCM для доставки при убитом приложении
- CallStateService - WebRTC звонки
- AiAssistantService - Oracle of Orpheus AI
- RoomsService - групповые чаты
- TelemetryService - полное логирование жизненного цикла

## Безопасность (КРИТИЧНО!)
- НИКОГДА не логируй приватные ключи, PIN коды или расшифрованные сообщения
- Все пароли/PIN только через FlutterSecureStorage
- Проверяй на SQL injection и XSS
- Используй compute() для криптографических операций
- Не добавляй screenshot capability без явного запроса
- Duress mode должен возвращать пустые данные, не null
- Panic wipe - безвозвратное удаление, проверяй дважды

## Тестирование
- Пиши unit тесты для новых сервисов в папке test/
- Используй моки для WebSocket/Database в тестах
- Запускай `flutter test` перед коммитами
- Проверяй тесты после изменений в сервисах

## Git workflow
- Коммиты на английском, формат: "feat: ...", "fix: ...", "refactor: ..."
- Не пушь в master без явного разрешения пользователя
- Staged changes: используй конкретные имена файлов, избегай `git add -A`
- Проверяй git status перед коммитом

## Предпочтения
- Избегай over-engineering — проще лучше
- Не добавляй features, которые не были запрошены
- Не добавляй error handling для невозможных сценариев
- Спрашивай через AskUserQuestion, если есть несколько вариантов решения
- Не создавай новые файлы без необходимости — предпочитай редактирование существующих
- Не добавляй docstrings/комментарии к коду, который не изменялся

## Локализация
- Английский (EN) имеет приоритет
- Русский (RU) как второй язык
- Все строки UI через AppLocalizations (класс `L10n`, `L10n.of(context)`)
- Редактируемые ИСТОЧНИКИ переводов: `lib/l10n/app_en.arb` (шаблон) и `lib/l10n/app_ru.arb`.
  Файлы `lib/l10n/app_localizations*.dart` — СГЕНЕРИРОВАННЫЕ (`flutter gen-l10n`), править их вручную нельзя.

## Чеклист релиза (ОБЯЗАТЕЛЬНО)
Перед каждым патчем или релизом агент ОБЯЗАН пройти все пункты по порядку.
Пропуск любого пункта запрещён. Результат каждого шага фиксируется.

### Фаза 1: Проверка задач
- [ ] Все запланированные issues для этой версии закрыты (проверить GitHub Issues)
- [ ] Каждая задача закоммичена отдельным коммитом с `Closes #N`
- [ ] Нет незавершённых TODO/FIXME в изменённых файлах

### Фаза 2: Качество кода
- [ ] `flutter analyze` — 0 ошибок (warnings допустимы)
- [ ] Нет утечек личных данных: grep по коду на имена, домены, ключи, пароли
- [ ] Локализация: все новые строки есть в EN и RU (app_en.arb + app_ru.arb)
- [ ] Нет hardcoded строк в UI — всё через L10n

### Фаза 3: Git
- [ ] `git status` — нет забытых unstaged изменений
- [ ] Все коммиты запушены (`git log origin/master..HEAD` пуст)
- [ ] История коммитов чистая, без мусорных коммитов

### Фаза 4: Версионирование
- [ ] `pubspec.yaml`: version обновлена (и version name, и build number)
- [ ] `config.dart`: appVersion обновлена
- [ ] Коммит с бампом версии создан

### Фаза 5: Changelog
- [ ] Сформирован публичный changelog на русском для пользователей
- [ ] Changelog загружен в админку (через API или вручную)

### Фаза 6: Сборка и публикация
- [ ] APK собран: `flutter build apk --release`
- [ ] APK загружен на сервер через админку
- [ ] Версия зарегистрирована в admin panel (version_code, version_name, download_url, changelog)
- [ ] Проверка: `curl https://api.orpheus.click/api/check-update?current_version_code=N` возвращает новую версию

### Фаза 7: Бэкенд (если были серверные изменения)
- [ ] Бэкенд задеплоен (Timeweb Apps автодеплой после push)
- [ ] Проверка что API отвечает: `curl https://api.orpheus.click/health`
- [ ] Sentry: нет новых критичных ошибок после деплоя

### Фаза 8: Документация и оповещение
- [ ] Oracle knowledge base обновлена (указать какие файлы базы заменить)
- [ ] Telegram dev-канал: уведомление о релизе
- [ ] GitHub Issues: milestone закрыт

## Особенности проекта
- Oracle of Orpheus - AI ассистент, всегда первый в списке контактов
- Notes Vault - зашифрованные заметки с tracking источника (manual/contact/room/oracle)
- Desktop Link - удалён из клиента (небезопасный протокол + мёртвый код); вернём безопасно после клиента+сервера, когда десктоп-приложение дозреет
- Orpheus Room - официальная комната, скрытая до релиза
- Single host: api.orpheus.click (legacy twc1 domain removed for privacy)
- HTTP fallback для критичных сигналов (call-offer, call-answer, hang-up)

## Важные файлы
- [main.dart](lib/main.dart) - точка входа
- [config.dart](lib/config.dart) - конфигурация приложения
- [crypto_service.dart](lib/services/crypto_service.dart) - все операции шифрования
- [websocket_service.dart](lib/services/websocket_service.dart) - real-time логика
- [database_service.dart](lib/services/database_service.dart) - SQLite операции
- [auth_service.dart](lib/services/auth_service.dart) - аутентификация и безопасность

## Общение
- Отвечай на русском языке (пользователь русскоязычный)
- Будь лаконичным и конкретным
- Используй markdown links для ссылок на код: [file.dart:123](path/to/file.dart#L123)
- Объясняй сложные изменения перед их внесением
