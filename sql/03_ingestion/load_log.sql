/*
Purpose : Load log table and the procedure that fills it. Records who, when, where, what.
Task    : E3-05
Layer   : audit (ecommerce_rfm_raw)
Re-run  : safe
*/
USE ecommerce_rfm_raw;
GO

IF OBJECT_ID(N'audit.load_log', N'U') IS NULL
CREATE TABLE audit.load_log
(
    load_id           int            NOT NULL CONSTRAINT pk_load_log PRIMARY KEY,
    file_name         varchar(260)   NOT NULL,
    target_table      sysname        NOT NULL,
    batch_size        int            NULL,
    started_at        datetime2(3)   NOT NULL,
    finished_at       datetime2(3)   NULL,
    duration_seconds  decimal(12,3)  NULL,
    rows_loaded       bigint         NULL,
    rows_per_second   bigint         NULL,
    status            varchar(20)    NOT NULL CONSTRAINT df_load_log_status DEFAULT ('running'),
    error_message     nvarchar(2048) NULL,
    login_name        sysname        NOT NULL CONSTRAINT df_load_log_login DEFAULT (ORIGINAL_LOGIN()),
    host_name         sysname        NULL CONSTRAINT df_load_log_host DEFAULT (HOST_NAME()),
    application_name  sysname        NULL CONSTRAINT df_load_log_app  DEFAULT (APP_NAME())
);
GO

-- Start of a load: one row, status 'running'
CREATE OR ALTER PROCEDURE audit.log_load_start
    @load_id int, @file_name varchar(260), @target_table sysname, @batch_size int
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit.load_log (load_id, file_name, target_table, batch_size, started_at)
    VALUES (@load_id, @file_name, @target_table, @batch_size, SYSUTCDATETIME());
END;
GO

-- End of a load: status, counts, duration
CREATE OR ALTER PROCEDURE audit.log_load_end
    @load_id int, @status varchar(20), @rows bigint = NULL, @error nvarchar(2048) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE l
    SET finished_at      = SYSUTCDATETIME(),
        duration_seconds = DATEDIFF(millisecond, l.started_at, SYSUTCDATETIME()) / 1000.0,
        rows_loaded      = @rows,
        rows_per_second  = CAST(@rows / NULLIF(DATEDIFF(millisecond, l.started_at, SYSUTCDATETIME()) / 1000.0, 0) AS bigint),
        status           = @status,
        error_message    = @error
    FROM audit.load_log AS l
    WHERE l.load_id = @load_id;
END;
GO
