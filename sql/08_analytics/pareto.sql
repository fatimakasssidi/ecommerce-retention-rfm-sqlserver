/*
Purpose : Pareto 80/20: cumulative revenue share of customers and of products, ranked from the highest (E7-08).
Task    : E7-08
Layer   : gold (ecommerce_rfm_dwh), views only
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_pareto_customers
AS
SELECT
    customer_id,
    revenue,
    ROW_NUMBER() OVER (ORDER BY revenue DESC, customer_id)                    AS revenue_rank,
    CAST(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC, customer_id
                                    ROWS UNBOUNDED PRECEDING)
                 / SUM(revenue) OVER () AS decimal(7,3))                      AS cumulative_revenue_pct,
    CAST(100.0 * ROW_NUMBER() OVER (ORDER BY revenue DESC, customer_id)
                 / COUNT(*) OVER () AS decimal(7,3))                          AS cumulative_customer_pct
FROM gold.v_customer_value;
GO

CREATE OR ALTER VIEW gold.v_pareto_products
AS
WITH product_revenue AS
(
    SELECT p.product_id, SUM(l.price) AS revenue
    FROM gold.fact_order_line AS l
    INNER JOIN gold.dim_product AS p ON p.product_key = l.product_key
    GROUP BY p.product_id
)
SELECT
    product_id,
    revenue,
    ROW_NUMBER() OVER (ORDER BY revenue DESC, product_id)                     AS revenue_rank,
    CAST(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC, product_id
                                    ROWS UNBOUNDED PRECEDING)
                 / SUM(revenue) OVER () AS decimal(7,3))                      AS cumulative_revenue_pct
FROM product_revenue;
GO

/* How many customers make 80% of revenue (share of the customer base):
SELECT CAST(100.0 * MIN(revenue_rank) / (SELECT COUNT(*) FROM gold.v_customer_value) AS decimal(6,2)) AS pct_customers_for_80_pct
FROM gold.v_pareto_customers WHERE cumulative_revenue_pct >= 80; */
