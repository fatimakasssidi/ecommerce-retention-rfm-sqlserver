/*
Purpose : Quarantine view: rejected bronze rows by reason, with share and sample (E6-03).
          The quarantine itself is audit.silver_rejects (created in load_silver.sql):
          every rejected row keeps its raw values and its reason.
Task    : E6-03
Layer   : audit (ecommerce_rfm_dwh)
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW audit.v_quarantine_summary
AS
SELECT
    q.reject_rule,
    COUNT_BIG(*)                                                     AS rejected_rows,
    CAST(100.0 * COUNT_BIG(*) / NULLIF(
        (SELECT COUNT_BIG(*) FROM ecommerce_rfm_raw.bronze.rees46_events), 0) AS decimal(9,4)) AS pct_of_bronze,
    MIN(q.rejected_at)                                               AS first_rejected_at,
    MAX(q.rejected_at)                                               AS last_rejected_at
FROM audit.silver_rejects AS q
GROUP BY q.reject_rule;
GO

/* To see examples of one reason:
   SELECT TOP (20) * FROM audit.silver_rejects WHERE reject_rule = 'bad_user_session'; */
