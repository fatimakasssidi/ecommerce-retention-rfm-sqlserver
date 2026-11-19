/*
Purpose : Cart abandonment: sessions with a cart event and no purchase, with count, value and
          a list. Value = sum of the cart prices (unknown prices are ignored) (E7-11).
Task    : E7-11
Layer   : gold (ecommerce_rfm_dwh), views only
Definition: K20 in metric_dictionary.md. Customer = customer key of the session's events (-1 if unknown).
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_cart_abandoned_sessions
AS
WITH session_flags AS
(
    SELECT
        e.session_id,
        SUM(CASE WHEN e.event_type_key = 2 THEN 1 ELSE 0 END)              AS cart_events,
        SUM(CASE WHEN e.event_type_key = 4 THEN 1 ELSE 0 END)              AS purchase_events,
        COUNT(DISTINCT CASE WHEN e.event_type_key = 2 THEN e.product_key END) AS distinct_products_carted,
        SUM(CASE WHEN e.event_type_key = 2 THEN e.price END)               AS cart_value,
        MIN(CASE WHEN e.event_type_key = 2 THEN e.event_time END)          AS first_cart_at,
        MAX(e.customer_key)                                                AS customer_key
    FROM gold.fact_event AS e
    GROUP BY e.session_id
)
SELECT
    session_id,
    customer_key,
    distinct_products_carted AS items,
    cart_value,
    first_cart_at
FROM session_flags
WHERE cart_events > 0 AND purchase_events = 0;
GO

CREATE OR ALTER VIEW gold.v_cart_abandonment_summary
AS
WITH sessions_with_cart AS
(
    SELECT e.session_id,
           MAX(CASE WHEN e.event_type_key = 4 THEN 1 ELSE 0 END) AS purchased
    FROM gold.fact_event AS e
    GROUP BY e.session_id
    HAVING SUM(CASE WHEN e.event_type_key = 2 THEN 1 ELSE 0 END) > 0
)
SELECT
    (SELECT COUNT(*) FROM sessions_with_cart)                                         AS sessions_with_cart,
    (SELECT COUNT(*) FROM sessions_with_cart WHERE purchased = 0)                     AS abandoned_sessions,
    CAST(100.0 * (SELECT COUNT(*) FROM sessions_with_cart WHERE purchased = 0)
         / NULLIF((SELECT COUNT(*) FROM sessions_with_cart), 0) AS decimal(6,2))      AS abandonment_pct,
    (SELECT COUNT(DISTINCT customer_key) FROM gold.v_cart_abandoned_sessions
      WHERE customer_key <> -1)                                                       AS abandoning_customers,
    (SELECT SUM(cart_value) FROM gold.v_cart_abandoned_sessions)                      AS abandoned_cart_value;
GO
