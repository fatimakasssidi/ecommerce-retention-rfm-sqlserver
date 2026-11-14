/*
Purpose : Follow a bulk load while it is running. Run it in a SECOND query window.
Task    : E3-03, E3-04 (reusable for every load)
Layer   : bronze
Note    : Reads only metadata (DMVs). It never waits on the table lock of the load.
Usage   : 1. Set @rows_before and @expected_rows below.
              October:  @rows_before = 0,         @expected_rows = 42448764
              November: @rows_before = 42448764,  @expected_rows = 66000000 (estimate)
          2. Run PART A as often as you like (progress, state, log, memory),
             or run PART B once: it prints one progress line every 20 seconds
             in the Messages tab, and stops by itself after 20 minutes.
*/

USE ecommerce_rfm_raw;
GO

/* =================================================================
   PART A: one snapshot
   ================================================================= */
DECLARE @rows_before   bigint = 0;          -- rows already in the table before this load
DECLARE @expected_rows bigint = 42448764;   -- rows expected from this load (for the percentage and the ETA)

-- A1. Progress. Rows become visible batch by batch (every 1,000,000 rows).
WITH progress AS
(
    SELECT
        SUM(ps.row_count) - @rows_before AS rows_this_load
    FROM sys.dm_db_partition_stats AS ps
    WHERE ps.object_id = OBJECT_ID(N'bronze.rees46_events') AND ps.index_id = 0
),
running AS
(
    SELECT TOP (1)
        r.session_id,
        r.start_time,
        DATEDIFF(second, r.start_time, SYSUTCDATETIME()) AS elapsed_seconds
    FROM sys.dm_exec_requests AS r
    WHERE r.command LIKE N'BULK INSERT%'
)
SELECT
    p.rows_this_load,
    CAST(100.0 * p.rows_this_load / @expected_rows AS decimal(5,1))              AS pct_done,
    u.elapsed_seconds,
    CAST(p.rows_this_load / NULLIF(u.elapsed_seconds, 0) AS bigint)              AS rows_per_second,
    (@expected_rows - p.rows_this_load)
        / NULLIF(p.rows_this_load / NULLIF(u.elapsed_seconds, 0), 0)             AS eta_seconds
FROM progress AS p
LEFT JOIN running AS u ON 1 = 1;

-- A2. The state of the load itself. blocking_session_id must be 0.
SELECT
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time              AS wait_ms,
    r.blocking_session_id,
    r.total_elapsed_time / 1000 AS elapsed_seconds,
    r.cpu_time               AS cpu_ms,
    r.writes                 AS pages_written
FROM sys.dm_exec_requests AS r
WHERE r.command LIKE N'BULK INSERT%';

-- A3. Log and data file
SELECT
    CAST(total_log_size_in_bytes / 1048576.0 AS decimal(12,1)) AS log_size_mb,
    CAST(used_log_space_in_bytes / 1048576.0 AS decimal(12,1)) AS log_used_mb,
    CAST(used_log_space_in_percent AS decimal(5,1))            AS log_used_pct
FROM sys.dm_db_log_space_usage;

SELECT name, type_desc, size * 8 / 1024 AS size_mb
FROM sys.database_files;

-- A4. Memory: SQL Server's use and what is left for the system
SELECT
    pm.physical_memory_in_use_kb / 1024     AS sql_memory_used_mb,
    sm.available_physical_memory_kb / 1024  AS machine_available_mb
FROM sys.dm_os_process_memory AS pm
CROSS JOIN sys.dm_os_sys_memory AS sm;
GO

/* =================================================================
   PART B: a progress line every 20 seconds (look at the Messages tab)
   ================================================================= */
DECLARE @rows_before_b   bigint = 0;
DECLARE @expected_rows_b bigint = 42448764;
DECLARE @i               int    = 0;
DECLARE @rows            bigint;
DECLARE @message         nvarchar(200);

WHILE @i < 60
BEGIN
    SELECT @rows = SUM(ps.row_count) - @rows_before_b
    FROM sys.dm_db_partition_stats AS ps
    WHERE ps.object_id = OBJECT_ID(N'bronze.rees46_events') AND ps.index_id = 0;

    SET @message = CONCAT(CONVERT(varchar(8), SYSUTCDATETIME(), 108), ' UTC   rows this load: ',
                          FORMAT(@rows, 'N0'), '   (',
                          CAST(100.0 * @rows / @expected_rows_b AS decimal(5,1)), ' %)');
    RAISERROR('%s', 0, 1, @message) WITH NOWAIT;

    WAITFOR DELAY '00:00:20';
    SET @i += 1;
END;
GO
