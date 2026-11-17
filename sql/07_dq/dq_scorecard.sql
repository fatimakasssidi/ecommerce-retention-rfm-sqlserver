/*
Purpose : Scorecard: the latest result of each rule, with its status (E6-07).
          PASS = no failure, FAIL = an error rule has failures,
          WARN = a warning rule has failures (expected cases, to be explained).
Task    : E6-07
Layer   : audit (ecommerce_rfm_dwh)
Usage   : SELECT * FROM audit.v_dq_scorecard ORDER BY rule_id;
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW audit.v_dq_scorecard
AS
WITH latest AS
(
    SELECT h.*,
           ROW_NUMBER() OVER (PARTITION BY h.rule_id ORDER BY h.dq_run_id DESC) AS rn
    FROM audit.v_dq_history AS h
)
SELECT
    l.rule_id,
    l.description,
    l.severity,
    l.rows_checked,
    l.rows_failed,
    l.pass_rate,
    CASE
        WHEN l.rows_failed = 0 THEN 'PASS'
        WHEN l.severity = 'error' THEN 'FAIL'
        ELSE 'WARN'
    END AS status,
    l.dq_run_id,
    l.run_at
FROM latest AS l
WHERE l.rn = 1;
GO
