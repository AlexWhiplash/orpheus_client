# Архитектура клиента (актуальная)

## Контекст и границы
Эта архитектура описывает **Flutter‑клиент** (`orpheus_client`). Сервер связи и админ‑панель — отдельные компоненты и описываются вне этого репозитория.

## Основные подсистемы (карта)
Ключевые файлы/модули:
- **Запуск приложения и “склейка” сервисов**: `lib/main.dart`
- **Конфиг URL и доменный fallback**: `lib/config.dart`
- **Криптография (ключи + E2E шифрование сообщений)**: `lib/services/crypto_service.dart`
- **Локальное хранение (контакты/сообщения)**: `lib/services/database_service.dart`
- **Сеть и протокол** (WS + HTTP fallback для критичных сигналов): `lib/services/websocket_service.dart`
- **Единая обработка входящих WS‑сообщений**: `lib/services/incoming_message_handler.dart`
- **Звонки**:
  - UI/оркестрация: `lib/call_screen.dart`
  - WebRTC: `lib/services/webrtc_service.dart`
  - Буфер входящих ICE: `lib/services/incoming_call_buffer.dart`
  - Глобальный флаг “звонок активен”: `lib/services/call_state_service.dart`
  - Foreground service на время звонка: `lib/services/background_call_service.dart`
- **Уведомления** (только локальные, без Google/FCM): `lib/services/notification_service.dart`
- **Безопасность входа/duress/wipe**: `lib/services/auth_service.dart`, ADR: `docs/DECISIONS/0003-security-system.md`
- **Навигационная часть безопасности** (лок‑оверлей поверх Navigator, `PushedRouteTracker`, `dropRoutesAboveHome`): `lib/main.dart:75-140`, `lib/main.dart:1247-1256`
- **Presence (онлайн‑статусы)**: `lib/services/presence_service.dart`
- **Обновления** (check-update + fallback по хостам): `lib/services/update_service.dart`
- **Лицензия/промо‑активация**: `lib/license_screen.dart`
- **Поддержка (чат)**: `lib/services/support_chat_service.dart`
- **Oracle of Orpheus (AI)**: `lib/services/ai_assistant_service.dart`, UI: `lib/screens/ai_assistant_chat_screen.dart`
- **Notes Vault (заметки)**: `lib/screens/notes_vault_screen.dart`, модель: `lib/models/note_model.dart`
- **Rooms (групповые чаты)**: `lib/services/rooms_service.dart`
- **Очистка сообщений**: `lib/services/message_cleanup_service.dart`
- **Настройки уведомлений**: `lib/services/notification_prefs_service.dart`

## Структура каталогов
- `lib/` — исходный код приложения
- `test/` — unit/widget тесты (контракты поведения)
- `android/` — Android‑часть (ресурсы/манифесты/gradle)

## Схема запуска (boot sequence)
Текущая последовательность инициализации (см. `lib/main.dart`):
1. `NotificationService.init()` (локальные уведомления, без Google/FCM)
2. `CryptoService.init()` (ключи из secure storage)
3. `AuthService.init()` (security config из secure storage)
4. `PanicWipeService.init()` (наблюдение lifecycle)
5. `NetworkMonitorService.init()` (события сети)
6. `WebSocketService.connect(pubkey)` (если ключи есть)
7. Подписка на WS‑стрим и обработка через `IncomingMessageHandler`
8. `TelemetryService.init()` (opt-in, по умолчанию выключена; санитизированные логи в БД)
9. `PushConnectionService.start()` + heartbeat (постоянный foreground-сервис доставки
   пушей при убитом приложении — замена FCM; только если есть ключи)

## Лок как оверлей и сброс маршрутов (инвариант duress/wipe)
`LockScreen` рисуется НЕ как `home`, а оверлеем поверх Navigator в `MaterialApp.builder`
(`lib/main.dart:1247-1256`): иначе любой запушенный маршрут (чат, звонок) перекрывал бы лок и
PIN обходился. Следствие: маршруты, открытые ДО лока, остаются смонтированными, и их `State`
держит уже расшифрованные данные (например историю чата в RAM), которые не перечитываются из
гейтнутой БД. Поэтому введён инвариант: **при смене личности сессии маршруты выше home снимаются**.
- `PushedRouteTracker` (`NavigatorObserver`, `lib/main.dart:75`) ведёт список маршрутов выше home;
  подключён через `navigatorObservers: appNavigatorObservers` (`lib/main.dart:1199`). Наблюдается
  только корневой Navigator — вложенных сегодня нет; появится вложенный, механизм его не покроет.
- `dropRoutesAboveHome()` (`lib/main.dart:129`) снимает маршруты через `NavigatorState.removeRoute`
  синхронно и БЕЗ pop-анимации, пока лок ещё нарисован, — чтобы не было кадра, где настоящий чат
  виден без лока сверху. `popUntil` не используется намеренно (анимация выхода ~300 мс).
- Три точки вызова: вход по коду принуждения (`main.dart:978`), завершение wipe (`main.dart:821`),
  вход настоящим PIN после duress-сессии (`main.dart:940`, по флагу `_duressUiActive`). После
  обычного автолока маршруты НЕ снимаются — пользователь должен вернуться на свой экран.
- Контракт для новых экранов: продолжение `await Navigator.push(...)` может выполниться уже после
  dispose — нужен guard по `mounted` (`rooms_screen.dart`).
- Контракт для `dispose()`: после wipe маршруты снимаются уже ПОСЛЕ стирания, поэтому любая запись
  из `dispose` идёт под гардом «личность ещё есть» (`call_screen.dart:1250`,
  `room_chat_screen.dart:112`) — иначе пересоздаётся SQLCipher-база с новым ключом.

## Пуши без Google
Вместо Firebase Cloud Messaging входящие при убитом приложении будит собственный постоянный
foreground-сервис `PushConnectionService` (`flutter_background_service`, тип Android `specialUse`).
Он держит WebSocket в отдельном isolate и показывает CallKit/уведомления через
`handleBackgroundPush`. Пока UI жив (heartbeat свежий) — сервис молчит; при убитом приложении
берёт доставку на себя. Дедуп пересечений — по `call_id`/`message_id`.

## Телеметрия (opt-in, по умолчанию выключена)
Цель: при явном включении пользователем (тумблер в экране отладочных логов) видеть **санитизированный** цикл жизни клиента в БД для диагностики. По умолчанию сбор и отправка выключены (`SEC-2`).

### Клиент
- Источник событий: `DebugLogger` + перехват `debugPrint` и `FlutterError`.
- Сервис: `lib/services/telemetry_service.dart`
- Транспорт: HTTP батчи на `/api/logs/batch` (только при включённой телеметрии)
- Контекст событий (**санитизирован** — ключи/pubkey/device_info удаляются):
  - `pubkey`, `call_id` (если есть)
  - `app_version`, `os`
  - `network`, `app_state`
- Фоновый обработчик доставки (push-изолят `PushConnectionService`) не отправляет ключи: телеметрия санитизирована (`recipient_pubkey` убран).

### Сервер (серверный репозиторий — вне этого репозитория)
- Таблица: `telemetry_logs`
- Логируются:
  - все HTTP запросы/ответы (middleware),
  - все WS сообщения (raw payload),
  - Redis‑routing события (если включён Redis bridge).
- TTL на очистку: `TELEMETRY_RETENTION_DAYS` (по умолчанию 14)
- Ограничение размера деталей: `TELEMETRY_MAX_DETAILS_SIZE` (по умолчанию 100000)

### Анализ
- По клиенту: `WHERE pubkey = '...'`
- По звонку: `WHERE call_id = '...'`

## Потоки данных (как работает функционал)

### 1) Идентичность и ключи
- **Идентификатор пользователя**: публичный ключ (base64).
- **Хранение ключей**: `flutter_secure_storage` (`CryptoService`).
- **Крипто для сообщений**: ECDH X25519 → общий секрет → ChaCha20‑Poly1305 AEAD (см. `CryptoService.encrypt/decrypt`).

### 2) Чат (сообщения)
**Исходящее сообщение** (`lib/chat_screen.dart` → `WebSocketService.sendChatMessage`):
1. UI пишет текст → сохраняем в SQLite через `DatabaseService.addMessage`.
2. Шифруем через `CryptoService.encrypt(recipientPubKey, text)` (в isolate).
3. Отправляем по WS: `{type:"chat", recipient_pubkey, payload}`.

- Доставка идёт через **персистентный outbox** (таблица `outbox`, SQLCipher, схема v10): сообщение
  попадает в очередь ДО первой записи в сокет и удаляется ТОЛЬКО по подтверждению сервера — явный
  `chat-ack` (сервер с `caps=['chat-ack']`) либо pong-fence на серверах без caps
  (`websocket_service.dart`). До подтверждения статус — `sending` («часики»).
- Смерть сокета или процесса даёт ресенд, а не потерю; дубль у получателя гасится дедупом по
  `messageId` (уникальный индекс `idx_unique_message_id`).
- Ретраи: таймер каждые 30 с, слив после PoP-аутентификации, `_reconcileOutbox` при старте.
  Старая prefs-очередь `PendingActionsService` — только разовый импорт legacy-строк (`main.dart`).

**Входящее сообщение** (`WebSocketService.stream` → `IncomingMessageHandler`):
1. Получаем `{type:"chat", sender_pubkey, payload}`.
2. Дешифруем payload через `CryptoService.decrypt(senderKey, payload)`.
3. Сохраняем в SQLite как входящее непрочитанное.
4. Если приложение в фоне — показываем уведомление (без текста сообщения), кроме системных “call-status” сообщений.

### 3) Звонки (сигналинг + WebRTC)
**Сигналинг** идёт через WS (и частично через HTTP fallback для критичных сигналов).

Входящий `call-offer`:
1. `IncomingMessageHandler` применяет TTL (если есть server_ts_ms), дедуп по sender и проверку “звонок уже активен”.
2. Поднимается call‑уведомление и открывается `CallScreen`.
3. ICE кандидаты, пришедшие раньше offer, не теряются: они буферизуются `IncomingCallBuffer`.

ICE кандидаты:
- Всегда буферизуются и пробрасываются в `CallScreen`.

Завершение звонка (`hang-up` / `call-rejected`):
- Сначала сигнал пробрасывается в `CallScreen`, затем скрывается уведомление (важный порядок, зафиксирован как контракт).

**WebRTC** (`WebRTCService`):
- Создание peerConnection, сбор local audio stream, создание offer/answer.
- Защита от гонок: очередь remote ICE до установки remote SDP.
- Поддержан ICE restart при смене сети (сигналы `ice-restart`, `ice-restart-answer`).

### 4) Уведомления
`NotificationService`:
- Только локальные уведомления (`flutter_local_notifications`) + CallKit для звонков. Google/FCM в
  проекте нет: при убитом приложении соединение держит собственный `PushConnectionService`.
- Уведомления о сообщениях поднимает main-изолят (`IncomingMessageHandler` →
  `NotificationService.showMessageNotification`). Push-изолят держит только своё постоянное
  уведомление foreground-сервиса (`push_connection_service.dart`, id 887, `showBadge: false`).
- Приватность: push по сообщениям не содержит текста сообщения (на стороне клиента показывается “Новое сообщение”).

### 5) Домены и fallback (устойчивость)
- `AppConfig.apiHosts` задаёт приоритет: новый домен → legacy.
- `WebSocketService` умеет переключать хост при ошибке подключения.
- `UpdateService` делает HTTP GET с fallback по всем хостам.

### 6) Безопасность приложения (PIN / duress / wipe)
Подробно: `docs/DECISIONS/0003-security-system.md`.
- PIN/duress/wipe code и lockout ladder — `AuthService` + `SecurityConfig`.
- Duress — сквозной режим, а не только фильтр БД. Гейты стоят на всех источниках данных:
  - локальная БД: чтения возвращают пустое (`DatabaseService`), деструктивные методы — no-op;
  - серверные данные: `RoomsService._pubkey` и `SupportChatService._pubkey` → `null`
    (`rooms_service.dart:25`, `support_chat_service.dart:47`), `loadMessages` под duress отдаёт
    ПУСТО и `error == null` (`support_chat_service.dart:62`) — иначе красный баннер ошибки сам был
    бы подсказкой; живой ответ по WS игнорируется (`support_chat_service.dart:219`);
  - навигация: см. § «Лок как оверлей и сброс маршрутов»;
  - UI-подсказки: точка непрочитанного комнат гасится (`home_screen.dart:41-42`), экран
    «Безопасность» не признаёт наличие кода принуждения и кода удаления — оба раздела остаются
    видимыми в состоянии «не настроено» (`security_settings_screen.dart:201-203`);
  - необратимые действия: экспорт аккаунта под duress требует PIN приложения вместо системного кода
    устройства (`settings_screen.dart:139`), пять сеттеров конфига (auto-wipe, panic-жест,
    биометрия, автолок, retention) и тумблер «имя звонящего на локскрине» — no-op
    (`auth_service.dart:477,486,497,513,588`, `security_settings_screen.dart:304`);
  - диагностика: лог не называет режим (`main.dart:970`).
- **Входящие в duress не сохраняются, а теряются**: `isContact` под duress → `false`
  (`database_service.dart:489`), строгий mutual-add дропает кадр до записи в БД
  (`incoming_message_handler.dart:128`), а сервер уже считает сообщение доставленным.
- Panic wipe реализован как “3 события ухода в фон” (ограничение Flutter; по умолчанию выключено).

**Известные ограничения (НЕ считать работающим):**
- Инвариант `LockScreen`: **из него нельзя дергать Navigator** — у виджета внутри
  `MaterialApp.builder` нет Navigator-предка, а пуш через `navigatorKey` уехал бы ПОД
  непрозрачный оверлей лока. Поэтому подтверждение кода удаления рисуется слоем внутри
  самого экрана (`Completer<bool> _wipeConfirm` + `Positioned.fill` в его `Stack`).
  До 26.07.2026 здесь стоял `showDialog`, и код удаления не срабатывал НИКОГДА.
- Duress не гейтит уведомления: всплывают уведомления комнат (`main.dart:541`) и ответов поддержки
  (`incoming_message_handler.dart:113-116`). Тела обезличены (`notification_service.dart:645`), но
  сам факт уведомления — подсказка.
- Экран отладочных логов достижим из duress-сессии (`settings_screen.dart:119-126`).
- `DatabaseService.clearChatHistory` (`database_service.dart:1066`) — единственный путь удаления
  БЕЗ duress-гейта.

### 7) Oracle of Orpheus (AI‑ассистент)
- **Сервис**: `lib/services/ai_assistant_service.dart`
- **UI**: `lib/screens/ai_assistant_chat_screen.dart`
- **Эндпоинт**: `POST /api/public/ai/call` (публичный, с заголовком `X-Pubkey`)
- **Память**: до 20 последних сообщений хранятся в SQLite и передаются серверу через `parent_message_id` для контекста
- **Функции UI**: приветственный экран с suggestion-кнопками, Markdown‑рендеринг ответов, индикатор памяти, очистка чата/памяти, сохранение ответов в Notes Vault (long-press)
- **Позиция**: Oracle всегда первый в списке контактов, статус "Always online"

### 8) Notes Vault (зашифрованные заметки)
- **UI**: `lib/screens/notes_vault_screen.dart`
- **Модель**: `lib/models/note_model.dart`
- **Хранение**: SQLite через `DatabaseService` (таблица `notes`)
- **Tracking источника**: каждая заметка имеет `sourceType` (`manual`, `contact`, `room`, `oracle`) и `sourceLabel`
- **Операции**: создание, чтение (DESC по дате), удаление (long-press + подтверждение); редактирование не поддерживается
- **Duress mode**: возвращает пустой список заметок

### 9) Rooms (групповые чаты)
- **Сервис**: `lib/services/rooms_service.dart`
- **Архитектура**: чистый HTTP‑клиент без локального хранения (stateless)
- **API**: `GET /api/rooms`, `POST /api/rooms`, `POST /api/rooms/join`, `GET/POST /api/rooms/{id}/messages`, `GET/POST /api/rooms/{id}/prefs` и др.
- **Инвайт**: присоединение по invite‑коду, ротация кода через `rotate-invite`
- **Panic clear**: безвозвратное удаление всей истории комнаты
- **Orpheus Room**: официальная комната (скрыта до релиза); `asOrpheus` флаг для официальных сообщений
- **Duress**: `RoomsService._pubkey` возвращает `null` (`rooms_service.dart:25`) — комнаты живут на
  СЕРВЕРЕ, гейт БД их не покрывает. Все методы трактуют `null` как «нет аккаунта»: чтения пустые,
  prefs отдают дефолты, мутации бросают, а UI показывает свою обычную ошибку соединения
  (неотличимо от недоступного сервера). Точка непрочитанного в табах гасится отдельно
  (`home_screen.dart:41-42`), т.к. живёт в кеше сервиса, а не в БД.

### 10) Desktop Link — УДАЛЁН из клиента
Паринг телефон↔десктоп по LAN удалён (недостижимый мёртвый код + небезопасный
протокол: открытый HTTP-обмен токеном, WS-сервер без аутентификации, неиспользуемый
`desktop_pubkey`). Вернём безопасно после доработки клиента и сервера, когда
десктоп-приложение дозреет (история в git; план — в памяти проекта).

### 11) Автоблокировка и очистка сообщений
- **Автоблокировка по неактивности**: `AuthService` отслеживает время последней активности; не блокируется во время активного звонка (`CallStateService`)
- **Очистка сообщений**: `MessageCleanupService` удаляет старые сообщения по политике (retention policy); триггеры: запуск, каждые 2 часа, смена политики; не работает в duress mode

## Где фиксировать решения и контракты
- Архитектурные решения: `docs/DECISIONS/`
- Контракты поведения: тесты (см. `docs/testing/README.md`)


