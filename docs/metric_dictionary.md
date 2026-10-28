# Metric Dictionary (v1)

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E1-03

**One definition per KPI.** The SQL in the gold layer and the DAX measures in Power BI must both follow this file (task E12-10). If a number differs between two places, this file decides which one is right.

Status values: **Draft** (decided, but depends on an assumption to confirm during profiling in E2) and **Confirmed** (no open assumption).

---

## 1. Global rules

1. **Per source.** Every KPI is computed per `source_system` (`online_retail`, `rees46`). Amounts from the two sources are never added together: they differ in currency and in time period.
2. **Customer identity.** A customer is the pair (`source_system`, `customer_id`).
3. **Missing customer ID.** Rows without a customer ID count in revenue and orders, but not in any customer KPI.
4. **Time.** A month is the calendar month of the order date, using the timestamp as stored in the source (REES46 is in UTC). Each source has one fixed snapshot date, set in task E1-04.
5. **Incomplete periods.** A partial last month is flagged and excluded from trends, cohorts and retention.
6. **No silent exclusions.** Rows removed from the KPIs are counted and reported by the data quality KPIs (K20, K21).
7. **Source of the numbers.** KPIs are calculated from cleaned data (silver and gold), never from bronze.

---

## 2. What the words mean in each source

| Concept | Online Retail II (`online_retail`) | REES46 (`rees46`) |
|---|---|---|
| Sales line | One invoice line | One `purchase` event |
| Order | One invoice number | One session (`user_session`) with at least one purchase. **Assumption:** there is no order ID |
| Customer | `Customer ID` (some rows are empty) | `user_id` |
| Quantity | `Quantity` | 1 per purchase event. **Assumption** |
| Unit price | `Price` in pounds sterling (to confirm on the source page) | `price`, currency not stated, so treated as currency units |
| Line amount | `quantity x price` | `price` |
| Date | Invoice date and time, local, no time zone | `event_time`, UTC |
| Cancellation | Invoice number starting with `C`, with a negative quantity | None expected |

**Valid sales line**
- *Online Retail II:* invoice does not start with `C`, quantity is above 0, price is above 0, and the stock code is a real product (the list of non-product codes such as postage or bank charges is fixed in E2).
- *REES46:* `event_type = 'purchase'` and price is above 0.

---

## 3. KPI definitions

### Revenue and orders

**K01 Gross sales amount**
- **Definition:** value of all valid sales lines in the period.
- **Formula:** `SUM(line_amount)` over valid sales lines.
- **Grain:** source and month (also by product, country, segment).
- **Edge cases:** cancellations and adjustment lines are excluded here, and shown in K02.
- **Status:** Draft (non-product stock codes confirmed in E2).

**K02 Cancelled amount**
- **Definition:** value of cancellations in the period, shown as a positive number.
- **Formula:** `ABS(SUM(line_amount))` over lines of invoices starting with `C`.
- **Grain:** source and month.
- **Edge cases:** a cancellation is counted in the month **of the cancellation invoice**, not the month of the original sale. This is simple and consistent, but the original sale is not always known. Returns and cancellations cannot be told apart in this source.
- **Source:** Online Retail II. REES46 has none, so K02 is 0.
- **Status:** Confirmed.

**K03 Net revenue**
- **Definition:** sales kept after cancellations.
- **Formula:** `K01 - K02`.
- **Grain:** source and month.
- **Edge cases:** can be negative in a month with unusually many cancellations. Lines with price 0 or below (adjustments, for example bad debt) are excluded and reported in K21.
- **Status:** Draft.

**K04 Order count**
- **Definition:** number of valid orders in the period.
- **Formula:** `COUNT(DISTINCT order_id)` over valid sales lines.
- **Grain:** source and month.
- **Edge cases:** *Online Retail II:* `order_id` is the invoice number. *REES46:* `order_id` is the session with at least one purchase, so two orders in one session count as one.
- **Status:** Draft (REES46 order rule confirmed in E2).

**K05 Average order value (AOV)**
- **Definition:** average value of an order, before cancellations.
- **Formula:** `K01 / K04`.
- **Grain:** source and month (also by segment).
- **Edge cases:** wholesale invoices create a long tail of very large orders, so the average can be pulled up. The median is shown next to it.
- **Status:** Draft.

### Customers

**K06 Active customers**
- **Definition:** customers with at least one valid order in the period.
- **Formula:** `COUNT(DISTINCT customer_id)` over valid orders with a customer ID.
- **Grain:** source and month.
- **Status:** Draft.

**K07 New customers**
- **Definition:** customers whose first valid order falls in the period.
- **Formula:** customers where `MIN(order_date)` is in the period.
- **Grain:** source and month.
- **Edge cases:** the data starts at one point in time, so customers who already existed appear as "new" in the first month. The first month of each source is flagged as unreliable for new-customer and cohort analysis.
- **Status:** Confirmed.

**K08 Returning customers**
- **Definition:** active customers who are not new in the period.
- **Formula:** `K06 - K07`.
- **Grain:** source and month.
- **Status:** Confirmed.

**K09 Repeat purchase rate**
- **Definition:** share of customers who bought more than once.
- **Formula:** customers with 2 or more valid orders / customers with at least 1 valid order, up to the snapshot date.
- **Grain:** source (also by cohort and segment).
- **Edge cases:** two orders on the same day count as two orders.
- **Status:** Confirmed.

**K10 Days to second order**
- **Definition:** days between a customer's first and second valid order.
- **Formula:** `DATEDIFF(day, first_order_date, second_order_date)`. Reported as the **median** and a distribution, not only the mean.
- **Grain:** source and cohort.
- **Edge cases:** only customers with 2 or more orders are included. This metric is used to justify the churn window (E1-05).
- **Status:** Confirmed.

**K11 Retention rate (by cohort)**
- **Definition:** share of a monthly cohort that buys again in a later month.
- **Cohort:** customers grouped by the month of their first valid order.
- **Formula:** customers in cohort C with at least one valid order in month `C + k` / size of cohort C. Month 0 is 100% by definition.
- **Grain:** source, cohort month and months since first order (k).
- **Edge cases:** the cohort of the first month of data is unreliable (see K07), and incomplete months are excluded (global rule 5). *REES46 covers a short period (to confirm in E2-04), so retention is mainly measured on Online Retail II.*
- **Status:** Draft.

**K12 Churned customer (flag)**
- **Definition:** a customer who has not bought for longer than the churn window.
- **Formula:** `days_since_last_order > N` at the snapshot date, where `N` is the churn window set in task E1-05 from the distribution in K10.
- **Grain:** customer, per source.
- **Edge cases:** `N` differs per source. REES46 can only support a short window because of its time span.
- **Status:** Draft until E1-05.

**K13 Churn rate**
- **Definition:** share of customers who are churned at the snapshot date.
- **Formula:** churned customers (K12) / customers with at least 1 valid order.
- **Grain:** source and month-end snapshot (for the trend).
- **Status:** Draft until E1-05.

**K14 Customer lifetime value (historical CLV)**
- **Definition:** total net revenue a customer has generated up to the snapshot date.
- **Formula:** `SUM(net_revenue)` per customer. The segment CLV is the average of its customers.
- **Grain:** customer, then segment and cohort.
- **Edge cases:** this is **historical and revenue-based**. It is not a forecast, and it is not profit, because no cost or margin data exists.
- **Status:** Draft.

**K15 Revenue share and Pareto**
- **Definition:** share of net revenue from a segment, or cumulative share when customers are ranked by net revenue.
- **Formula:** segment net revenue / total net revenue of customers with an ID. Pareto: cumulative net revenue share of customers ranked from highest to lowest.
- **Grain:** source and segment.
- **Edge cases:** revenue from rows without a customer ID is excluded from the denominator and reported separately.
- **Status:** Draft.

**K16 RFM components**
- **Definition:** recency, frequency and monetary values per customer.
- **Formula:** defined in `docs/rfm_rules.md` (task E1-04).
- **Status:** Open until E1-04.

### Funnel (REES46)

A funnel counts **distinct sessions**. A session counts at a stage only if it also reached the earlier stage, so the funnel always goes down.

**K17 View-to-cart rate**
- **Formula:** sessions with a view and a cart event / sessions with a view event.
- **Grain:** category and month.

**K18 Cart-to-purchase rate**
- **Formula:** sessions with a view, a cart and a purchase / sessions with a view and a cart.
- **Grain:** category and month.

**K19 Conversion rate**
- **Formula:** sessions with a view and a purchase / sessions with a view.
- **Grain:** category and month.
- **Edge cases (K17 to K19):** missing category values form their own "unknown" group. Sessions that start before the data window are cut and can reduce the rates.
- **Status:** Draft (confirmed after profiling in E2-04).

### Data quality

**K20 Data quality pass rate**
- **Formula:** rows that pass a rule / rows checked by that rule.
- **Grain:** source, rule and load run.
- **Status:** Confirmed.

**K21 Excluded row rate**
- **Formula:** rows removed from KPI calculations (cancellations treated separately, bad prices, non-product codes, duplicates) / rows loaded into silver.
- **Grain:** source and reason.
- **Status:** Confirmed.

---

## 4. Edge-case register

| Case | Source | Decision | Where it shows |
|---|---|---|---|
| Cancellation invoices (`C...`) | Online Retail II | Excluded from K01, shown in K02, counted in the month of cancellation | K02, K03 |
| Returns | Online Retail II | Cannot be separated from cancellations | K02 |
| Missing customer ID | Online Retail II | Kept in revenue and orders, excluded from customer KPIs | K06 to K15 |
| Price of 0 or below (adjustments) | Online Retail II | Excluded from sales, reported | K21 |
| Non-product stock codes (postage, fees) | Online Retail II | Excluded from product revenue, listed in E2 | K01, K21 |
| Duplicate rows | Both | Removed in silver, counted | K21 |
| Large wholesale orders | Online Retail II | Kept, flagged, median shown with AOV | K05 |
| No order ID | REES46 | Order approximated by session with a purchase | K04 |
| No quantity | REES46 | 1 unit per purchase event | K01 |
| First month of data | Both | Flagged as unreliable for new customers and cohorts | K07, K11 |
| Different currency and period | Both | Amounts are never added across sources | Global rule 1 |

---

## 5. Open items

| Item | Resolved in |
|---|---|
| List of non-product stock codes | E2-03 |
| Confirm currency of Online Retail II prices | E2-02 |
| REES46 order and quantity assumptions, and its time span | E2-04 |
| Churn window `N` per source | E1-05 |
| RFM windows and segment rules | E1-04 |

---

## 6. Decisions confirmed

| ID | Decision | Confirmed on |
|---|---|---|
| D1 | Cancellations are counted in the month of the cancellation invoice, not the month of the original sale | 2026-10-28 |
| D2 | AOV is calculated before cancellations (K01 divided by K04), with the median shown next to it | 2026-10-28 |
| D3 | A REES46 order is a session with at least one purchase, and each purchase event is 1 unit. Re-checked in E2-04 | 2026-10-28 |
| D4 | Rows without a customer ID stay in revenue and orders, and are excluded from customer KPIs | 2026-10-28 |
