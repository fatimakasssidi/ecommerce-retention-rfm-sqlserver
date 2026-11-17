# ETL Failure and Recovery Test (E5-09)

Project: E-commerce Customer Retention & RFM (SQL Server)
Procedure tested: `audit.run_full_etl` (file `etl_master.sql`)

## Goal

Prove that when the ETL fails:
1. the failure is recorded (who, which step, which message),
2. the database is not left half-loaded,
3. the next run recovers and produces the same result.

## Method

A failure is forced with the parameter `@simulate_failure = 'gold'`, which raises an error
in the step `gold facts (batched)`, after the dimensions are loaded and before the facts.

```sql
EXEC audit.run_full_etl @simulate_failure = 'gold';   -- expected: fails on purpose
SELECT step_name, error_number, error_message FROM audit.etl_error;
EXEC audit.run_full_etl;                              -- expected: recovers
```

## Results

| Run | Date (UTC) | Trigger | Status | Rows in fact_event | Notes |
|---|---|---|---|---|---|
| 1 | 2026-11-16 13:09 | manual, first attempt | abandoned | NULL | Stopped by hand (KILL). Earlier single-transaction design, now superseded |
| 2 | 2026-11-17 08:48 | manual | success | 109,819,992 | Earlier single-transaction version of the gold load |
| 3 | 2026-11-17 09:04 | `@simulate_failure = 'gold'` | **failed** (on purpose) | NULL | Error 50099 at step `gold facts (batched)` |
| 4 | 2026-11-17 09:05 | manual recovery | success | 109,819,992 | Batched load (5,000,000 per batch), 17 minutes |
| 5 | 2026-11-17 10:23 | SQL Server Agent job | success | 109,819,992 | Same procedure, started by the scheduled job, 21 minutes |

## Checks

| Check | Expected | Result |
|---|---|---|
| Failure recorded in `audit.etl_error` | One row for step `gold facts (batched)` | Yes: error 50099, message "Simulated failure (test only)." |
| Failed run marked in `audit.etl_run` | `failed` | Yes (run 3) |
| Recovery run succeeds | `success` | Yes (run 4) |
| Same result after recovery | 109,819,992 events, equal to silver | Yes |
| Batch log consistent | Sum of batches = silver events | Yes (checked in the gold validation) |
| No duplicate data after recovery | Fact count equals silver count | Yes: the batched load truncates the facts before reloading |

## Why the recovery is safe

- The gold facts are emptied at the start of each run, then rebuilt. A failed run therefore
  leaves partial facts, and the next run replaces them entirely. The recovery run does not
  add to the old rows.
- Each batch is committed on its own. If a run fails in the middle, `@resume = 1` continues
  after the last committed batch, without reloading it.
- The silver layer is not touched by the daily job, so a gold failure cannot damage silver.

## Conclusion

The ETL failure is recorded with its step and message, the failed run is marked as failed,
and the next run recovers to the same result (109,819,992 events, equal to silver).
E5-09 passes.
