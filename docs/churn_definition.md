# Churn Definition (v2)

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E1-05

This file fixes the **rule** for churn and the **method** to choose its value. The value of the churn window (`N`) is provisional and is confirmed with the full data in E3-09. KPI formulas are in `docs/metric_dictionary.md` (K12 and K13).

---

## 1. The problem

Customers of an online store do not cancel anything. They simply stop buying. Churn therefore cannot be read from the data, it has to be **defined by inactivity**: a buyer is considered churned when they have been silent for longer than they normally would be.

A churned buyer is only *probably* gone. Some come back, and the rule allows for that (section 5).

---

## 2. The rule

At a given snapshot date, for each buyer with at least one valid order:

`days_since_last_order = snapshot_date - date of the last valid order`

| Status | Condition | Meaning |
|---|---|---|
| **Active** | `days_since_last_order <= 0.5 x N` | Buying normally |
| **Slipping** | `0.5 x N < days_since_last_order <= N` | Quiet for longer than usual, still recoverable |
| **Churned** | `days_since_last_order > N` | Silent longer than the churn window |

- `is_churned = 1` when the status is Churned. This is the flag in K12.
- The **at-risk list** for marketing (question Q4) is the buyers with status Slipping, plus Churned buyers who were high value (RFM segments Champions, Loyal Customers or Can't Lose Them at their last active snapshot).
- The status is called "Slipping" and not "At Risk" so it is never confused with the RFM segment of the same name.

---

## 3. How `N` is chosen

The data covers only about two months, so the window must be short. The rule needs an observed period of at least about **2 x N**, which means **`N` cannot be larger than about 30 days**.

1. Take every buyer with 2 or more valid orders, and calculate the **gap in days between each pair of consecutive orders**.
2. Look at the distribution of those gaps (median, 75th, 90th and 95th percentile).
3. Set `N` near the **90th percentile** of the gaps, between 14 and 21 days.
4. Check the choice with the validation test in section 6.

**Bias to remember:** only gaps shorter than the data period can be observed, so the gaps are cut off and their percentiles are lower than the real ones. This is why `N` is validated with the reactivation test, and not chosen from the percentile alone.

| Item | Provisional value |
|---|---|
| `N` | 14 days. To be fixed between 14 and 21 days in E3-09 |

---

## 4. Limits of the data

- **Short period.** With a period of about 61 days, only short-term churn can be measured. The report says "inactive for more than N days", never "lost customer".
- **Start of the data.** Buyers whose previous orders are before the data starts look like new buyers. The first week is flagged as unreliable (see K06).
- **End of the data.** Buyers who would churn just after the snapshot date cannot be known. Snapshots closer to the end than `N` days are labeled incomplete.
- **Black Friday.** The big sale at the end of November can bring back buyers who were silent. It is checked separately in the validation.

---

## 5. Churn over time (no peeking at the future)

- **As-of calculation.** For a weekly snapshot, only orders up to that date are used. A later purchase never changes an earlier snapshot.
- **Churn date.** A buyer becomes churned on `last order date + N + 1 day`.
- **Weekly churn rate** (K13): buyers who became churned during week W / buyers who were not churned at the start of week W.
- **Reactivation.** A churned buyer who orders again is counted as **reactivated** in that week and is Active again from then on. The number of reactivations is reported next to the churn rate.
- Snapshots before the first complete week are not calculated.

---

## 6. Validation test

To check that `N` is reasonable, take a snapshot **about 4 weeks before the end of the data**, flag churned buyers with that `N`, and measure how many of them **bought again** in the following weeks. Run it once with the Black Friday week and once without it.

| Reactivation rate | Reading |
|---|---|
| Below about 10% | `N` is reasonable |
| Between 10% and 25% | `N` is a little short: try a longer value (up to 21 days) |
| Above 25% | `N` is too short, or the period is too short to say |

These limits are a starting point to adjust with the real results. The test result and the final `N` are written in `docs/validation.md` (E7-13).

---

## 7. Edge cases

| Case | Rule |
|---|---|
| Buyer with one order | Classified with the same rule |
| Events without a `user_id` | Not classified |
| Users who never bought | Not part of churn (they are browsers or cart abandoners) |
| Black Friday buyers | Flagged and reported separately |

---

## 8. Open items

| Item | Resolved in |
|---|---|
| Time span and the final distribution of gaps between orders | E3-07 |
| Final `N` (14 to 21 days) | E3-09 |
| Result of the validation test | E7-13 |
