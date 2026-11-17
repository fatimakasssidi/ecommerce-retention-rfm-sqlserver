/*
Purpose : Verify every E5 object exists and the data is correct (run in ecommerce_rfm_dwh).
Task    : E5-01 to E5-09
*/
USE ecommerce_rfm_dwh;
GO

-- 1. Objects (expected: all listed rows present)
SELECT 'table'     AS kind, SCHEMA_NAME(t.schema_id) + '.' + t.name AS object_name
FROM sys.tables AS t
WHERE SCHEMA_NAME(t.schema_id) = N'audit'
UNION ALL
SELECT 'procedure', SCHEMA_NAME(p.schema_id) + '.' + p.name
FROM sys.procedures AS p
WHERE SCHEMA_NAME(p.schema_id) IN (N'audit', N'silver', N'gold')
ORDER BY kind, object_name;

-- 2. Silver reconciliation (E5-01): bronze = silver + rejected
SELECT
    (SELECT COUNT_BIG(*) FROM ecommerce_rfm_raw.bronze.rees46_events) AS bronze_rows,
    (SELECT COUNT_BIG(*) FROM silver.rees46_event)                     AS silver_events,
    (SELECT COUNT_BIG(*) FROM audit.silver_rejects)                    AS rejected_rows;

-- 3. Gold facts match silver (E5-03)
SELECT 'fact_event' AS check_name,
       (SELECT COUNT_BIG(*) FROM gold.fact_event)           AS gold_rows,
       (SELECT COUNT_BIG(*) FROM silver.rees46_event)       AS silver_rows
UNION ALL
SELECT 'fact_order_line', (SELECT COUNT_BIG(*) FROM gold.fact_order_line),
       (SELECT COUNT_BIG(*) FROM silver.rees46_event WHERE event_type = 'purchase')
UNION ALL
SELECT 'fact_order', (SELECT COUNT(*) FROM gold.fact_order),
       (SELECT COUNT(DISTINCT user_session) FROM silver.rees46_event WHERE event_type = 'purchase');

-- 4. Last run status (E5-06, E5-09): the last run must be success
SELECT TOP (5) run_id, status, started_at, finished_at, rows_loaded
FROM audit.etl_run ORDER BY run_id DESC;

-- 5. Failures are recorded (E5-05, E5-09)
SELECT COUNT(*) AS recorded_errors FROM audit.etl_error;

-- 6. SQL Agent job (E5-07)
SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name = N'rees46_full_etl';
