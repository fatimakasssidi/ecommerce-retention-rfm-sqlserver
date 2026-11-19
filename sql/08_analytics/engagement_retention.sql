/*
Purpose : Weekly engagement retention. Cohort = week of a user's first event (any type).
          Share of the cohort with any event N weeks later (E7-05).
Task    : E7-05
Layer   : gold (ecommerce_rfm_dwh), view only
Note    : Uses all events, so it measures visits, not purchases. Compare with E7-04.
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_engagement_retention
AS
WITH active_by_week AS
(
    SELECT DISTINCT c.customer_id, d.week_start_date AS active_week
    FROM gold.fact_event AS e
    INNER JOIN gold.dim_customer AS c ON c.customer_key = e.customer_key
    INNER JOIN gold.dim_date     AS d ON d.date_key     = e.date_key
    WHERE c.customer_id <> -1
),
cohort_of AS
(
    SELECT customer_id, MIN(active_week) AS cohort_week
    FROM active_by_week
    GROUP BY customer_id
),
cells AS
(
    SELECT co.cohort_week,
           DATEDIFF(day, co.cohort_week, aw.active_week) / 7 AS weeks_since,
           COUNT(DISTINCT aw.customer_id)                    AS users
    FROM cohort_of AS co
    INNER JOIN active_by_week AS aw ON aw.customer_id = co.customer_id
    GROUP BY co.cohort_week, DATEDIFF(day, co.cohort_week, aw.active_week) / 7
),
sized AS
(
    SELECT cl.*,
           MAX(CASE WHEN cl.weeks_since = 0 THEN cl.users END) OVER (PARTITION BY cl.cohort_week) AS cohort_size
    FROM cells AS cl
)
SELECT
    s.cohort_week,
    s.weeks_since,
    s.cohort_size,
    s.users,
    CAST(100.0 * s.users / NULLIF(s.cohort_size, 0) AS decimal(6,2)) AS retention_pct
FROM sized AS s;
GO
