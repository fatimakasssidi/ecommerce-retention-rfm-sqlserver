/*
Purpose : Ranking of category groups and brands by revenue and conversion (E7-12).
          Revenue = purchase lines. Conversion = sessions with a purchase / sessions with a view.
Task    : E7-12
Layer   : gold (ecommerce_rfm_dwh), views only
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_category_ranking
AS
SELECT
    ISNULL(cat.level_1, N'unclassified')                           AS category_group,
    SUM(l.price)                                                   AS revenue,
    COUNT(*)                                                       AS purchase_lines,
    CAST(100.0 * SUM(l.price) / SUM(SUM(l.price)) OVER () AS decimal(6,2)) AS pct_revenue,
    RANK() OVER (ORDER BY SUM(l.price) DESC)                       AS revenue_rank
FROM gold.fact_order_line AS l
INNER JOIN gold.dim_product  AS p   ON p.product_key  = l.product_key
INNER JOIN gold.dim_category AS cat ON cat.category_key = p.category_key
GROUP BY ISNULL(cat.level_1, N'unclassified');
GO

CREATE OR ALTER VIEW gold.v_brand_ranking
AS
WITH brand_revenue AS
(
    SELECT p.brand_key, SUM(l.price) AS revenue, COUNT(*) AS purchase_lines
    FROM gold.fact_order_line AS l
    INNER JOIN gold.dim_product AS p ON p.product_key = l.product_key
    GROUP BY p.brand_key
),
brand_views AS
(
    SELECT p.brand_key,
           COUNT(DISTINCT CASE WHEN e.event_type_key = 1 THEN e.session_id END) AS sessions_viewed,
           COUNT(DISTINCT CASE WHEN e.event_type_key = 4 THEN e.session_id END) AS sessions_purchased
    FROM gold.fact_event AS e
    INNER JOIN gold.dim_product AS p ON p.product_key = e.product_key
    GROUP BY p.brand_key
)
SELECT
    b.brand_name,
    r.revenue,
    r.purchase_lines,
    v.sessions_viewed,
    v.sessions_purchased,
    CAST(100.0 * v.sessions_purchased / NULLIF(v.sessions_viewed, 0) AS decimal(7,2)) AS conversion_pct,
    RANK() OVER (ORDER BY r.revenue DESC)                                              AS revenue_rank
FROM brand_revenue AS r
INNER JOIN brand_views AS v ON v.brand_key = r.brand_key
INNER JOIN gold.dim_brand AS b ON b.brand_key = r.brand_key;
GO
