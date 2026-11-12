/*
Purpose : Load one REES46 monthly file into bronze.rees46_events, in batches.
          Every row gets the file name and the load id. Each run is logged in audit.load_log.
Task    : E3-03, E3-05
Layer   : bronze
Example : EXEC bronze.load_bronze @file_name = '2019-Oct.csv', @load_id = 1,
                                  @batch_size = 1000000, @truncate_first = 1;
*/
USE ecommerce_rfm_raw;
GO

CREATE OR ALTER PROCEDURE bronze.load_bronze
    @file_name      varchar(260),
    @load_id        int,
    @batch_size     int = 1000000,
    @truncate_first bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @file_name NOT IN ('2019-Oct.csv', '2019-Nov.csv')
        THROW 50001, 'File name not allowed. Use 2019-Oct.csv or 2019-Nov.csv.', 1;
    IF @batch_size < 0
        THROW 50002, '@batch_size must be 0 or a positive number.', 1;

    IF @truncate_first = 1
        TRUNCATE TABLE bronze.rees46_events;
    ELSE IF EXISTS (SELECT 1 FROM bronze.rees46_events WHERE dwh_source_file = @file_name)
        THROW 50003, 'This file is already loaded. Use @truncate_first = 1 to empty the table and reload.', 1;

    DECLARE @start_time datetime2(3) = SYSUTCDATETIME();
    DECLARE @path       nvarchar(300) = N'/data/raw/rees46/' + @file_name;
    DECLARE @sql        nvarchar(max);
    DECLARE @rows       bigint;
    DECLARE @seconds    decimal(12,3);
    DECLARE @error_text nvarchar(2048);

    DECLARE @drop_defaults nvarchar(max) = N'
        IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N''df_rees46_events_dwh_source_file'')
            ALTER TABLE bronze.rees46_events DROP CONSTRAINT df_rees46_events_dwh_source_file;
        IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N''df_rees46_events_dwh_load_id'')
            ALTER TABLE bronze.rees46_events DROP CONSTRAINT df_rees46_events_dwh_load_id;';

    -- Log the start (own transaction, so it survives a failed load)
    EXEC audit.log_load_start @load_id, @file_name, N'bronze.rees46_events', @batch_size;

    BEGIN TRY
        EXEC (@drop_defaults);
        SET @sql = N'
            ALTER TABLE bronze.rees46_events ADD CONSTRAINT df_rees46_events_dwh_source_file
                DEFAULT (''' + @file_name + N''') FOR dwh_source_file;
            ALTER TABLE bronze.rees46_events ADD CONSTRAINT df_rees46_events_dwh_load_id
                DEFAULT (' + CAST(@load_id AS nvarchar(20)) + N') FOR dwh_load_id;';
        EXEC (@sql);

        SET @sql = N'
            BULK INSERT bronze.v_rees46_events_load
            FROM ''' + @path + N'''
            WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', TABLOCK'
            + CASE WHEN @batch_size > 0 THEN N', BATCHSIZE = ' + CAST(@batch_size AS nvarchar(20)) ELSE N'' END
            + N');';
        EXEC (@sql);

        SET @seconds = DATEDIFF(millisecond, @start_time, SYSUTCDATETIME()) / 1000.0;
        EXEC (@drop_defaults);

        SELECT @rows = COUNT_BIG(*) FROM bronze.rees46_events WHERE dwh_source_file = @file_name;

        EXEC audit.log_load_end @load_id, 'success', @rows, NULL;

        SELECT @file_name AS file_name, @load_id AS load_id, @batch_size AS batch_size,
               @rows AS rows_loaded, @seconds AS load_seconds,
               CAST(@rows / NULLIF(@seconds, 0) AS bigint) AS rows_per_second;
    END TRY
    BEGIN CATCH
        SET @error_text = ERROR_MESSAGE();
        BEGIN TRY EXEC (@drop_defaults); END TRY BEGIN CATCH END CATCH;
        EXEC audit.log_load_end @load_id, 'failed', NULL, @error_text;
        THROW 50004, @error_text, 1;
    END CATCH;
END;
GO
