/*
Purpose : Weekly purchase retention. Cohort = week of a customer's first order.
          Each cell = buyers of the cohort who ordered again N weeks later (E7-04).
Task    : E7-04
Layer   : gold (ecommerce_rfm_dwh), view only
Rules   : week 0 = 100% by definition. Partial cohorts (week of 30 Sep or 25 Nov) and partial observation
          weeks (starting 25 Nov or later) are flagged, not hidden.
          Customers without a customer link (-1) are excluded.
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_cohort_retention
AS
WITH orders_by_week AS
(
    SELECT DISTINCT c.customer_id, d.week_start_date AS order_week
    FROM gold.fact_order AS o
    INNER JOIN gold.dim_customer AS c ON c.customer_key = o.customer_key
    INNER JOIN gold.dim_date     AS d ON d.date_key     = o.order_date_key
    WHERE c.customer_id <> -1
),
cohort_of AS
(
    SELECT customer_id, MIN(order_week) AS cohort_week
    FROM orders_by_week
    GROUP BY customer_id
),
cells AS
(
    SELECT co.cohort_week,
           DATEDIFF(day, co.cohort_week, ow.order_week) / 7 AS weeks_since,
           COUNT(DISTINCT ow.customer_id)                   AS buyers
    FROM cohort_of AS co
    INNER JOIN orders_by_week AS ow ON ow.customer_id = co.customer_id
    GROUP BY co.cohort_week, DATEDIFF(day, co.cohort_week, ow.order_week) / 7
),
sized AS
(
    SELECT cl.*,
           MAX(CASE WHEN cl.weeks_since = 0 THEN cl.buyers END) OVER (PARTITION BY cl.cohort_week) AS cohort_size
    FROM cells AS cl
)
SELECT
    s.cohort_week,
    s.weeks_since,
    s.cohort_size,
    s.buyers,
    CAST(100.0 * s.buyers / NULLIF(s.cohort_size, 0) AS decimal(6,2)) AS retention_pct,
    CAST(CASE WHEN dc.is_partial_week = 1 THEN 1 ELSE 0 END AS bit)  AS is_partial_cohort,
    CAST(CASE WHEN DATEADD(day, 7 * s.weeks_since, s.cohort_week) >= '2019-11-25' THEN 1 ELSE 0 END AS bit) AS is_partial_observation
FROM sized AS s
INNER JOIN gold.dim_date AS dc ON dc.full_date = s.cohort_week;
GO
