# RFM Scoring Rules (v1)

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E1-04

RFM ranks customers on three questions: how **recently** did they buy (Recency), how **often** do they buy (Frequency), and how **much** do they spend (Monetary). Each customer gets a score from 1 (worst) to 5 (best) on each dimension, and the scores are mapped to a named segment such as "Champions" or "At Risk".

These rules use the definitions in `docs/metric_dictionary.md`. Where this file and the dictionary disagree, the dictionary wins.

---

## 1. Inputs per customer

Only customers with an ID and at least one valid order are scored. Everything is calculated **per source**.

| Component | Definition | Based on |
|---|---|---|
| Recency (`recency_days`) | Snapshot date minus the date of the customer's last valid order, in days | K04 orders |
| Frequency (`frequency_count`) | Number of distinct valid orders in the window | K04 |
| Monetary (`monetary_amount`) | Net revenue of the customer in the window | K03 |

---

## 2. Snapshot date and window

| Source | Snapshot date | Window |
|---|---|---|
| `online_retail` | The day after the last invoice date in the data. Expected: 2011-12-10, to confirm in E2-03 | Full history (about 24 months) |
| `rees46` | The day after the last event date in the data, to confirm in E2-04 | Full history (a short period) |

- The snapshot date is a **parameter** of the calculation (`@snapshot_date`), never `GETDATE()`. This makes every result reproducible.
- Each run is stored with its `snapshot_date`, so segment changes over time can be followed later.
- REES46 covers a short period, so its recency values are small. Its RFM is labeled "short-window RFM" and is interpreted with care.

---

## 3. Scoring

Each dimension gets a score from 1 to 5, where **5 is always the best**.

| Dimension | Method | Direction |
|---|---|---|
| Recency | Percentile thresholds at the 20th, 40th, 60th and 80th percentile of `recency_days` | Fewer days is better, so the lowest 20% of days gets score 5 |
| Monetary | Percentile thresholds at the 20th, 40th, 60th and 80th percentile of `monetary_amount` | Higher is better |
| Frequency | Fixed thresholds on `frequency_count` (provisional): 1 order = 1, 2 = 2, 3 to 4 = 3, 5 to 9 = 4, 10 or more = 5 | Higher is better |

**Why percentile thresholds and not `NTILE(5)`:** many customers share exactly the same value (for example, the same recency day or a single order). `NTILE` splits tied customers across different buckets in an arbitrary order, so two identical customers can get different scores, and the result can change between runs. With thresholds, equal values always get equal scores, and the result is reproducible.

**Why frequency is different:** it is a small whole number, and a large share of customers have exactly one order. Percentiles would collapse (the 20th, 40th and 60th percentile can all be 1), so fixed thresholds based on the real distribution are clearer. The thresholds above are provisional and are checked against the distribution in E2.

**Combined frequency and monetary score:**
`fm_score = ROUND((frequency_score + monetary_score) / 2.0)`, with halves rounded up.

Thresholds are recalculated on each run and per source, and the values used are stored with the results.

---

## 4. Segment mapping

The segment is looked up from the pair (`recency_score`, `fm_score`). The grid below is stored in a table (`gold.dim_rfm_segment`) and not hardcoded in a `CASE` expression, so the rules can change without changing the code.

| Recency score | FM = 1 | FM = 2 | FM = 3 | FM = 4 | FM = 5 |
|---|---|---|---|---|---|
| **5** | New Customers | Potential Loyalists | Potential Loyalists | Champions | Champions |
| **4** | New Customers | Potential Loyalists | Potential Loyalists | Champions | Champions |
| **3** | About to Sleep | Need Attention | Need Attention | Loyal Customers | Loyal Customers |
| **2** | About to Sleep | About to Sleep | At Risk | At Risk | Can't Lose Them |
| **1** | Hibernating | Hibernating | At Risk | At Risk | Can't Lose Them |

All 25 combinations belong to exactly one segment.

| Segment | Meaning | Suggested action |
|---|---|---|
| Champions | Bought recently, often, and spend a lot | Reward them, ask for reviews, early access |
| Loyal Customers | Good frequency and spend, fairly recent | Loyalty program, upsell |
| Potential Loyalists | Recent, moderate frequency and spend | Encourage a repeat purchase, recommendations |
| New Customers | Very recent, low frequency and spend | Onboarding, welcome offer |
| Need Attention | Average on all three | Limited-time offers, reminders |
| About to Sleep | Falling recency, low engagement | Reactivation message before they lapse |
| At Risk | Used to buy often or spend a lot, but not recently | Personal win-back offers |
| Can't Lose Them | Highest value, but have gone quiet | Priority outreach, direct contact |
| Hibernating | Long inactive and low value | Low-cost reactivation, or leave alone |

---

## 5. Edge cases

| Case | Rule |
|---|---|
| Rows without a customer ID | Not scored (counted in revenue only) |
| Customer with only cancellations | No valid order, so not scored |
| Customer with net revenue of 0 or below | Scored on the valid orders, and `monetary_amount` floored at 0 |
| Very large wholesale customers | Percentile thresholds limit their effect on the scores of others |
| Ties | Equal values get equal scores (section 3) |
| Customers with one order | Allowed. They fall mainly into New Customers, About to Sleep or Hibernating |
| Different sources | Scored separately, never in the same ranking |

---

## 6. Output

Table `gold.report_customer_rfm`, one row per customer and snapshot date:

`source_system`, `customer_id`, `snapshot_date`, `recency_days`, `frequency_count`, `monetary_amount`, `recency_score`, `frequency_score`, `monetary_score`, `fm_score`, `rfm_segment`.

---

## 7. Open items

| Item | Resolved in |
|---|---|
| Real snapshot dates (last date in each source) | E2-03, E2-04 |
| Frequency thresholds, checked against the real distribution | E2-03 |
| Whether short-window RFM on REES46 is useful or only informative | E2-04 and E7 |
