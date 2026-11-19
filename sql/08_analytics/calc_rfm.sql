/*
Purpose : RFM for one snapshot date: recency, frequency, monetary, scores 1 to 5, segment (E7-02).
          Also writes the segment snapshot used by the SCD2 procedure (gold.apply_customer_segment_scd2).
Task    : E7-02
Layer   : gold (ecommerce_rfm_dwh)
Rules   : rfm_rules.md
          - recency and monetary: percentile thresholds at 20, 40, 60, 80 (ties get the same score)
          - frequency: fixed thresholds 1, 2, 3, 4-5, 6+
          - fm_score = ROUND((frequency + monetary) / 2), halves up
          - segment looked up in gold.dim_rfm_segment (grid, 25 cells)
Run     : EXEC gold.calc_rfm @snapshot_date = '2019-12-01';   -- re-runnable for the same date
*/
USE ecommerce_rfm_dwh;
GO

/* 1. The segment grid (9 segments from the 5 by 5 grid of rfm_rules.md) */
IF OBJECT_ID(N'gold.dim_rfm_segment', N'U') IS NULL
CREATE TABLE gold.dim_rfm_segment
(
    recency_score  tinyint     NOT NULL,
    fm_score       tinyint     NOT NULL,
    rfm_segment    varchar(30) NOT NULL,
    CONSTRAINT pk_dim_rfm_segment PRIMARY KEY (recency_score, fm_score),
    CONSTRAINT ck_dim_rfm_segment_r CHECK (recency_score BETWEEN 1 AND 5),
    CONSTRAINT ck_dim_rfm_segment_fm CHECK (fm_score BETWEEN 1 AND 5)
);
GO
IF NOT EXISTS (SELECT 1 FROM gold.dim_rfm_segment)
BEGIN
    INSERT INTO gold.dim_rfm_segment (recency_score, fm_score, rfm_segment) VALUES
    (5,1,'New Customers'),(5,2,'Potential Loyalists'),(5,3,'Potential Loyalists'),(5,4,'Champions'),(5,5,'Champions'),
    (4,1,'New Customers'),(4,2,'Potential Loyalists'),(4,3,'Potential Loyalists'),(4,4,'Champions'),(4,5,'Champions'),
    (3,1,'About to Sleep'),(3,2,'Need Attention'),(3,3,'Need Attention'),(3,4,'Loyal Customers'),(3,5,'Loyal Customers'),
    (2,1,'About to Sleep'),(2,2,'About to Sleep'),(2,3,'At Risk'),(2,4,'At Risk'),(2,5,'Can''t Lose Them'),
    (1,1,'Hibernating'),(1,2,'Hibernating'),(1,3,'At Risk'),(1,4,'At Risk'),(1,5,'Can''t Lose Them');
END;
GO

/* 2. The report table: one row per customer and snapshot */
IF OBJECT_ID(N'gold.report_customer_rfm', N'U') IS NULL
CREATE TABLE gold.report_customer_rfm
(
    customer_id      int          NOT NULL,
    snapshot_date    date         NOT NULL,
    recency_days     int          NOT NULL,
    frequency_count  int          NOT NULL,
    monetary_amount  decimal(14,2) NOT NULL,
    recency_score    tinyint      NOT NULL,
    frequency_score  tinyint      NOT NULL,
    monetary_score   tinyint      NOT NULL,
    fm_score         tinyint      NOT NULL,
    rfm_segment      varchar(30)  NOT NULL,
    dwh_create_date  datetime2(0) NOT NULL CONSTRAINT df_report_customer_rfm_create DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_report_customer_rfm PRIMARY KEY (customer_id, snapshot_date)
);
GO

CREATE OR ALTER PROCEDURE gold.calc_rfm
    @snapshot_date date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    /* 3. Base: orders up to the snapshot date, per customer (customer -1 excluded) */
    SELECT
        c.customer_id,
        MAX(d.full_date)                AS last_order_date,
        COUNT(*)                        AS frequency_count,
        SUM(o.order_value)              AS monetary_amount
    INTO #base
    FROM gold.fact_order AS o
    INNER JOIN gold.dim_customer AS c ON c.customer_key = o.customer_key
    INNER JOIN gold.dim_date     AS d ON d.date_key     = o.order_date_key
    WHERE d.full_date <= @snapshot_date
      AND c.customer_id <> -1
    GROUP BY c.customer_id;

    ALTER TABLE #base ADD recency_days int NULL;
    UPDATE #base SET recency_days = DATEDIFF(day, last_order_date, @snapshot_date);

    /* 4. Percentile thresholds (recency and monetary) */
    DECLARE @r20 float, @r40 float, @r60 float, @r80 float;
    DECLARE @m20 float, @m40 float, @m60 float, @m80 float;

    SELECT TOP (1)
        @r20 = PERCENTILE_CONT(0.2) WITHIN GROUP (ORDER BY recency_days) OVER (),
        @r40 = PERCENTILE_CONT(0.4) WITHIN GROUP (ORDER BY recency_days) OVER (),
        @r60 = PERCENTILE_CONT(0.6) WITHIN GROUP (ORDER BY recency_days) OVER (),
        @r80 = PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY recency_days) OVER ()
    FROM #base;

    SELECT TOP (1)
        @m20 = PERCENTILE_CONT(0.2) WITHIN GROUP (ORDER BY monetary_amount) OVER (),
        @m40 = PERCENTILE_CONT(0.4) WITHIN GROUP (ORDER BY monetary_amount) OVER (),
        @m60 = PERCENTILE_CONT(0.6) WITHIN GROUP (ORDER BY monetary_amount) OVER (),
        @m80 = PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY monetary_amount) OVER ()
    FROM #base;

    /* 5. Scores (5 = best). Lower recency days is better. */
    SELECT
        b.customer_id, b.recency_days, b.frequency_count, b.monetary_amount,
        CAST(CASE WHEN b.recency_days <= @r20 THEN 5 WHEN b.recency_days <= @r40 THEN 4
                  WHEN b.recency_days <= @r60 THEN 3 WHEN b.recency_days <= @r80 THEN 2 ELSE 1 END AS tinyint) AS recency_score,
        CAST(CASE WHEN b.frequency_count >= 6 THEN 5 WHEN b.frequency_count >= 4 THEN 4
                  WHEN b.frequency_count = 3 THEN 3 WHEN b.frequency_count = 2 THEN 2 ELSE 1 END AS tinyint) AS frequency_score,
        CAST(CASE WHEN b.monetary_amount >= @m80 THEN 5 WHEN b.monetary_amount >= @m60 THEN 4
                  WHEN b.monetary_amount >= @m40 THEN 3 WHEN b.monetary_amount >= @m20 THEN 2 ELSE 1 END AS tinyint) AS monetary_score
    INTO #scored
    FROM #base AS b;

    ALTER TABLE #scored ADD fm_score tinyint NULL, rfm_segment varchar(30) NULL;

    UPDATE #scored
    SET fm_score = CAST(ROUND((frequency_score + monetary_score) / 2.0, 0) AS tinyint);

    /* 6. Segment from the grid */
    UPDATE s
    SET s.rfm_segment = g.rfm_segment
    FROM #scored AS s
    INNER JOIN gold.dim_rfm_segment AS g
            ON g.recency_score = s.recency_score AND g.fm_score = s.fm_score;

    /* 7. Write the report (re-runnable: the same snapshot is replaced) */
    DELETE FROM gold.report_customer_rfm WHERE snapshot_date = @snapshot_date;

    INSERT INTO gold.report_customer_rfm
        (customer_id, snapshot_date, recency_days, frequency_count, monetary_amount,
         recency_score, frequency_score, monetary_score, fm_score, rfm_segment)
    SELECT customer_id, @snapshot_date, recency_days, frequency_count, monetary_amount,
           recency_score, frequency_score, monetary_score, fm_score, rfm_segment
    FROM #scored;

    /* 8. Segment snapshot for the SCD2 history (gold.apply_customer_segment_scd2) */
    DELETE FROM gold.customer_segment_snapshot WHERE snapshot_date = @snapshot_date;

    INSERT INTO gold.customer_segment_snapshot (customer_id, snapshot_date, rfm_segment)
    SELECT customer_id, @snapshot_date, rfm_segment FROM #scored;

    DROP TABLE #base;
    DROP TABLE #scored;

    COMMIT TRANSACTION;

    SELECT @snapshot_date AS snapshot_date, COUNT(*) AS customers,
           MIN(recency_days) AS min_recency, MAX(recency_days) AS max_recency
    FROM gold.report_customer_rfm WHERE snapshot_date = @snapshot_date;
END;
GO
