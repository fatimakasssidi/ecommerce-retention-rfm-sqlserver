/*
Purpose : Master procedure, updated for the batched gold load.
          - gold only by default (silver is NOT rebuilt: it takes about an hour)
          - @include_silver = 1 rebuilds silver first (only when bronze changed)
          - logs every run in audit.etl_run, every error in audit.etl_error
Task    : E5-06, E5-09
Layer   : ecommerce_rfm_dwh
Run     : EXEC audit.run_full_etl;                          -- gold only (normal)
          EXEC audit.run_full_etl @simulate_failure='gold'; -- failure test (E5-09)
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER PROCEDURE audit.run_full_etl
    @include_silver   bit         = 0,
    @simulate_failure varchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id int;
    DECLARE @step   varchar(100) = 'start';

    INSERT INTO audit.etl_run (procedure_name) VALUES (N'audit.run_full_etl');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        IF @include_silver = 1
        BEGIN
            SET @step = 'silver';
            EXEC silver.load_silver;
        END;

        SET @step = 'gold dimensions';
        EXEC gold.load_gold_dimensions;

        SET @step = 'gold facts (batched)';
        IF @simulate_failure = 'gold' THROW 50099, 'Simulated failure (test only).', 1;
        EXEC gold.load_fact_event_batched @batch_size = 5000000, @resume = 0;

        SET @step = 'gold orders and lines';
        EXEC gold.load_fact_order_and_lines;

        UPDATE audit.etl_run
        SET status = 'success', finished_at = SYSUTCDATETIME(),
            rows_loaded = (SELECT COUNT_BIG(*) FROM gold.fact_event)
        WHERE run_id = @run_id;
    END TRY
    BEGIN CATCH
        INSERT INTO audit.etl_error (run_id, step_name, error_number, error_message)
        VALUES (@run_id, @step, ERROR_NUMBER(), ERROR_MESSAGE());

        UPDATE audit.etl_run
        SET status = 'failed', finished_at = SYSUTCDATETIME()
        WHERE run_id = @run_id;

        THROW;
    END CATCH;
END;
GO
