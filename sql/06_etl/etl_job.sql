/*
Purpose : SQL Server Agent job that runs the full ETL (E5-07).
Note    : SQL Server Agent must be running (MSSQL_AGENT_ENABLED is true in docker-compose.yml).
          The data is static, so the schedule is for the design, not for new data.
*/
USE msdb;
GO
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'rees46_full_etl')
BEGIN
    EXEC dbo.sp_add_job @job_name = N'rees46_full_etl', @enabled = 1;
    EXEC dbo.sp_add_jobstep
         @job_name = N'rees46_full_etl',
         @step_name = N'run full etl',
         @subsystem = N'TSQL',
         @database_name = N'ecommerce_rfm_dwh',
         @command = N'EXEC audit.run_full_etl;',
         @on_fail_action = 2;   -- stop the job and report failure
    EXEC dbo.sp_add_jobschedule
         @job_name = N'rees46_full_etl',
         @name = N'daily 02:00',
         @freq_type = 4,            -- daily
         @freq_interval = 1,
         @active_start_time = 020000;
    EXEC dbo.sp_add_jobserver @job_name = N'rees46_full_etl', @server_name = N'(local)';
END;
GO
