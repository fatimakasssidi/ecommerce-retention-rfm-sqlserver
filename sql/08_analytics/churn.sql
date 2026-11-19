/*
Purpose : Churn status per customer at a snapshot date, and the at-risk list (E7-06).
          Rule (churn_definition.md): Active <= 0.5 x N days, Slipping <= N, Churned > N.
          At risk = Slipping, or Churned with a high-value segment.
Task    : E7-06
Layer   : gold (ecommerce_rfm_dwh)
Depends : gold.calc_rfm for the same snapshot date (recency and segment come from it)
Run     : EXEC gold.calc_churn @snapshot_date = '2019-12-01', @churn_days = 14;
Note    : N = 14 is provisional (D6). The reactivation test (docs/validation.md) confirms it.
          The segment used is the one of the snapshot (the rule's "last active snapshot" is simplified).
*/
USE ecommerce_rfm_dwh;
GO

IF OBJECT_ID(N'gold.report_customer_churn', N'U') IS NULL
CREATE TABLE gold.report_customer_churn
(
    customer_id          int          NOT NULL,
    snapshot_date        date         NOT NULL,
    days_since_last_order int         NOT NULL,
    churn_status         varchar(10)  NOT NULL CONSTRAINT ck_churn_status CHECK (churn_status IN ('Active', 'Slipping', 'Churned')),
    is_churned           bit          NOT NULL,
    rfm_segment          varchar(30)  NULL,
    is_at_risk           bit          NOT NULL,
    dwh_create_date      datetime2(0) NOT NULL CONSTRAINT df_report_customer_churn_create DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_report_customer_churn PRIMARY KEY (customer_id, snapshot_date)
);
GO

CREATE OR ALTER PROCEDURE gold.calc_churn
    @snapshot_date date,
    @churn_days   int = 14
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    DELETE FROM gold.report_customer_churn WHERE snapshot_date = @snapshot_date;

    INSERT INTO gold.report_customer_churn
        (customer_id, snapshot_date, days_since_last_order, churn_status, is_churned, rfm_segment, is_at_risk)
    SELECT
        r.customer_id,
        @snapshot_date,
        r.recency_days,
        CASE WHEN r.recency_days <= 0.5 * @churn_days THEN 'Active'
             WHEN r.recency_days <= @churn_days       THEN 'Slipping'
             ELSE 'Churned' END,
        CASE WHEN r.recency_days > @churn_days THEN 1 ELSE 0 END,
        r.rfm_segment,
        CASE WHEN r.recency_days > 0.5 * @churn_days
              AND (r.recency_days <= @churn_days
                   OR r.rfm_segment IN ('Champions', 'Loyal Customers', 'Can''t Lose Them'))
             THEN 1 ELSE 0 END
    FROM gold.report_customer_rfm AS r
    WHERE r.snapshot_date = @snapshot_date;

    COMMIT TRANSACTION;

    SELECT churn_status, COUNT(*) AS customers, SUM(CAST(is_at_risk AS int)) AS at_risk
    FROM gold.report_customer_churn WHERE snapshot_date = @snapshot_date
    GROUP BY churn_status;
END;
GO
