/*
Purpose : Core metrics by day and by week: orders, buyers, revenue, average order value (E7-01).
Task    : E7-01
Layer   : gold (ecommerce_rfm_dwh). Views only: no data is written.
Depends : gold.fact_order, gold.dim_date
Definitions: metric_dictionary.md K01 to K06. Revenue = sum of order values (decision D7: currency units).
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_daily_metrics
AS
SELECT
    d.full_date                                                          AS metric_date,
    d.week_start_date,
    d.is_partial_week,
    d.is_black_friday,
    COUNT(*)                                                             AS orders,
    COUNT(DISTINCT CASE WHEN o.customer_key <> -1 THEN o.customer_key END) AS buyers,
    SUM(o.order_value)                                                   AS revenue,
    CAST(SUM(o.order_value) / NULLIF(COUNT(*), 0) AS decimal(12,2))      AS average_order_value
FROM gold.fact_order AS o
INNER JOIN gold.dim_date AS d ON d.date_key = o.order_date_key
GROUP BY d.full_date, d.week_start_date, d.is_partial_week, d.is_black_friday;
GO

CREATE OR ALTER VIEW gold.v_weekly_metrics
AS
SELECT
    d.week_start_date,
    MAX(CAST(d.is_partial_week AS int))                                  AS is_partial_week,
    COUNT(*)                                                             AS orders,
    COUNT(DISTINCT CASE WHEN o.customer_key <> -1 THEN o.customer_key END) AS buyers,
    SUM(o.order_value)                                                   AS revenue,
    CAST(SUM(o.order_value) / NULLIF(COUNT(*), 0) AS decimal(12,2))      AS average_order_value
FROM gold.fact_order AS o
INNER JOIN gold.dim_date AS d ON d.date_key = o.order_date_key
GROUP BY d.week_start_date;
GO
