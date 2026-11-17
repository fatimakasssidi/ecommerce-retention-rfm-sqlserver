# Scheduling the ETL (E5-07)

Project: E-commerce Customer Retention & RFM (SQL Server)
Job: `rees46_full_etl` (script `etl_job.sql`)

## What the job does

Runs `EXEC audit.run_full_etl;` in the database `ecommerce_rfm_dwh`, every day at 02:00.
The job runs the gold layer only. The silver rebuild is off by default, because it takes
about an hour and fills the transaction log.

| Setting | Value | Reason |
|---|---|---|
| Schedule | Daily, 02:00 | Typical off-peak time for a batch job |
| Step type | T-SQL | Runs inside SQL Server |
| On failure | Stop the job and report failure | The error is visible in the job history and in `audit.etl_error` |
| Silver rebuild | Off | Silver is rebuilt only when bronze changes (`@include_silver = 1`) |

## Requirements

- SQL Server Agent must be running (`MSSQL_AGENT_ENABLED: "true"` in `docker-compose.yml`).
- Do not run a manual load while the job runs: both would write to the same tables.
- The machine must be on at 02:00 (Docker and SQL Server must be running).

## Test results

| Test | Date (UTC) | Result |
|---|---|---|
| Job started by hand (`sp_start_job`) | 2026-11-17 10:23 | Started |
| Run recorded in `audit.etl_run` | run 5 | `success`, 109,819,992 events |
| Duration | about 21 minutes | Same as the manual run |

## How to operate it

| Action | Command |
|---|---|
| Start now | `EXEC msdb.dbo.sp_start_job @job_name = N'rees46_full_etl';` |
| Enable the daily run | `EXEC msdb.dbo.sp_update_job @job_name = N'rees46_full_etl', @enabled = 1;` |
| Disable the daily run | `EXEC msdb.dbo.sp_update_job @job_name = N'rees46_full_etl', @enabled = 0;` |
| Last result | `SELECT TOP (1) run_id, status, finished_at, rows_loaded FROM audit.etl_run ORDER BY run_id DESC;` |

## Current setting

The job is **disabled** after the test, so it does not rebuild the gold layer every day
while the project is in development. Enable it when the data is refreshed regularly.
