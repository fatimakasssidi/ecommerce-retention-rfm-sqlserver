# Reconciliation Across Layers (E6-05)

Project: E-commerce Customer Retention & RFM (SQL Server)

The totals must agree between bronze, silver and gold. Differences are either zero, or explained.

## Row counts

| Measure | Bronze | Silver | Gold | Difference | Explained by |
|---|---|---|---|---|---|
| All events | 109,950,743 | 109,819,992 | 109,819,992 | 0 | 130,739 duplicate rows + 12 without session (silver_rejects) |
| Purchase events | see query | see query | 1,659,703 (order lines) | 0 | none |
| Purchase sessions (orders) | n/a | 1,402,758 | 1,402,758 | 0 | none |

## Revenue (sum of prices of purchase events)

Run this query in SSMS (it scans bronze, so it takes a few minutes):

```sql
USE ecommerce_rfm_dwh;

SELECT 'bronze' AS layer,
       CAST(SUM(TRY_CONVERT(decimal(18,2), b.price)) AS decimal(18,2)) AS purchase_revenue,
       COUNT_BIG(*) AS purchase_events
FROM ecommerce_rfm_raw.bronze.rees46_events AS b
WHERE b.event_type = 'purchase'
UNION ALL
SELECT 'silver', CAST(SUM(price) AS decimal(18,2)), COUNT_BIG(*)
FROM silver.rees46_event WHERE event_type = 'purchase'
UNION ALL
SELECT 'gold', CAST(SUM(price) AS decimal(18,2)), COUNT_BIG(*)
FROM gold.fact_order_line;
```

**Expected:** gold equals silver exactly. Bronze and silver are equal only if no purchase was
rejected. This is not yet verified on the full data, so check it with:

```sql
SELECT raw_event_type, reject_rule, COUNT_BIG(*) AS rows_rejected
FROM audit.silver_rejects
GROUP BY raw_event_type, reject_rule
ORDER BY rows_rejected DESC;
```
If a purchase appears in the result, its rows are the difference between bronze and silver,
and that difference must be written in the table below.

Result (to fill in after the query):

| Layer | Purchase revenue | Purchase events |
|---|---|---|
| bronze | | |
| silver | | |
| gold | | |

## Conclusion

Any difference above must be explained before the reconciliation is closed.
