# Серверная инструкция — оплата лицензии USDT-TRC20 (для кодера)

Имплементейшн-гайд под уже готовую клиентскую часть (коммит `feat(license): in-app
USDT-TRC20 purchase flow`). Компонент: **Orpheus Backend** (FastAPI). Смежные доки:
`USDT_TRON_SPEC.md` (обоснование + антифрод), `ROADMAP.md`.

Задача сервера: принять оплату USDT в сети TRON на **свежий HD-адрес на каждый заказ**,
поймать её вотчером через **TronGrid** (свою ноду не поднимаем), и **активировать
лицензию для pubkey**. Клиент менять НЕ нужно — он уже соответствует контракту ниже.

---

## 1. Контракт API (клиент УЖЕ шлёт/ждёт именно это)

### 1.1 `GET /api/purchase/tariffs`
Ответ (цены задаём НА СЕРВЕРЕ, клиент их не хардкодит):
```json
{ "tariffs": [
  { "id": "1m",   "title": "1 месяц",   "duration_days": 30,  "price_usdt": "5" },
  { "id": "6m",   "title": "6 месяцев", "duration_days": 180, "price_usdt": "25" },
  { "id": "life", "title": "Навсегда",  "duration_days": 0,   "price_usdt": "99" }
] }
```
- `id` — строка; `title` — то, что видит пользователь (локализацию можно решать на
  сервере по заголовку/языку или отдавать нейтрально); `duration_days` — int (0 =
  бессрочно); `price_usdt` — строка (чтобы не терять точность).

### 1.2 `POST /api/purchase/invoice`
Тело от клиента:
```json
{ "pubkey": "<base64 публичный ключ>", "tariff_id": "6m" }
```
Ответ:
```json
{ "order_id": "ord_abc123",
  "address": "T...(свежий TRON-адрес)",
  "amount_usdt": "25",
  "network": "TRC20",
  "expires_at": 1751750000 }
```
- `expires_at` — **epoch-СЕКУНДЫ (UTC)** ЛИБО ISO-8601 со смещением (клиент понимает
  оба; если ISO — обязательно с `Z`/таймзоной, клиент делает `toLocal()`).
- `network` — строка (для UI-предупреждения). `amount_usdt` — строка.

### 1.3 `GET /api/purchase/status?order_id=...`
```json
{ "status": "pending" }   // pending | seen | confirmed | expired
```
- Клиент считает оплату прошедшей на `confirmed` (и на `active` — тоже принимает).

### 1.4 WS-пуш (для мгновенной разблокировки, опционально но желательно)
На сессию этого pubkey отправить ОДНО из (клиент уже слушает оба):
```json
{ "type": "payment-confirmed" }
{ "type": "license-status", "status": "active" }
```
Поллинг `status` — основной путь (WS флапает), WS — быстрый бонус.

---

## 2. Модель данных (минимум)

Таблица `purchase_orders`:
```
order_id        TEXT PK
pubkey          TEXT              -- кому активировать
tariff_id       TEXT
amount_usdt     NUMERIC(20,6)     -- ожидаемая сумма (источник истины, НЕ от клиента)
address         TEXT UNIQUE       -- свежий HD-адрес
hd_index        INTEGER UNIQUE    -- индекс деривации (никогда не переиспользуется)
status          TEXT              -- pending|seen|confirmed|expired
tx_hash         TEXT NULL UNIQUE  -- потраченная tx (идемпотентность)
created_at, expires_at, confirmed_at
```
Счётчик `hd_index` — глобально монотонный (следующий индекс на каждый инвойс).

---

## 3. HD-кошелёк (свежий адрес на заказ)

TRON: BIP-44 `m/44'/195'/0'/0/i` (coin type 195). Детект можно вести по **xpub**
(watch-only); приватные ключи (seed) нужны только для sweep — держать офлайн (§7).

Python (пример на `bip_utils`):
```python
from bip_utils import Bip44, Bip44Coins, Bip44Changes

def derive_address(seed_bytes: bytes, index: int) -> str:
    acct = (Bip44.FromSeed(seed_bytes, Bip44Coins.TRON)
            .Purpose().Coin().Account(0).Change(Bip44Changes.CHAIN_EXT)
            .AddressIndex(index))
    return acct.PublicKey().ToAddress()   # base58 'T...'
```
На `POST /invoice`: взять `next_index`, `address = derive_address(..., idx)`, создать
order, вернуть адрес+сумму+expires. **Адрес не переиспользуем** между заказами.

---

## 4. Вотчер TronGrid

**Конфиг:** `TRONGRID_API_KEY`, `USDT_CONTRACT = TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`
(mainnet — ⚠ сверить), `USDT_DECIMALS = 6`. Заголовок ко всем запросам:
`TRON-PRO-API-KEY: <key>`.

**Цикл (крон/воркер, раз в ~10-15с):**
1. Взять активные (не expired, не confirmed) заказы.
2. Для каждого адреса опросить входящие TRC-20 переводы:
```
GET https://api.trongrid.io/v1/accounts/{address}/transactions/trc20
    ?only_to=true
    &contract_address=TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t
    &min_timestamp={last_seen_ms}
```
   Ответ — массив переводов: `transaction_id`, `from`, `to`, `value` (строка, в
   наименьших единицах = usdt * 10^6), `token_info.address`, `block_timestamp`.
3. **Проверки (антифрод, §6)** — контракт == USDT, `to` == адрес заказа,
   `value >= amount_usdt * 10^6`, `transaction_id` ещё не потрачен.
4. Пометить `seen`; дождаться **solidified** (см. ниже) → `confirmed`.
5. **Активация:** выставить лицензию для `pubkey`, записать `tx_hash`, послать WS.

**Solidified (подтверждение):** TRON финализирует ~через 19 блоков (~1 мин). Проще
всего проверять через **solidity-ноду**: транзакция, видимая на
`https://api.trongrid.io/walletsolidity/gettransactioninfobyid` (POST `{"value":
txid}`) с непустым `blockNumber` — уже солидифицирована. Либо сверять `blockNumber`
tx с текущим solid-блоком (`/walletsolidity/getnowblock`) на разницу >= ~19.

**Надёжность:** ретраи + backoff; хранить `last_seen_ms` на заказ/глобально и
опрашивать по `min_timestamp`, чтобы после простоя TronGrid **добрать пропущенное**
(платёж не теряется). Лимиты TronGrid — ⚠ проверить; при упоре — платный план или
фолбэк-провайдер (GetBlock/NowNodes/Tatum).

---

## 5. Активация лицензии

На `confirmed`:
- Пометить лицензию активной для `pubkey` на срок тарифа (тот же механизм, что
  выдаёт `activate-promo`; для `duration_days=0` — бессрочно).
- `order.status='confirmed'`, `order.tx_hash=<txid>`, `confirmed_at=now`.
- Послать WS на сессии этого pubkey: `{"type":"license-status","status":"active"}`.
- `GET /status` после этого возвращает `confirmed`.

Идемпотентность: если `tx_hash` уже записан у любого заказа — не активировать повторно.

---

## 6. Антифрод — чеклист сервера (ОБЯЗАТЕЛЬНО)

- [ ] **Контракт токена == USDT** (точный адрес). Иначе шлют свой «USDT»-токен →
      бесплатная «оплата». Самое критичное.
- [ ] **`to` == адрес заказа** (матчим по адресу, не по сумме — адрес уникален).
- [ ] **`value >= amount_usdt * 10^6`** (недоплату не активируем).
- [ ] **solidified** (не активировать на неподтверждённой/reverted).
- [ ] **`tx_hash` не потрачен** (идемпотентность, защита от двойного клейма).
- [ ] **Инвойс не просрочен**; поздняя оплата на просроченный — в ручной разбор,
      не терять (реконсиляция вотчера).
- [ ] **Адрес/hd_index не переиспользуются** никогда.
- [ ] **Rate-limit** `POST /invoice` по pubkey/IP (антиспам, защита от исчерпания
      индексов и замусоривания БД); TTL инвойса; переиспользовать неоплаченный
      pending того же pubkey+tariff вместо плодения.
- [ ] **Сумма — с сервера** (в order), клиентскому вводу не доверяем.
- [ ] **Рычаг:** возможность **отозвать лицензию + забанить** pubkey/tx при абьюзе.
- [ ] Логи/алерты на аномалии (чужой контракт, недоплаты, оплаты на expired, всплеск
      инвойсов).

Подпись `POST /invoice` ключом клиента — НЕ обязательна для корректности (оплата на
адрес заказа активирует именно тот pubkey, что в заказе; «оплатить за чужого» = подарок,
не атака). Максимум — опциональный антиспам.

---

## 7. Sweep (вывод средств) и безопасность

- USDT оседает на per-invoice HD-адресах. Для консолидации — TRC-20 перевод с каждого
  на основной кошелёк. Перевод TRC-20 требует **energy/bandwidth (TRX)** на адресе:
  либо чуть пополнять TRX, либо делегировать energy. Батчами по расписанию.
- **Seed (spend-ключи) держать офлайн**, подпись sweep — офлайн/из изолированного
  окружения; на боевом сервере — только xpub (watch-only) для детекта. Это резко
  снижает hot-wallet риск.
- Секреты (`TRONGRID_API_KEY`, seed/xpub) — в защищённом хранилище, не в репозитории.

---

## 8. Конфиг (чек-лист развёртывания)
- `TRONGRID_API_KEY` (регистрация на trongrid.io).
- `USDT_CONTRACT` = `TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t` (⚠ сверить перед боем).
- HD `xpub` для детекта (+ seed офлайн для sweep).
- Тарифы/цены (в админке/БД) — отдаются `/tariffs`.
- Invoice TTL (напр. 30 мин), политика подтверждений (solidified).
- Приёмный основной кошелёк для sweep.

---

## 9. Тестирование
1. **Testnet (Nile/Shasta):** тестовый USDT-контракт + `https://nile.trongrid.io`;
   прогнать полный цикл invoice → оплата → confirmed → активация → WS.
2. Сценарии: недоплата (не активируется), переплата (активируется), чужой токен
   (игнор), просрочка (expired), двойная отправка той же tx (идемпотентность,
   без двойной активации), TronGrid недоступен → реконсиляция после восстановления.
3. Проверить, что клиент авто-разблокируется по поллингу И по WS.

---

## 10. Порядок работ (предлагаемый)
1. Таблица `purchase_orders` + HD-деривация + `/tariffs` + `/invoice` + `/status`.
2. Вотчер TronGrid (mainnet-контракт, solidified) + активация + WS-пуш.
3. Антифрод-проверки (§6) + rate-limit + отзыв/бан.
4. Sweep (офлайн-подпись) — можно после запуска, вручную на старте.
5. Тест на testnet, затем mainnet с малым ценником.
