# Тестирование (Flutter-клиент Orpheus)

Цель тестов — **зафиксировать правильное поведение** приложения (особенно в сообщениях и звонках), чтобы после любых правок `flutter test` давал уверенность, что критичные сценарии не сломаны.

## Быстрый запуск

### Все тесты
```powershell
flutter test
```

### Быстрый прогон без отчётов
```powershell
.\quick_test.ps1
```

### Прогон с выводом отчёта в консоль
```powershell
.\test_runner.ps1
```
Печатает форматированную сводку в консоль (файлы не создаёт).

### Прогон с сохранением отчёта в файл
```powershell
.\test_runner_clean.ps1
```
Сохраняет отчёт в `test_reports/clean_report_<дата-время>.txt` (папка создаётся автоматически).

## Что именно тесты гарантируют (контракты)

### Сообщения (чат)
- Входящий `chat`:
  - расшифровывается через криптосервис
  - сохраняется в БД как входящее непрочитанное (`isSentByMe=false`, `isRead=false`, `status=delivered`)
  - уведомление в фоне показывается **без текста сообщения** (только имя отправителя)
  - системные call-status сообщения (`Исходящий звонок`/`Входящий звонок`/`Пропущен звонок`) **не поднимают** уведомление

### Звонки (сигналинг)
- Входящий `call-offer`:
  - поднимает уведомление о звонке
  - открывает экран звонка
- `ice-candidate`:
  - **буферизуется** (может прийти раньше `call-offer`) и не должен теряться
- `hang-up` / `call-rejected`:
  - в обработчике сначала отправляется сигнал в `CallScreen`, затем скрывается call-уведомление (чтобы скрытие уведомления не блокировало завершение звонка)

### Исходящие пакеты (протокол)
- `sendChatMessage(...)` формирует JSON с `type=chat`, `recipient_pubkey`, `payload`
- `sendSignalingMessage(...)` формирует JSON с `recipient_pubkey`, `type`, `data`
- Для критичных сигналов `hang-up` / `call-rejected` включена гарантия доставки: **WS + HTTP fallback**

## Что пока НЕ покрыто тестами (приоритет)

### Высокий приоритет (критичные сценарии)
- `lib/call_screen.dart`: состояния звонка (Incoming/Dialing/Connecting/Connected), отправка `hang-up`/`call-rejected` при закрытии, системные сообщения в чат
- `lib/chat_screen.dart`: отправка сообщения, очистка истории, поведение при ошибке шифрования/отправки
- `lib/services/webrtc_service.dart`: логика очереди ICE/SDP (частично тестируется косвенно, но не покрыта unit-тестами)
- `lib/services/notification_service.dart`: поведение FCM/local notifications (требует моков Firebase/Notifications)

### Средний приоритет
- `lib/services/auth_service.dart` + PIN/duress/lock/wipe сценарии (часть логики сейчас не закреплена unit-тестами)
- `lib/services/panic_wipe_service.dart`
- `lib/services/pending_actions_service.dart`
- `lib/services/background_call_service.dart`

## Что уже закреплено unit-тестами (контракты)

### Безопасность
- `AuthService` (PIN/duress/wipeCode/autoWipe + storage roundtrip): `test/services/auth_service_test.dart`
- `SecurityConfig` (lockout ladder по ADR 0003 + сериализация): `test/models/security_config_test.dart`
- `PanicWipeService` (3 быстрых ухода в фон → wipe): `test/services/panic_wipe_service_test.dart`

### Pending actions
- `PendingActionsService` (pending call rejections: дедупликация/очистка/устойчивость к ошибкам): `test/services/pending_actions_service_test.dart`

### Звонки (простые контракты)
- `IncomingCallBuffer` (буферизация ICE до offer): `test/services/incoming_call_buffer_test.dart`
- `CallStateService` (флаг активного звонка): `test/services/call_state_service_test.dart`
- `BackgroundCallService` (foreground service на время звонка): `test/services/background_call_service_test.dart`
- `CallSessionController` (контрактный lifecycle CallScreen: hang-up/reject + системные сообщения): `test/services/call_session_controller_test.dart`

### WebRTC (контракты гонок)
- Очередь remote ICE кандидатов до установки remote SDP: `test/services/webrtc_candidate_queue_test.dart`
- Интеграция очереди с WebRTCService (ICE до/после SDP + reset на hangUp): `test/services/webrtc_service_queue_integration_test.dart`

### Уведомления (локальные контракты)
- `NotificationService` (каналы + call/message + privacy + best‑effort): `test/services/notification_service_test.dart`

### Чат (контракты форматирования и отправки)
- `ChatTimeRules` (Сегодня/Вчера/дата, разделители, скрытие времени в одну минуту): `test/services/chat_time_rules_test.dart`
- `ChatSessionController` (send/clear/read, статусы sent/failed): `test/services/chat_session_controller_test.dart`

## Где лежат тесты
- `test/models/` — модели
- `test/services/` — сервисы
- `test/widgets/` — widget-тесты

## Каталог тестов (для отчёта/инвестора)

Сводный список тестовых наборов с кратким описанием (1 строка на файл): `docs/testing/TEST_CATALOG.md`

## Примечание про документацию/логи
- `AI_WORKLOG.md` — **журнал** действий (не “истина” про текущее поведение).
- Актуальная документация проекта — в `docs/` (см. `docs/README.md`).


