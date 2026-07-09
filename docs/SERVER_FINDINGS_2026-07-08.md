# Orpheus Backend — разбор кода vs device-тест (08.07.2026)

Глубокий разбор ветки `feature/server-tasks-no-crypto` (коммит `8893c61`) в сопоставлении
с клиентским контрактом и находками device-теста 08.07 (Samsung SM-S938B ↔ Pixel 7 Pro,
прод `api.orpheus.click`).

## ГЛАВНОЕ: ветка НЕ задеплоена на прод

`feature/server-tasks-no-crypto` = один незамёрженный коммит `8893c61` (07.07). Прод
автодеплоится с mainline и этого коммита **не содержит**. Device-тест 08.07 бил в
**старый прод-код** — поэтому часть задач «не работала», хотя в коде они уже сделаны.

**Единственная проверка, которая всё решает:** открыть 1 WS-сокет на pubkey, вызвать
`POST /api/activate-promo`, и смотреть, придёт ли `license-status:active` в этот же сокет
за ~30с. Если нет — на проде нет `8893c61`.

---

## По задачам

### №2 — WS-сессии / presence / keepalive — ГОТОВО в коде (нужен деплой)
- Реестр `Dict[str, List[WebSocket]]` — **несколько сокетов на pubkey** (fan-out, не
  takeover). `connect()` только добавляет, `disconnect(ws)` убирает только один сокет,
  presence уходит offline только когда закрылся ПОСЛЕДНИЙ. (`main.py:886, 900-956, 990-1006, 918-965`)
- Sweeper мёртвых сессий 75с / 15с (`main.py:114-115, 1170-1179`); при app-ping клиента 30с
  запас 2.5×. Presence идемпотентен для 2 изолятов клиента; ре-бродкаст на реконнекте.
- Покрыто тестами (`tests/test_ws_sessions.py`, `test_ws_presence.py`).
- **Остаток (не блокер):** при ГРЯЗНОМ килле (сеть/убийство без close-фрейма) мёртвый
  сокет висит в списке до ~90с (75+15), пока sweeper не выметет или первый send в него не
  упадёт (тогда чистится сам). Первый call-offer после грязного реконнекта может словить
  один упавший send по «призраку» до само-лечения. Само-лечится, но если хочется убрать
  окно — нужен server-side ping с коротким idle ЛИБО takeover по liveness-пробе (НЕ
  «новый выбивает старого» — это сломает 2 легитимных изолята). (`main.py:905, 1006`)

### license-status:active после активации — DEPLOY-GAP (код верен, не на проде)
- `activate_promo` → `notify_license_activated` → `manager.send_personal_message` fan-out
  во ВСЕ сокеты pubkey + `payment-confirmed`, с Redis-форвардом на другие ноды
  (`main.py:2168, 2173-2189`). Плюс страховка: ре-чек лицензии на каждый `ping`
  (`main.py:2633-2637`). Тесты зелёные (`test_ws_sessions.py:181, 213` — 3 passed).
- Механизм существует **только** в `8893c61`. Симптом device-теста (ни пуша после
  активации, ни ре-чека по ping за ~3 мин) внутренне согласуется со «старым прод-кодом».
- **Действие:** смерджить ветку → задеплоить. Больше ничего.

### №4 — публичный RU-changelog — CONTENT-GAP (код верен, нет данных)
- `GET /api/public/releases` (`app/public_api.py:12, 66`) отдаёт массив с
  `version_name/created_at/public_changelog/version_code` — контракт совпадает с клиентом.
- Пустой список потому, что функция **отфильтровывает записи с пустым `public_changelog`**
  (`public_api.py:59-64`), а на проде версия зарегистрирована без текста changelog. Прод
  `curl /api/public/releases` = `[]`, `curl /api/check-update` = `version_code 0` — т.е.
  на проде в админке **вообще не заведена версия с changelog**.
- **Действие (админка):** залить RU-текст (файл `PUBLIC_CHANGELOG_RU.md`) в поле
  `public_changelog` версии — `PUT /api/versions/{id}` (`admin_api.py:152-169`); `id` из
  `GET /api/versions`. Auth: `Bearer`-токен из `POST /api/auth/login` (form-encoded
  username+password).
- **Отдельный баг приватности:** публичный `/releases` отдаёт `internal_notes` наружу
  (`public_api.py:48-50, 61`) — их надо вырезать из публичного ответа (правило «без утечек»).

### №5 — удаление комнаты + №3 — поддержка pre-auth — ГОТОВО
- `POST /api/rooms/{id}/delete` — owner-only (`owner_pubkey != pubkey` → 403), блок
  Orpheus-комнаты, транзакция удаляет messages+members+room, и **шлёт WS `room-deleted`**
  членам перед удалением (`rooms_api.py:546-579, 562-567`). Покрыто тестами.
- Поддержка (`app/support_api.py`) — **без лицензионного гейта**, идентификация по
  `X-Pubkey` (`support_api.py:64-69`). Работает до активации.
- **Хвосты:** (а) `room-deleted` шлётся только онлайн-членам (офлайн не queue'ится,
  `rooms_api.py:127`), И у клиента **нет обработчика** `room-deleted` — событие теряется,
  член видит пропажу по refresh. Опциональная КЛИЕНТСКАЯ доработка: добавить обработчик
  `room-deleted` (по int `room_id`), оставив refresh как фолбэк. (б) Тексты ошибок
  поддержки захардкожены по-русски (`support_api.py:71,73,106`) — минуют клиентскую L10n.

### №1 — оплата USDT-TRON — PARTIAL ~30% (нужна доделка, не фикс)
Ветка называется `-no-crypto` не случайно — крипто-путь оставлен заглушкой за
`PAYMENTS_ENABLED=0` (`main.py:119`).
- **3 REST-эндпоинта клиента отсутствуют.** Клиент зовёт `GET /api/purchase/tariffs`,
  `POST /api/purchase/invoice`, `GET /api/purchase/status`. Сервер вместо этого говорит по
  WS `payment-create-invoice` (`main.py:2672-2684`) с несовместимой формой payload
  (`payment_id/amount` vs клиентские `order_id/amount_usdt/network`). Клиент купить не может.
- **Вотчер следит за нативным TRX, не USDT TRC-20** (`payments.py:195-208, 239`): читает
  баланс TRX аккаунта, без контракта USDT, без разбора транзакции, без solidified.
- **Реальный баг:** `tx_id` = константа `"trx_auto_detected"` под UNIQUE-констрейнтом
  (`payments.py:242, 42`) → активируется только ПЕРВЫЙ авто-детект, второй падает на
  IntegrityError.
- HD-адрес выводится верно (`m/44'/195'/0'/0/i`, `payments.py:76-85`), но `bip_utils`
  **нет в requirements.txt** → при включении оплаты упадёт на импорте.
- **Действие:** это полноценная доделка (эндпоинты + тарифы + TRC-20-вотчер с проверкой
  контракта/суммы/отправителя + solidified + дедуп по реальному tx_hash + rate-limit +
  bip_utils в requirements). Держать `PAYMENTS_ENABLED=0` пока не готово. Заодно починить
  `tx_id`-коллизию и добавить `bip_utils`.

### Бонус-паритет (перекрытие №2/№5): платёжный путь мимо `notify_license_activated`
Вотчер шлёт license-status «руками» (`payments.py:247-254`), минуя Redis-fan-out и
offline-доставку из `notify_license_activated`. Патч: прокинуть нотифаер —
`asyncio.create_task(payment_watcher(database, manager, notify_license_activated))`
(`main.py:2525`), затем `if notify: await notify(pubkey)` в `payments.py:245`. Плюс
стухший комментарий `sleep(60)` vs «15с» (`payments.py:264`) и тест платёжного пути
(вотчер замокан в `conftest.py:38-41`).

---

## Топ-3 действия (по важности)
1. **Смерджить `feature/server-tasks-no-crypto` в деплой-ветку → Timeweb передеплоит прод.**
   Одним махом чинит: license-status-пуш (гл. вопрос), корень флапа WS/призрачных сессий,
   и доставку `room-deleted`. Проверить: 2 сокета на pubkey + `POST /api/activate-promo`.
2. **Залить RU `public_changelog`** на текущую прод-версию через `PUT /api/versions/{id}`.
   Одна админ-команда — убирает офлайн-фолбэк в клиенте. Заодно вырезать `internal_notes`
   из публичного ответа.
3. **Оплату вести как отдельную сборку, не фикс.** До неё — починить `tx_id`-коллизию и
   добавить `bip_utils`, но держать `PAYMENTS_ENABLED=0`, пока не готовы 3 REST-эндпоинта
   и настоящий TRC-20/solidified-вотчер.
