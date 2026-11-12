# Design Decisions (E4)

Project: E-commerce Customer Retention & RFM (SQL Server)
Tasks: E4-03 (customer and order rules), E4-04 (star schema outline)

---

## 1. Customer and order rules (E4-03)

| Concept | Rule | Why | Evidence |
|---|---|---|---|
| **Customer** | `user_id` | Only identifier of a person in the data | Official data card: "Permanent user ID" |
| **Order** | A session with at least one purchase event (`order_id` = `user_session`) | The file has no order id (D3) | 8,456 purchase sessions in the sample |
| **Order line** | One purchase event | Each purchase event is one product at one price | Multi-purchase sessions: 720 of 8,456 in the sample |
| **Order date** | Date of the first purchase event of the session | One date per order | Session time span: mostly 1 to 10 minutes |
| **Order value** | Sum of the prices of its purchase events | Revenue is the sum of purchase prices | Purchases have no zero price |
| **Customer of an order** | `user_id` of its purchase events (the first one, if they differ) | A session can carry 2 user ids (940 sessions) | Issue I-06 |
| **Unknown customer** | An event without `user_id` is kept in revenue, excluded from customer KPIs | Decision D4 | 0 in the full data, rule kept as safeguard |

---

## 2. Star schema outline (E4-04)

**Grain:** the grain of a fact table is what one row means. Each fact has exactly one.

| Table | Grain | Measures | Keys to dimensions |
|---|---|---|---|
| `fact_event` | One source event (view, cart, purchase, ...) | Price (NULL when unknown) | customer, product, date, event type, session |
| `fact_order_line` | One purchase event | Price | order, customer, product, date |
| `fact_order` | One session with a purchase | Order value, number of lines | customer, date |

| Dimension | Grain | Notes |
|---|---|---|
| `dim_customer` | One `user_id` | Will hold the RFM segment history (SCD Type 2, E4-05) |
| `dim_product` | One product | Brand and category keys |
| `dim_category` | One category | Levels of the path |
| `dim_brand` | One brand | Includes "unknown" (-1) |
| `dim_date` | One calendar day | Week, weekday, partial-week flag, Black Friday flag (E4-06) |
| `dim_event_type` | One event type | View, cart, purchase, remove_from_cart |

**Why both `fact_event` and `fact_order_line`:** the funnel (view, cart, purchase) needs every event. Revenue and AOV need only purchases, so they read the smaller order-line fact.

---

## 3. Limits to keep in mind

- Orders are approximated (I-07): the order count is a lower bound until the full data is compared.
- A session can carry 2 user ids (I-06): the customer of an order is the user of its first purchase.
- Prices are in currency units (D7).
