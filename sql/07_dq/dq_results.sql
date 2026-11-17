/*
Purpose : Data quality results log: rule catalog, runs and results (E6-04).
Task    : E6-01 (catalog), E6-04
Layer   : audit (ecommerce_rfm_dwh)
Re-run  : safe. Catalog rows are merged, history is kept.
*/
USE ecommerce_rfm_dwh;
GO

IF OBJECT_ID(N'audit.dq_rule', N'U') IS NULL
CREATE TABLE audit.dq_rule
(
    rule_id      varchar(10)  NOT NULL CONSTRAINT pk_dq_rule PRIMARY KEY,
    table_name   varchar(100) NOT NULL,
    description  varchar(400) NOT NULL,
    severity     varchar(10)  NOT NULL CONSTRAINT ck_dq_rule_severity CHECK (severity IN ('error', 'warning'))
);
GO

IF OBJECT_ID(N'audit.dq_run', N'U') IS NULL
CREATE TABLE audit.dq_run
(
    dq_run_id  int           NOT NULL IDENTITY(1,1) CONSTRAINT pk_dq_run PRIMARY KEY,
    run_at     datetime2(0)  NOT NULL CONSTRAINT df_dq_run_at DEFAULT (SYSUTCDATETIME()),
    login_name sysname       NOT NULL CONSTRAINT df_dq_run_login DEFAULT (ORIGINAL_LOGIN())
);
GO

IF OBJECT_ID(N'audit.dq_result', N'U') IS NULL
CREATE TABLE audit.dq_result
(
    result_id    int          NOT NULL IDENTITY(1,1) CONSTRAINT pk_dq_result PRIMARY KEY,
    dq_run_id    int          NOT NULL CONSTRAINT fk_dq_result_run  FOREIGN KEY REFERENCES audit.dq_run (dq_run_id),
    rule_id      varchar(10)  NOT NULL CONSTRAINT fk_dq_result_rule FOREIGN KEY REFERENCES audit.dq_rule (rule_id),
    rows_checked bigint       NOT NULL,
    rows_failed  bigint       NOT NULL,
    pass_rate    decimal(7,4) NOT NULL   -- 1 - rows_failed / rows_checked
);
GO

/* The catalog: every rule, its table, its meaning, and its severity.
   error   = must be 0 for the data to be trusted
   warning = expected to be above 0 in some cases, reported and explained */
MERGE audit.dq_rule AS t
USING (VALUES
    ('DQ-01', 'silver.rees46_event',  'Event has product, user and session', 'error'),
    ('DQ-02', 'silver.rees46_event',  'Purchase has a price above 0', 'error'),
    ('DQ-03', 'silver.rees46_event',  'Event time inside the data period 2019-10-01 to 2019-11-30', 'error'),
    ('DQ-04', 'silver.rees46_event',  'Event type is one of view, cart, remove_from_cart, purchase', 'error'),
    ('DQ-05', 'silver.rees46_event',  'Zero price on a view or cart is kept as unknown (NULL)', 'warning'),
    ('DQ-06', 'gold.fact_event',      'Event linked to a known customer version (not -1)', 'warning'),
    ('DQ-07', 'gold.fact_event',      'Gold events equal silver events', 'error'),
    ('DQ-08', 'gold.fact_order_line', 'Gold order lines equal silver purchase events', 'error'),
    ('DQ-09', 'gold.fact_order',      'Gold orders equal silver purchase sessions', 'error'),
    ('DQ-10', 'silver.rees46_product','Product has a known brand (not unknown -1)', 'warning'),
    ('DQ-11', 'silver.rees46_product','Product category has a code (not unclassified)', 'warning'),
    ('DQ-12', 'silver.rees46_event',  'Session linked to one user only', 'warning'),
    ('DQ-13', 'audit.silver_rejects', 'Bronze rows = silver events + rejected rows', 'error')
) AS s (rule_id, table_name, description, severity)
ON t.rule_id = s.rule_id
WHEN MATCHED THEN UPDATE SET table_name = s.table_name, description = s.description, severity = s.severity
WHEN NOT MATCHED THEN INSERT (rule_id, table_name, description, severity)
    VALUES (s.rule_id, s.table_name, s.description, s.severity);
GO

CREATE OR ALTER VIEW audit.v_dq_history
AS
SELECT r.dq_run_id, r.run_at, res.rule_id, c.description, c.severity,
       res.rows_checked, res.rows_failed, res.pass_rate
FROM audit.dq_run AS r
INNER JOIN audit.dq_result AS res ON res.dq_run_id = r.dq_run_id
INNER JOIN audit.dq_rule AS c ON c.rule_id = res.rule_id;
GO
