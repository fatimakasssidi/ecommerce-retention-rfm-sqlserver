/*
Purpose : Time analysis: running revenue, week over week change, hour and weekday patterns,
          Black Friday effect (E7-09).
Task    : E7-09
Layer   : gold (ecommerce_rfm_dwh), views only
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_running_revenue
AS
SELECT
    metric_date,
    revenue,
    SUM(revenue) OVER (ORDER BY metric_date ROWS UNBOUNDED PRECEDING) AS running_revenue,
    orders,
    SUM(orders)  OVER (ORDER BY metric_date ROWS UNBOUNDED PRECEDING) AS running_orders
FROM gold.v_daily_metrics;
GO

CREATE OR ALTER VIEW gold.v_week_over_week
AS
SELECT
    week_start_date,
    is_partial_week,
    revenue,
    LAG(revenue) OVER (ORDER BY week_start_date)                       AS previous_week_revenue,
    CAST(100.0 * (revenue - LAG(revenue) OVER (ORDER BY week_start_date))
         / NULLIF(LAG(revenue) OVER (ORDER BY week_start_date), 0) AS decimal(9,2)) AS change_pct
FROM gold.v_weekly_metrics;
GO

CREATE OR ALTER VIEW gold.v_hour_weekday
AS
SELECT
    DATENAME(weekday, e.event_time)                 AS weekday_name,
    DATEPART(weekday, e.event_time)                 AS weekday_number,
    DATEPART(hour, e.event_time)                    AS hour_utc,
    COUNT_BIG(*)                                    AS events,
    SUM(CASE WHEN e.event_type_key = 4 THEN 1 ELSE 0 END) AS purchases
FROM gold.fact_event AS e
GROUP BY DATENAME(weekday, e.event_time), DATEPART(weekday, e.event_time), DATEPART(hour, e.event_time);
GO

/* Black Friday effect: each day against the average day of the 4 complete weeks before it.
   Black Friday = 29 Nov 2019. Read with care: the sample of 61 days contains one such event. */
CREATE OR ALTER VIEW gold.v_black_friday_effect
AS
WITH baseline AS
(
    SELECT AVG(revenue) AS avg_daily_revenue
    FROM gold.v_daily_metrics
    WHERE metric_date BETWEEN '2019-10-28' AND '2019-11-24'
)
SELECT
    m.metric_date,
    m.revenue,
    CAST(m.revenue / b.avg_daily_revenue AS decimal(9,3)) AS ratio_to_baseline_day,
    m.is_black_friday
FROM gold.v_daily_metrics AS m
CROSS JOIN baseline AS b
WHERE m.metric_date BETWEEN '2019-11-22' AND '2019-12-01';
GO
