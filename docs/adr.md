# Architecture Decision Records

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E4-08

Each record has four parts: **Context** (the problem), **Decision**, **Consequences** (what it costs), and **Evidence** (where the fact comes from).

---

## ADR-001: Two databases, one for raw data and one for clean data

- **Context:** raw data is large and can be rebuilt from the files. Clean data is the asset.
- **Decision:** `ecommerce_rfm_raw` (bronze, SIMPLE recovery) and `ecommerce_rfm_dwh` (silver, gold, serving, FULL recovery).
- **Consequences:** cross-database names are needed in the bronze-to-silver load. No foreign keys across the two databases.
- **Evidence:** bronze load of 110 million rows, minimally logged in SIMPLE recovery.

## ADR-002: Layered design (bronze, silver, gold, serving)

- **Context:** raw text, clean typed data and analysis-ready data have different needs.
- **Decision:** bronze keeps text as received. Silver is normalized with keys. Gold is a star schema. Serving is the contract for Power BI.
- **Consequences:** more tables and loads, but each layer can be rebuilt from the one before it.
- **Evidence:** bronze reconciles exactly with the files (109,950,743 rows).

## ADR-003: Bronze stores all columns as text

- **Context:** a bad value must never stop a load of 110 million rows.
- **Decision:** `varchar` for every source column. Typing and checks happen in silver.
- **Consequences:** bronze is larger than typed storage (about 182 bytes per row). Bad values are found by checks, not by failed loads.
- **Evidence:** format checks on the full bronze table.

## ADR-004: An order is a session with at least one purchase

- **Context:** the file has no order id.
- **Decision:** `order_id` = `user_session` of a session with a purchase (D3). Each purchase event is one order line, one unit.
- **Consequences:** the order count is a lower bound. Sessions with several purchases may hide several orders.
- **Evidence:** 8,456 purchase sessions in the sample, 720 with several purchase events. Revenue is not affected.

## ADR-005: The funnel counts each stage on its own

- **Context:** 33% of purchase sessions have no cart event on the full data.
- **Decision:** each stage counts the sessions that reached it, without requiring earlier stages (D8). The share without a cart is reported next to the funnel.
- **Consequences:** a funnel can show more purchases than carts for some categories. The report must state this.
- **Evidence:** full profiling, query 8 (462,538 of 1,402,758 purchase sessions).

## ADR-006: SCD Type 2 on the customer segment only, weekly

- **Context:** customer segments change over time, and orders must show the segment at purchase.
- **Decision:** track `rfm_segment` in `dim_customer` with validity dates, changed weekly. Churn status stays in a report table.
- **Consequences:** facts must join on the version valid on the event date. Rows grow with segment changes.
- **Evidence:** the data has no other customer attributes that change.

## ADR-007: Load in batches of 1,000,000 rows

- **Context:** the batch size affects speed and the size of each transaction.
- **Decision:** `BATCHSIZE = 1,000,000`.
- **Consequences:** a failed load leaves the earlier batches in the table, so a reload needs `@truncate_first = 1`.
- **Evidence:** batch test on October: 1,000,000 rows gave 176,657 rows per second. 100,000 gave 125,624, and one batch gave 135,050.

## ADR-008: Foreign keys are declared now, and tested for their cost later

- **Context:** keys protect the data, but checking them slows loads.
- **Decision:** declare foreign keys in silver and gold. Measure their cost and the effect of trusted and untrusted keys in E8-10.
- **Consequences:** loads check every key. The cost is known only after the measurement.
- **Evidence:** to be measured in E8-10.

## ADR-009: Memory is capped for the container and for SQL Server

- **Context:** the PC has 16 GB of RAM, shared with Windows, Docker and later Power BI.
- **Decision:** WSL2 limited to 10 GB, SQL Server limited to 8 GB (`MSSQL_MEMORY_LIMIT_MB`).
- **Consequences:** queries on large tables spill to disk. Power BI runs with the server limit lowered during loads.
- **Evidence:** `free -m` and `sys.dm_os_sys_info` after the change (setup.md).
