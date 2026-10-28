# Churn Definition (v1)

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E1-05

This file fixes the **rule** for churn and the **method** to choose its value. The value of the churn window (`N`) is provisional and is confirmed with real data in E2-03. KPI formulas are in `docs/metric_dictionary.md` (K12 and K13).

---

## 1. The problem

Customers of an online shop do not cancel anything. They simply stop buying. Churn therefore cannot be read from the data, it has to be **defined by inactivity**: a customer is considered churned when they have been silent for longer than they normally would be.

A churned customer is only *probably* gone. Some come back, and the rule allows for that (section 5).

---

## 2. The rule

At a given snapshot date, for each customer with at least one valid order:

`days_since_last_order = snapshot_date - date of the last valid order`

| Status | Condition | Meaning |
|---|---|---|
| **Active** | `days_since_last_order <= 0.5 x N` | Buying normally |
| **Slipping** | `0.5 x N < days_since_last_order <= N` | Quiet for longer than usual, still recoverable |
| **Churned** | `days_since_last_order > N` | Silent longer than the churn window |

- `is_churned = 1` when the status is Churned. This is the flag in K12.
- The **at-risk list** for marketing (question Q4) is the customers with status Slipping, plus Churned customers who were high value (RFM segments Champions, Loyal Customers or Can't Lose Them at their last active snapshot).
- The status is called "Slipping" and not "At Risk" so it is never confused with the RFM segment of the same name.

---

## 3. How `N` is chosen

1. Take every customer with 2 or more valid orders, and calculate the **gap in days between each pair of consecutive orders**.
2. Look at the distribution of those gaps (median, 75th, 90th and 95th percentile), overall and for the main segments.
3. Set `N` near the **90th percentile** of the gaps: a customer who is silent longer than 90% of normal gaps has probably stopped. Round to a multiple of 30 days, with a minimum of 30.
4. Check the choice with the validation test in section 6.

| Source | Provisional `N` | Status |
|---|---|---|
| `online_retail` | 90 days | **Provisional.** Expected between 90 and 180 days after profiling. This is a giftware shop with a Christmas peak, so seasonal customers who buy once a year may need a longer window |
| `rees46` | Not set | See section 4 |

---

## 4. Limits of the data

- **Short period (REES46).** The churn rule needs an observed period of at least about **2 x N**. REES46 covers a short period (confirmed in E2-04), so a window of 90 days is impossible. Churn is reported for REES46 only if the profiling shows that it is meaningful. Otherwise it is marked "not computed" and not shown, which is better than a misleading number.
- **Start of the data.** Customers whose previous orders are before the start of the data look like new customers. The first months of each source are flagged as unreliable (see K07).
- **End of the data.** Customers who would churn just after the snapshot date cannot be known. Snapshots closer to the end than `N` days are labeled incomplete.

---

## 5. Churn over time (no peeking at the future)

- **As-of calculation.** For a month-end snapshot, only orders up to that date are used. A later purchase never changes an earlier snapshot.
- **Churn date.** A customer becomes churned on `last order date + N + 1 day`.
- **Monthly churn rate** (K13): customers who became churned during month M / customers who were not churned at the start of month M.
- **Reactivation.** A churned customer who orders again is counted as **reactivated** in that month and is Active again from then on. The number of reactivations is reported next to the churn rate.

---

## 6. Validation test

To check that `N` is reasonable, take a snapshot **about 6 months before the end of the data**, flag churned customers with that `N`, and measure how many of them **bought again** in the following months.

| Reactivation rate | Reading |
|---|---|
| Below about 10% | `N` is reasonable |
| Between 10% and 25% | `N` is a little short: check seasonal customers and try the next multiple of 30 |
| Above 25% | `N` is too short: increase it |

These limits are a starting point to be adjusted with the real results. The test result and the final `N` are written in `docs/validation.md` (E7-11).

---

## 7. Edge cases

| Case | Rule |
|---|---|
| Customer with one order | Classified with the same rule (their gap history is empty, so they use the source-level `N`) |
| Customer with only cancellations | No valid order, so not classified |
| Rows without a customer ID | Not classified |
| Seasonal customers (buy once a year) | May look churned between seasons. Handled by choosing a longer `N` and by the validation test |
| Different sources | Each has its own `N`, and results are never combined |

---

## 8. Open items

| Item | Resolved in |
|---|---|
| Distribution of the gaps between orders and the final `N` for Online Retail II | E2-03 |
| Whether churn is meaningful for REES46 | E2-04 |
| Result of the validation test | E7-11 |
