# Orpheus Client — принципы работы функционала (по блокам)

## 1) Идентичность и ключи
- **Идентификатор**: публичный ключ (base64).
- **Хранение**: приватный/публичный ключ сохраняются в `flutter_secure_storage` (`CryptoService`).
- **Операции**:
  - инициализация и загрузка ключей: `CryptoService.init()`
  - генерация: `CryptoService.generateNewKeys()`
  - импорт приватного ключа: `CryptoService.importPrivateKey(...)`

## 2) Шифрование сообщений (E2E)
- **Алгоритмы**: X25519 (shared secret) + ChaCha20‑Poly1305 AEAD (`cryptography`).
- **Производительность**: encrypt/decrypt выполняются через `compute(...)` (отдельный isolate), чтобы не блокировать UI.
- **Контракт**: на сервер уходит только `payload` (шифртекст + nonce + mac), клиент хранит расшифрованный текст локально.

## 3) Локальное хранилище (контакты/сообщения)
- **База**: SQLite через `sqflite_sqlcipher` — БД **зашифрована** (SQLCipher, ключ из Android Keystore), схема **v10** (`DatabaseService`).
- **Контакты**: `contacts(id, name, publicKey)`.
- **Сообщения**: `messages(contactPublicKey, text, isSentByMe, timestamp, status, isRead)`.
- **Outbox**: `outbox(messageId PK, recipientKey, payload, createdAt, attempts, lastAttemptAt)` — персистентная очередь исходящих chat (появилась в v10).
- **Duress mode**: методы чтения возвращают пустые данные. Входящие личные сообщения при этом **не сохраняются, а теряются**: `isContact` под duress → `false` (`database_service.dart:489`), и строгий mutual-add дропает кадр до записи (`incoming_message_handler.dart:128`) — известный открытый дефект. Гейт БД не единственный: серверные данные закрываются в `RoomsService`/`SupportChatService` (см. § 8).

## 4) Чат (UX + протокол)
**Исходящие**:
- UI сохраняет сообщение локально (статус `sending`) и кладёт его в персистентный **outbox** (SQLCipher) — ВСЕГДА, независимо от наличия соединения.
- Строка удаляется из outbox только по подтверждению сервера: явный `chat-ack` (сервер с `caps=['chat-ack']`) либо pong-fence на серверах без caps. Только тогда статус становится `sent`.
- Ретрай: таймер 30 с, слив после PoP-аутентификации, reconcile при старте. Смерть процесса даёт ресенд, а не потерю; дубль у получателя гасится дедупом по `messageId`.
- Ограничение fence-режима (сервер без `chat-ack`): pong доказывает живость сокета, но не приём кадра.
- `PendingActionsService` — legacy: разовый импорт застрявших prefs-строк при старте.

**Входящие**:
- Единой точкой является `IncomingMessageHandler`:
  - дешифрование payload
  - сохранение в БД
  - уведомление UI через stream
  - уведомление пользователя (если приложение в фоне и это не системное call-status сообщение)

## 5) Сеть, реконнект и fallback
- **WebSocket**: `WebSocketService` с экспоненциальным backoff и ping/pong.
- **Смена сети**: `NetworkMonitorService` инициирует быстрый реконнект.
- **Fallback по доменам**:
  - `AppConfig.apiHosts` задаёт приоритет хостов
  - WS переключает хост при ошибках подключения
  - HTTP‑запросы для обновлений и некоторых сигналов идут с попытками по всем хостам

## 6) Звонки
Состоит из двух частей:
- **Сигналинг** (WS + HTTP fallback для критичных сигналов): `WebSocketService`, `IncomingMessageHandler`
- **Медиа** (WebRTC): `WebRTCService`

Ключевые принципы:
- ICE кандидаты могут прийти раньше offer → всегда буферизуются (`IncomingCallBuffer`).
- “Критичные сигналы” (`hang-up`, `call-rejected`, `ice-restart*`) дублируются через HTTP fallback (гарантия доставки при проблемах WS/шардинге).
- При активном звонке приложение не должно “само заблокироваться” поверх UI звонка (`CallStateService`).
- При потере сети предусмотрен ICE restart (в том числе авто‑триггер при Disconnected/Failed).

## 7) Уведомления
- **FCM**: получение токена, обновление токена, обработка onMessage/onMessageOpenedApp/getInitialMessage.
- **Background handler**: локальные уведомления показываются только для data‑only сообщений (чтобы не ломать системный звук/поведение).
- **Приватность**: уведомление о сообщении не содержит текста сообщения.

## 8) Безопасность приложения (PIN / duress / wipe)
Блоки:
- **PIN + lockout ladder**: защита от перебора на уровне UI (монотонное время).
- **Duress**: вход по коду принуждения даёт «пустой профиль». Что закрыто:
  - локальная БД — пустые чтения; серверные данные — `RoomsService._pubkey`/`SupportChatService._pubkey` → `null` (`rooms_service.dart:25`, `support_chat_service.dart:47`), история поддержки пустая и БЕЗ ошибки на экране (`support_chat_service.dart:62`);
  - **навигация**: лок — оверлей поверх Navigator (`main.dart:1247-1256`), поэтому открытые до лока маршруты держат расшифрованные данные; при duress-входе они снимаются `dropRoutesAboveHome()` синхронно, пока лок ещё нарисован (`main.dart:978`, реализация `main.dart:129`). То же после wipe (`main.dart:821`) и при входе настоящим PIN после duress-сессии (`main.dart:940`);
  - реальный входящий/висящий звонок в duress-сессию не переносится (`main.dart:979-986`);
  - необратимое: экспорт аккаунта требует PIN приложения, а не системный код устройства (`settings_screen.dart:139`); сеттеры настроек безопасности — no-op (`auth_service.dart:477,486,497,513,588`);
  - подсказок нет: экран «Безопасность» не признаёт наличие кода принуждения/удаления (`security_settings_screen.dart:201-203`), лог не называет режим (`main.dart:970`).
- **Wipe code + подтверждение удержанием**: **НЕ РАБОТАЕТ с локскрина** — `showDialog` из `LockScreen` не имеет Navigator-предка, т.к. лок рисуется оверлеем (`lock_screen.dart:242`). Auto-wipe после N неудачных попыток работает (`lock_screen.dart:226-227`).
- **Panic wipe**: три ухода в фон в окне времени (по умолчанию выключено).
- **Известные дыры duress**: уведомления не гейтятся (комнаты `main.dart:541`, поддержка `incoming_message_handler.dart:113-116`; тела обезличены, но факт уведомления — подсказка); экран отладочных логов достижим из duress-сессии (`settings_screen.dart:119-126`); `clearChatHistory` — единственный путь удаления без гейта (`database_service.dart:1066`); входящие личные сообщения в duress теряются.

Источник решения: `docs/DECISIONS/0003-security-system.md`.

## 9) Лицензия и активация
- Экран активации: `lib/license_screen.dart`.
- Промокод: HTTP `POST /api/activate-promo` с `pubkey` и `code`.
- Подтверждение лицензии: события по WS (`license-status`, `payment-confirmed`).

## 10) Поддержка (чат)
- HTTP API с заголовком `X-Pubkey`:
  - `GET /api/support/messages`
  - `POST /api/support/message`
  - `POST /api/support/logs`
  - `GET /api/support/unread`
- Отправка логов: экспорт `DebugLogger` + device info.

## 11) Телеметрия (opt-in, по умолчанию выключена)
- Источник: `DebugLogger` + перехват `debugPrint` + `FlutterError`.
- Отправка: HTTP батчи на `/api/logs/batch` с заголовком `X-Pubkey` — **только при включённой пользователем телеметрии** (тумблер в экране отладочных логов); по умолчанию выключена (`SEC-2`).
- Данные **санитизированы**: удаляются `peer_pubkey`/`*_pubkey`/`*_key`/`device_info` (в т.ч. в фоновом FCM-хендлере).
- Назначение: диагностика при явном согласии; не «полный цикл жизни».



