/*
Purpose : Funnel by category group and week: sessions that viewed, carted, purchased (E7-10).
          Rule D8: each stage counts the sessions that reached that stage, on its own.
          So a cart rate can be above 100% in rare cases, and the purchase rate is read with that in mind.
Task    : E7-10
Layer   : gold (ecommerce_rfm_dwh), view only
Event type keys (gold.dim_event_type): 1 view, 2 cart, 3 remove_from_cart, 4 purchase
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_funnel_category_week
AS
SELECT
    ISNULL(cat.level_1, N'unclassified')                                                    AS category_group,
    d.week_start_date,
    d.is_partial_week,
    COUNT(DISTINCT CASE WHEN e.event_type_key = 1 THEN e.session_id END)                    AS sessions_viewed,
    COUNT(DISTINCT CASE WHEN e.event_type_key = 2 THEN e.session_id END)                    AS sessions_carted,
    COUNT(DISTINCT CASE WHEN e.event_type_key = 4 THEN e.session_id END)                    AS sessions_purchased,
    CAST(100.0 * COUNT(DISTINCT CASE WHEN e.event_type_key = 2 THEN e.session_id END)
         / NULLIF(COUNT(DISTINCT CASE WHEN e.event_type_key = 1 THEN e.session_id END), 0) AS decimal(7,2)) AS view_to_cart_pct,
    CAST(100.0 * COUNT(DISTINCT CASE WHEN e.event_type_key = 4 THEN e.session_id END)
         / NULLIF(COUNT(DISTINCT CASE WHEN e.event_type_key = 1 THEN e.session_id END), 0) AS decimal(7,2)) AS view_to_purchase_pct
FROM gold.fact_event AS e
INNER JOIN gold.dim_product  AS p   ON p.product_key  = e.product_key
INNER JOIN gold.dim_category AS cat ON cat.category_key = p.category_key
INNER JOIN gold.dim_date     AS d   ON d.date_key     = e.date_key
GROUP BY ISNULL(cat.level_1, N'unclassified'), d.week_start_date, d.is_partial_week;
GO
