# RFM Scoring Rules (v2)

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E1-04

RFM ranks buyers on three questions: how **recently** did they buy (Recency), how **often** do they buy (Frequency), and how **much** do they spend (Monetary). Each buyer gets a score from 1 (worst) to 5 (best) on each dimension, and the scores are mapped to a named segment such as "Champions" or "At Risk".

These rules use the definitions in `docs/metric_dictionary.md`. Where this file and the dictionary disagree, the dictionary wins.

---

## 1. Inputs per buyer

Only buyers with a `user_id` and at least one valid order are scored. Users who only browse are not scored (see section 5).

| Component | Definition | Based on |
|---|---|---|
| Recency (`recency_days`) | Snapshot date minus the date of the buyer's last valid order, in days | K02 |
| Frequency (`frequency_count`) | Number of distinct valid orders in the window | K02 |
| Monetary (`monetary_amount`) | Revenue of the buyer in the window | K01 |

---

## 2. Snapshot date and window

| Item | Rule |
|---|---|
| Snapshot date | The day after the last event date in the data. Expected 2019-12-01, to confirm in E3-07 |
| Window | The full data period (about 61 days) |

- The snapshot date is a **parameter** of the calculation (`@snapshot_date`), never `GETDATE()`, so every result is reproducible.
- Each run is stored with its `snapshot_date`, so segment changes over time can be followed.
- The period is short, so recency values range from 0 to about 60 days. The result is called **short-window RFM** and is read with that in mind.

---

## 3. Scoring

Each dimension gets a score from 1 to 5, where **5 is always the best**.

| Dimension | Method | Direction |
|---|---|---|
| Recency | Percentile thresholds at the 20th, 40th, 60th and 80th percentile of `recency_days` | Fewer days is better, so the lowest 20% of days gets score 5 |
| Monetary | Percentile thresholds at the 20th, 40th, 60th and 80th percentile of `monetary_amount` | Higher is better |
| Frequency | Fixed thresholds on `frequency_count` (provisional): 1 order = 1, 2 = 2, 3 = 3, 4 to 5 = 4, 6 or more = 5 | Higher is better |

**Why percentile thresholds and not `NTILE(5)`:** many buyers share exactly the same value (for example, the same recency day or a single order). `NTILE` splits tied buyers across different buckets in an arbitrary order, so two identical buyers can get different scores, and the result can change between runs. With thresholds, equal values always get equal scores, and the result is reproducible.

**Why frequency is different:** it is a small whole number, and a large share of buyers have exactly one order, so percentiles would collapse. Fixed thresholds based on the real distribution are clearer. The thresholds are provisional and are checked in E3-09.

**Combined frequency and monetary score:**
`fm_score = ROUND((frequency_score + monetary_score) / 2.0)`, with halves rounded up.

Thresholds are recalculated on each run, and the values used are stored with the results.

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
| Can't Lose Them | Highest value, but have gone quiet | Priority outreach |
| Hibernating | Inactive and low value | Low-cost reactivation, or leave alone |

---

## 5. Users who do not buy

RFM needs a purchase, so visitors who never buy are outside it. They are not ignored: they are grouped separately for marketing.

| Group | Rule |
|---|---|
| Cart abandoners | At least one cart event and no purchase in the period |
| Browsers | Views only |

These groups are an output of the cart abandonment analysis (E7-11).

---

## 6. Edge cases

| Case | Rule |
|---|---|
| Events without a `user_id` | Not scored (counted in revenue only) |
| Ties | Equal values get equal scores (section 3) |
| Buyers with one order | Allowed. They fall mainly into New Customers, About to Sleep or Hibernating |
| Black Friday | Buyers whose only order is on Black Friday are flagged, because their recency and spend are driven by the event |
| Very large spenders | Percentile thresholds limit their effect on the scores of others |

---

## 7. Output

Table `gold.report_customer_rfm`, one row per buyer and snapshot date:

`customer_id`, `snapshot_date`, `recency_days`, `frequency_count`, `monetary_amount`, `recency_score`, `frequency_score`, `monetary_score`, `fm_score`, `rfm_segment`.

---

## 8. Open items

| Item | Resolved in |
|---|---|
| Real snapshot date (last event date) | E3-07 |
| Frequency thresholds, checked against the real distribution | E3-09 |

---

## 9. Decisions confirmed

| ID | Decision | Confirmed on |
|---|---|---|
| R1 | Percentile thresholds for recency and monetary, instead of `NTILE` | 2026-10-28 |
| R2 | Nine segments from the 5 by 5 grid | 2026-10-28 |
