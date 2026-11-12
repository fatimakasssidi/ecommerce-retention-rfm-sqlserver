/*
Purpose : Reconcile bronze row counts with the source files (E3-06).
Task    : E3-06
Note    : Line count of a file = data rows + 1 header line.
          Run the first two commands in PowerShell, then the SQL.
*/
-- PowerShell (lines in each file, including the header):
--   docker exec rfm-sqlserver sh -c "wc -l /data/raw/rees46/2019-Oct.csv"
--   docker exec rfm-sqlserver sh -c "wc -l /data/raw/rees46/2019-Nov.csv"

USE ecommerce_rfm_raw;
GO

-- Table rows per file, compared with (wc -l - 1)
SELECT
    dwh_source_file,
    COUNT_BIG(*) AS table_rows
FROM bronze.rees46_events
GROUP BY dwh_source_file;

-- Log rows vs table rows
SELECT
    l.file_name,
    l.status,
    l.rows_loaded                                AS logged_rows,
    t.table_rows,
    l.rows_loaded - t.table_rows                 AS difference
FROM audit.load_log AS l
LEFT JOIN
(
    SELECT dwh_source_file, COUNT_BIG(*) AS table_rows
    FROM bronze.rees46_events
    GROUP BY dwh_source_file
) AS t ON t.dwh_source_file = l.file_name
WHERE l.status = 'success';
GO
