/*
Purpose : Segment summary: size, share of customers, share of revenue, averages per segment,
          for the latest RFM snapshot (E7-03).
Task    : E7-03
Layer   : gold (ecommerce_rfm_dwh)
Depends : gold.report_customer_rfm (run gold.calc_rfm first)
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER VIEW gold.v_rfm_latest
AS
SELECT r.*
FROM gold.report_customer_rfm AS r
WHERE r.snapshot_date = (SELECT MAX(snapshot_date) FROM gold.report_customer_rfm);
GO

CREATE OR ALTER VIEW gold.v_segment_summary
AS
SELECT
    s.rfm_segment,
    COUNT(*)                                                       AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS decimal(6,2)) AS pct_customers,
    SUM(s.monetary_amount)                                         AS revenue,
    CAST(100.0 * SUM(s.monetary_amount) / SUM(SUM(s.monetary_amount)) OVER () AS decimal(6,2)) AS pct_revenue,
    CAST(AVG(CAST(s.recency_days AS float))    AS decimal(9,1))    AS avg_recency_days,
    CAST(AVG(CAST(s.frequency_count AS float)) AS decimal(9,2))    AS avg_orders,
    CAST(AVG(s.monetary_amount)                AS decimal(12,2))   AS avg_revenue_per_customer
FROM gold.v_rfm_latest AS s
GROUP BY s.rfm_segment;
GO
