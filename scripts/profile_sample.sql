/*
Purpose : Profile a sample of the REES46 events: volume, time coverage, event types,
          missing values, prices, duplicates, users and sessions, products, categories.
Task    : E2-05
Layer   : bronze (throwaway profiling table)
Run     : section by section. Select one section and press F5, then read its result.
Note    : The profiling table is dropped at the end (section 11). The real bronze
          table is created later, in E3-01.
*/

USE ecommerce_rfm_raw;
GO

/* ---------------------------------------------------------------
   0. Load the sample (created in the container as /tmp/profile_sample.csv)
   The files use LF line endings (verified in E2-03), so ROWTERMINATOR '0x0a' is correct.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'bronze.rees46_events_profile_sample', N'U') IS NOT NULL
    DROP TABLE bronze.rees46_events_profile_sample;
GO

CREATE TABLE bronze.rees46_events_profile_sample
(
    event_time    varchar(100) NULL,
    event_type    varchar(100) NULL,
    product_id    varchar(100) NULL,
    category_id   varchar(100) NULL,
    category_code varchar(400) NULL,
    brand         varchar(400) NULL,
    price         varchar(100) NULL,
    user_id       varchar(100) NULL,
    user_session  varchar(100) NULL
);
GO

BULK INSERT bronze.rees46_events_profile_sample
FROM '/tmp/profile_sample.csv'
WITH
(
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '0x0a',
    CODEPAGE        = '65001',
    TABLOCK
);
GO

/* ---------------------------------------------------------------
   1. Volume and time coverage
   --------------------------------------------------------------- */
SELECT COUNT(*) AS row_count
FROM bronze.rees46_events_profile_sample;

SELECT
    SUM(CASE WHEN TRY_CONVERT(datetime2(0), LEFT(event_time, 19)) IS NULL THEN 1 ELSE 0 END) AS bad_timestamp_rows,
    MIN(TRY_CONVERT(datetime2(0), LEFT(event_time, 19)))                                     AS first_event,
    MAX(TRY_CONVERT(datetime2(0), LEFT(event_time, 19)))                                     AS last_event,
    COUNT(DISTINCT CONVERT(date, TRY_CONVERT(datetime2(0), LEFT(event_time, 19))))           AS distinct_days
FROM bronze.rees46_events_profile_sample;

-- Does every timestamp end with ' UTC'?
SELECT COUNT(*) AS rows_without_utc_suffix
FROM bronze.rees46_events_profile_sample
WHERE event_time NOT LIKE '% UTC';

/* ---------------------------------------------------------------
   2. Event types
   --------------------------------------------------------------- */
SELECT
    event_type,
    COUNT(*)                                                        AS event_count,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS decimal(5,2)) AS pct
FROM bronze.rees46_events_profile_sample
GROUP BY event_type
ORDER BY event_count DESC;

/* ---------------------------------------------------------------
   3. Missing values (NULL or empty text), per column
   --------------------------------------------------------------- */
SELECT
    SUM(CASE WHEN event_time    IS NULL OR event_time    = '' THEN 1 ELSE 0 END) AS event_time_missing,
    SUM(CASE WHEN event_type    IS NULL OR event_type    = '' THEN 1 ELSE 0 END) AS event_type_missing,
    SUM(CASE WHEN product_id    IS NULL OR product_id    = '' THEN 1 ELSE 0 END) AS product_id_missing,
    SUM(CASE WHEN category_id   IS NULL OR category_id   = '' THEN 1 ELSE 0 END) AS category_id_missing,
    SUM(CASE WHEN category_code IS NULL OR category_code = '' THEN 1 ELSE 0 END) AS category_code_missing,
    SUM(CASE WHEN brand         IS NULL OR brand         = '' THEN 1 ELSE 0 END) AS brand_missing,
    SUM(CASE WHEN price         IS NULL OR price         = '' THEN 1 ELSE 0 END) AS price_missing,
    SUM(CASE WHEN user_id       IS NULL OR user_id       = '' THEN 1 ELSE 0 END) AS user_id_missing,
    SUM(CASE WHEN user_session  IS NULL OR user_session  = '' THEN 1 ELSE 0 END) AS user_session_missing
FROM bronze.rees46_events_profile_sample;

-- How are empty values stored by BULK INSERT: NULL or empty text?
SELECT
    SUM(CASE WHEN brand IS NULL THEN 1 ELSE 0 END) AS brand_is_null,
    SUM(CASE WHEN brand = ''    THEN 1 ELSE 0 END) AS brand_is_empty_text
FROM bronze.rees46_events_profile_sample;

/* ---------------------------------------------------------------
   4. Prices
   --------------------------------------------------------------- */
SELECT
    SUM(CASE WHEN price <> '' AND TRY_CONVERT(decimal(18,2), price) IS NULL THEN 1 ELSE 0 END) AS price_not_numeric,
    SUM(CASE WHEN TRY_CONVERT(decimal(18,2), price) = 0 THEN 1 ELSE 0 END)                     AS price_zero,
    SUM(CASE WHEN TRY_CONVERT(decimal(18,2), price) < 0 THEN 1 ELSE 0 END)                     AS price_negative,
    MIN(TRY_CONVERT(decimal(18,2), price))                                                     AS min_price,
    MAX(TRY_CONVERT(decimal(18,2), price))                                                     AS max_price,
    CAST(AVG(TRY_CONVERT(decimal(18,2), price)) AS decimal(18,2))                              AS avg_price
FROM bronze.rees46_events_profile_sample;

SELECT DISTINCT
    PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY p.price_num) OVER () AS median_price,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY p.price_num) OVER () AS p99_price
FROM
(
    SELECT TRY_CONVERT(decimal(18,2), price) AS price_num
    FROM bronze.rees46_events_profile_sample
    WHERE TRY_CONVERT(decimal(18,2), price) IS NOT NULL
) AS p;

SELECT TOP (10)
    TRY_CONVERT(decimal(18,2), price) AS price_value,
    event_type,
    category_code,
    brand
FROM bronze.rees46_events_profile_sample
WHERE TRY_CONVERT(decimal(18,2), price) IS NOT NULL
ORDER BY TRY_CONVERT(decimal(18,2), price) DESC;

/* ---------------------------------------------------------------
   5. Identical duplicate rows (all 9 columns equal)
   --------------------------------------------------------------- */
SELECT
    COUNT(*)           AS duplicate_groups,
    SUM(d.row_count - 1) AS surplus_rows
FROM
(
    SELECT COUNT(*) AS row_count
    FROM bronze.rees46_events_profile_sample
    GROUP BY event_time, event_type, product_id, category_id, category_code,
             brand, price, user_id, user_session
    HAVING COUNT(*) > 1
) AS d;

-- Which event types are duplicated?
SELECT
    d.event_type,
    SUM(d.row_count - 1) AS surplus_rows
FROM
(
    SELECT event_type, COUNT(*) AS row_count
    FROM bronze.rees46_events_profile_sample
    GROUP BY event_time, event_type, product_id, category_id, category_code,
             brand, price, user_id, user_session
    HAVING COUNT(*) > 1
) AS d
GROUP BY d.event_type;

/* ---------------------------------------------------------------
   6. Users and sessions
   --------------------------------------------------------------- */
SELECT
    COUNT(DISTINCT user_id)      AS distinct_users,
    COUNT(DISTINCT user_session) AS distinct_sessions,
    COUNT(DISTINCT product_id)   AS distinct_products,
    COUNT(DISTINCT category_id)  AS distinct_categories,
    COUNT(DISTINCT brand)        AS distinct_brands
FROM bronze.rees46_events_profile_sample;

-- Sessions linked to more than one user
SELECT COUNT(*) AS sessions_with_several_users
FROM
(
    SELECT user_session
    FROM bronze.rees46_events_profile_sample
    GROUP BY user_session
    HAVING COUNT(DISTINCT user_id) > 1
) AS s;

-- Purchases per session (supports decision D3: an order is a session with a purchase)
SELECT
    CASE WHEN s.purchase_count >= 3 THEN '3 or more' ELSE CAST(s.purchase_count AS varchar(10)) END AS purchases_in_session,
    COUNT(*) AS session_count
FROM
(
    SELECT user_session, COUNT(*) AS purchase_count
    FROM bronze.rees46_events_profile_sample
    WHERE event_type = 'purchase'
    GROUP BY user_session
) AS s
GROUP BY CASE WHEN s.purchase_count >= 3 THEN '3 or more' ELSE CAST(s.purchase_count AS varchar(10)) END
ORDER BY purchases_in_session;

-- Sessions with a purchase but no view in the sample (blocks cut sessions, so read with care)
SELECT COUNT(*) AS purchase_sessions_without_view
FROM
(
    SELECT user_session
    FROM bronze.rees46_events_profile_sample
    GROUP BY user_session
    HAVING SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) > 0
       AND SUM(CASE WHEN event_type = 'view'     THEN 1 ELSE 0 END) = 0
) AS s;

-- Purchase sessions without a cart event (decides whether the strict funnel rule
-- in the metric dictionary, K17 to K20, must change)
SELECT
    COUNT(*)                                                           AS purchase_sessions,
    SUM(CASE WHEN s.cart_events = 0 THEN 1 ELSE 0 END)                 AS purchase_sessions_without_cart,
    CAST(100.0 * SUM(CASE WHEN s.cart_events = 0 THEN 1 ELSE 0 END)
         / COUNT(*) AS decimal(5,2))                                   AS pct_without_cart
FROM
(
    SELECT
        user_session,
        SUM(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS cart_events
    FROM bronze.rees46_events_profile_sample
    GROUP BY user_session
    HAVING SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) > 0
) AS s;

/* ---------------------------------------------------------------
   7. Products: is one product always described the same way?
   --------------------------------------------------------------- */
SELECT COUNT(*) AS products_with_several_categories
FROM
(
    SELECT product_id
    FROM bronze.rees46_events_profile_sample
    GROUP BY product_id
    HAVING COUNT(DISTINCT category_id) > 1
) AS p;

SELECT COUNT(*) AS products_with_several_brands
FROM
(
    SELECT product_id
    FROM bronze.rees46_events_profile_sample
    WHERE brand IS NOT NULL AND brand <> ''
    GROUP BY product_id
    HAVING COUNT(DISTINCT brand) > 1
) AS p;

SELECT COUNT(*) AS products_with_missing_and_present_brand
FROM
(
    SELECT product_id
    FROM bronze.rees46_events_profile_sample
    GROUP BY product_id
    HAVING SUM(CASE WHEN brand IS NULL OR brand = '' THEN 1 ELSE 0 END) > 0
       AND SUM(CASE WHEN brand IS NOT NULL AND brand <> '' THEN 1 ELSE 0 END) > 0
) AS p;

SELECT COUNT(*) AS products_with_several_prices
FROM
(
    SELECT product_id
    FROM bronze.rees46_events_profile_sample
    GROUP BY product_id
    HAVING COUNT(DISTINCT price) > 1
) AS p;

/* ---------------------------------------------------------------
   8. Category code: depth of the path
   --------------------------------------------------------------- */
SELECT
    CASE WHEN category_code IS NULL OR category_code = '' THEN 0
         ELSE LEN(category_code) - LEN(REPLACE(category_code, '.', '')) + 1
    END AS category_levels,
    COUNT(*) AS event_count
FROM bronze.rees46_events_profile_sample
GROUP BY CASE WHEN category_code IS NULL OR category_code = '' THEN 0
              ELSE LEN(category_code) - LEN(REPLACE(category_code, '.', '')) + 1
         END
ORDER BY category_levels;

/* ---------------------------------------------------------------
   9. Events per hour of the day (UTC), to see the daily rhythm
   --------------------------------------------------------------- */
SELECT
    DATEPART(hour, TRY_CONVERT(datetime2(0), LEFT(event_time, 19))) AS hour_utc,
    COUNT(*) AS event_count
FROM bronze.rees46_events_profile_sample
GROUP BY DATEPART(hour, TRY_CONVERT(datetime2(0), LEFT(event_time, 19)))
ORDER BY hour_utc;

/* ---------------------------------------------------------------
   10. Longest values, to size the real bronze columns
   --------------------------------------------------------------- */
SELECT
    MAX(LEN(event_time))    AS max_event_time,
    MAX(LEN(event_type))    AS max_event_type,
    MAX(LEN(category_code)) AS max_category_code,
    MAX(LEN(brand))         AS max_brand,
    MAX(LEN(price))         AS max_price,
    MAX(LEN(user_session))  AS max_user_session
FROM bronze.rees46_events_profile_sample;

/* ---------------------------------------------------------------
   11. Cleanup (run when the findings are written down)
   --------------------------------------------------------------- */
-- DROP TABLE bronze.rees46_events_profile_sample;
