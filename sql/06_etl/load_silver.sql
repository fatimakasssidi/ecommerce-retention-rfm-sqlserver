/*
Purpose : Load silver from bronze. Every bronze row ends in silver OR in audit.silver_rejects,
          with the reason. The procedure checks that nothing is lost.
Task    : E5-01
Layer   : silver (ecommerce_rfm_dwh), reads ecommerce_rfm_raw.bronze
Rules   : - a value that cannot be converted rejects the row (reason recorded)
          - identical duplicate rows keep one copy, the others are rejected as duplicate_row (I-05)
          - a zero price on a view or cart becomes NULL, the row is kept (I-04)
          - a purchase needs a price above 0
          - a product with several categories or brands keeps the most frequent one (I-10)
          - an empty brand becomes the unknown brand (-1) (I-02)
Check   : bronze rows = silver events + rejected rows, or the procedure fails and rolls back.
Note    : Full rebuild in one transaction. Incremental loads come in E5-04.
*/
USE ecommerce_rfm_dwh;
GO

/* ---------------------------------------------------------------
   Rejects table: one row per rejected bronze row, with its reason
   --------------------------------------------------------------- */
IF OBJECT_ID(N'audit.silver_rejects', N'U') IS NULL
CREATE TABLE audit.silver_rejects
(
    reject_id        bigint        NOT NULL IDENTITY(1,1) CONSTRAINT pk_silver_rejects PRIMARY KEY,
    reject_rule      varchar(50)   NOT NULL,
    raw_event_time   varchar(100)  NULL,
    raw_event_type   varchar(100)  NULL,
    raw_product_id   varchar(100)  NULL,
    raw_user_id      varchar(100)  NULL,
    raw_user_session varchar(100)  NULL,
    raw_price        varchar(100)  NULL,
    dwh_load_id      int           NULL,
    dwh_source_file  varchar(260)  NULL,
    rejected_at      datetime2(0)  NOT NULL CONSTRAINT df_silver_rejects_at DEFAULT (SYSUTCDATETIME())
);
GO

CREATE OR ALTER PROCEDURE silver.load_silver
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    /* 0. Empty silver and the rejects, children first. Brand -1 is kept. */
    DELETE FROM audit.silver_rejects;
    DELETE FROM silver.rees46_event;
    DELETE FROM silver.rees46_session;
    DELETE FROM silver.rees46_user;
    DELETE FROM silver.rees46_product;
    DELETE FROM silver.rees46_category;
    DELETE FROM silver.rees46_brand WHERE brand_id <> -1;

    /* 1. Brand: each distinct non-empty brand name */
    INSERT INTO silver.rees46_brand (brand_name)
    SELECT DISTINCT NULLIF(LTRIM(RTRIM(b.brand)), '')
    FROM ecommerce_rfm_raw.bronze.rees46_events AS b
    WHERE NULLIF(LTRIM(RTRIM(b.brand)), '') IS NOT NULL;

    /* 2. Category: one row per category_id, with its code and up to 4 levels */
    ;WITH cat AS
    (
        SELECT
            TRY_CONVERT(bigint, b.category_id) AS category_id,
            MAX(NULLIF(b.category_code, ''))   AS category_code
        FROM ecommerce_rfm_raw.bronze.rees46_events AS b
        WHERE TRY_CONVERT(bigint, b.category_id) IS NOT NULL
        GROUP BY TRY_CONVERT(bigint, b.category_id)
    ),
    parts AS
    (
        SELECT c.category_id, s.value AS part, s.ordinal
        FROM cat AS c
        CROSS APPLY STRING_SPLIT(c.category_code, '.', 1) AS s
        WHERE c.category_code IS NOT NULL
    )
    INSERT INTO silver.rees46_category (category_id, category_code, level_1, level_2, level_3, level_4)
    SELECT
        c.category_id,
        c.category_code,
        MAX(CASE WHEN p.ordinal = 1 THEN p.part END),
        MAX(CASE WHEN p.ordinal = 2 THEN p.part END),
        MAX(CASE WHEN p.ordinal = 3 THEN p.part END),
        MAX(CASE WHEN p.ordinal = 4 THEN p.part END)
    FROM cat AS c
    LEFT JOIN parts AS p ON p.category_id = c.category_id
    GROUP BY c.category_id, c.category_code;

    /* 3. Product: most frequent category and brand. Brand never given = -1 */
    ;WITH pc AS
    (
        SELECT
            TRY_CONVERT(int, b.product_id)     AS product_id,
            TRY_CONVERT(bigint, b.category_id) AS category_id,
            ROW_NUMBER() OVER (PARTITION BY TRY_CONVERT(int, b.product_id)
                               ORDER BY COUNT_BIG(*) DESC, TRY_CONVERT(bigint, b.category_id)) AS rn
        FROM ecommerce_rfm_raw.bronze.rees46_events AS b
        WHERE TRY_CONVERT(int, b.product_id) IS NOT NULL
          AND TRY_CONVERT(bigint, b.category_id) IS NOT NULL
        GROUP BY TRY_CONVERT(int, b.product_id), TRY_CONVERT(bigint, b.category_id)
    ),
    pb AS
    (
        SELECT
            TRY_CONVERT(int, b.product_id) AS product_id,
            br.brand_id                    AS brand_id,
            ROW_NUMBER() OVER (PARTITION BY TRY_CONVERT(int, b.product_id)
                               ORDER BY COUNT_BIG(*) DESC, br.brand_id) AS rn
        FROM ecommerce_rfm_raw.bronze.rees46_events AS b
        INNER JOIN silver.rees46_brand AS br
            ON br.brand_name = NULLIF(LTRIM(RTRIM(b.brand)), '')
        WHERE TRY_CONVERT(int, b.product_id) IS NOT NULL
        GROUP BY TRY_CONVERT(int, b.product_id), br.brand_id
    )
    INSERT INTO silver.rees46_product (product_id, category_id, brand_id)
    SELECT pc.product_id, pc.category_id, ISNULL(pb.brand_id, -1)
    FROM pc
    LEFT JOIN pb ON pb.product_id = pc.product_id AND pb.rn = 1
    WHERE pc.rn = 1;

    /* 4. User and session. A session is not linked to one user (ADR-006). */
    INSERT INTO silver.rees46_user (user_id)
    SELECT DISTINCT TRY_CONVERT(int, b.user_id)
    FROM ecommerce_rfm_raw.bronze.rees46_events AS b
    WHERE TRY_CONVERT(int, b.user_id) IS NOT NULL;

    INSERT INTO silver.rees46_session (user_session)
    SELECT DISTINCT TRY_CONVERT(uniqueidentifier, b.user_session)
    FROM ecommerce_rfm_raw.bronze.rees46_events AS b
    WHERE TRY_CONVERT(uniqueidentifier, b.user_session) IS NOT NULL;

    /* 5. Event. Each bronze row gets a reject reason, or none (kept).
          The result is a temporary table, used by the two inserts below. */
    ;WITH src AS
    (
        SELECT
            b.event_time   AS raw_event_time,
            b.event_type   AS raw_event_type,
            b.product_id   AS raw_product_id,
            b.user_id      AS raw_user_id,
            b.user_session AS raw_user_session,
            b.price        AS raw_price,
            TRY_CONVERT(datetime2(0), LEFT(b.event_time, 19))  AS event_time,
            b.event_type,
            TRY_CONVERT(int, b.product_id)                     AS product_id,
            TRY_CONVERT(int, b.user_id)                        AS user_id,
            TRY_CONVERT(uniqueidentifier, b.user_session)      AS user_session,
            TRY_CONVERT(decimal(18,2), b.price)                AS price_value,
            b.dwh_load_id,
            b.dwh_source_file,
            ROW_NUMBER() OVER (PARTITION BY b.event_time, b.event_type, b.product_id, b.category_id,
                                            b.category_code, b.brand, b.price, b.user_id, b.user_session
                               ORDER BY (SELECT 1))            AS copy_no
        FROM ecommerce_rfm_raw.bronze.rees46_events AS b
    )
    SELECT
        s.*,
        CASE
            WHEN s.copy_no > 1                                                         THEN 'duplicate_row'
            WHEN s.event_time IS NULL                                                  THEN 'bad_event_time'
            WHEN s.event_type NOT IN ('view', 'cart', 'remove_from_cart', 'purchase')  THEN 'bad_event_type'
            WHEN s.product_id IS NULL                                                  THEN 'bad_product_id'
            WHEN s.user_id IS NULL                                                     THEN 'bad_user_id'
            WHEN s.user_session IS NULL                                                THEN 'bad_user_session'
            WHEN s.event_type = 'purchase' AND (s.price_value IS NULL OR s.price_value <= 0)
                                                                                       THEN 'bad_purchase_price'
            ELSE NULL
        END AS reject_rule
    INTO #checked
    FROM src AS s;

    /* 5a. Rejected rows go to the audit table, with their reason */
    INSERT INTO audit.silver_rejects
        (reject_rule, raw_event_time, raw_event_type, raw_product_id, raw_user_id,
         raw_user_session, raw_price, dwh_load_id, dwh_source_file)
    SELECT reject_rule, raw_event_time, raw_event_type, raw_product_id, raw_user_id,
           raw_user_session, raw_price, dwh_load_id, dwh_source_file
    FROM #checked
    WHERE reject_rule IS NOT NULL;

    /* 5b. Kept rows go to silver. A zero price on a view or cart becomes NULL. */
    INSERT INTO silver.rees46_event
        (event_time, event_type, product_id, user_id, user_session, price, dwh_load_id, dwh_source_file)
    SELECT
        event_time,
        event_type,
        product_id,
        user_id,
        user_session,
        CASE WHEN price_value > 0 THEN price_value ELSE NULL END,
        dwh_load_id,
        dwh_source_file
    FROM #checked
    WHERE reject_rule IS NULL;

    /* 6. Reconciliation: nothing is lost. If the counts differ, the whole load is rolled back. */
    DECLARE @bronze  bigint = (SELECT COUNT_BIG(*) FROM ecommerce_rfm_raw.bronze.rees46_events);
    DECLARE @silver  bigint = (SELECT COUNT_BIG(*) FROM silver.rees46_event);
    DECLARE @rejects bigint = (SELECT COUNT_BIG(*) FROM audit.silver_rejects);

    IF @bronze <> @silver + @rejects
        THROW 50010, 'Silver load does not reconcile: bronze rows are not all in silver or in the rejects.', 1;

    COMMIT TRANSACTION;

    /* 7. Result, per reason */
    SELECT @bronze AS bronze_rows, @silver AS silver_events, @rejects AS rejected_rows;

    SELECT reject_rule, COUNT_BIG(*) AS rows_rejected
    FROM audit.silver_rejects
    GROUP BY reject_rule
    ORDER BY rows_rejected DESC;
END;
GO
