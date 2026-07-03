# AI Worklog

Журнал действий по изолированному треку `wl/dev` (независимая версия клиента,
работаем на актуальном Flutter; upstream `master` не трогаем).

---

## 2026-07-03 — SECURITY-fix: заблокированный телефон авто-отвечал на звонок

Симптом владельца (device-тест): входящий на ЗАБЛОКИРОВАННЫЙ телефон сам поднимал
трубку (на разлоченный — нет). Лог приёмника: `🔔 Local notification tap:
{type:incoming_call,...}` -> сразу `--- [WebRTC] ANSWERING CALL ---`.

Причина: `NotificationService.onIncomingCallFromNotification` (main.dart:220) звал
`_navigateToCallScreen(..., autoAnswer: true)`. Уведомление входящего показывается с
`fullScreenIntent: true` (notification_service.dart:558); на локскрине система САМА
запускает full-screen активити и дёргает этот колбэк БЕЗ нажатия -> autoAnswer:true ->
трубка поднималась автоматически (собеседник мог слышать окружение). На разлоченном
fullScreenIntent не авто-запускается, ответ идёт через CallKit-кнопку -> бага нет.

Фикс: тап/полноэкранный показ уведомления -> `autoAnswer: false` (открываем звонящий
экран, ждём «Ответить»). Реальный CallKit accept (`_handleCallKitAccept`,
main_callkit.dart:253) остаётся `autoAnswer: true` — там это корректно (юзер нажал
«Ответить»). Проверки: analyze 0, test 353. Требует device-подтверждения.

## 2026-07-03 — Приватность имени звонящего на локскрине (по запросу владельца)

Владелец: показывать имя контакта на локскрине — утечка (видно, КТО звонит).
Дизайн: заблокировано -> нейтральная подпись «Закрытая связь» / «Secure connection» (без
имени/ключа), разблокировано -> имя; + настройка-флаг (по умолчанию ВЫКЛ).

Сделано:
- Нативно: `MainActivity` settings-канал -> `isDeviceLocked` (KeyguardManager.isKeyguardLocked).
- `DeviceSettingsService`: `isDeviceLocked()` + флаг `showCallerNameWhenLocked` (SharedPrefs).
- Оба пути показа CallKit применяют гейт: `notification_service._showNativeIncomingCall`
  (push) и `incoming_message_handler._showCallKitIncoming` (WS). При locked && !флаг ->
  nameCaller = l10n.incomingEncryptedCall, handle = '' (не светим и префикс ключа).
- l10n: incomingEncryptedCall, callerNameOnLockTitle/Desc (en+ru, gen-l10n).
- UI: тумблер в `security_settings_screen` (_buildSwitchTile + async load флага).
- Публичный `NotificationService.incomingEncryptedCallLabel()` (WS-путь не лезет к
  @visibleForTesting notificationL10n).

Требует device-проверки: locked -> нейтральная подпись; unlocked -> имя; флаг ON ->
имя на locked. Проверки: analyze 0, test 353.

**Fix после device-теста:** первая версия использовала keyguard-проверку через
method-channel — но входящий на ЗАБЛОКИРОВАННОМ телефоне обрабатывается в ОТДЕЛЬНОМ
push-изоляте, где канал к MainActivity недоступен -> isDeviceLocked падал в catch,
возвращал false -> имя показывалось (лог: «звонок от Самсунг»). Переведено на флаг
`app_in_foreground` в SharedPreferences: пишет main-изолят по lifecycle
(+ начальное значение в initState), читают оба пути показа через
`hideCallerIdentityOnIncoming()` с `prefs.reload()` (prefs кешируются per-isolate).
Имя показываем ТОЛЬКО когда Orpheus реально на переднем плане; лок/сворачивание/
убито -> нейтрально. Флаг настройки перекрывает.

## 2026-07-03 — Device-тест звонков: улов багов (Samsung<->Pixel)

Прогон звонков между двумя телефонами. Подтверждено рабочим: полноэкранный входящий
ПОВЕРХ локскрина (фикс showWhenLocked не сломал звонки), звук двусторонний.

Найдено 3 бага:
- **B (починен): имя звонящего = префикс ключа.** Push-путь показа CallKit
  (`notification_service._showNativeIncomingCall`) брал имя из пуша (сервер имён не
  знает) -> префикс ключа "4UhYCcXl". Фикс: резолв локального имени из БД
  (getContact.name, best-effort, timeout 1с, фолбэк на префикс). WS-путь
  (`incoming_message_handler`) это уже делал.
- **A (в работе): задвоенное уведомление «In call» на звонящем** (Orpheus + префикс
  ключа) — foreground-сервис + CallKit? Нужны логи звонящего (Samsung).
- **C (в работе, критично): экран звонка авто-закрывается при гашении экрана.** Лог:
  Connected -> ICE Disconnected -> Failed за ~17с после лока. Реконнект не пережил
  background (троттлинг таймеров/деградация связи) -> onError -> onFatal -> _safePop
  закрыл экран -> показался home. Пользователь принял за «окно не восстановилось».
  Нужен отдельный тест реконнекта в FOREGROUND (смена сети без гашения экрана),
  чтобы отделить логику реконнекта от проблемы бэкграунда.

## 2026-07-03 — Fix: чужой call-rejected рвал соединённый звонок (device-тест)

Симптом владельца: звонок на заблокированный телефон «один сигнал и вырубился».
Лог: звонок Connected -> через ~1с звонящий Dispose+hang-up. Причина: обработчик
сигналов `hang-up`/`call-rejected` (call_screen.dart:437) звал `_onRemoteHangup()`
БЕЗ проверки call_id -> завершал ЛЮБОЙ звонок. Устаревший `call-rejected` от
предыдущего захода (тайаут-reject локскрина, долетевший поздно по HTTP-fallback)
приходил во время нового соединённого звонка и убивал его. Отправители call_id
прикрепляют (`{'call_id': callId}` / `_attachCallId`). Фикс: игнорируем отбой,
если его call_id задан и НЕ равен текущему `_callId`; при отсутствии call_id —
как раньше (старые клиенты). Проверки: analyze 0, test 353.

## 2026-07-03 — Fix: дубль answer ломал WebRTC-негоциацию (device-тест звонков)

Device-тест звонка (Samsung<->Pixel): в логе `E flutter: setRemoteDescription:
Failed to set remote answer sdp: Called in wrong state: stable` из
`webrtc_service.handleAnswer`. Причина: сигналы шлются по WS И по HTTP-fallback →
answer приходит дважды; второй раз PC уже в stable → необработанное исключение,
из-за которого первая негоциация закрывалась и звонок соединялся только с ретрая
(симптом владельца «оборвался тут же, на Pixel продолжает звонить»). Фикс:
`handleAnswer` применяет answer только при signalingState == have-local-offer
(дедуп дубликата, корректно работает и для ice-restart-answer) + try/catch.

Аудио в звонке при этом работало (Connected -> Completed, ~55с разговора),
двусторонний звук подтверждён. Требует device-ретеста: входящий на ЗАБЛОКИРОВАННЫЙ
телефон (в логе показался как local-notification, а не full-screen CallKit —
отдельно понаблюдать). Проверки: analyze 0.

---

## 2026-07-03 — BT-разрешение: priming вместо пугающего диалога (device-тест)

Пользователь при звонке увидел системный диалог «устройства поблизости… определять
относительное положение» и встревожился. Проверил итоговый манифест: только
`BLUETOOTH_CONNECT` (+ legacy BLUETOOTH), НИКАКИХ BLUETOOTH_SCAN / LOCATION /
NEARBY_WIFI. Т.е. это генерик-формулировка группы «Nearby devices» от Android,
показывается даже для CONNECT; слежки нет. Разрешение нужно только для вывода звука
звонка в BT-гарнитуру (запрашивалось молча в `webrtc_service.initialize`).
Владелец выбрал «оставить + priming». Сделано: убрал `bluetoothConnect` из тихого
запроса webrtc (там только микрофон); в `call_screen` добавил `_maybePrimeBluetooth`
— разовый (prefs-флаг) поясняющий диалог ПЕРЕД системным запросом, показывается с
задержкой после выдачи микрофона. Проверки: analyze 0, test 353.

---

## 2026-07-03 — Fix: приложение поверх системного локскрина (device-тест)

Симптом: просыпаешь заблокированный телефон — сразу виден Orpheus, минуя PIN
устройства. Причина: `AndroidManifest.xml` объявлял `android:showWhenLocked="true"`
+ `android:turnScreenOn="true"` БЕЗУСЛОВНО на MainActivity, хотя onCreate-комментарий
и enableCallMode/disableCallMode задумывали рантайм-управление «только во время
звонка». Манифестные флаги — забытый вестигиальный код. Убраны из манифеста →
дефолт уважает keyguard, показ поверх блокировки остаётся через рантайм
`enableCallMode` (call_screen initState). ТРЕБУЕТ device-проверки: (а) разбудил
локскрин — виден keyguard телефона, не Orpheus; (б) ВХОДЯЩИЙ ЗВОНОК всё ещё
показывается поверх локскрина (рантайм-путь).

---

## 2026-07-03 — Строгая блокировка на background (по запросу владельца)

`didChangeAppLifecycleState`: в ветке `paused` теперь сразу `authService.lock()` +
`_isLocked=true` при `isPinEnabled` (раньше только отменяли таймер, лок ставился на
resume по elapsed). Исключение — `hasActiveCall || hasPendingCall` (звонок должен
остаться доступен). Заодно задействована переменная `hasActiveCall`, которая висела
unused после сплита main.dart. Проверки: analyze 0, test 353.
Продуктовый нюанс (озвучен владельцу): звонок на УЖЕ залоченное фоновое приложение
потребует PIN для ответа.

---

## 2026-07-03 — Device-тест на живых устройствах: найдены и починены баги

Прогон release-APK на Samsung + Pixel 7 Pro (GrapheneOS). Подтверждено рабочим:
de-Google (WS-коннект без GMS на чистом GrapheneOS), Oracle/AI + markdown,
все меню настроек, лицензия-активация, анти-скриншот (FLAG_SECURE), авто-лок по
неактивности (лог: armed 60s -> locked ровно через 60s).

**Критический баг (release-блокер) — потеря аккаунта при рестарте.** Причина
исследована агентом (source-verified): дефолтный key-шифр v10
`RSA_ECB_OAEPwithSHA_256andMGF1Padding` генерит ключ с digest только SHA-256, но
расшифровывает с MGF1=SHA-1 → строгий KeyMint (Titan M2 / Knox — НЕ
GrapheneOS-специфика, Samsung тоже падал) отклоняет unwrap приватным ключом на
новом процессе. Запись публичным ключом (софтверно) проходит → "пишется, не
читается после рестарта". Наши resetOnError:false + migrateOnAlgorithmChange:false
превращали это в тупик "нет данных". Фикс (`secure_storage_options.dart`):
keyCipherAlgorithm -> `RSA_ECB_PKCS1Padding` (не задет MGF1, тихий — важно для
фонового чтения ключа БД из push-изолята), resetOnError:true, бамп reset-флага.
Подтверждено на Pixel: закрыл -> открыл -> аккаунт+PIN на месте.

**UI-баги (тоже device-only):**
- Онбординг + бета-дисклеймер (`home_screen`): нескролящийся Column + barrierDismissible:false
  -> кнопка за экраном на маленьком экране/крупном шрифте. Фикс: SingleChildScrollView.
- Экран лицензии (`license_screen`): AppBar с явной кнопкой "назад" на корневом гейте
  -> Navigator.pop в пустой стек -> чёрный экран. Фикс: leading только при Navigator.canPop.
- Setup-диалог уведомлений/питания (`device_settings_service`): весь на хардкод-английском
  + каждый шаг делал Navigator.pop перед открытием настроек Android (диалог исчезал).
  Фикс: локализация RU/EN (~17 строк) + убран Navigator.pop (диалог переживает поход в настройки).

**Апстрим:** завести баг в juliansteenbakker/flutter_secure_storage (OAEP-ключ должен
авторизовать оба digest ИЛИ MGF1=SHA-256). Нельзя починить из Dart — отсюда обход через PKCS1.

Проверки: analyze 0 ошибок, test 353 passed, device-тест на 2 устройствах.

---

## 2026-07-03 — Консолидированный device-чеклист перед релизом

`docs/DEVICE_TEST_CHECKLIST.md` — собраны все device-gated пункты, накопленные за
сессию (то, что нельзя проверить сборкой/тестами): звонки (callkit 3 + контроллер +
реконнект при смене сети + микрофон в фоне + звонок из убитого состояния),
уведомления (local_notifications 22), биометрия/PIN/LOGIC-6 (local_auth 3, монотонная
блокировка), de-Google (доставка без GMS), лицензия оффлайн, minSdk 24 (Android 6
дропнут). Ссылается на SECURE_STORAGE_V10_CHECKLIST.md. Матрица OEM/версий Android.
UI-1 (доступность) и UI-2 (цвета) — отложены по решению владельца.

---

## 2026-07-03 — ARCH-3: разбит god-файл main.dart (1298 → 760)

Блок CallKit + навигации звонка (`_initCallKit`, `_checkActiveCallOnStart`,
`_handleCallKitAccept/Decline`, `_openCallScreenFromCallKit`, `_navigateToCallScreen`,
`processPendingCallAfterUnlock`, `_checkActiveCallOnResumed` — строки 272-807)
вынесен в `main_callkit.dart` через `part`/`part of`. Физический split, одна
библиотека (глобалы/приваты main.dart доступны в part-файле), ноль изменений
логики. Проверки: analyze 0 ошибок (1 предсуществующий unused-local warning вне
блока), test 353 passed, debug APK собран.

С этим ARCH-3 закрыт целиком: все три god-файла разгружены (contacts_screen 1310→433,
call_screen build() 287→90 + логика в контроллер, main 1298→760).

---

## 2026-07-03 — ARCH-3/#1 шаг 3 (Stage B): перепровязка call_screen на контроллер

Виджет `_CallScreenState` переведён на `CallSessionController`.

Приём низкого риска: поля состояния (`_callState/_debugStatus/_networkState/
_wsStatus/_isReconnecting/_reconnectAttempts`) стали ГЕТТЕРАМИ-делегатами к
контроллеру -> все ЧТЕНИЯ (десятки, включая UI) не тронуты, меняли только ЗАПИСИ.
- Создание контроллера в initState (+ `_WebRtcCallOps` — реализация CallOps поверх
  WebRTCService/сигналинга); `addListener(_onControllerChanged)` ПОСЛЕДНИМ (чтобы
  синхронные нач. правки сети/WS не дёргали setState в initState).
- Переходы (`onConnecting/onConnected/onRemoteHangup/onError`), 3 подписки
  (сеть/WS/onIceRestartNeeded), входящий ICE-restart (`setDebugStatus`) -> контроллер.
- Удалены `_handleNetworkLost/_handleNetworkRestored/_attemptIceRestart` (в
  контроллере); осталась WebRTC-операция `_performIceRestart` за `CallOps`.
- dispose: removeListener + controller.dispose (стопит запланированные повторы).

**Адверсариал-ревью Stage B поймало 2 РЕАЛЬНЫХ регресса реконнекта — исправлены:**
1. (#1, major) запланированный повтор при ws-down ставился на 2с < дебаунса 3с ->
   всегда съедался, реконнект умирал после 1 попытки. Фикс: split на debounced
   `attemptIceRestart` (внешние триггеры) + `_runIceRestart` (повторы, минуя дебаунс).
2. (#2) внутренний max-attempts путь звал `controller.onError` минуя `_safePop` ->
   экран не закрывался. Фикс: callback `onFatal` (единый путь авто-закрытия для
   прямых ошибок И исчерпания попыток).
Плюс `_notify()` с гуардом `_isClosed` (нет throw notifyListeners после dispose).

**Повторное ревью фиксов:** оба регресса CONFIRMED-FIXED, `_notify`-гуард sound.
Нашло один НОВЫЙ минорный race: раз повторы минуют дебаунс, внешний триггер мог
совпасть с запланированным повтором -> две параллельные цепочки. Закрыто флагом
`_iceRestartInFlight` (try/finally вокруг `_runIceRestart`). На фиксы+гвард добавлено
4 теста (повтор не дебаунсится, onError->onFatal, exhaustion->onFatal, in-flight гвард).

**ОСТАЁТСЯ (device-gated, перед релизом):** прогон реального звонка — слышимость,
реконнект при смене Wi-Fi<->cellular, звонок из убитого состояния, авто-закрытие.

Проверки: analyze 0 ошибок, test 353 passed, debug APK собран, адверсариал-ревью x2.

---

## 2026-07-03 — ARCH-3/#1 шаг 2: CallSessionController + тесты (dead code)

Поэтапный вынос логики звонка (по выбору владельца: сначала контроллер+тесты как
отдельный модуль, потом перепровязка виджета — чтобы rewire шёл по проверенному коду).

Создано:
- `lib/services/call_session_controller.dart` — `CallSessionController extends
  ChangeNotifier`: домен-enum `CallState`, машина состояний (initialStateFor,
  onNetworkLost/Restored, onConnected, onRemoteHangup, onError, statusText) и
  политика ICE-restart (attemptIceRestart: дебаунс 3с, лимит 5 попыток, повторы
  через инжектируемый scheduler, ожидание WS). Внешние операции за узким
  инъектируемым `CallOps` (restartIce) — это и есть peer-интерфейс из TEST-4.
  Часы и планировщик тоже инжектятся -> всё юнит-тестируемо.
- `test/services/call_session_controller_test.dart` — 17 тестов: initialStateFor,
  statusText-маппинг, guard onNetworkLost (только из Connected), сброс на
  onConnected, Rejected/Failed, инкремент попыток, дебаунс, исчерпание->Failed,
  ws-not-connected->повтор, восстановление WS->рестарт, no-op вне реконнекта.

Логика 1-в-1 с виджетом (мирроринг прочитанного `_CallScreenState`). Контроллер
НЕ подключён к call_screen — dead code, нулевой риск для живого пути звонка.

**Следующий шаг (Stage B):** перепровязать `_CallScreenState` на контроллер
(setState -> слушатель, глобалы -> реализация CallOps поверх WebRTCService/
websocketService), затем адверсариал-ревью + прогон звонка на устройстве.

Проверки: analyze 0 ошибок, test 347 passed (+17).

---

## 2026-07-03 — ARCH-3/#1 шаг 1: разбит build() экрана звонка (287 строк)

Первый (безопасный) шаг рефактора call_screen (вариант #1 — вынос логики в
контроллер). Монстр-`build()` (287 строк) разбит на `_buildStatusSection()`,
`_buildAvatar()`, `_buildAudioVisualizer()`, `_buildDebugOverlay()`. Чистая
экстракция под-виджетов — дерево идентично, логика не тронута. build() теперь ~90
строк. Проверки: analyze 0 ошибок, test 330 passed, debug APK собран.

Следующие шаги #1: (шаг 2) безопасные извлечения (статус-сообщения в чат, медиа-
контролы); (шаг 3) вынос машины состояний + сигналинга + ICE-restart в
`CallSessionController` С НОВЫМИ юнит-тестами (закрывает TEST-4) + адверсариал-ревью.

---

## 2026-07-03 — ARCH-3: разбит god-файл contacts_screen (1310 → 433)

Приватные виджет-классы (`_ContactRow`, `_Avatar`, `_UnreadPill`, `_AddContactDialog`,
`_ContactActionsSheet`, `_ActionTile`, `_DeleteContactDialog`, `_OracleContactRow`,
`_OracleAvatar`, `_AddContactHint`) вынесены в `contacts_screen_widgets.dart` через
`part`/`part of` — физический split, одна библиотека, ноль изменений видимости/логики.
Экран (state) теперь 433 строки вместо 1310. Проверки: analyze 0 ошибок, test 330 passed.

---

## 2026-07-03 — ARCH-1: разрыв цикла AuthService ↔ DatabaseService (крупный рефактор)

**Задача:** разорвать циклическую зависимость двух ядровых сервисов безопасности
(БД читала `AuthService.instance.isDuressMode`, auth импортировал БД для wipe).

**Сделано (инверсия зависимости, поведение не меняется):**
- `database_service.dart`: убран `import auth_service`; геттер
  `_isDuressMode => AuthService.instance.isDuressMode` → плоское поле
  `bool _isDuressMode = false` + `setDuressMode(bool)`. БД про AuthService не знает.
- `auth_service.dart`: единый `_setDuressMode(value)` = поле + push в
  `DatabaseService.instance.setDuressMode`. Все 6 переходов duress (verifyPin
  success/duress, disableDuressCode, lock, exitDuressMode, performWipe) идут через него.
- Цикл разорван: остаётся ОДНОнаправленная auth→database (была и раньше, для wipe).

**Перепроверка критичного (по просьбе владельца):** запущен адверсариал-ревьюер на
duress-корректность. Вердикт — в проде утечки НЕТ, поведение эквивалентно: набор
guard-методов не менялся; push синхронный/атомарный с auth-флагом (нет гонки);
duress рантайм-only (не персистится → оба стартуют false); БД — единственный
consumer скрытия данных. Единственная находка — тест-гигиена (fail-safe): тест-инстанс
через createForTesting пушит в DB-синглтон → добавлен `tearDown` со сбросом в
`auth_service_test.dart`.

**Проверки:** analyze 0 ошибок; test 330 passed (включая duress); + адверсариал-ревью.

---

## 2026-07-02 — UI-9: отладочный лог-оверлей звонка спрятан в release

`call_screen.dart`: скрытая кнопка (тап по «Secure Call») открывала оверлей с
сигналинг/ICE-логами. Переключатель (`onTap`) и рендер оверлея (`if (...)`)
загейчены за `kDebugMode` — в release недоступны. Импорт `foundation` (kDebugMode).
Проверки: analyze 0 ошибок.

QUAL-9 (инлайн-changelog в config.dart) НЕ трогал: `changelogData` — живой
offline-fallback в updates_screen (+ config_test), удаление сломает офлайн-changelog.
Правило config.dart запрещает *добавлять* записи, а не хранить fallback.

---

## 2026-07-02 — LOGIC-6: блокировка брутфорса по монотонным часам

**Задача:** прогрессивная блокировка PIN считалась по `DateTime.now()` — обходится
переводом системных часов вперёд.

**Сделано (минимальный, низкорисковый фикс — хардним только сам гейт):**
- Нативно: `MainActivity` → метод `getElapsedRealtime` в settings-канале
  (`SystemClock.elapsedRealtime`). Dart-обёртка `lib/services/monotonic_clock.dart`
  (`MonotonicClock.elapsedRealtimeMs()` → int?, null при ошибке).
- `security_config.dart`: поле `lastFailedElapsedMs` (persist) + метод
  `isLockedOutMonotonic(nowElapsedMs)` — по монотонным часам, с fallback на wall-clock
  `isLockedOut` (если null или ребут: nowElapsed < сохранённого).
- `auth_service.dart`: инъекция `monotonicNow` (тест-seam), запись elapsedRealtime в
  `_incrementFailedAttempts`, гейт `verifyPin` → `isLockedOutMonotonic(await _monotonicNow())`.
- lock_screen НЕ трогали: его `isLockedOut` для UI (косметика) — под тампером покажет
  клавиатуру, но verifyPin отклонит; для обычного юзера wall==mono, консистентно.
- Тесты: 5 новых на `isLockedOutMonotonic` (тампер/ребут/fallback); в 3 виджет-теста
  добавлен `monotonicNow: () async => 0` (реальный канал не резолвится под fake-async).

**Проверки:** analyze 0 ошибок; test 330 passed (+5); debug APK — ок.

---

## 2026-07-02 — DEP-3: flutter_markdown → flutter_markdown_plus

`flutter_markdown` заброшен (Flutter-команда прекратила поддержку). Заменён на
поддерживаемый форк `flutter_markdown_plus` ^1.0.7 (drop-in: `MarkdownBody`/
`MarkdownStyleSheet`/`onTapLink` идентичны, сменился только импорт в
`ai_assistant_chat_screen.dart`). Убрано единственное discontinued-предупреждение.
Проверки: analyze 0 ошибок, test 325 passed.

---

## 2026-07-02 — Обновление всех зависимостей + ADR по secure_storage

Задача владельца: зафиксировать решение по secure_storage в доках и обновить ВСЕ
зависимости.

**ADR:** `docs/DECISIONS/0004-secure-storage-v10-migration.md` — зафиксирован выбор
(честный переход на современные шифры v10, данные v9 в жертву).

**Фаза 1 (в пределах мажоров, `flutter pub upgrade`, без ломающих изменений):**
flutter_webrtc 1.2→1.5.2 (DEP-12), cryptography 2.7→2.9, dio 5.9→5.10, http 1.5→1.6,
audioplayers 6.5→6.8, path_provider/shared_preferences/uuid/cupertino_icons/
flutter_native_splash — патчи; dev: build_runner 2.10→2.15, mockito 5.6→5.7,
sqflite_common_ffi 2.3→2.4. Проверки: analyze 0 ошибок, test 325 passed, debug APK — ок.

**Фаза 2 (мажоры) — СДЕЛАНО.** Обновлены все мажоры разом; breaking changes по
каждому пакету исследованы параллельным workflow (10 агентов, по source-тегам +
GitHub changelogs), правки применены по точным новым API.

Правки кода:
- **flutter_callkit_incoming 2→3:** `CallEvent` — sealed class с подклассами
  (`CallEventActionCallAccept(:final callKitParams)` и т.д.) вместо `event.event/body`;
  onEvent переписан на pattern-matching (main.dart), хендлеры не тронуты — форма body
  реконструируется хелпером `_callKitParamsToBody`. `textAccept/textDecline` переехали
  из `CallKitParams` в `AndroidParams` (notification_service + incoming_message_handler).
  `activeCalls()` → `List<CallKitParams>` (доступ `.id`/`.extra` вместо `['id']`/`['extra']`).
- **flutter_local_notifications 17→22:** `initialize/show/cancel` — позиционные →
  именованные параметры (5 мест в notification_service). Конструкторы не менялись.
- **local_auth 2→3:** `authenticate(options: AuthenticationOptions(stickyAuth:...))` →
  плоские `persistAcrossBackgrounding:`/`biometricOnly:` (lock_screen, security_settings,
  settings).
- **share_plus 10→13:** `Share.share(...)` → `SharePlus.instance.share(ShareParams(...))`
  (deprecation, 2 места).
- Без правок кода: permission_handler 12, connectivity_plus 7, device_info_plus 13,
  package_info_plus 10, rxdart 0.28, sentry_flutter 9, flutter_lints 6 (API не задет).

Build/toolchain (форсят зависимости):
- **minSdk 23 → 24** (`maxOf(24, flutter.minSdkVersion)`) — Android 6.0 больше не
  поддерживается (форсят local_notifications 22 + local_auth 3). Продуктовое решение.
- desugar_jdk_libs 2.0.4 → 2.1.4 (local_notifications 19+).
- AGP 8.9.1 → 8.12.1, Gradle wrapper 8.12 → 8.13, Kotlin 2.1.0 → 2.2.20
  (форсят connectivity_plus/device_info_plus/package_info_plus/share_plus).

**ТРЕБУЕТ ПРОВЕРКИ НА УСТРОЙСТВЕ (5 мажоров notifications + callkit rewrite):**
входящий звонок из убитого состояния (CallKit из push-сервиса), full-screen с локскрина,
показ/тап уведомлений + каналы, биометрия, вход по PIN; на Android 13/14/15 и OEM.
API 23 (Android 6.0) устройства теперь не поддерживаются.

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 325 passed; `flutter build
apk` (debug) — см. коммит.

---

## 2026-07-02 — DEP-1: flutter_secure_storage 9 → 10 (безопасный мост)

**Задача:** подготовить апгрейд самого security-критичного пакета (хранит
X25519-ключи, хэши PIN/duress/wipe, ключ шифрования БД) с чеклистом под девайс.

**Research (multi-agent, по source-тегам v9.2.4/v10.3.1 + live GitHub issues):**
v10 стабилен (10.3.1), но ДЕФОЛТНЫЙ путь 9→10 = документированная потеря данных
для нашей конфигурации (дефолтные опции, невосстановимые ключи): v10 сменил шифры
(ключ PKCS1→OAEP, данные CBC→GCM) и по умолчанию `resetOnError: true` +
`migrateWithBackup: false` → сбой авто-миграции безвозвратно стирает storage
(issues #1043, #1079 — в проде, unrecoverable). Мы использовали
`const FlutterSecureStorage()` без опций — худший случай.

**Решение владельца:** данными можно пожертвовать (закрытая бета) → делаем ЧЕСТНЫЙ
переход на современные шифры, а не временный мост.

**Сделано (реальная миграция на современные шифры):**
- `pubspec.yaml`: `^9.0.0` → `^10.3.1`.
- `lib/services/secure_storage_options.dart`: единые опции (современные шифры v10
  по умолчанию — OAEP + GCM; `resetOnError: false`, `migrateOnAlgorithmChange: false`)
  + общий `appSecureStorage`. Плюс `ensureSecureStorageMigrated()` — одноразовый
  детерминированный `deleteAll()` (флаг `secure_storage_v10_reset_done` в prefs).
- `main.dart`: `ensureSecureStorageMigrated()` вызывается ДО первого чтения ключей
  (перед `cryptoService.init()`). Так старый формат v9 стирается ДО того, как v10
  попробует свою (крашащую) авто-миграцию.
- Все 3 места (crypto_service, auth_service, database_service) → `appSecureStorage`.
- API read/write/delete/deleteAll не менялся; `minSdk` 23 (v10 требует 23) — без бампа.
- `docs/SECURE_STORAGE_V10_CHECKLIST.md` переписан под этот путь (главный тест —
  обновление v9→v10 ПОВЕРХ: старт без краша, старый аккаунт чисто стёрт, новый
  заводится, вход по PIN, wipe).

**Последствие (согласовано):** существующие бета-пользователи теряют старый аккаунт,
создают новый. Никакого костыля/deprecated-шифра — сразу v11-совместимый формат.
См. [[secure-storage-v10-bridge]].

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 325 passed; `flutter
build apk` (debug) — успешно (нативный v10.3.1, compileSdk 36). Поведение на железе
подтверждается чеклистом — до этого не релизить существующим пользователям.

---

## 2026-07-02 — PERF-1 (финал): пагинация начальной загрузки чата

**Задача:** остаток PERF-1 — при открытии чата грузилась вся история. Инкрементальный
append для входящих уже был сделан ранее; здесь — начальная загрузка страницами.

**Сделано:**
- `database_service.dart`: `getMessagesForContactLatest(key, limit)` (последние N,
  ORDER BY DESC LIMIT + reverse→ASC) и `getMessagesForContactBefore(key, beforeMs, limit)`
  (старше метки, для подгрузки вверх). Оба поверх индекса `(contactPublicKey, timestamp)`.
- `chat_screen.dart`: `_loadChatHistory` грузит последнюю страницу (50); scroll-listener
  `_onScroll` у `maxScrollExtent` (reverse=true → старое сверху) вызывает `_loadOlder`,
  который prepend-ит старую страницу (дедуп по messageId). Prepend при reverse=true
  скролл-стабилен. `_hasMoreOlder`/`_isLoadingOlder` гварды.

**ТРЕБУЕТ ПРОВЕРКИ НА УСТРОЙСТВЕ:** плавность подгрузки вверх и отсутствие «прыжков»
на реальной длинной истории (логика скролл-стабильна by design, но UX стоит увидеть).

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 325 passed.

---

## 2026-07-02 — PROD-5: меню «…» в чате вместо one-tap очистки

**Задача:** кнопка «…» (иконка меню) сразу открывала подтверждение очистки истории —
вводило в заблуждение и опасно.

**Сделано:** `chat_screen.dart` — `_showChatMenu()` (bottom sheet): «Информация о
контакте» + «Очистить историю». `_showContactInfo()` показывает имя + полный
публичный ключ (SelectableText, для сверки против MITM) + подсказку `verifyKeyHint`
+ копирование. Кнопка «…» теперь зовёт меню, а не очистку напрямую. Добавлены
l10n-ключи `contactInfo`/`verifyKeyHint` (EN/RU). Крипто не задействовано — просто
показ хранимого ключа (сверка ключей = базовая защита от MITM для E2E).

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 325 passed.

---

## 2026-07-02 — PROD-4: время последнего сообщения в строке контакта

**Решение владельца:** показывать ТОЛЬКО время + сортировку, БЕЗ текста
последнего сообщения (приватность: контент не светим на главном экране; duress).

**Сделано:**
- `contact_model.dart`: добавлено поле `lastMessageTime` (epoch ms, не персистится).
- `database_service.getContacts()`: уже сортировал по `MAX(m.timestamp)` — теперь
  это значение возвращается в модель (0 → null).
- `contacts_screen.dart` `_ContactRow`: вместо хвоста pubkey — компактное
  локализованное время (`_formatLastTime`: сегодня → HH:mm, этот год → «12 июн.»,
  иначе dd.MM.yyyy). У контактов без переписки строка времени скрыта.

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 325 passed.

---

## 2026-07-02 — PROD-3: поиск по контактам

**Сделано:** `contacts_screen.dart` — иконка поиска в AppBar (toggle), поле поиска
над списком, фильтр по имени в памяти. При активном поиске Оракул и empty-hint
скрыты, пустой результат → `noContactsFound`. Добавлены l10n-ключи
`searchContactsHint`/`noContactsFound` (EN/RU), перегенерирован l10n.

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 325 passed.

---

## 2026-07-02 — Desktop Link удалён (PROD-1/ARCH-5/SEC-9), вариант A

**Задача:** решить судьбу Desktop Link. Решение владельца — удалить сейчас (вариант A),
переделать безопасно потом, после клиента и сервера.

**Сделано:**
- Удалены `lib/screens/desktop_link_screen.dart`, `lib/services/desktop_link_service.dart`,
  `lib/services/desktop_link_server.dart`, `lib/models/desktop_session_model.dart`,
  `test/services/desktop_link_service_test.dart`.
- Убраны 13 l10n-ключей `desktopLink*` из `app_en.arb`/`app_ru.arb`, перегенерирован l10n.
- Доки обновлены: CLAUDE.md, docs/ARCHITECTURE.md, docs/PROJECT_STRUCTURE.md.
- В памяти проекта — план возврата (безопасный протокол) в `desktop-link-future`.

**Почему:** экран был недостижим из UI (мёртвый груз в каждой сборке), протокол
небезопасен (открытый HTTP-обмен токеном, WS-сервер без auth на anyIPv4:8765,
неиспользуемый desktop_pubkey). Десктоп-приложение само ещё «в разработке» — паринговать
не с чем. panic-wipe остаток сессии уже чистил (deleteAll).

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 325 passed (−3 теста
удалённого сервиса); висячих ссылок на desktop_link в коде нет.

---

## 2026-07-02 — PROD-6: онбординг при первом запуске

**Задача:** новый пользователь попадал на пустой экран без объяснения, как
подключиться. Добавить лёгкий one-time онбординг (QR/ID → контакт → PIN).

**Сделано:**
- `home_screen.dart`: `_maybeShowOnboarding()` — диалог из 3 подсказок (ключ/QR,
  добавить контакт, PIN), гейт `onboarding_seen_v1` в SharedPreferences, показ
  один раз после бета-дисклеймера, перед device-settings. Хелпер `_onboardingTip`.
- Строки inline-двуязычные (EN/RU) — консистентно с соседними one-time диалогами
  в этом же экране (бета-дисклеймер, device-settings), стиль через дизайн-токены
  (AppColors.action/AppRadii/AppButton).
- `beta_disclaimer_test.dart`: в моки добавлен `onboarding_seen_v1: true`, чтобы
  онбординг не всплывал во время теста дисклеймера.

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 328 passed.

---

## 2026-07-02 — PROD-2/QUAL-3: тумблер биометрии сделан настоящим

**Задача:** тумблер биометрии показывал «включено», но ничего не сохранял
(`// TODO` в `_toggleBiometrics`), значение отскакивало на перерисовке.

**Сделано:**
- `auth_service.dart`: добавлен `setBiometricEnabled(bool)` (по паттерну
  `setPanicGestureEnabled`) — пишет `isBiometricEnabled` в `SecurityConfig` и
  сохраняет через `_saveConfig()`.
- `security_settings_screen.dart._toggleBiometrics`: при включении после успешной
  биометрии сохраняет флаг (`setBiometricEnabled(true)`), при отказе — тумблер
  остаётся выключенным; при выключении — `setBiometricEnabled(false)`.
- Разблокировка уже читала `config.isBiometricEnabled` (`lock_screen._tryBiometricAuth`),
  поэтому фича работает end-to-end без правок экрана блокировки.

**Проверки:** `flutter analyze` — 0 ошибок; auth-тесты зелёные.

---

## 2026-07-02 — PERF-2: индекс messages.timestamp

**Задача:** авто-очистка истории (`WHERE timestamp < ?`) делала полный скан —
составной индекс `(contactPublicKey, timestamp)` не применялся, т.к. в WHERE нет
ведущего столбца `contactPublicKey`.

**Сделано:** `database_service.dart` — добавлен отдельный
`CREATE INDEX idx_messages_timestamp ON messages(timestamp)` в `_createMessagesTable`
(для новых БД) и миграция `if (oldVersion < 8)` (для существующих). Версия БД 7→8.
CLAUDE.md: «версия 6» → «версия 8 (SQLCipher)».

**Проверки:** `flutter analyze` — 0 ошибок; тесты БД и message_cleanup — зелёные.

---

## 2026-07-02 — OPS-2: постоянный applicationId (click.orpheus.app)

**Задача:** сменить `com.example.orpheus_project` на нормальный reverse-DNS id
до первого релиза (после релиза не меняется; сторы банят com.example).

**Сделано:**
- `android/app/build.gradle.kts`: `applicationId = "click.orpheus.app"`
  (reverse-DNS домена orpheus.click — выбран владельцем).
- Изменён ТОЛЬКО applicationId. `namespace`/Kotlin-package/имена MethodChannel
  (`com.example.orpheus_project/*`) оставлены прежними — они внутренние, магазину
  не видны, а их переименование = крупный риск ради косметики. FileProvider
  authority (`${applicationId}.fileprovider` / runtime `packageName`) остаётся
  консистентной автоматически.
- Смена стала тривиальной после удаления Firebase (не нужна перерегистрация
  google-services).

**Проверка:** `flutter build apk` (debug) — успешно; `aapt dump badging` →
`package: name='click.orpheus.app'`.

---

## 2026-07-02 — Микрофон при свёрнутом приложении во время звонка

**Задача:** восстановить поведение «говорить, когда приложение свёрнуто во время
звонка». После отказа от FCM единый постоянный сервис стал `specialUse` и по
правилам Android 14 (while-in-use, boot/background-старт) не может держать
микрофон. Решение — отдельный короткоживущий нативный `microphone`-сервис,
запускаемый из видимой Activity ответа (паттерн Signal/Molly WebRtcCallService).

**Сделано:**
- Нативный `android/.../CallAudioService.kt` — foreground-сервис типа `microphone`:
  `startForeground(..., FOREGROUND_SERVICE_TYPE_MICROPHONE)` на API 29+, с
  try/catch (сбой старта не роняет звонок), канал `orpheus_call_audio` (LOW),
  `STOP`-экшен. Держит микрофон, пока приложение свёрнуто во время разговора.
- `MainActivity.kt`: в `CALL_CHANNEL` добавлены `startCallAudio(title)` /
  `stopCallAudio` (через `ContextCompat.startForegroundService`, best-effort).
- Манифест: `<service .CallAudioService foregroundServiceType="microphone" exported=false>`
  (permission `FOREGROUND_SERVICE_MICROPHONE` уже был).
- Dart: `CallNativeUiService.startCallAudio/stopCallAudio`; вызовы в
  `call_screen.dart` — старт в `initState` (видимая Activity → старт mic-FGS
  легален), стоп в `dispose`.

**Почему из CallScreen:** microphone-FGS можно стартовать ТОЛЬКО из foreground
(видимый экран). CallScreen при ответе — видимая Activity, поэтому старт легален
и сервис НЕ «прилипает» как запрещённый. Если старт всё же отклонён — тихий
фолбэк: обычный звонок при видимом экране получает микрофон и без FGS.

**ТРЕБУЕТ ПРОВЕРКИ НА УСТРОЙСТВЕ:** реально ли микрофон продолжает работать при
сворачивании во время звонка на Android 12/13/14/15 и на строгих OEM.

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 328 passed;
`flutter build apk` (debug) — успешно (Kotlin-сервис компилируется, манифест
сливается).

---

## 2026-07-02 — Лицензия: убран grace-период кэша (по решению)

**Задача:** упростить модель офлайн-лицензии. Раньше офлайн-доступ давался только
если последняя онлайн-проверка была не старше 21 дня (grace-период с отметкой
времени). Решено убрать таймаут полностью: лицензия проверяется на сервере
(онлайн-отзыв мгновенно выключает), а без сети приложение доступно по кэшу.

**Сделано:**
- `main.dart`: удалены `_licenseGrace` (21 день) и ключ `license_checked_at`
  (отметка времени). `_loadCachedLicense` пускает офлайн по `license_active==true`
  без проверки возраста; `_persistLicense` пишет только флаг, без времени.
- Онлайн-отзыв работает как раньше: WS `license-status` со `status!=active`
  выставляет `_isLicensed=false` и перезаписывает кэш → офлайн запрётся тоже.

**Мотивация (со слов владельца):** лишние вычисления, слежка за временем, расход
ресурсов/батареи. Теперь ничего не «тикает».

**Проверки:** `flutter analyze lib/main.dart` — 0 ошибок.

---

## 2026-07-02 — Де-гуглизация, фаза 3: QR без ML Kit + отказ от FCM

**Задача:** убрать последние проприетарные привязки к Google — закрытый ML Kit в
QR-сканере и Firebase Cloud Messaging (пуши). Курс: клиент без сервисов Google.

**Сделано (QR):**
- `mobile_scanner` (тянул закрытый `com.google.mlkit:barcode-scanning`) → `qr_code_dart_scan`
  (декодирование на чистом Dart через `zxing_lib`, поверх официального `camera`-плагина;
  ноль GMS/ML Kit). `qr_scan_screen.dart`: `MobileScanner` → `QRCodeDartScanView`,
  `onDetect(BarcodeCapture)` → `onCapture(Result)`, ошибка камеры через `onCameraError`.

**Сделано (FCM → постоянный foreground-сервис):**
- Удалены `firebase_core`, `firebase_messaging` (pubspec); плагин
  `com.google.gms.google-services` (оба build.gradle.kts); `google-services.json`;
  firebase-правила ProGuard; FCM-meta-data в манифесте; кастомный `BootReceiver.kt`
  (стартовал Activity — запрещено на Android 10+; автозапуск теперь через boot-receiver
  плагина flutter_background_service).
- `notification_service.dart`: FCM background handler (`firebaseMessagingBackgroundHandler(RemoteMessage)`)
  → публичный `handleBackgroundPush(Map)`; `init()` без FCM (только локальные уведомления +
  Android 13 permission); убраны `fcmToken`, `onTokenUpdated`, FCM-обработчики.
- `websocket_service.dart`: убран `_sendFcmToken()` / сообщение `register-fcm` — WS-сокет
  сам теперь является push-каналом.
- Новый `push_connection_service.dart`: постоянный foreground-сервис (`flutter_background_service`,
  тип `specialUse`, autoStart + autoStartOnBoot). В сервисном isolate — WS-слушатель, который
  приводит WS-кадры к плоскому виду (как раньше FCM data) и вызывает те же
  `_showNativeIncomingCall` / `_handleBackgroundMessage` через `handleBackgroundPush`.
- `background_call_service.dart` → тонкий фасад над `PushConnectionService` (flutter_background_service
  одноинстансный, поэтому «сервис на время звонка» сведён к смене текста постоянного уведомления;
  звонок больше не стартует/останавливает отдельный сервис).
- `main.dart`: старт сервиса + heartbeat main-изолята (`push_main_alive_ts`) и публикация
  публичного ключа (`push_user_pubkey`, не секрет) в SharedPreferences для координации;
  на panic-wipe гасим heartbeat и сервис.
- `call_id_storage.dart`: `sourceFcm`→`sourcePush`, `tryShowCallKitForFcm`→`tryShowCallKitForPush`.

**Архитектура пушей (почему так):** тип `specialUse` — единственный без лимита времени
(dataSync ограничен ~6ч/сутки на Android 15) и разрешённый к автозапуску при загрузке
(microphone/dataSync — нельзя). Микрофон в постоянный сервис не влить: boot-стартованный
сервис не может держать while-in-use микрофон (Android 14) — активный звонок обслуживает
видимый CallScreen. Координация main↔сервис через heartbeat, чтобы не было двух сокетов на
один pubkey.

**КОНТРАКТ БЭКЕНДА (отдельный репозиторий — требуется правка на сервере):**
- Клиент больше НЕ шлёт WS-сообщение `{"type":"register-fcm","token":...}`. Сервер должен
  перестать требовать/использовать FCM-токены и **не** пытаться доставлять через FCM.
- Оффлайн-доставку сервер должен отдавать в WS-сокет при (ре)коннекте (chat уже дедупится по
  `message_id`; call-offer хранить с коротким TTL и уникальным `call_id`/`server_ts_ms`).
- `/api/signal` и `/api/logs/batch` не трогать — уже FCM-free.

**ТРЕБУЕТ ПРОВЕРКИ НА УСТРОЙСТВЕ (нельзя валидировать из репозитория):**
- Доставка входящего звонка/сообщения при УБИТОМ приложении (свайп из recents) — задержка
  перехвата сервисом ≈ порог heartbeat (12с) + тик (4с). Настроить пороги на реальной сети.
- Автозапуск сервиса после ребута (boot-start `specialUse` разрешён, но OEM могут блокировать).
- Xiaomi/Huawei/Oppo/Vivo/Samsung: исключение из энергосбережения (уже есть DeviceSettingsService)
  + ручной автозапуск — без них OEM-киллеры рвут сервис (программного обхода нет).
- Микрофон при сворачивании приложения ВО ВРЕМЯ звонка (постоянный сервис — specialUse без mic).
  Если критично — вынести звонковый микрофон в отдельный нативный `microphone`-сервис
  (запуск из видимой Activity ответа) — задокументированный follow-up.

**Проверки:** `flutter analyze` — 0 ошибок; `flutter test` — 328 passed; `flutter build apk`
(debug и release) — успешно (нативные `camera_android_camerax`, слияние манифеста `specialUse`,
Gradle без google-services). Проверено: release-APK содержит **ноль** классов
`com.google.firebase` / `com.google.mlkit` / `com.google.android.gms`.

**Синхронизация доков:** обновлены README (нет google-services.json), docs/ARCHITECTURE.md
(boot sequence без Firebase + раздел «Пуши без Google»), WORKSPACE_STRUCTURE.md, CLAUDE.md и
устаревшие комментарии «FCM-изолят» → «сервисный изолят».

---

## 2026-07-02 — Де-гуглизация, фаза 1: privacy-правки (без крупной миграции)

**Задача:** первый пакет правок по курсу «клиент без сервисов Google» + смежные
утечки наружу. Безопасные изменения, не трогающие крупные потоки (звонки/пуши).

**Сделано:**
- `android/app/build.gradle.kts` — удалён `firebase-analytics` + `firebase-bom`
  (из Dart не используется, слал события на app-measurement.com по умолчанию).
- `lib/main.dart` — `SentryFlutter.init` теперь под opt-in флагом `telemetry_enabled`
  (по умолчанию наружу ничего); `environment` = `kReleaseMode ? production : development`.
- `lib/screens/status_screen.dart` — регион по локали устройства вместо
  plaintext-запроса к ip-api.com (ARCH-6); удалён неиспользуемый http-клиент/параметр.
- `lib/services/notification_service.dart` — `_sendBackgroundTelemetry` уважает
  opt-in и больше не шлёт `peer_pubkey`/сырой payload (регресс SEC-2).
- `test/widgets/status_screen_test.dart` — убран ip-api мок (регион теперь локальный).

**Проверки:** `flutter analyze` — 0 ошибок; целевые тесты зелёные.

---

## 2026-07-02 — Де-гуглизация: шрифты Inter забандлены локально

**Задача:** курс на клиент без сервисов Google (решение владельца). Первый шаг —
убрать рантайм-загрузку шрифтов с серверов Google; параллельно запущен полный
аудит проприетарных зависимостей (multi-agent workflow).

**Сделано:**
- Пакет `google_fonts` удалён из `pubspec.yaml`. Раньше Inter мог тянуться в
  рантайме с `fonts.gstatic.com` — сетевой след к Google для privacy-мессенджера.
- Inter 4.1 (официальный релиз rsms/inter, лицензия OFL) забандлен статикой:
  `assets/fonts/Inter-{Regular,Medium,SemiBold,Bold}.ttf` + `OFL.txt`, объявлен
  в `pubspec.yaml` (`family: Inter`, веса 400/500/600/700 — все, что использует тема).
- `lib/theme/app_theme.dart`, `lib/theme/app_tokens.dart` — `GoogleFonts.inter(...)`
  → `TextStyle(fontFamily: 'Inter', ...)`; `GoogleFonts.interTextTheme(base)` →
  `base.apply(fontFamily: 'Inter')` (двойное применение family устранено).

**Проверки:** `flutter analyze` — 0 ошибок (616 issues, было 638); `flutter test` —
327 passed / 0 failed.

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

---

## 2026-07-01 — Зелёные тесты: разбор 20 падений (Фаза 2)

**Задача:** довести тест-сьют до зелёного на Flutter 3.44. Было 303 passed / 20 failed
(version-skew, помеченный ранее как следующая задача).

**Диагностика (мульти-агентный разбор по каждому падению):** причины оказались смешанными —
не единый version-skew:
- устаревшие RU-литералы в ассертах после миграции на gen-l10n (`СКАНИРОВАНИЕ QR` → фактически
  `СКАНИРОВАТЬ QR-КОД`; `Неверный PIN-код` → `Неверный PIN`; неразрывный дефис U+2011 в `PIN‑код`);
- забытая локаль в `pumpWidget` (contacts, диалог обновления) → `L10n.of(context)!` кидал null-check;
- строки, захардкоженные по-английски (уведомления, панель звонка, заголовок «История обновлений»);
- диалоги, читавшие язык из глобального синглтона `LocaleService` вместо виджет-дерева;
- реальный дефект каркаса Flutter 3.44 (ListTile без Material-предка) на экране настроек;
- самопротиворечивый тест `getWithFallback` (писан под 2 хоста, а остался один).

**Изменения кода:**
- `lib/services/notification_service.dart` — ВСЕ строки уведомлений двуязычные через gen-l10n
  (звонок, сообщение, чат-сообщение, официальный ответ, тестовое, дефолтное имя, а также CallKit:
  Ответить/Отклонить/Пропущенный/Перезвонить и fallback-уведомление звонка). Фоновый FCM-изолят
  без контекста → добавлен хелпер `notificationL10n()`: резолвит язык по сохранённому `app_locale`
  → системная локаль → `en`, затем `lookupL10n(Locale)`. RU-юзер получает RU, EN — EN.
  (Системные названия Android-каналов не трогаем — регистрируются один раз.)
- `lib/widgets/call/control_panel.dart` — подписи кнопок звонка через `L10n.of(context)`
  (`decline`/`answerCall`/`microphone`/`speaker`/`endCall`).
- `lib/l10n/app_{en,ru}.arb` — добавлены ключи `answerCall`, `microphone`, `newMessage`,
  `unknownCaller` (обе локали); перегенерён `app_localizations*.dart`.
- `lib/updates_screen.dart` — заголовок через `L10n.of(context).updateHistory.toUpperCase()`
  (переиспользован существующий ключ; EN-визуал сохранён).
- `lib/screens/settings_screen.dart` — `_MenuCard`: Column обёрнут в `Material(transparency)`
  (фикс debug-ассерта Flutter 3.44 + видимый ripple).
- `lib/screens/home_screen.dart`, `lib/screens/lock_screen.dart` — язык диалога бета-дисклеймера
  и диалога wipe берётся из `Localizations.localeOf(context)` (в проде эквивалентно синглтону).

**Изменения тестов:** обновлены устаревшие литералы (help/qr/lock), добавлена локаль+делегаты в
pump'ы (contacts, диалог обновления), переписан `getWithFallback` под один хост (+тест на `null`).

**Статус:** `flutter analyze` → 0 errors; `flutter test` → **324 passed / 0 failed**.

**Команды:** `flutter analyze`, `flutter test`.

---

## 2026-07-01 — Шифрование локальной БД (аудит SEC-1) [ветка wl/db-encryption]

**Задача:** первый заход по ремедиации аудита (`AUDIT_REPORT.md`) — закрыть критическую находку
`SEC-1`: локальная БД хранилась в открытом виде, из-за чего PIN/duress/panic-wipe были косметикой.
Директива пользователя: потеря данных допустима (критичных данных нет) → миграцию не делаем.

**Сделано:**
- `pubspec.yaml`: `sqflite` → `sqflite_sqlcipher ^3.4.0` (drop-in API + пароль/PRAGMA key).
- `lib/services/database_service.dart`: ключ шифрования БД — 256 случайных бит (`Random.secure`),
  хранится в Keystore-backed `flutter_secure_storage` (`orpheus_db_key`). `openDatabase(..., password:)`.
  При первом запуске (нет ключа) старая НЕзашифрованная БД удаляется, создаётся свежая зашифрованная.
  В `deleteDatabaseFile()` (panic-wipe) ключ БД тоже удаляется → остаточный шифртекст невосстановим,
  следующий запуск создаёт новый ключ + пустую БД. Логи переведены на `DebugLogger`.
- `android/app/src/main/AndroidManifest.xml`: `allowBackup="false"` + `dataExtractionRules`.
- `android/app/src/main/res/xml/data_extraction_rules.xml`: исключить всё из cloud-backup и
  device-transfer (SEC-7 / DB-2 / OPS-3).
- `test/services/database_service_test.dart`: убран импорт удалённого `package:sqflite/sqflite.dart`
  (типы/фабрика берутся из `sqflite_common_ffi`).

**Дизайн-решение:** ключ БД — случайный в Keystore, НЕ из PIN. Причина: приложение принимает и пишет
сообщения, пока заблокировано (WebSocket под экраном PIN) и в фоне; ключ из PIN там недоступен →
входящие терялись бы. Компромисс: PIN остаётся UI-замком, данные защищает Keystore-ключ (это огромный
шаг от plaintext). PIN-деривация — отдельное продуктовое решение (жертва приёмом в фоне).

**Статус:** `flutter analyze` → 0 errors; `flutter test` → **324 passed / 0 failed**.
Реальная проверка SQLCipher/манифеста — сборка `flutter build apk --debug` (нативные libs + resources).

**Команды:** `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug`.

---

## 2026-07-01 - Телеметрия opt-in + без метаданных (аудит SEC-2) [ветка wl/audit-fixes]

**Задача:** закрыть SEC-2 - телеметрия была включена по умолчанию и слала на сервер публичные
ключи контактов (граф общения) и отпечаток устройства.

**Сделано (lib/services/telemetry_service.dart, переписан):**
- `_enabled = false` по умолчанию; флаг persist в SharedPreferences; `setEnabled()` + `isEnabled`.
- Из выгрузки убраны `peer_pubkey` и `device_info` (отпечаток); `device_info_plus` больше не
  используется в телеметрии. `os` оставлен грубым (android/ios).
- `_sanitizeContext()` вырезает из context ключи-личности контактов перед отправкой.
- Тумблер включения добавлен в скрытый экран отладочных логов (lib/screens/debug_logs_screen.dart).
- `X-Pubkey` оставлен: телеметрия теперь opt-in, владелец включает её для отладки СВОЕГО устройства.

**Статус:** analyze 0 errors; test 324 passed / 0 failed.

---

## 2026-07-01 - Стабильный message_id: дедуп + удалить у обоих (аудит LOGIC-1/2) [ветка wl/audit-fixes]

**Задача:** LOGIC-1 (тихая потеря быстрых входящих из-за 5-сек окна дедупа) и LOGIC-2 («удалить
у обоих» не срабатывало у получателя из-за матча по метке времени). Решение: стабильный `message_id`
(UUID) в конверте, одинаковый у обеих сторон.

**Сделано (8 файлов lib + тесты):**
- `models/chat_message_model.dart`: поле `messageId` (+toMap).
- `services/database_service.dart`: колонка `messageId`; версия 6->7; убран UNIQUE-индекс по timestamp
  (DB-4), добавлены индекс `(contactPublicKey,timestamp)` и UNIQUE `(contactPublicKey,messageId)`;
  методы `deleteMessagesByMessageIds`, `messageExistsByMessageId`; чтение messageId в mapping.
- `services/incoming_message_handler.dart`: дедуп по `message_id` (точный) с fallback на окно для
  старых клиентов; delete-for-both по `message_ids` (fallback timestamps_ms); +2 метода в интерфейс.
- `services/websocket_service.dart`: `message_id` в конверте chat, `message_ids` в delete-for-both,
  проброс через pending-очередь на реконнекте.
- `services/pending_actions_service.dart`: `messageId` в PendingMessage/сериализации.
- `chat_screen.dart`: генерация UUID при отправке (пакет `uuid`, был неиспользуем - DEP-10);
  delete-for-both/self по id.
- `main.dart`: адаптер IncomingMessageDatabase - 2 новых метода.
- Тесты: тест-схемы messages + `messageId`; фейк `_FakeDb` +2 метода; новый тест на LOGIC-1
  (разные id в окне не теряются, одинаковый id - дубль).

**Обратная совместимость:** message_id в открытом виде рядом с зашифрованным payload; старые клиенты
игнорируют лишнее поле; без id - прежнее окно дедупа.

**Статус:** analyze 0 errors; test 325 passed / 0 failed; flutter build apk --debug OK.

---

## 2026-07-01 - Реальный статус исходящих сообщений (аудит LOGIC-3/LOGIC-4/UI-8) [ветка wl/msg-status]

**Задача:** сообщение всегда показывало двойную галку «доставлено», даже при сбое шифрования/
отправки (ошибка молча проглатывалась) - баг доверия.

**Сделано:**
- `chat_screen.dart`: `_sendMessage` теперь стартует со статусом `sending`, при успехе -> `sent`,
  при ошибке (encrypt/send) -> `failed` (раньше `catch (_)` глотал ошибку). Иконка статуса через
  `_buildStatusIcon`: часы/одиночная галка/красный error (двойная галка delivered/read пока не
  используется - сервер релей без квитанций).
- `database_service.dart`: добавлен `updateMessageStatusByMessageId` (обновление по стабильному id).
- Тест: DB-тест на `updateMessageStatusByMessageId` + `deleteMessagesByMessageIds`.

**Статус:** analyze 0 errors; test 326 passed / 0 failed.

---

## 2026-07-01 - Экран приветствия: loading/guard при создании аккаунта (аудит UI-5)

**Сделано (welcome_screen.dart):** `_createNewAccount` - guard от двойного тапа (иначе перегенерация
ключей поверх созданных), `isLoading` на кнопке + блокировка кнопок на время генерации, обработка
ошибки со SnackBar (раньше без loading и без обработки). Импорт-ключа уже закрывал диалог до await
и показывал ошибку - не трогал.

**Статус:** analyze 0 errors; test 326 passed / 0 failed.

---

## 2026-07-01 - Батч: офлайн-лицензия, QR-камера, диалог контакта (аудит LOGIC-8/UI-3/UI-4/UI-7) [ветка wl/audit-fixes-3]

- **LOGIC-8** (`main.dart`): кэш подтверждённой лицензии в SharedPreferences (`license_active`);
  `_loadCachedLicense()` пускает офлайн-пользователя сразу (guard `!_isCheckCompleted` - онлайн-ответ
  в приоритете); `_persistLicense()` на license-status/payment-confirmed/подтверждении на экране.
- **UI-3** (`qr_scan_screen.dart`): `MobileScanner.errorBuilder` -> экран «нет доступа к камере» +
  кнопка «Открыть настройки» (`openAppSettings`, permission_handler). l10n: cameraAccessDenied/openSettings.
- **UI-4/UI-7** (`contacts_screen.dart`): `_AddContactDialog` -> StatefulWidget: валидация (пустые поля /
  формат ключа base64x32), блокировка кнопок + loading на время сохранения, инлайн-ошибка + try/catch.
  l10n: fillAllFields/invalidPublicKey.

**Статус:** analyze 0 errors; test 326 passed / 0 failed; flutter build apk --debug OK.

---

## 2026-07-01 - Лицензия: grace-период 21 день (уточнение LOGIC-8 после обсуждения отзыва)

По обсуждению с владельцем: бессрочный кэш лицензии не давал отозвать лицензию у вечно-офлайн
устройства. Решение - grace-период 21 день.

**main.dart:** к кэшу `license_active` добавлена отметка `license_checked_at` (время последней
онлайн-проверки). `_loadCachedLicense` пускает офлайн только если проверка была <= 21 дня назад;
`_persistLicense` пишет метку времени при каждом ответе сервера. Онлайн-отзыв - мгновенный
(перезапись кэша на inactive), вечно-офлайн отозванная лицензия запрётся максимум через 21 день.

**Статус:** analyze 0 errors; test 326 passed / 0 failed.

---

## 2026-07-01 - Производительность: инкрементальный чат + debounce контактов (аудит PERF-1/PERF-3) [ветка wl/perf]

- **PERF-1** (`chat_screen.dart` + `database_service.dart`): вместо перечитывания всей переписки на
  каждое входящее - `getMessagesForContactAfter(afterMs)` + `_appendNewMessages()` дописывают только
  новое (дедуп по messageId). Вынесен общий маппер строки `_rowToMessage`. Пагинация начальной
  загрузки (скролл вверх) - отдельный follow-up.
- **PERF-3** (`contacts_screen.dart`): обновление списка на события `messageUpdateController`
  debounce-ится (400мс) через `_scheduleRefresh` - пачка входящих не пере-агрегирует всю таблицу.
- Тест: DB-тест на `getMessagesForContactAfter`.

**Статус:** analyze 0 errors; test 327 passed / 0 failed.

---

## 2026-07-01 - Гигиена логирования в release (аудит QUAL-1/OPS-6) [ветка wl/log-hygiene]

**Задача:** структурированные логи и голые print уходили в системный logcat в release, включая
события безопасности (duress/wipe/неверный PIN) и дамп security-конфига с хэшами.

**Сделано:**
- `debug_logger_service.dart`: `print` в `DebugLogger.log` обёрнут в `if (kDebugMode)` - в release
  логи не идут в logcat (остаются в RAM-буфере для in-app экрана + телеметрии). Гейтит 218 лог-сайтов.
- `auth_service.dart`: 10 чувствительных `print` -> `DebugLogger` (гейтнуто). Дамп `$_config`
  (хэши/соль) убран полностью - не пишем даже в буфер.
- `main.dart`: убраны из логов префикс публичного ключа и состояние PIN при старте.
- Остальные ~200 операционных `print` (websocket/notification/database/...) - follow-up QUAL-7.

**Статус:** analyze 0 errors; test 327 passed / 0 failed.

---

## 2026-07-01 - Чистка мёртвого кода (аудит ARCH-4/QUAL-2/DEP-9) [ветка wl/deadcode]

Верифицировано grep-ом, что не используется, и удалено:
- `lib/main_test.dart` (183 строки) - осиротевшее WebRTC-тест-приложение (свой main/runApp) в lib/.
- `lib/services/call_session_controller.dart`, `chat_session_controller.dart` - пустые заглушки (1 строка),
  ни одной ссылки (тестов на них тоже нет - docs/testing упоминает их ошибочно).
- Зависимость `provider` из pubspec (0 импортов; state - через синглтоны).

**Статус:** pub get OK; analyze 0 errors; test 327 passed / 0 failed.

---

## 2026-07-01 - Защита аварийного wipe: исчерпывающий + best-effort + живой ключ (аудит SEC-5/LOGIC-7 + ARCH-7) [ветка wl/wipe-harden]

**Задача:** SEC-5 (wipe стирал не всё secure storage - оставались desktop-link сессия и ключ БД) +
LOGIC-7 (wipe прерывался на первом сбое, onWipeCompleted не звался).

**Сделано (после адверсариал-верификации воркфлоу - 3 линзы):**
- `auth_service.dart`: `AuthSecureStorage.deleteAll()` (+ прод + 5 тест-моков); performWipe переписан
  best-effort (каждый шаг в try/catch, состояние/навигация сбрасываются всегда), secure storage чистится
  целиком через `deleteAll`. Ещё 2 голых auth-принта -> DebugLogger.
- **Верификация нашла HIGH:** wipe звал `CryptoService().deleteAccount()` на ОДНОРАЗОВОМ экземпляре,
  а живой `cryptoService` держал приватный ключ в памяти + сокет оставался под стёртой личностью.
  Фикс: `CryptoService` -> синглтон (ARCH-7); performWipe зовёт `CryptoService.instance.deleteAccount()`
  (чистит ключи в памяти; reconnect не поднимется - publicKeyBase64 == null).
- **Верификация нашла MEDIUM:** `_isWiping` снимается после шага 2 -> входящее могло пересоздать БД+ключ.
  Фикс: добавлен `onWipeStarted` (main.dart разрывает websocket В НАЧАЛЕ wipe) + разрыв в onWipeCompleted.
- Обновлены 3 вызова `CryptoService()` -> `.instance` (main, status_screen, auth performWipe).
- LOW (APK-updates не чистятся - не секрет; нет сигнала об ошибке wipe в UI) - отмечено как follow-up.

**Статус:** analyze 0 errors; test 327 passed / 0 failed; сборка APK - в процессе.

---

## 2026-07-01 - Авто-контакт для сообщений от неизвестных отправителей (аудит DB-6) [wl/dev]

**Задача:** сообщение от отправителя, которого нет в контактах, сохранялось (`addMessage`), но
`getContacts` (LEFT JOIN от contacts) его не показывал -> пользователь видел только пуш, а переписки в
списке не было.

**Сделано:** `database_service.addContactIfMissing(publicKey)` (имя = префикс ключа, без duress-проверки,
как addMessage); вызывается в chat-пути `incoming_message_handler` перед `addMessage`. +метод в интерфейс
`IncomingMessageDatabase`, адаптер (main.dart) и фейк (тест). Ассерт в тесте: неизвестный отправитель
авто-добавлен в контакты.

**Статус:** analyze 0 errors; test 327 passed / 0 failed.

---

## 2026-07-01 - Гонка переподключения WebSocket (аудит LOGIC-9) [ветка wl/ws-connect]

**Задача:** `_initConnection` (async `WebSocket.connect().then`) не защищён от параллельного запуска
(`_forceReconnect`/reconnect-таймер зовут напрямую) -> два `.then` -> два живых сокета -> двойная
доставка + утечка.

**Сделано:** generation-токен `_connectionGeneration`. `_initConnection` захватывает `gen = ++_connectionGeneration`;
в `.then` устаревший сокет закрывается и НЕ подписывается; в `.catchError` устаревшая попытка игнорируется;
`disconnect()` бампает поколение (инвалидирует in-flight connect).

**Адверсариал-верификация (2 линзы) нашла регресс (MEDIUM x2):** обработчики `onDone/onError` НЕ были
защищены поколением -> закрытие живого предшественника новым connect дёргало `_handleDisconnect` ->
лишний цикл реконнектов (каждую секунду, backoff сбрасывается на успехе). Исправлено: `onDone/onError`
теперь проверяют `gen != _connectionGeneration` и выходят для устаревшего сокета. Плюс reentrancy-guard
`_sendingPending` в `_sendPendingMessages` (LOW). connect-timeout (LOW, pre-existing) - follow-up.

**Статус:** analyze 0 errors; test 327 passed / 0 failed.

---

## 2026-07-01 - PIN на настоящий Argon2id + verifyPin async (аудит SEC-8 + LOGIC-5) [ветка wl/pin-argon2]

**Задача:** SEC-8 — PIN хэшировался 10000×SHA-256 под видом Argon2id (слабо против перебора
украденного конфига; для 4-6-значного PIN вся стойкость в цене KDF). LOGIC-5 — счётчик попыток
писался fire-and-forget.

**Сделано:**
- Argon2id из пакета `cryptography` (memory=19456≈19МБ OWASP-минимум, t=2, p=1, hashLength=32).
  Новый хэш тегируется `argon2id$`; `_verifyHash` поддерживает и legacy SHA-256 -> без блокировки/сброса.
- `verifyPin` -> `Future<PinVerifyResult>` async; счётчики попыток awaited (LOGIC-5, durable до реакции UI).
  Обновлены ВСЕ вызовы (lock_screen, pin_setup x3, settings, changePin/disablePin/exitDuressMode + тесты).
- Авто-апгрейд legacy->Argon2id при первом входе — для PIN И кода принуждения (`_maybeUpgradeLegacyHash`).
- Тест-сим `createForTesting(fastHash:true)` (быстрый sync-хэш) — реальный Argon2id async не резолвится
  под fake-clock WidgetTester.pump (виджет-тесты зависали). Сим гейтнут `kDebugMode` -> в release всегда Argon2id.

**Адверсариал-верификация (3 линзы):** crypto=solid, async-seam=solid, migration=has-issues.
Исправлено по итогам: memory 12->19МБ (MEDIUM, OWASP); апгрейд duress-кода (LOW); гейт сим-а kDebugMode (LOW);
short-circuit апгрейда в fast-тестах (LOW). Constant-time compare — не нужен (локальная модель, Argon2 доминирует).
Остаток: legacy wipe-код не апгрейдится (он и так стирается при вводе) — задокументировано.

**Статус:** analyze 0 errors; test 327 passed / 0 failed; APK — пересобирается.

---

## 2026-07-02 - OPS-1: подпись release своим keystore [wl/dev]

`build.gradle.kts`: загрузка `android/key.properties` (в .gitignore) + `signingConfigs.release`;
`buildTypes.release` подписывает release-ключом при наличии key.properties, иначе фолбэк на debug
(сборка/CI без секретов). Добавлены `android/key.properties.example` (с инструкцией keytool) и
`**/*.jks` в .gitignore. Владелец генерирует keystore сам.

**Статус:** `flutter build apk --release` OK (фолбэк на debug-подпись, APK 128.9 МБ).

---

## 2026-07-02 - WS connect watchdog (pre-existing LOW из верификации LOGIC-9) [ветка wl/ws-timeout]

`websocket_service.dart`: `WebSocket.connect` не имел таймаута -> при зависшем connect статус навсегда
залипал в Connecting, а `connect()` блокировал новые попытки. Добавлен `_connectTimeout` (20с): по
таймауту бампает `_connectionGeneration` (опоздавший сокет закроется в .then по gen-guard, без утечки),
ротирует хост, зовёт `_handleDisconnect` (реконнект). Отменяется на успехе/ошибке/disconnect.

**Статус:** analyze 0 errors; test 327 passed / 0 failed.

---

## 2026-07-02 - Дедуп in-flight запросов бейджей (аудит PERF-4) [wl/dev]

`badge_service.dart`: `getBadge` без дедупа плодил параллельные HTTP на один pubkey (preloadBadges
зовётся на каждый refresh контактов). Добавлен `_inFlight` (pubkey -> Future) + `putIfAbsent` со
self-clean `whenComplete`; логика запроса вынесена в `_fetchAndCache`.

**Статус:** analyze 0 errors; test 327 passed / 0 failed.

---

## 2026-07-02 - Синхронизация документации с изменениями сессии [wl/dev]

Параллельный аудит 11 doc-файлов (воркфлоу) нашёл 22 устаревших утверждения в 6 файлах; исправлено:
- README: подпись release (OPS-1) — key.properties вместо "debug-ключ".
- SECURITY_REVIEW: находки P0 wipe / P2 PIN / P2 логи помечены ✅ устранёнными (SEC-1/5, SEC-8, SEC-2/QUAL-1).
- FEATURES_AND_LIMITATIONS: пп.1 (хранение) и 5 (логи/телеметрия) → закрыто.
- ARCHITECTURE / FUNCTIONAL_PRINCIPLES / PROJECT_STRUCTURE: БД → SQLCipher/зашифрована; телеметрия → opt-in,
  выключена по умолчанию, санитизирована.
5 файлов (PROJECT_OVERVIEW, GETTING_STARTED, PHILOSOPHY, DEVELOPMENT_GUIDE, docs/README) — без устаревшего.
