/*
Purpose : Full-volume profiling of bronze (E3-07). Answers the questions the sample could not:
          volumes, days, event types, duplicates, prices, missing values, rhythm by hour.
Task    : E3-07
Note    : Each query scans the whole table (110 million rows). Run one at a time.
*/
USE ecommerce_rfm_raw;
GO

-- 1. Period and days (first and last event, number of days)
SELECT
    MIN(TRY_CONVERT(datetime2(0), LEFT(event_time, 19))) AS first_event,
    MAX(TRY_CONVERT(datetime2(0), LEFT(event_time, 19))) AS last_event,
    COUNT(DISTINCT CONVERT(date, TRY_CONVERT(datetime2(0), LEFT(event_time, 19)))) AS distinct_days
FROM bronze.rees46_events;

-- 2. Event types (is remove_from_cart present?)
SELECT event_type, COUNT_BIG(*) AS event_count,
       CAST(100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER () AS decimal(6,3)) AS pct
FROM bronze.rees46_events
GROUP BY event_type
ORDER BY event_count DESC;

-- 3. Missing values per column
SELECT
    SUM(CASE WHEN brand = '' OR brand IS NULL THEN 1 ELSE 0 END)                 AS brand_missing,
    SUM(CASE WHEN category_code = '' OR category_code IS NULL THEN 1 ELSE 0 END) AS category_code_missing,
    SUM(CASE WHEN user_id = '' OR user_id IS NULL THEN 1 ELSE 0 END)             AS user_id_missing,
    SUM(CASE WHEN user_session = '' OR user_session IS NULL THEN 1 ELSE 0 END)   AS user_session_missing,
    SUM(CASE WHEN price = '' OR price IS NULL THEN 1 ELSE 0 END)                 AS price_missing
FROM bronze.rees46_events;

-- 4. Prices: zero, negative, extremes, percentiles (on purchases)
SELECT event_type,
       SUM(CASE WHEN TRY_CONVERT(decimal(18,2), price) = 0 THEN 1 ELSE 0 END) AS zero_price,
       SUM(CASE WHEN TRY_CONVERT(decimal(18,2), price) < 0 THEN 1 ELSE 0 END) AS negative_price,
       MIN(TRY_CONVERT(decimal(18,2), price)) AS min_price,
       MAX(TRY_CONVERT(decimal(18,2), price)) AS max_price
FROM bronze.rees46_events
GROUP BY event_type;

-- 5. Duplicates: identical rows (all 9 columns), counted by group
SELECT
    SUM(d.row_count - 1) AS surplus_rows,
    COUNT(*)             AS duplicate_groups
FROM
(
    SELECT COUNT_BIG(*) AS row_count
    FROM bronze.rees46_events
    GROUP BY event_time, event_type, product_id, category_id, category_code,
             brand, price, user_id, user_session
    HAVING COUNT_BIG(*) > 1
) AS d;

-- 6. Rhythm by hour (UTC): now meaningful, the whole period is loaded
SELECT DATEPART(hour, TRY_CONVERT(datetime2(0), LEFT(event_time, 19))) AS hour_utc,
       COUNT_BIG(*) AS event_count
FROM bronze.rees46_events
GROUP BY DATEPART(hour, TRY_CONVERT(datetime2(0), LEFT(event_time, 19)))
ORDER BY hour_utc;

-- 7. Daily volume (to see Black Friday, 29 November 2019)
SELECT CONVERT(date, TRY_CONVERT(datetime2(0), LEFT(event_time, 19))) AS event_day,
       COUNT_BIG(*) AS event_count
FROM bronze.rees46_events
GROUP BY CONVERT(date, TRY_CONVERT(datetime2(0), LEFT(event_time, 19)))
ORDER BY event_day;

-- 8. Purchases with no view and no cart in the same session (funnel rule, D8), full data
SELECT
    COUNT(*)                                                       AS purchase_sessions,
    SUM(CASE WHEN s.cart_events = 0 THEN 1 ELSE 0 END)             AS without_cart,
    CAST(100.0 * SUM(CASE WHEN s.cart_events = 0 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(6,2)) AS pct_without_cart
FROM
(
    SELECT user_session,
           SUM(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS cart_events
    FROM bronze.rees46_events
    GROUP BY user_session
    HAVING SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) > 0
) AS s;

-- 9. Sessions linked to several users
SELECT COUNT(*) AS sessions_with_several_users
FROM (SELECT user_session FROM bronze.rees46_events
      GROUP BY user_session HAVING COUNT(DISTINCT user_id) > 1) AS x;
GO
