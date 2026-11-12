/*
Purpose : Test the bulk load on a 1,000,000-row slice before loading the full files:
          format options, encoding, speed, log use and the technical columns.
Task    : E3-02
Layer   : bronze
Note    : TRUNCATE empties the table. Use only while testing.
Slice   : created inside the container with
          head -n 1000001 /data/raw/rees46/2019-Oct.csv > /tmp/slice_oct_1m.csv
          (the header plus 1,000,000 lines). The files use LF line endings.
*/

USE ecommerce_rfm_raw;
GO

TRUNCATE TABLE bronze.rees46_events;
GO

/* ---------------------------------------------------------------
   1. Log use BEFORE the load: note the row for ecommerce_rfm_raw
   --------------------------------------------------------------- */
DBCC SQLPERF(LOGSPACE);
GO

/* ---------------------------------------------------------------
   2. The load, with its duration
   --------------------------------------------------------------- */
DECLARE @start datetime2(3) = SYSUTCDATETIME();

-- CODEPAGE is not supported by BULK INSERT on Linux, so it is not used.
BULK INSERT bronze.v_rees46_events_load
FROM '/tmp/slice_oct_1m.csv'
WITH
(
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '0x0a',
    TABLOCK
);

SELECT DATEDIFF(millisecond, @start, SYSUTCDATETIME()) / 1000.0 AS load_seconds;
GO

/* ---------------------------------------------------------------
   3. Log use AFTER the load: compare with the first result
   --------------------------------------------------------------- */
DBCC SQLPERF(LOGSPACE);
GO

/* ---------------------------------------------------------------
   4. Checks. Expected row count: 1,000,000
   --------------------------------------------------------------- */
SELECT COUNT(*) AS row_count
FROM bronze.rees46_events;

SELECT TOP (5)
    event_time, event_type, product_id, category_id, category_code,
    brand, price, user_id, user_session,
    dwh_load_id, dwh_source_file, dwh_create_date
FROM bronze.rees46_events;

-- Event types
SELECT event_type, COUNT(*) AS event_count
FROM bronze.rees46_events
GROUP BY event_type
ORDER BY event_count DESC;

-- Line-ending check: any value still carrying a carriage return?
SELECT COUNT(*) AS rows_with_carriage_return
FROM bronze.rees46_events
WHERE user_session LIKE '%' + CHAR(13);

-- Empty values: stored as NULL or as empty text?
SELECT
    SUM(CASE WHEN brand IS NULL THEN 1 ELSE 0 END) AS brand_is_null,
    SUM(CASE WHEN brand = ''    THEN 1 ELSE 0 END) AS brand_is_empty_text
FROM bronze.rees46_events;

-- Does every row have its 9 values in the right place? A shifted column would show here.
SELECT
    SUM(CASE WHEN event_time    NOT LIKE '____-__-__ __:__:__ UTC' THEN 1 ELSE 0 END) AS bad_event_time_format,
    SUM(CASE WHEN TRY_CONVERT(decimal(18,2), price) IS NULL        THEN 1 ELSE 0 END) AS bad_price,
    SUM(CASE WHEN TRY_CONVERT(int, user_id)         IS NULL        THEN 1 ELSE 0 END) AS bad_user_id,
    SUM(CASE WHEN LEN(user_session) <> 36                          THEN 1 ELSE 0 END) AS bad_session_length
FROM bronze.rees46_events;

-- The technical columns: how many different values of dwh_create_date did one load produce?
SELECT dwh_create_date, COUNT(*) AS row_count
FROM bronze.rees46_events
GROUP BY dwh_create_date;

-- Real size per row (compare with the estimate of about 182 bytes)
EXEC sp_spaceused N'bronze.rees46_events';
GO
