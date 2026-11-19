# Validation of the Analytics Layer (E7-13)

Project: E-commerce Customer Retention & RFM (SQL Server)
Layer: gold (`ecommerce_rfm_dwh`). Each check is a query, with the expected result and the actual result.

## 0. Run order (views need their tables first)

1. `core_metrics.sql` (views only, no table needed)
2. `calc_rfm.sql`, then `EXEC gold.calc_rfm @snapshot_date = '2019-12-01';`
3. `segment_summary.sql`
4. `cohort_retention.sql`, `engagement_retention.sql`
5. `churn.sql`, then `EXEC gold.calc_churn @snapshot_date = '2019-12-01', @churn_days = 14;`
6. `customer_value.sql`, `pareto.sql`
7. `time_analysis.sql`, `funnel.sql`, `cart_abandonment.sql`, `category_brand.sql`

## 1. Totals reconcile

| Check | Query | Expected |
|---|---|---|
| Order value = purchase lines | `SELECT SUM(order_value) FROM gold.fact_order` and `SELECT SUM(price) FROM gold.fact_order_line` | Equal (505,126,293.44 measured) |
| Daily = weekly revenue | `SELECT SUM(revenue) FROM gold.v_daily_metrics` and `SELECT SUM(revenue) FROM gold.v_weekly_metrics` | Equal |
| Segment revenue = customer revenue | `SELECT SUM(revenue) FROM gold.v_segment_summary` and `SELECT SUM(monetary_amount) FROM gold.v_rfm_latest` | Equal |
| Segment customers = RFM customers | `SELECT SUM(customers) FROM gold.v_segment_summary` and `SELECT COUNT(*) FROM gold.v_rfm_latest` | Equal |
| Customer value = RFM monetary | Compare `gold.v_customer_value` revenue with `gold.v_rfm_latest` monetary for the same customers | Equal |

## 2. Cohorts are coherent

| Check | Query | Expected |
|---|---|---|
| Week 0 is 100% | `SELECT COUNT(*) FROM gold.v_cohort_retention WHERE weeks_since = 0 AND retention_pct <> 100` | 0 |
| Retention never grows above 100% | `SELECT COUNT(*) FROM gold.v_cohort_retention WHERE retention_pct > 100` | 0 |
| Engagement week 0 is 100% | `SELECT COUNT(*) FROM gold.v_engagement_retention WHERE weeks_since = 0 AND retention_pct <> 100` | 0 |

## 3. Funnel sanity (decision D8)

| Check | Query | Expected |
|---|---|---|
| Sessions per stage are non-negative and rates are coherent | `SELECT COUNT(*) FROM gold.v_funnel_category_week WHERE view_to_purchase_pct > 100` | 0 |
| Cart rate above 100% (allowed by D8, must be explained) | `SELECT COUNT(*) FROM gold.v_funnel_category_week WHERE view_to_cart_pct > 100` | Counted and explained |

## 4. Churn window: the reactivation test

Purpose: confirm that N = 14 days (decision D6) is reasonable. Snapshot 4 weeks before the end of the data
(2 November 2019). Buyers classed Churned are followed until 30 November.

```sql
USE ecommerce_rfm_dwh;
EXEC gold.calc_rfm   @snapshot_date = '2019-11-02';
EXEC gold.calc_churn @snapshot_date = '2019-11-02', @churn_days = 14;

SELECT
    COUNT(*)                                                    AS churned_buyers,
    SUM(CASE WHEN EXISTS (
            SELECT 1
            FROM gold.fact_order AS o
            INNER JOIN gold.dim_customer AS c ON c.customer_key = o.customer_key
            INNER JOIN gold.dim_date     AS d ON d.date_key     = o.order_date_key
            WHERE c.customer_id = ch.customer_id
              AND d.full_date > '2019-11-02' AND d.full_date <= '2019-11-30')
        THEN 1 ELSE 0 END)                                      AS reactivated,
    CAST(100.0 * SUM(CASE WHEN EXISTS (
            SELECT 1
            FROM gold.fact_order AS o
            INNER JOIN gold.dim_customer AS c ON c.customer_key = o.customer_key
            INNER JOIN gold.dim_date     AS d ON d.date_key     = o.order_date_key
            WHERE c.customer_id = ch.customer_id
              AND d.full_date > '2019-11-02' AND d.full_date <= '2019-11-30')
        THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS decimal(6,2)) AS reactivation_pct
FROM gold.report_customer_churn AS ch
WHERE ch.snapshot_date = '2019-11-02' AND ch.is_churned = 1;
```

Run it again with `@churn_days = 21` to compare.

| Reactivation rate | Reading (churn_definition.md, section 6) | Decision |
|---|---|---|
| Below 10% | N is reasonable | Keep N |
| 10% to 25% | N is a little short | Try 21 days |
| Above 25% | N is too short, or the period is too short | Keep the result as a limit |

**Black Friday check.** Repeat the query with `d.full_date <= '2019-11-24'` (before Black Friday) to see
whether the sale brings back buyers who were silent. Report both numbers.

**Result (to fill in):**

| Churn window | Churned buyers | Reactivated | Reactivation % | Decision |
|---|---|---|---|---|
| 14 days | | | | |
| 21 days | | | | |

## 5. Interpretation limits

- The period is 61 days, so every "churn" is inactivity inside the period, not a lost customer.
- The segment used for "high value" is the segment at the snapshot date (simplified, see churn.sql).
- Cart value ignores unknown prices (NULL), so it is a lower bound.
- The funnel is counted per stage (D8), so stages are not strictly nested.
