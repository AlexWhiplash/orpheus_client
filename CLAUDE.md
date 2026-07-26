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
- RoomsService - групповые чаты; данные НА СЕРВЕРЕ, duress-гейт через `_pubkey == null` (rooms_service.dart:25), а не через БД
- SupportChatService - чат с разработчиком; данные тоже на сервере, тот же гейт + своя duress-ветка в `loadMessages` (support_chat_service.dart:47/62)
- TelemetryService - полное логирование жизненного цикла

## Безопасность (КРИТИЧНО!)
- НИКОГДА не логируй приватные ключи, PIN коды или расшифрованные сообщения
- Все пароли/PIN только через FlutterSecureStorage
- Проверяй на SQL injection и XSS
- Используй compute() для криптографических операций
- Не добавляй screenshot capability без явного запроса
- Duress mode: гейт нужен на ТРЁХ уровнях, гейта в БД НЕДОСТАТОЧНО
  - Локальная БД (`DatabaseService`): чтения возвращают пусто (`[]`/`{}`/`0`), не null; деструктивные методы — no-op
  - Серверные сервисы (`RoomsService`, `SupportChatService`): под duress `_pubkey` возвращает **null**, чтобы запрос вообще не ушёл на сервер от имени жертвы (rooms_service.dart:25, support_chat_service.dart:47); у поддержки своя duress-ветка в `loadMessages` — пусто и `error == null` (support_chat_service.dart:62), иначе красный баннер ошибки сам стал бы подсказкой
  - UI/навигация: лок рисуется ОВЕРЛЕЕМ поверх Navigator (main.dart:1247-1256), поэтому маршруты, открытые до лока, остаются смонтированными с расшифрованными данными в `State` и не перечитывают гейтнутую БД. Любая смена личности сессии обязана звать `dropRoutesAboveHome()` (main.dart:129; вызовы — main.dart:821/940/978)
  - Настройки под duress не меняются: пять сеттеров `AuthService` — no-op (auth_service.dart:477/486/497/513/588) плюс тумблер имени звонящего (security_settings_screen.dart:304); экран безопасности не признаёт, что duress/wipe-код настроен (security_settings_screen.dart:201-203); экспорт аккаунта требует PIN приложения, а не системный код устройства (settings_screen.dart:139)
  - Логи не называют режим: ни `DebugLogger`, ни `print` не пишут «duress»/«wipe» — экран логов достижим из duress-сессии
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
- [ ] Если менялся любой экран/сервис, читающий или пишущий данные: проверено поведение под duress (пусто из БД, ни одного запроса на сервер, `dropRoutesAboveHome()` на переходах режима, никаких «настройка сохранена», никаких упоминаний duress в логах)

### Фаза 3: Git
- [ ] `git status` — нет забытых unstaged изменений
- [ ] Все коммиты запушены (`git log origin/master..HEAD` пуст)
- [ ] История коммитов чистая, без мусорных коммитов

### Фаза 4: Версионирование
- [ ] `pubspec.yaml`: version обновлена (и version name, и build number)
- [ ] `config.dart`: appVersion обновлена
- [ ] `config.dart`: `debugFileLogging = false` для публичного релиза (сейчас в репозитории `true` — тест-сборка, config.dart:10; при `true` пишется файловый лог и снимается защита от скриншотов). Для тест-сборок флаг оставлять `true` и бампить только build number
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

## Известные открытые дефекты (НЕ заявляй как работающие)
- ~~Код wipe с экрана лока не срабатывает~~ ПОЧИНЕНО 26.07.2026: подтверждение рисуется СЛОЕМ внутри `LockScreen` (`Completer<bool> _wipeConfirm` + `Positioned.fill` в его `Stack`), а не через `showDialog` — у виджета внутри `MaterialApp.builder` нет Navigator-предка. **Инвариант: из `LockScreen` нельзя дергать Navigator вообще** (ни `showDialog`, ни `navigatorKey` — во втором случае диалог уедет ПОД непрозрачный оверлей лока). Тесты держат это в группе «LockScreen как оверлей (структура прода)» — она поднимает лок в `builder`, как в проде; старая группа с `home:` баг не ловила.
- Duress не гейтит уведомления: всплывают уведомления комнат (main.dart:541) и ответов поддержки (incoming_message_handler.dart:113-116). Содержимое обезличено (`l10n.newMessage`, notification_service.dart:645), но сам факт уведомления доказывает наблюдателю наличие скрытого аккаунта.
- ~~Экран отладочных логов достижим из duress~~ и ~~`clearChatHistory` без гейта~~ — ПОЧИНЕНО 26.07.2026 (секретный тап no-op под duress; гейт в `clearChatHistory`).
- Входящие личные сообщения во время duress теряются безвозвратно: `isContact` под duress отдаёт `false` (database_service.dart:489), и строгий mutual-add дропает кадр до сохранения (incoming_message_handler.dart:128), а сервер уже считает его доставленным.
- `verifyPin(основной PIN)` внутри duress-сессии зовёт `_setDuressMode(false)` — гейт БД снимается, а UI остаётся duress-сессией (рассогласованное состояние). Тот же корень, что неиспользуемый `exitDuressMode`.

## Важные файлы
- [main.dart](lib/main.dart) - точка входа; здесь же навигационная часть безопасности: лок-оверлей (main.dart:1247-1256), `PushedRouteTracker` (main.dart:75) и `dropRoutesAboveHome()` (main.dart:129) с тремя вызовами (main.dart:821/940/978)
- [security_settings_screen.dart](lib/screens/security_settings_screen.dart) - настройки безопасности и маскировка duress/wipe-кода под duress (security_settings_screen.dart:201-203)
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
