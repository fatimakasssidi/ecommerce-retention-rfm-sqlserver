# Data Quality Rule Catalog (E6-01)

Project: E-commerce Customer Retention & RFM (SQL Server)
Stored in `audit.dq_rule`. Checked by `audit.run_dq_checks`. Latest status in `audit.v_dq_scorecard`.

**Severity**
- **error**: must be 0 for the data to be trusted. Any failure stops the release.
- **warning**: can be above 0 in known cases. Reported and explained, not blocking.

| Rule | Table | Check | Severity | Expected on the full data | Why |
|---|---|---|---|---|---|
| DQ-01 | silver.rees46_event | Product, user and session present | error | 0 | Silver NOT NULL keys |
| DQ-02 | silver.rees46_event | Purchase price above 0 | error | 0 | Revenue depends on it (purchases have no zero price in the data) |
| DQ-03 | silver.rees46_event | Event time in 2019-10-01 to 2019-11-30 | error | 0 | Data period (61 days) |
| DQ-04 | silver.rees46_event | Event type in the four allowed values | error | 0 | Source official types |
| DQ-05 | silver.rees46_event | Zero price on a view or cart kept as unknown | warning | 256,761 (the zero-price events of the source) | Source has zero prices on views and carts, not on purchases |
| DQ-06 | gold.fact_event | Event linked to a known customer version | warning | Small (users without a version) | All users have a version (unknown segment until E7) |
| DQ-07 | gold.fact_event | Gold events equal silver events | error | 0 | Completeness of the fact |
| DQ-08 | gold.fact_order_line | Gold order lines equal silver purchases | error | 0 | Completeness of revenue |
| DQ-09 | gold.fact_order | Gold orders equal silver purchase sessions | error | 0 | Completeness of orders |
| DQ-10 | silver.rees46_product | Product with a known brand | warning | About 15,000 products (22%) | Brand missing for those products in the source |
| DQ-11 | silver.rees46_product | Category with a code | warning | About 388 categories (60%) | Category path missing in the source (I-03) |
| DQ-12 | silver.rees46_event | Session linked to one user only | warning | 940 sessions | Source: a session can carry two user ids (I-06) |
| DQ-13 | audit.silver_rejects | Bronze = silver + rejected | error | 0 | Nothing lost in silver |

## Quarantine (E6-03)

Rejected rows are kept in `audit.silver_rejects` with their raw values and their reason
(`duplicate_row`, `bad_user_session`, ...). The summary is in `audit.v_quarantine_summary`.

## How to run

```sql
EXEC audit.run_dq_checks;       -- stores the run and shows the results
SELECT * FROM audit.v_dq_scorecard ORDER BY rule_id;
SELECT * FROM audit.v_quarantine_summary;
```
