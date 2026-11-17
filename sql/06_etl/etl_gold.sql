/*
Purpose : E5-02 to E5-06 in one file (ecommerce_rfm_dwh).
          - audit tables for runs and errors           (E5-05)
          - dimension loads, SCD2 on customer segment  (E5-02)
          - fact loads with keys and unknown member -1 (E5-03)
          - watermark: loads only what is new          (E5-04)
          - master procedure, idempotent               (E5-06)
Note    : Run after silver.load_silver. Untested: run in order and send the errors.
*/
USE ecommerce_rfm_dwh;
GO

/* ===============================================================
   E5-05  Audit tables
   =============================================================== */
IF OBJECT_ID(N'audit.etl_run', N'U') IS NULL
CREATE TABLE audit.etl_run
(
    run_id          int           NOT NULL IDENTITY(1,1) CONSTRAINT pk_etl_run PRIMARY KEY,
    procedure_name  sysname       NOT NULL,
    started_at      datetime2(0)  NOT NULL CONSTRAINT df_etl_run_started DEFAULT (SYSUTCDATETIME()),
    finished_at     datetime2(0)  NULL,
    status          varchar(20)   NOT NULL CONSTRAINT df_etl_run_status DEFAULT ('running'),
    rows_loaded     bigint        NULL,
    login_name      sysname       NOT NULL CONSTRAINT df_etl_run_login DEFAULT (ORIGINAL_LOGIN()),
    host_name       sysname       NULL     CONSTRAINT df_etl_run_host  DEFAULT (HOST_NAME())
);
GO
IF OBJECT_ID(N'audit.etl_error', N'U') IS NULL
CREATE TABLE audit.etl_error
(
    error_id       int            NOT NULL IDENTITY(1,1) CONSTRAINT pk_etl_error PRIMARY KEY,
    run_id         int            NOT NULL CONSTRAINT fk_etl_error_run FOREIGN KEY REFERENCES audit.etl_run (run_id),
    step_name      varchar(100)   NOT NULL,
    error_number   int            NULL,
    error_message  nvarchar(2048) NOT NULL,
    occurred_at    datetime2(0)   NOT NULL CONSTRAINT df_etl_error_at DEFAULT (SYSUTCDATETIME())
);
GO

/* ===============================================================
   E5-04  Watermark: the last silver event already sent to gold
   =============================================================== */
IF OBJECT_ID(N'audit.watermark', N'U') IS NULL
CREATE TABLE audit.watermark
(
    source_name      varchar(50) NOT NULL CONSTRAINT pk_watermark PRIMARY KEY,
    last_event_id    bigint      NOT NULL CONSTRAINT df_watermark_last DEFAULT (0),
    updated_at       datetime2(0) NOT NULL CONSTRAINT df_watermark_at DEFAULT (SYSUTCDATETIME())
);
GO
-- Silver is rebuilt in full on each run, so event ids change: gold is rebuilt in full too.
-- The watermark is kept for the day silver becomes incremental (see E5-04 note).

/* ===============================================================
   E5-02  Dimensions. Key-stable: existing keys are never changed.
   =============================================================== */
CREATE OR ALTER PROCEDURE gold.load_gold_dimensions
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Brand (unknown member -1 is created once)
    IF NOT EXISTS (SELECT 1 FROM gold.dim_brand WHERE brand_key = -1)
    BEGIN
        SET IDENTITY_INSERT gold.dim_brand ON;
        INSERT INTO gold.dim_brand (brand_key, brand_id, brand_name) VALUES (-1, -1, N'unknown');
        SET IDENTITY_INSERT gold.dim_brand OFF;
    END;
    INSERT INTO gold.dim_brand (brand_id, brand_name)
    SELECT s.brand_id, s.brand_name
    FROM silver.rees46_brand AS s
    WHERE s.brand_id <> -1
      AND NOT EXISTS (SELECT 1 FROM gold.dim_brand AS g WHERE g.brand_id = s.brand_id);

    -- Category
    INSERT INTO gold.dim_category (category_id, category_code, level_1, level_2, level_3, level_4, is_unclassified)
    SELECT s.category_id, s.category_code, s.level_1, s.level_2, s.level_3, s.level_4,
           CASE WHEN s.category_code IS NULL THEN 1 ELSE 0 END
    FROM silver.rees46_category AS s
    WHERE NOT EXISTS (SELECT 1 FROM gold.dim_category AS g WHERE g.category_id = s.category_id);

    -- Product: keys of category and brand are looked up here
    INSERT INTO gold.dim_product (product_id, category_key, brand_key)
    SELECT s.product_id, c.category_key, b.brand_key
    FROM silver.rees46_product AS s
    INNER JOIN gold.dim_category AS c ON c.category_id = s.category_id
    INNER JOIN gold.dim_brand    AS b ON b.brand_id    = s.brand_id
    WHERE NOT EXISTS (SELECT 1 FROM gold.dim_product AS g WHERE g.product_id = s.product_id);

    -- Customer: new users get their first version. The segment is set by E7 (rfm).
    INSERT INTO gold.dim_customer (customer_id, rfm_segment, dwh_valid_from, dwh_valid_to, dwh_is_current)
    SELECT u.user_id, N'unknown', '2019-10-01', '9999-12-31', 1
    FROM silver.rees46_user AS u
    WHERE NOT EXISTS (SELECT 1 FROM gold.dim_customer AS g WHERE g.customer_id = u.user_id AND g.dwh_is_current = 1);
END;
GO

/* ===============================================================
   E5-02  SCD2 for the segment: the segment snapshots come from E7.
          A new segment closes the current version and opens a new one.
   =============================================================== */
IF OBJECT_ID(N'gold.customer_segment_snapshot', N'U') IS NULL
CREATE TABLE gold.customer_segment_snapshot
(
    customer_id   int         NOT NULL,
    snapshot_date date        NOT NULL,   -- weekly
    rfm_segment   varchar(30) NOT NULL,
    CONSTRAINT pk_customer_segment_snapshot PRIMARY KEY (customer_id, snapshot_date)
);
GO

CREATE OR ALTER PROCEDURE gold.apply_customer_segment_scd2
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    -- 1. Customers whose latest snapshot differs from their current version
    ;WITH latest AS
    (
        SELECT customer_id, snapshot_date, rfm_segment,
               ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY snapshot_date DESC) AS rn
        FROM gold.customer_segment_snapshot
    )
    SELECT c.customer_key, l.customer_id, l.snapshot_date, l.rfm_segment
    INTO #changed
    FROM latest AS l
    INNER JOIN gold.dim_customer AS c
            ON c.customer_id = l.customer_id AND c.dwh_is_current = 1
    WHERE l.rn = 1 AND c.rfm_segment <> l.rfm_segment;

    -- 2. Close the current version of each changed customer
    UPDATE c
    SET c.dwh_valid_to = DATEADD(day, -1, ch.snapshot_date),
        c.dwh_is_current = 0
    FROM gold.dim_customer AS c
    INNER JOIN #changed AS ch ON ch.customer_key = c.customer_key;

    -- 3. Open the new version (valid from the snapshot date)
    INSERT INTO gold.dim_customer (customer_id, rfm_segment, dwh_valid_from, dwh_valid_to, dwh_is_current)
    SELECT ch.customer_id, ch.rfm_segment, ch.snapshot_date, '9999-12-31', 1
    FROM #changed AS ch;

    DROP TABLE #changed;
    COMMIT TRANSACTION;
END;
GO

/* ===============================================================
   E5-03  Facts: see gold_load_batched.sql (batched, replaces the old single-transaction load)
   =============================================================== */

/* ===============================================================
   E5-06 master procedure: see etl_master.sql
   =============================================================== */
