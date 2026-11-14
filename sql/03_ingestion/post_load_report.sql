/*
Purpose : Report on the state of bronze.rees46_events after loading: rows and labels per
          load, size, log use, files, and format checks on every row.
Task    : E3-03, E3-04
Layer   : bronze
Run     : section by section (select one section and press F5), or the whole script.
          It only reads data. The checks scan the whole table, so each takes a while.
*/

USE ecommerce_rfm_raw;
GO

/* ---------------------------------------------------------------
   1. Rows and labels per load. Every row must carry a file name and a load id.
      distinct_create_dates answers: how many different timestamps did a load produce?
   --------------------------------------------------------------- */
SELECT
    dwh_load_id,
    dwh_source_file,
    COUNT_BIG(*)                     AS rows_loaded,
    COUNT(DISTINCT dwh_create_date)  AS distinct_create_dates,
    MIN(dwh_create_date)             AS first_create_date,
    MAX(dwh_create_date)             AS last_create_date
FROM bronze.rees46_events
GROUP BY dwh_load_id, dwh_source_file
ORDER BY dwh_load_id;

/* ---------------------------------------------------------------
   2. Size: total and bytes per row (the storage plan estimated about 182)
   --------------------------------------------------------------- */
EXEC sp_spaceused N'bronze.rees46_events';

SELECT
    SUM(row_count)                                           AS table_rows,
    CAST(SUM(used_page_count) * 8.0 / 1024 / 1024 AS decimal(10,2)) AS used_gib,
    CAST(SUM(used_page_count) * 8192.0 / SUM(row_count) AS decimal(10,1)) AS bytes_per_row
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'bronze.rees46_events') AND index_id = 0;

/* ---------------------------------------------------------------
   3. Log use and file sizes
   --------------------------------------------------------------- */
DBCC SQLPERF(LOGSPACE);

SELECT name, type_desc, size * 8 / 1024 AS size_mb
FROM sys.database_files;

/* ---------------------------------------------------------------
   4. Format checks on every row (one scan). All the "bad" counters must be 0.
   --------------------------------------------------------------- */
SELECT
    COUNT_BIG(*)                                                                         AS row_count,
    SUM(CASE WHEN event_time NOT LIKE '____-__-__ __:__:__ UTC'    THEN 1 ELSE 0 END)   AS bad_event_time_format,
    SUM(CASE WHEN TRY_CONVERT(decimal(18,2), price) IS NULL        THEN 1 ELSE 0 END)   AS bad_price,
    SUM(CASE WHEN TRY_CONVERT(int, user_id) IS NULL                THEN 1 ELSE 0 END)   AS bad_user_id,
    SUM(CASE WHEN TRY_CONVERT(int, product_id) IS NULL             THEN 1 ELSE 0 END)   AS bad_product_id,
    SUM(CASE WHEN TRY_CONVERT(bigint, category_id) IS NULL         THEN 1 ELSE 0 END)   AS bad_category_id,
    SUM(CASE WHEN LEN(user_session) <> 36                          THEN 1 ELSE 0 END)   AS bad_session_length,
    SUM(CASE WHEN user_session LIKE '%' + CHAR(13)                 THEN 1 ELSE 0 END)   AS rows_with_carriage_return,
    SUM(CASE WHEN brand IS NULL THEN 1 ELSE 0 END)                                      AS brand_is_null,
    SUM(CASE WHEN brand = ''    THEN 1 ELSE 0 END)                                      AS brand_is_empty_text
FROM bronze.rees46_events;
GO
