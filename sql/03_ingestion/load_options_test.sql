/*
Purpose : Compare loading options on the same 1,000,000 rows (E3-08).
Task    : E3-08
Note    : Run each block after TRUNCATE. Record duration and log use in the table at the end.
*/
USE ecommerce_rfm_raw;
GO

-- Option A: batch size 1,000,000 (current)
TRUNCATE TABLE bronze.rees46_events;
EXEC bronze.load_bronze @file_name='2019-Oct.csv', @load_id=101, @batch_size=1000000, @truncate_first=1;
GO
-- Option B: batch size 100,000
EXEC bronze.load_bronze @file_name='2019-Oct.csv', @load_id=102, @batch_size=100000, @truncate_first=1;
GO
-- Option C: one single batch (0 = whole file)
EXEC bronze.load_bronze @file_name='2019-Oct.csv', @load_id=103, @batch_size=0, @truncate_first=1;
GO

-- Result: one row per option, from the audit log
SELECT load_id, batch_size, rows_loaded, duration_seconds, rows_per_second, status
FROM audit.load_log
WHERE load_id IN (101, 102, 103)
ORDER BY load_id;
GO
