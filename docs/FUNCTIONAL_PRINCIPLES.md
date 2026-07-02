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
- **База**: SQLite через `sqflite_sqlcipher` — БД **зашифрована** (SQLCipher, ключ из Android Keystore), схема v7 (`DatabaseService`).
- **Контакты**: `contacts(id, name, publicKey)`.
- **Сообщения**: `messages(contactPublicKey, text, isSentByMe, timestamp, status, isRead)`.
- **Duress mode**: методы чтения возвращают пустые данные, но входящие сообщения сохраняются (см. `DatabaseService`, `AuthService`).

## 4) Чат (UX + протокол)
**Исходящие**:
- UI сохраняет сообщение локально и затем пытается отправить по сети.
- При отсутствии соединения сообщение кладётся в `PendingActionsService` и отправляется после реконнекта.

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
- **PIN + lockout ladder**: защита от перебора на уровне UI.
- **Duress**: скрытие данных в UI (пустой профиль).
- **Wipe code + подтверждение удержанием**: защита от случайного удаления.
- **Panic wipe**: три ухода в фон в окне времени (по умолчанию выключено).

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



