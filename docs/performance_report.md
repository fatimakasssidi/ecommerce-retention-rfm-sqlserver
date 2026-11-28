# Performance Report (E8)

Project: E-commerce Customer Retention & RFM (SQL Server)
Tasks: E8-06 (problems and fixes), E8-07 (compression), E8-09 (benchmark), E8-10 (joins and foreign keys)

Method: every result is a before and after measurement on the full data (110 million events).
Time = elapsed time from `SET STATISTICS TIME`. Reads = logical reads from `SET STATISTICS IO`.
Each change is applied alone, measured, then kept or undone. Numbers are filled in when each step runs.

---

## 1. Benchmark (E8-09)

| Query | Baseline (ms) | + Indexes (ms) | + Columnstore (ms) | + Partitioning (ms) | Reads before | Reads after |
|---|---|---|---|---|---|---|
| B1 revenue by category and month | 447 | | | | 10,099 | |
| B2 funnel view | 130,025 | | | | 884,792 | |
| B3 revenue per customer | 9,325 | | | | 9,917 | |
| B4 events by hour and type | 8,488 | | | | 878,099 | |
| B5 sessions per product | 56,732 | | | | 882,259 | |
| B6 purchases in November | 5,183 | | | | 881,484 | |

**Baseline conditions (run 1 of 3):** elapsed time = "SQL Server Execution Times" from the Messages tab, reads = sum of logical reads over all tables of the query. Parse and compile time excluded. Single run, not yet the median of three. Nothing else running (to confirm). Physical reads present on B2 (1,172) and B6 (23,864): the first run read some pages from disk.

Size of `gold.fact_event`: rowstore (before) ______ MB, columnstore (after) ______ MB.

Top results for the README: state the largest gain with its query and its before and after numbers.

---

## 2. Problems and fixes (E8-06)

### 2.1 Parameter sniffing

The first run of a stored procedure caches a plan for the parameter value it received. A value with few rows
then gets a plan built for many rows, and the reverse.

Demonstration (`gold.orders_for_customer` below): run it with a customer that has one order, then with a
customer that has hundreds. The second run reuses the first plan.

```sql
USE ecommerce_rfm_dwh;
GO
CREATE OR ALTER PROCEDURE gold.orders_for_customer @customer_key int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT order_key, order_date_key, line_count, order_value
    FROM gold.fact_order
    WHERE customer_key = @customer_key;
END;
GO

-- one rare and one frequent customer key
SELECT TOP (1) customer_key AS rare_key FROM gold.fact_order GROUP BY customer_key HAVING COUNT(*) = 1;
SELECT TOP (1) customer_key AS frequent_key FROM gold.fact_order GROUP BY customer_key ORDER BY COUNT(*) DESC;
```

Run the rare key first, then the frequent key, with the actual plan on. Problem: the frequent key uses the plan
built for the rare one.

Fix: add `OPTION (RECOMPILE)` to the statement, so each call builds its own plan.

```sql
CREATE OR ALTER PROCEDURE gold.orders_for_customer @customer_key int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT order_key, order_date_key, line_count, order_value
    FROM gold.fact_order
    WHERE customer_key = @customer_key
    OPTION (RECOMPILE);
END;
GO
```

Result (to fill): plan and time for the frequent key, before and after the fix: ______

### 2.2 Query rewrite: a function on the filter column

A filter that wraps the column in a function cannot use an index on it.

```sql
-- slow: the function hides date_key from the index
SELECT COUNT_BIG(*) FROM gold.fact_event WHERE LEFT(CAST(date_key AS char(8)), 6) = '201911';

-- fast: a range on the column itself
SELECT COUNT_BIG(*) FROM gold.fact_event WHERE date_key BETWEEN 20191101 AND 20191130;
```

Result (to fill): reads and time for each: ______

---

## 3. Compression (E8-07)

SQL Server estimates the saving of each compression level before it is applied:

```sql
EXEC sp_estimate_data_compression_savings N'gold', N'fact_event', NULL, NULL, N'PAGE';
EXEC sp_estimate_data_compression_savings N'gold', N'fact_event', NULL, NULL, N'ROW';
```

| Level | Size before (MB) | Size after (MB) | Saving | Speed effect (B1 to B6) |
|---|---|---|---|---|
| Row | | | | |
| Page | | | | |
| Columnstore (E8-04) | | | | |

Columnstore is the chosen level for the fact (see E8-04). Row and page are kept as a comparison only.

---

## 4. Join and foreign key experiments (E8-10)

### 4.1 Join strategies on the same data

Each join is forced with a hint, and the actual plan shows the operator used. Results are on the full data.

```sql
-- J1 hash join (the usual choice for large inputs)
SELECT p.category_key, COUNT_BIG(*) AS events
FROM gold.fact_event AS e
INNER JOIN gold.dim_product AS p ON p.product_key = e.product_key
GROUP BY p.category_key
OPTION (HASH JOIN);

-- J2 merge join (needs both inputs sorted on the key)
SELECT p.category_key, COUNT_BIG(*) AS events
FROM gold.fact_event AS e
INNER JOIN gold.dim_product AS p ON p.product_key = e.product_key
GROUP BY p.category_key
OPTION (MERGE JOIN);

-- J3 nested loops (fast only when the outer input is small)
SELECT p.category_key, COUNT_BIG(*) AS events
FROM gold.fact_event AS e
INNER JOIN gold.dim_product AS p ON p.product_key = e.product_key
WHERE e.date_key = 20191129
GROUP BY p.category_key
OPTION (LOOP JOIN);
```

| Join | Operator in plan | Time (ms) | Reads | Comment |
|---|---|---|---|---|
| J1 hash (full table) | Hash Match, columnstore scan of fact_event, scan of dim_product | 1,240 | 17,994 | Fastest full-table join. The default choice |
| J2 merge (full table) | Sort of the fact side, then Merge Join | 1,721 | 19,141 | Slower: sorts 110 million rows first |
| J3 nested loops (one day only) | Nested Loops, seek on pk_dim_product per row | 141 | 958 | Covers about 1.8 million rows, not comparable with J1 and J2. Shows the seek pattern |

Reading: a nested loop on the full fact would be very slow, so J3 is restricted to one day. The optimizer
chooses the operator itself without hints; the hint experiment shows why.

### 4.2 Trusted and untrusted foreign keys

A foreign key created with `WITH NOCHECK` is not trusted: the optimizer cannot rely on it, and it cannot
remove joins that the key makes redundant.

```sql
-- state of the foreign keys: is_not_trusted = 1 means not trusted
SELECT name, OBJECT_NAME(parent_object_id) AS child_table, is_not_trusted
FROM sys.foreign_keys
WHERE SCHEMA_NAME(schema_id) = N'gold';
```

Result: all 12 foreign keys in the gold schema are trusted (is_not_trusted = 0).

Test: a query that joins a fact to a dimension but uses only the fact's columns. A trusted key lets the
optimizer drop the join; an untrusted one cannot.

```sql
SELECT COUNT_BIG(*) AS lines
FROM gold.fact_order_line AS l
INNER JOIN gold.dim_product AS p ON p.product_key = l.product_key;
```

Procedure: (1) record the plan of the query above, (2) make the keys trusted:

```sql
ALTER TABLE gold.fact_order_line WITH CHECK CHECK CONSTRAINT fk_fact_order_line_product;
```

(3) record the plan again. Result:

| Key state | Join to dim_product in plan | Operators | Elapsed (ms) | CPU (ms) |
|---|---|---|---|---|
| Untrusted (NOCHECK) | Present: Hash Match, index scan of uq_dim_product_id, seek on pk_dim_product | 7 | 277 | 1,695 |
| Trusted (WITH CHECK) | Removed by the optimizer | 3 | 35 | 323 |

Reading: the trusted foreign key lets the optimizer remove the join, because every order line is known to
have a matching product. Single runs: the trusted plan is about 8 times faster in elapsed time (35 ms against 277 ms) and about 5 times
lighter in CPU (323 ms against 1,695 ms). Repeat both states three times to report medians.

Cost of trust: `WITH CHECK` re-checks every row, which takes time on 1.7 million lines. This cost is paid once,
at the moment the key is made trusted, not on each query.

---

## 5. Conclusion

To be completed when the benchmark table is filled. Each row of section 1 gets one sentence: what was changed,
what it gained, and whether it was kept.
