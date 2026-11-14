# SCD Type 2 Design: dim_customer (E4-05)

Project: E-commerce Customer Retention & RFM (SQL Server)

---

## 1. Why SCD Type 2 here

The data has no changing customer attributes. The only attribute that changes over time is the **RFM segment**, which we compute from the purchases. A customer moves from "Champions" to "At Risk" when they stop buying.

SCD Type 2 keeps every version, so we can answer: **"what was this customer's segment when they bought?"**

---

## 2. What is tracked, and what is not

| Attribute | Tracked as SCD2? | Why |
|---|---|---|
| `rfm_segment` | **Yes** | Changes over time, and drives marketing decisions |
| `churn_status` (Active, Slipping, Churned) | **No**, in a separate report table | Changes often (weekly). Keeping it in the dimension would multiply the rows |
| `user_id` | No, it is the business key | Never changes |

---

## 3. Granularity: weekly, not daily

RFM is recalculated **once per week**, on the snapshot date of the week. A daily version would create about 7 times more rows for little value on 61 days of data.

---

## 4. Table design

| Column | Meaning |
|---|---|
| `customer_key` | Surrogate key, one per version (identity) |
| `customer_id` | Business key: the `user_id` |
| `rfm_segment` | The segment of this version |
| `dwh_valid_from` | First day this version applies |
| `dwh_valid_to` | Last day this version applies. Open rows use `9999-12-31` |
| `dwh_is_current` | 1 for the current version, 0 for history |

**Unknown member:** `customer_key = -1` (for events without a customer).

---

## 5. Load rule (each week)

For each customer with a new weekly segment:
1. If the segment is **the same** as the current row: do nothing.
2. If the segment is **different**: close the current row (`dwh_valid_to` = the day before, `dwh_is_current` = 0) and insert a new row (`dwh_valid_from` = the snapshot day, open end, current = 1).
3. A new customer: insert one row, open end.

---

## 6. Example

| customer_key | customer_id | rfm_segment | valid_from | valid_to | is_current |
|---|---|---|---|---|---|
| 101 | 555 | Champions | 2019-10-01 | 2019-10-20 | 0 |
| 240 | 555 | At Risk | 2019-10-21 | 9999-12-31 | 1 |

Customer 555 was a Champion until 20 October, then became At Risk.

---

## 7. How facts use it: point-in-time key

A fact row takes the `customer_key` that was valid **on the date of the event**. Example: an order on 15 October points to key 101, not 240. This is how "segment at purchase" is answered.

---

## 8. Cost and trade-off

| Item | Estimate |
|---|---|
| Rows | About buyers + segment changes (weekly). To be measured in E5 |
| Join cost | A join on key plus date range, for each order. Tested in E8 |
| Benefit | History preserved, honest analysis of "who was valuable when" |

**Decision:** SCD Type 2 on `rfm_segment` only, weekly, with `customer_key` for facts. Churn stays in a report table.
