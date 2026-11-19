/*
Purpose : Customer value to date: revenue, orders, first and last order, by customer,
          and the average value per segment and per cohort month (E7-07).
Task    : E7-07
Layer   : gold (ecommerce_rfm_dwh), views only
Note    : Historical revenue only, not a forecast and not profit (no cost data). Period is 61 days.
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_customer_value
AS
SELECT
    c.customer_id,
    COUNT(*)                                          AS orders,
    SUM(o.order_value)                                AS revenue,
    CAST(AVG(o.order_value) AS decimal(12,2))         AS average_order_value,
    MIN(d.full_date)                                  AS first_order_date,
    MAX(d.full_date)                                  AS last_order_date
FROM gold.fact_order AS o
INNER JOIN gold.dim_customer AS c ON c.customer_key = o.customer_key
INNER JOIN gold.dim_date     AS d ON d.date_key     = o.order_date_key
WHERE c.customer_id <> -1
GROUP BY c.customer_id;
GO

CREATE OR ALTER VIEW gold.v_value_by_segment
AS
SELECT
    r.rfm_segment,
    COUNT(*)                                       AS customers,
    CAST(AVG(v.revenue) AS decimal(12,2))          AS average_value,
    CAST(AVG(CAST(v.orders AS float)) AS decimal(9,2)) AS average_orders
FROM gold.v_rfm_latest AS r
INNER JOIN gold.v_customer_value AS v ON v.customer_id = r.customer_id
GROUP BY r.rfm_segment;
GO

CREATE OR ALTER VIEW gold.v_value_by_cohort_month
AS
SELECT
    FORMAT(v.first_order_date, 'yyyy-MM')          AS first_order_month,
    COUNT(*)                                       AS customers,
    CAST(AVG(v.revenue) AS decimal(12,2))          AS average_value
FROM gold.v_customer_value AS v
GROUP BY FORMAT(v.first_order_date, 'yyyy-MM');
GO
