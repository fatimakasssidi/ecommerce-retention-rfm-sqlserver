# Source Schema: REES46 Events

Project: E-commerce Customer Retention & RFM (SQL Server)
Tasks: E2-03, E2-04

This file describes the structure of the REES46 files. Each fact has a status: **Verified** (seen on the real files, with the check that proved it) or **To verify** (expected, confirmed in E2-03 or E3-07).

---

## 1. File format

| Item | Observation | Status | Evidence |
|---|---|---|---|
| Files | `2019-Oct.csv`, `2019-Nov.csv` | Verified | Sizes and hashes in `data_sources.md` |
| Separator | Comma | Verified | Header and sample rows |
| Header | Yes, on line 1, identical in both files | Verified | `head -n 1` on both files |
| Line ending | LF (`\n`, no `\r`) | Verified | `od -c` on the header line |
| Invisible mark (BOM) | None, the file starts with `eve` | Verified | First 3 bytes are `65 76 65` |
| Double quotes | None in either file | Verified | `tr -cd '\042' \| wc -c` gave 0 and 0 |
| First event | `2019-10-01 00:00:00 UTC` | Verified | First rows of the October file |
| Last event of October | `2019-10-31 23:59:59 UTC`, complete row | Verified | `tail -n 3` |
| Last event of November | `2019-11-30 23:59:59 UTC`, complete row | Verified | `tail -n 3` |
| First event of November | Expected `2019-11-01 00:00:00 UTC` | To verify | `head -n 2` on the November file |
| Fields per line | Exactly 9 on every line, header included | Verified | `awk -F, 'NF!=9'` gave 0 for both files |
| Event types | `view`, `cart` and `purchase` seen. `remove_from_cart` not seen yet | Verified for 3 types, to verify for the rest | `grep -m 3` on `cart` and `purchase`, then profiling |
| Encoding | UTF-8 expected (no BOM) | To verify | Check on non-ASCII values in E3-07 |
| Order | Sorted by `event_time` in the rows seen | To verify | E3-07 |
| Empty values | Empty fields between commas, seen in `brand` and `category_code` | Verified | Sample rows |

---

## 2. Grain

**One row is one event: one user did one thing (view, cart or purchase) with one product at one moment.**

Important consequences:
- **There is no event ID.** Nothing in the file identifies a row uniquely, so two identical rows cannot be told apart. A surrogate key is added in silver.
- **A row is not an order, and not a customer.** Orders, customers, products and categories have to be derived from the events.
- **The same product, user or session appears many times,** so these columns repeat across millions of rows.

---

## 3. Columns

| Column | Example | What it is | Bronze type | Planned silver type |
|---|---|---|---|---|
| `event_time` | `2019-10-01 00:00:00 UTC` | Event timestamp as text, with a ` UTC` suffix | `varchar(100)` | `datetime2(0)`, parsed after removing the suffix |
| `event_type` | `view` | `view`, `cart`, `purchase` (and possibly `remove_from_cart`) | `varchar(100)` | `tinyint` key to a small lookup table, or `varchar(20)` |
| `product_id` | `3900821` | Product identifier (7 to 8 digits seen) | `varchar(100)` | `int` |
| `category_id` | `2053013552326770905` | Category identifier (19 digits) | `varchar(100)` | `bigint` |
| `category_code` | `appliances.environment.water_heater` | Category path with dots. Can be empty | `varchar(400)` | `varchar(200)`, split into levels |
| `brand` | `lenovo` | Brand, lowercase. Can be empty | `varchar(400)` | `varchar(100)` |
| `price` | `543.10` | Price with 2 decimals, currency not stated | `varchar(100)` | `decimal(18,2)`, reduced if the maximum price allows |
| `user_id` | `541312140` | Anonymous user (9 digits) | `varchar(100)` | `int` |
| `user_session` | `72d76fde-8bb3-4e00-8c23-a032dfed738c` | Session identifier, a UUID | `varchar(100)` | `uniqueidentifier` |

**Why these silver types**
- A number that fits in `int` (up to 2,147,483,647) should not be stored as `bigint` or text. `product_id` and `user_id` fit. `category_id` has 19 digits and needs `bigint` (up to about 9.2 billion billion).
- A UUID as `uniqueidentifier` takes 16 bytes, while the same text in `varchar(36)` takes 38. Over 100 million rows that saves about 2.2 GB.
- Bronze keeps everything as text on purpose, so a bad value never stops a load. The strict types arrive in silver.

---

## 4. Expected relationships

These come from what the columns mean. They are **assumptions to test** in profiling (sections 7 and 6 of `profile_sample.sql`), not facts.

| Relationship | Expected | Why it matters |
|---|---|---|
| Product to category | Many products to one category | Foreign key from product to category |
| Product to brand | Many products to one brand, but the brand may be empty on some events | A clean product table needs a rule for missing or conflicting brand |
| Session to user | One user has many sessions, a session belongs to one user | The order rule (D3) and session-based KPIs |
| Event to product, user, session | Each event points to one of each | Foreign keys of the event table |
| Category code | A path with up to several levels, separated by dots | A category hierarchy table |

---

## 5. What the files already tell us

- **The timestamp is not a standard SQL date.** The ` UTC` suffix makes a direct conversion fail, so silver removes it (for example `TRY_CONVERT(datetime2(0), LEFT(event_time, 19))`). Bronze keeps the original text.
- **A missing category code does not mean a missing category.** One row has an empty `category_code` but a valid `category_id`.
- **Empty brand and empty category code are common.** They are treated as "unknown" in silver, not as errors.
- **Cart and purchase rows have the same 9 columns as views,** and a purchase carries its unit price, so revenue can be read from the purchase event.
- **A product seems to keep the same price and category.** Product `5100816` appears in a cart event and in a purchase by another user with the same price and the same empty `category_code`. To be tested on more data.
- **The first purchase of the file (00:02:14) comes before the first cart event (00:05:14).** The session may have started before the data begins, or purchases may happen without a cart event. This matters for the funnel rule, see the open items.
- **The data covers 61 days,** from 1 October to 30 November 2019. The RFM snapshot date is therefore expected to be 2019-12-01 (confirmed in E3-07).
- **Weeks:** 1 October 2019 is a Tuesday and 30 November a Saturday, so with weeks starting on Monday the first and last weeks are partial and there are 7 complete weeks (7 October to 24 November). The Black Friday week (25 November to 1 December) is the partial last week.

---

## 6. Assumptions carried from the metric dictionary

| Assumption | Where it is checked |
|---|---|
| No order ID: an order is a session with at least one purchase (D3) | E2-05 and E3-07 |
| No quantity: one unit per purchase event | E3-07 |
| No cancellations or returns | E3-07 |
| Currency is not stated | `data_sources.md` |
| Customer is the `user_id` | E2-05 |

---

## 7. Open items

| Item | Resolved in |
|---|---|
| First event of November | E2-03 |
| Do purchase sessions always contain a cart event? If not, the strict funnel rule (K17 to K20) must change | E2-05 and E3-07 |
| Which event types really exist (`remove_from_cart`?) | E3-07 |
| Rows with price of 0 or below | E3-07 |
| Identical duplicate rows | E3-07 |
| Rows without a `user_id` or a session | E3-07 |
| Whether products keep one category, brand and price | E2-05 and E3-07 |
