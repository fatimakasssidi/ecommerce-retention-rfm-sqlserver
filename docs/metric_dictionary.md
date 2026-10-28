# Metric Dictionary (v2)

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E1-03

**One definition per KPI.** The SQL in the gold layer and the DAX measures in Power BI must both follow this file (task E12-10). If a number differs between two places, this file decides which one is right.

Status values: **Draft** (decided, but depends on an assumption to confirm during profiling in E3-07) and **Confirmed** (no open assumption).

---

## 1. Global rules

1. **One source.** All KPIs come from the REES46 events (October and November 2019).
2. **Customer identity.** A customer is a `user_id`. Rows without a `user_id` count in revenue and orders, but not in any customer KPI.
3. **Time.** All timestamps are UTC, as stored in the source. A **day** is the UTC calendar day. A **week** starts on Monday.
4. **Partial periods.** The first and last weeks of the data are partial. They are flagged and excluded from retention and churn calculations, and shown with a marker in trends.
5. **Black Friday.** The Black Friday period (29 November 2019) is flagged in the date dimension so its effect can be isolated.
6. **No silent exclusions.** Rows removed from the KPIs are counted and reported by the data quality KPIs (K21, K22).
7. **Source of the numbers.** KPIs are calculated from cleaned data (silver and gold), never from bronze.

---

## 2. What the words mean in this source

| Concept | Meaning in REES46 |
|---|---|
| Event | One row: `event_time`, `event_type`, `product_id`, `category_id`, `category_code`, `brand`, `price`, `user_id`, `user_session` |
| Event types | `view`, `cart`, `purchase`. A `remove_from_cart` type is expected too (to confirm in E3-07) |
| Sales line | One `purchase` event |
| Order | One session (`user_session`) with at least one purchase. **Assumption:** there is no order ID |
| Order date | The timestamp of the first purchase event of the session |
| Customer | `user_id` |
| Quantity | 1 per purchase event. **Assumption** |
| Line amount | `price` (currency not stated, so "currency units") |
| Cancellation or return | Not recorded |

**Valid purchase:** `event_type = 'purchase'`, `price` above 0, and `user_id` not empty.

---

## 3. KPI definitions

### Revenue and orders

**K01 Revenue**
- **Definition:** value of all valid purchases in the period.
- **Formula:** `SUM(price)` over valid purchases.
- **Grain:** day, week and month, also by category and brand.
- **Edge cases:** the data has no cancellations or returns, so this is gross revenue. Price outliers are flagged in the data quality checks.
- **Status:** Draft (price anomalies reviewed in E3-07).

**K02 Order count**
- **Definition:** number of orders in the period.
- **Formula:** `COUNT(DISTINCT user_session)` over sessions with at least one valid purchase.
- **Grain:** day, week and month.
- **Edge cases:** two real orders inside one session count as one. A session that crosses midnight is counted on the date of its first purchase.
- **Status:** Draft (confirmed in E3-07).

**K03 Average order value (AOV)**
- **Definition:** average value of an order.
- **Formula:** `K01 / K02`. The median order value is shown next to it.
- **Grain:** day, week and month, also by segment.
- **Status:** Draft.

### Customers

**K04 Active users**
- **Definition:** users with at least one event of any type in the period.
- **Formula:** `COUNT(DISTINCT user_id)`.
- **Grain:** day and week.
- **Status:** Confirmed.

**K05 Active buyers**
- **Definition:** users with at least one valid order in the period.
- **Formula:** `COUNT(DISTINCT user_id)` over valid orders.
- **Grain:** day and week.
- **Status:** Confirmed.

**K06 New buyers**
- **Definition:** users whose first valid order falls in the period.
- **Formula:** users where `MIN(order_date)` is in the period.
- **Grain:** day and week.
- **Edge cases:** users who bought before the data starts appear as new in the first weeks. The first week is flagged as unreliable.
- **Status:** Confirmed.

**K07 Returning buyers**
- **Formula:** `K05 - K06`.
- **Status:** Confirmed.

**K08 Repeat purchase rate**
- **Definition:** share of buyers who bought more than once.
- **Formula:** buyers with 2 or more valid orders / buyers with at least 1 valid order.
- **Grain:** whole period, and by weekly cohort.
- **Edge cases:** the period is short, so buyers who first bought late have had little time to buy again. A fair version is also reported: the **14-day repeat rate**, using only buyers whose first order is at least 14 days before the end of the data.
- **Status:** Draft.

**K09 Days to second order**
- **Definition:** days between a buyer's first and second valid order.
- **Formula:** `DATEDIFF(day, first_order_date, second_order_date)`, reported as the **median** and a distribution.
- **Edge cases:** only gaps shorter than the period can be observed, so long gaps are missing. This limits how the churn window is chosen (see `churn_definition.md`).
- **Status:** Draft.

**K10 Purchase retention (weekly cohort)**
- **Definition:** share of a weekly cohort of first-time buyers who buy again in a later week.
- **Cohort:** buyers grouped by the week of their first valid order.
- **Formula:** buyers of cohort C with at least one valid order in week `C + k` / size of cohort C. Week 0 is 100% by definition.
- **Grain:** cohort week and weeks since first order (k).
- **Edge cases:** the partial first week is excluded as a cohort, and partial weeks are excluded as observation weeks.
- **Status:** Draft.

**K11 Engagement retention (weekly cohort)**
- **Definition:** share of a weekly cohort of new users who come back with any event in a later week.
- **Cohort:** users grouped by the week of their first event.
- **Formula:** users of cohort C with at least one event in week `C + k` / size of cohort C.
- **Edge cases:** same as K10. Users first seen in the first week may have been active before the data starts.
- **Status:** Draft.

**K12 Churned buyer (flag)**
- **Definition:** a buyer who has not ordered for longer than the churn window.
- **Formula:** `days_since_last_order > N` at the snapshot date. The rule and the choice of `N` are in `churn_definition.md`.
- **Grain:** buyer and snapshot date.
- **Status:** Draft (N confirmed in E3-09).

**K13 Churn rate (weekly)**
- **Definition:** share of buyers who become churned during a week.
- **Formula:** buyers who became churned during week W / buyers not churned at the start of week W. Reactivated buyers are reported next to it.
- **Grain:** week.
- **Status:** Draft (N confirmed in E3-09).

**K14 Customer value to date**
- **Definition:** total revenue a buyer has generated up to the snapshot date.
- **Formula:** `SUM(price)` over the buyer's valid purchases. The segment value is the average of its buyers.
- **Grain:** buyer, then segment and cohort.
- **Edge cases:** historical and revenue-based. It is not a forecast and not profit, because no cost data exists. The period is about two months.
- **Status:** Draft.

**K15 Revenue share and Pareto**
- **Definition:** share of revenue from a segment, or cumulative share when buyers are ranked by revenue.
- **Formula:** segment revenue / revenue of buyers with a `user_id`. Pareto: cumulative revenue share of buyers ranked from highest to lowest.
- **Grain:** segment, or buyer rank.
- **Status:** Draft.

**K16 RFM components**
- **Definition:** recency, frequency and monetary values per buyer.
- **Formula:** defined in `rfm_rules.md`.
- **Status:** Draft.

### Funnel

A funnel counts **distinct sessions**. A session counts at a stage only if it also reached the earlier stage, so the funnel always goes down.

**K17 View-to-cart rate**
- **Formula:** sessions with a view and a cart event / sessions with a view event.
- **Grain:** category and week.

**K18 Cart-to-purchase rate**
- **Formula:** sessions with a view, a cart and a purchase / sessions with a view and a cart.
- **Grain:** category and week.

**K19 Conversion rate**
- **Formula:** sessions with a view and a purchase / sessions with a view.
- **Grain:** category and week.

**K20 Cart abandonment rate**
- **Definition:** share of sessions with a cart event that end without a purchase.
- **Formula:** sessions with a cart event and no purchase / sessions with a cart event.
- **Grain:** category and week. The list of abandoned sessions (with value of the carts) is an output of E7-11.
- **Edge cases (K17 to K20):** missing categories form an "unknown" group. Sessions cut by the start or end of the data can lower the rates.
- **Status:** Draft (confirmed in E3-07).

### Data quality

**K21 Data quality pass rate**
- **Formula:** rows that pass a rule / rows checked by that rule.
- **Grain:** rule and load run.
- **Status:** Confirmed.

**K22 Excluded row rate**
- **Formula:** rows removed from KPI calculations (duplicates, invalid prices, unknown event types, missing users) / rows loaded into silver.
- **Grain:** reason and load run.
- **Status:** Confirmed.

---

## 4. Edge-case register

| Case | Decision | Where it shows |
|---|---|---|
| Identical duplicate rows | Removed in silver and counted | K22 |
| Missing brand or category | Kept, grouped as "unknown" | K17 to K20 |
| Price of 0 or below | Excluded from revenue, counted | K01, K22 |
| Missing `user_id` | Kept in revenue and orders, excluded from customer KPIs | K04 to K16 |
| Unknown event type | Excluded, counted | K22 |
| Timestamp outside the data period | Excluded, counted | K22 |
| No order ID | Order approximated by session with a purchase | K02 |
| No quantity | 1 unit per purchase event | K01 |
| No cancellations or returns | Revenue is gross | K01 |
| First and last weeks | Partial, excluded from retention and churn | K06, K10 to K13 |
| Black Friday | Flagged in the date dimension | K01, K02 |
| One person with several IDs | Cannot be detected, listed as a limitation | All customer KPIs |

---

## 5. Open items

| Item | Resolved in |
|---|---|
| Exact first and last event dates and the time span | E3-07 |
| Whether `remove_from_cart` exists and how to treat it | E3-07 |
| Price anomalies and duplicate counts | E3-07 |
| Whether sessions can contain several orders | E3-07 |
| Churn window `N` | E3-09 |
| RFM frequency thresholds | E3-09 |

---

## 6. Decisions

| ID | Decision | Status |
|---|---|---|
| D1 | Cancellations counted in the month of cancellation | **Superseded**: the single dataset has no cancellations |
| D2 | AOV before cancellations | **Superseded**: same reason. AOV is revenue divided by orders |
| D3 | An order is a session with at least one purchase, and each purchase event is 1 unit | Confirmed |
| D4 | Rows without a customer ID stay in revenue and orders, and are excluded from customer KPIs | Confirmed |
| D5 | Retention and churn are measured in weeks, with partial first and last weeks excluded | **To confirm** |
| D6 | The churn window is provisional at 14 days, fixed after profiling (E3-09) | **To confirm** |
| D7 | Amounts are reported as currency units, because the source gives no currency | **To confirm** |
