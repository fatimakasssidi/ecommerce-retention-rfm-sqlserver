/*
Purpose : Run the 13 data quality rules and store the results (E6-02).
          Each run writes one dq_run and one dq_result per rule.
Task    : E6-02
Layer   : audit (ecommerce_rfm_dwh)
Run     : EXEC audit.run_dq_checks;
Note    : Scans the full tables (several minutes). Run it after the ETL, not during a load.
*/
USE ecommerce_rfm_dwh;
GO

CREATE OR ALTER PROCEDURE audit.run_dq_checks
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run int;
    INSERT INTO audit.dq_run DEFAULT VALUES;
    SET @run = SCOPE_IDENTITY();

    CREATE TABLE #raw (rule_id varchar(10) NOT NULL, rows_checked bigint NOT NULL, rows_failed bigint NOT NULL);

    /* DQ-01: product, user and session present */
    INSERT INTO #raw
    SELECT 'DQ-01', COUNT_BIG(*),
           SUM(CASE WHEN product_id IS NULL OR user_id IS NULL OR user_session IS NULL THEN 1 ELSE 0 END)
    FROM silver.rees46_event;

    /* DQ-02: purchase price above 0 */
    INSERT INTO #raw
    SELECT 'DQ-02', SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END),
           SUM(CASE WHEN event_type = 'purchase' AND (price IS NULL OR price <= 0) THEN 1 ELSE 0 END)
    FROM silver.rees46_event;

    /* DQ-03: event time inside the data period */
    INSERT INTO #raw
    SELECT 'DQ-03', COUNT_BIG(*),
           SUM(CASE WHEN event_time < '2019-10-01' OR event_time >= '2019-12-01' THEN 1 ELSE 0 END)
    FROM silver.rees46_event;

    /* DQ-04: event type allowed */
    INSERT INTO #raw
    SELECT 'DQ-04', COUNT_BIG(*),
           SUM(CASE WHEN event_type NOT IN ('view', 'cart', 'remove_from_cart', 'purchase') THEN 1 ELSE 0 END)
    FROM silver.rees46_event;

    /* DQ-05: non-purchase events with an unknown price (zero price in the source) */
    INSERT INTO #raw
    SELECT 'DQ-05', SUM(CASE WHEN event_type <> 'purchase' THEN 1 ELSE 0 END),
           SUM(CASE WHEN event_type <> 'purchase' AND price IS NULL THEN 1 ELSE 0 END)
    FROM silver.rees46_event;

    /* DQ-06: events linked to a known customer version */
    INSERT INTO #raw
    SELECT 'DQ-06', COUNT_BIG(*),
           SUM(CASE WHEN customer_key = -1 THEN 1 ELSE 0 END)
    FROM gold.fact_event;

    /* DQ-07: gold events equal silver events (difference counted as failed) */
    INSERT INTO #raw
    SELECT 'DQ-07', (SELECT COUNT_BIG(*) FROM silver.rees46_event),
           ABS((SELECT COUNT_BIG(*) FROM silver.rees46_event) - (SELECT COUNT_BIG(*) FROM gold.fact_event));

    /* DQ-08: gold order lines equal silver purchase events */
    INSERT INTO #raw
    SELECT 'DQ-08', (SELECT COUNT_BIG(*) FROM silver.rees46_event WHERE event_type = 'purchase'),
           ABS((SELECT COUNT_BIG(*) FROM silver.rees46_event WHERE event_type = 'purchase')
             - (SELECT COUNT_BIG(*) FROM gold.fact_order_line));

    /* DQ-09: gold orders equal silver purchase sessions */
    INSERT INTO #raw
    SELECT 'DQ-09', (SELECT COUNT(DISTINCT user_session) FROM silver.rees46_event WHERE event_type = 'purchase'),
           ABS((SELECT COUNT(DISTINCT user_session) FROM silver.rees46_event WHERE event_type = 'purchase')
             - (SELECT COUNT(*) FROM gold.fact_order));

    /* DQ-10: product with a known brand */
    INSERT INTO #raw
    SELECT 'DQ-10', COUNT_BIG(*), SUM(CASE WHEN brand_id = -1 THEN 1 ELSE 0 END)
    FROM silver.rees46_product;

    /* DQ-11: product whose category has a code */
    INSERT INTO #raw
    SELECT 'DQ-11', COUNT_BIG(*), SUM(CASE WHEN c.category_code IS NULL THEN 1 ELSE 0 END)
    FROM silver.rees46_product AS p
    INNER JOIN silver.rees46_category AS c ON c.category_id = p.category_id;

    /* DQ-12: sessions linked to one user only */
    INSERT INTO #raw
    SELECT 'DQ-12', (SELECT COUNT_BIG(*) FROM (SELECT user_session FROM silver.rees46_event GROUP BY user_session) AS s),
           (SELECT COUNT_BIG(*) FROM (SELECT user_session FROM silver.rees46_event
                                      GROUP BY user_session HAVING COUNT(DISTINCT user_id) > 1) AS m);

    /* DQ-13: bronze = silver + rejected */
    INSERT INTO #raw
    SELECT 'DQ-13', (SELECT COUNT_BIG(*) FROM ecommerce_rfm_raw.bronze.rees46_events),
           ABS((SELECT COUNT_BIG(*) FROM ecommerce_rfm_raw.bronze.rees46_events)
             - (SELECT COUNT_BIG(*) FROM silver.rees46_event)
             - (SELECT COUNT_BIG(*) FROM audit.silver_rejects));

    INSERT INTO audit.dq_result (dq_run_id, rule_id, rows_checked, rows_failed, pass_rate)
    SELECT @run, rule_id, rows_checked, rows_failed,
           CASE WHEN rows_checked = 0 THEN 1.0
                ELSE CAST(1.0 - CAST(rows_failed AS float) / rows_checked AS decimal(7,4)) END
    FROM #raw;

    DROP TABLE #raw;

    SELECT rule_id, description, severity, rows_checked, rows_failed, pass_rate
    FROM audit.v_dq_history
    WHERE dq_run_id = @run
    ORDER BY rule_id;
END;
GO
