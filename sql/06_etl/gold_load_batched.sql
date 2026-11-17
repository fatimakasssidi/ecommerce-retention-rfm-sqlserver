/*
Purpose : Load the gold facts in batches, committing each batch, so the log stays small.
          Replaces gold.load_gold_facts for the large fact_event table.
Task    : E5-03 (batched), E5-04
Layer   : gold (ecommerce_rfm_dwh)
Run     : 1. EXEC gold.load_gold_dimensions;             (once, idempotent)
          2. EXEC gold.load_fact_event_batched @batch_size = 5000000, @resume = 0;
          3. EXEC gold.load_fact_order_and_lines;
          To resume after a stop: EXEC gold.load_fact_event_batched @resume = 1;
Progress: SELECT * FROM audit.gold_batch_log ORDER BY batch_id;
*/
USE ecommerce_rfm_dwh;
GO

IF OBJECT_ID(N'audit.gold_batch_log', N'U') IS NULL
CREATE TABLE audit.gold_batch_log
(
    batch_id       int           NOT NULL IDENTITY(1,1) CONSTRAINT pk_gold_batch_log PRIMARY KEY,
    step_name      varchar(50)   NOT NULL,
    range_from     bigint        NULL,
    range_to       bigint        NULL,
    rows_loaded    bigint        NOT NULL,
    seconds_taken  decimal(12,1) NOT NULL,
    finished_at    datetime2(0)  NOT NULL CONSTRAINT df_gold_batch_log_at DEFAULT (SYSUTCDATETIME())
);
GO

/* ---------------------------------------------------------------
   1. fact_event in batches of @batch_size events (by silver event_id)
   --------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE gold.load_fact_event_batched
    @batch_size bigint = 5000000,
    @resume     bit    = 0           -- 0 = start from scratch, 1 = continue after the last batch
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @min   bigint, @max bigint, @lo bigint;
    DECLARE @t     datetime2(3);
    DECLARE @rows  bigint;
    DECLARE @used  decimal(5,2);

    IF @resume = 0
    BEGIN
        -- fresh start: empty the facts (child tables first), forget old batch records
        -- TRUNCATE is refused on a table that a foreign key points to (fact_order),
        -- so the two linked tables use DELETE (small: about 3 million rows in total)
        DELETE FROM gold.fact_order_line;
        DELETE FROM gold.fact_order;
        TRUNCATE TABLE gold.fact_event;
        DELETE FROM audit.gold_batch_log WHERE step_name = 'fact_event';
    END;

    SELECT @min = MIN(event_id), @max = MAX(event_id) FROM silver.rees46_event;

    SET @lo = @min;
    IF @resume = 1
        SELECT @lo = ISNULL(MAX(range_to) + 1, @min)
        FROM audit.gold_batch_log WHERE step_name = 'fact_event';

    WHILE @lo <= @max
    BEGIN
        SET @t = SYSUTCDATETIME();

        -- one batch = one statement = one transaction, committed when it ends
        INSERT INTO gold.fact_event
            (event_key, date_key, event_time, event_type_key, customer_key, product_key, session_id, price)
        SELECT
            e.event_id,
            CAST(CONVERT(char(8), CAST(e.event_time AS date), 112) AS int),
            e.event_time,
            t.event_type_key,
            ISNULL(c.customer_key, -1),
            p.product_key,
            e.user_session,
            e.price
        FROM silver.rees46_event AS e
        INNER JOIN gold.dim_event_type AS t ON t.event_type = e.event_type
        INNER JOIN gold.dim_product    AS p ON p.product_id = e.product_id
        LEFT JOIN  gold.dim_customer   AS c
               ON c.customer_id = e.user_id
              AND CAST(e.event_time AS date) BETWEEN c.dwh_valid_from AND c.dwh_valid_to
        WHERE e.event_id >= @lo AND e.event_id < @lo + @batch_size;

        SET @rows = @@ROWCOUNT;

        -- free the log space of the batch just committed
        CHECKPOINT;

        INSERT INTO audit.gold_batch_log (step_name, range_from, range_to, rows_loaded, seconds_taken)
        VALUES ('fact_event', @lo, @lo + @batch_size - 1, @rows,
                DATEDIFF(millisecond, @t, SYSUTCDATETIME()) / 1000.0);

        -- safety stop: the log must not fill the disk
        SELECT @used = used_log_space_in_percent FROM sys.dm_db_log_space_usage;
        IF @used > 60
            THROW 50020, 'Log above 60 percent. Stopped to protect the disk. Resume with @resume = 1.', 1;

        SET @lo = @lo + @batch_size;
    END;
END;
GO

/* ---------------------------------------------------------------
   2. fact_order and fact_order_line (about 3 million rows: one statement is fine)
   --------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE gold.load_fact_order_and_lines
AS
BEGIN
    SET NOCOUNT ON;

    -- fact_order: one row per session with a purchase (ADR-004). Customer = first purchase user.
    ;WITH purchases AS
    (
        SELECT e.event_id, e.user_session, e.user_id, e.event_time, e.price,
               ROW_NUMBER() OVER (PARTITION BY e.user_session ORDER BY e.event_time, e.event_id) AS rn
        FROM silver.rees46_event AS e
        WHERE e.event_type = 'purchase'
    ),
    first_purchase AS
    (
        SELECT user_session, user_id, event_time FROM purchases WHERE rn = 1
    ),
    totals AS
    (
        SELECT user_session, COUNT(*) AS line_count, SUM(price) AS order_value
        FROM purchases
        GROUP BY user_session
    )
    INSERT INTO gold.fact_order (session_id, customer_key, order_date_key, line_count, order_value)
    SELECT t.user_session,
           ISNULL(c.customer_key, -1),
           CAST(CONVERT(char(8), CAST(f.event_time AS date), 112) AS int),
           t.line_count,
           t.order_value
    FROM totals AS t
    INNER JOIN first_purchase AS f ON f.user_session = t.user_session
    LEFT JOIN  gold.dim_customer AS c
           ON c.customer_id = f.user_id
          AND CAST(f.event_time AS date) BETWEEN c.dwh_valid_from AND c.dwh_valid_to;

    -- fact_order_line: one row per purchase event
    INSERT INTO gold.fact_order_line
        (order_line_key, order_key, date_key, customer_key, product_key, price)
    SELECT
        e.event_id,
        o.order_key,
        CAST(CONVERT(char(8), CAST(e.event_time AS date), 112) AS int),
        ISNULL(c.customer_key, -1),
        p.product_key,
        e.price
    FROM silver.rees46_event AS e
    INNER JOIN gold.fact_order AS o ON o.session_id = e.user_session
    INNER JOIN gold.dim_product AS p ON p.product_id = e.product_id
    LEFT JOIN  gold.dim_customer AS c
           ON c.customer_id = e.user_id
          AND CAST(e.event_time AS date) BETWEEN c.dwh_valid_from AND c.dwh_valid_to
    WHERE e.event_type = 'purchase';
END;
GO
