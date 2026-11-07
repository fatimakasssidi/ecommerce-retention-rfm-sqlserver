# Data Dictionary (v1)

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E2-06

This file says **what each field means** and which values are allowed. It does not repeat the file format (see `source_schema.md`), the evidence (see `profiling_rees46.md`) or the list of problems and decisions (see `issues_log.md`).

**How to read the "Meaning" column.** The meanings below come from the column names and from the values seen on real rows. They are **inferred** until they are compared with the official description on the Kaggle data card. The last column tells which ones are still to confirm.

---

## 1. Source fields (one row is one event)

| Field | Meaning | Allowed values | Missing? | Silver type | Related issues | Official definition |
|---|---|---|---|---|---|---|
| `event_time` | Moment of the event, in UTC | Text like `2019-10-01 00:00:00 UTC`, between 1 October and 30 November 2019 | Never (0 in the sample) | `datetime2(0)` | I-01, I-17 | To confirm |
| `event_type` | What the user did | `view`, `cart`, `purchase` seen. `remove_from_cart` not seen yet | Never (0) | `tinyint` key to a lookup table, or `varchar(20)` | I-16, I-17 | To confirm |
| `product_id` | The product the event is about | Whole number, up to 8 digits seen | Never (0) | `int` | I-10 | To confirm |
| `category_id` | The category of the product | Whole number, 19 digits | Never (0) | `bigint` | I-03 | To confirm |
| `category_code` | Path of the category, levels separated by dots (for example `electronics.smartphone`) | 2 to 4 levels when present | **Yes: 32.51% of events**, because 388 of 648 categories never have a code | `varchar(100)`, split into up to 4 levels | I-03 | To confirm |
| `brand` | Brand of the product, in lowercase | Free text, up to 30 characters seen | **Yes: 14.02% of events** | `varchar(100)` | I-02, I-10 | To confirm |
| `price` | Unit price of the product at the event, currency not stated | Number with 2 decimals, 0 to 2574.07 seen. 0 appears on views and carts only | Never (0). **Zero in 0.22%** | `decimal(18,2)`, narrower if the full data allows | I-04, I-11, I-12 | To confirm |
| `user_id` | The anonymous user who did the event | Whole number, 9 digits | Never (0) | `int` | I-06, I-13 | To confirm |
| `user_session` | The visit (session) the event belongs to. A user has several sessions | UUID, 36 characters | Never (0) | `uniqueidentifier` | I-06, I-07 | To confirm |

Counts in the "Missing?" column come from the 560,000-row sample and are re-measured on the full data in E3-07.

---

## 2. Derived fields (planned)

These do not exist in the files. They are built in silver and gold. Their formulas are in `metric_dictionary.md`.

| Field | Meaning | Rule |
|---|---|---|
| `event_id` | Row identifier | A surrogate key, because the file has no event ID (see I-05) |
| `customer_id` | The customer | The source `user_id` |
| `order_id` | The order | The session that contains at least one valid purchase (decision D3). The order count is a lower bound (I-07) |
| `order_date` | Date of the order | The date of the first purchase event of the session |
| `is_valid_purchase` | A purchase that counts as revenue | `event_type = 'purchase'` and `price > 0` |
| `category_level_1` to `category_level_4` | The parts of the category path | Split of `category_code`. Empty when the path is missing |
| `is_unclassified_category` | The category has no code | `1` when `category_code` is missing |
| `brand_resolved` | Brand of a product | The single non-empty brand of the product, the most frequent one if several, otherwise `unknown` (I-02, I-10) |
| `price_is_unknown` | The price on a view or cart is 0 | `1` when `price = 0` on a non-purchase event (I-04) |

---

## 3. Glossary

| Term | Meaning in this project |
|---|---|
| **Event** | One row of the file |
| **View, cart, purchase** | The three event types: looked at a product, added it to the cart, bought it |
| **Session** | One visit, identified by `user_session` |
| **User** and **customer** | The same thing here: a `user_id`. One person can have several ids (I-13) |
| **Order** | A session with at least one valid purchase (derived, I-07) |
| **Order line** | One purchase event: one product at one price, counted as one unit (I-08) |
| **Valid purchase** | A purchase event with a price above 0 |
| **Unclassified category** | A category with no `category_code` anywhere |
| **Sample** | The 560,000 events used in E2-05. It supports structure questions, not volumes |
