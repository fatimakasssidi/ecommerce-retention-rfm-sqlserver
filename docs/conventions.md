# Naming Conventions and T-SQL Style Guide

Project: E-commerce Customer Retention & RFM (SQL Server)
Scope: every database object, script and commit in this repository.

**Rule zero: consistency beats preference.** If a rule here and your habit disagree, follow the rule. If a rule is wrong, change this file first, then the code.

## Table of contents

1. [General principles](#1-general-principles)
2. [Databases, layers and schemas](#2-databases-layers-and-schemas)
3. [Table naming](#3-table-naming)
4. [Column naming](#4-column-naming)
5. [Views, stored procedures and functions](#5-views-stored-procedures-and-functions)
6. [Constraints and indexes](#6-constraints-and-indexes)
7. [Data types](#7-data-types)
8. [T-SQL code style](#8-t-sql-code-style)
9. [Repository and Git conventions](#9-repository-and-git-conventions)
10. [Review checklist](#10-review-checklist)

---

## 1. General principles

- **Case style:** `snake_case`, lowercase letters, words separated by underscores (`_`). This applies to databases, schemas, tables, columns, views, procedures, constraints, indexes, parameters and variables.
- **Language:** English only, ASCII characters only, no spaces.
- **Reserved words:** never use SQL reserved words as object names.
- **Abbreviations:** avoid them. Approved exceptions: `id`, `rfm`, `etl`, `dq`, `clv`, `dwh`.
- **Always name things explicitly.** No auto-generated constraint or index names.

---

## 2. Databases, layers and schemas

The project follows the **Bronze / Silver / Gold** layering, split over two databases so raw data and clean data are separated.

| Database | Layers (schemas) | Recovery model | Notes |
|---|---|---|---|
| `ecommerce_rfm_raw` | `bronze`, `audit` | `SIMPLE` | Raw landing tables loaded as-is from the source files. Can be dropped and reloaded at any time. Small log during huge bulk loads. Not part of the backup strategy |
| `ecommerce_rfm_dwh` | `silver`, `gold`, `audit`, `serving` | `FULL` | The real asset: backed up and restore-tested (E9) |

| Schema | Meaning | Contents |
|---|---|---|
| `bronze` | Raw data | One table per source entity, loaded as-is. No cleaning, no typing |
| `silver` | Cleaned data | Cleaned, typed, deduplicated and standardized data, still aligned with the source systems |
| `gold` | Business data | Star schema (dimensions, facts), plus report tables (RFM, cohorts, aggregates) |
| `serving` | Consumption layer | Views over gold, consumed by Power BI. This is the contract (E11) |
| `audit` | Operations | Load logs, ETL runs and errors, data quality rules, results and quarantine |

Rules:
- Every object lives in a named schema. Never create objects in `dbo`.
- Always schema-qualify object names in code (`silver.rees46_event`, never just `rees46_event`).
- Data flows one way: `bronze` -> `silver` -> `gold` -> `serving`. A layer never reads from a layer after it.
- Trade-offs of two databases: no foreign keys across databases, and the bronze-to-silver load uses three-part names (`ecommerce_rfm_raw.bronze.rees46_events`). Three-part names are allowed **only** in the load procedure that reads from bronze.

### Source systems

The project has one source system. Use its name as the prefix of bronze and silver tables:

| Source system | Name |
|---|---|
| REES46 eCommerce behavior (Kaggle) | `rees46` |

---

## 3. Table naming

### Bronze rules
- Every name starts with the **source system name**, followed by the entity name as it appears in the source. No renaming to business terms.
- Pattern: **`<source_system>_<entity>`**
  - `<source_system>`: `rees46`.
  - `<entity>`: the source file or entity name, converted to snake_case.
  - Example: `bronze.rees46_events`.
- The monthly files (`2019-Oct.csv`, `2019-Nov.csv`) go into **one table**, and the file name is stored in `dwh_source_file`.

### Silver rules
- Same pattern as bronze: **`<source_system>_<entity>`**. Tables stay aligned with the source.
- Silver is where the flat event file is typed, deduplicated and split into real entities when it makes sense, for example `silver.rees46_event` and `silver.rees46_product`.
- Names are singular for entities, except when the source uses a plural for an event log.

### Gold rules
- Business-aligned names, starting with the **category prefix**.
- Pattern: **`<category>_<entity>`**
  - `<category>`: the role of the table (see the glossary).
  - `<entity>`: a descriptive business name (`customer`, `product`, `sales`).
  - Examples: `gold.dim_customer`, `gold.dim_product`, `gold.dim_date`, `gold.fact_event`, `gold.fact_order`, `gold.report_customer_rfm`.

### Glossary of category patterns

| Pattern | Meaning | Examples |
|---|---|---|
| `dim_` | Dimension table | `dim_customer`, `dim_product`, `dim_date`, `dim_source` |
| `fact_` | Fact table | `fact_event`, `fact_order` |
| `report_` | Report, aggregate or analytics output table | `report_customer_rfm`, `report_cohort_retention`, `report_daily_events`, `report_funnel` |

### Audit tables
`audit.load_log`, `audit.etl_run`, `audit.etl_error`, `audit.dq_rule`, `audit.dq_result`, `audit.quarantine_<entity>`.

---

## 4. Column naming

### General
- `snake_case`, lowercase.
- Do not repeat the table name in a column unless it is a key: `customer.country`, not `customer.customer_country`.
- **Bronze columns** keep the source column names, only converted to snake_case (`event_time`, `event_type`, `user_id` stay as they are). No business renaming in bronze.
- **Silver and gold columns** follow the rules below.

### Surrogate keys
- Every primary key of a dimension uses the suffix `_key`.
- Pattern: **`<table_name>_key`**, integer identity.
  - `<table_name>`: the entity the key belongs to, without the category prefix.
  - Example: `customer_key` is the surrogate key of `gold.dim_customer`.
- A foreign key in a fact has the same name as the key it points to: `gold.fact_order.customer_key`.
- The **unknown member** of every dimension has the key `-1`.

### Business keys
- Pattern: **`<entity>_id`** (`customer_id`, `order_id`, `product_id`).
- In gold, `customer_id` is the source `user_id`, and `order_id` is derived from the session of a purchase (the source has no order ID).

### Technical columns
- Every technical (system-generated) column starts with **`dwh_`**, followed by a descriptive name.
- Pattern: **`dwh_<column_name>`**

| Column | Type | Meaning |
|---|---|---|
| `dwh_load_id` | int | Identifier of the load run that wrote the row |
| `dwh_source_file` | varchar | Source file the row came from (bronze) |
| `dwh_create_date` | datetime2 | When the row was inserted into the warehouse (UTC) |
| `dwh_update_date` | datetime2 | When the row was last updated (UTC) |
| `dwh_valid_from` | datetime2 | SCD Type 2: start of validity |
| `dwh_valid_to` | datetime2 | SCD Type 2: end of validity (`9999-12-31` for the current row) |
| `dwh_is_current` | bit | SCD Type 2: `1` for the current version |

### Typed suffixes and prefixes

| Meaning | Rule | Example |
|---|---|---|
| Date (no time) | `<thing>_date`, type `date` | `order_date` |
| Date and time | `<thing>_at`, type `datetime2`, UTC | `event_at` |
| Boolean flag | `is_<something>`, type `bit` | `is_cancelled` |
| Money | `<thing>_amount`, type `decimal(18,2)` | `line_amount` |
| Count | `<thing>_count`, type `int` or `bigint` | `order_count` |
| Quantity | `quantity` | `quantity` |
| Ratio or percentage | `<thing>_rate` or `<thing>_pct` | `retention_rate` |

### RFM columns
`recency_days`, `frequency_count`, `monetary_amount`, `recency_score`, `frequency_score`, `monetary_score`, `rfm_segment`, `snapshot_date`.

---

## 5. Views, stored procedures and functions

### Views
- Views in `serving` mirror the gold table they expose and use the **same names** (`serving.dim_customer`, `serving.fact_order`, `serving.report_customer_rfm`). The schema already tells you it is a view.
- Views elsewhere (helper views) use the pattern `<layer>.v_<name>`.
- Renaming or removing a column in `serving` is a breaking change and must be documented in `docs/serving_contract.md`.

### Stored procedures
- **Loading procedures** follow **`load_<layer>`**, stored in the schema of the layer they load:

| Procedure | Meaning |
|---|---|
| `bronze.load_bronze` | Loads the source files into bronze |
| `silver.load_silver` | Cleans and loads bronze into silver |
| `gold.load_gold` | Builds dimensions and facts from silver |

- When a layer needs one procedure per entity, use **`load_<layer>_<entity>`**, and keep `load_<layer>` as the master procedure that calls them (for example `gold.load_gold_dim_customer`, `gold.load_gold_fact_order`).
- **Other procedures** use **`<verb>_<object>`** with these verbs: `calc`, `run`, `check`, `rebuild`, `purge`.
  - Examples: `gold.calc_rfm`, `audit.run_dq_checks`, `audit.run_full_etl`.
- **Functions:** `fn_<name>`. Prefer inline table-valued functions over scalar functions.
- **Triggers:** avoid them. If one is needed, document why in the script header.
- **Script file name = object name:** `load_silver.sql` contains `silver.load_silver`.

### Parameters, variables and temp tables
| Item | Rule | Example |
|---|---|---|
| Parameter | `@snake_case` | `@snapshot_date` |
| Local variable | `@snake_case` | `@row_count` |
| Temp table | `#snake_case` | `#customer_orders` |

---

## 6. Constraints and indexes

All names use snake_case with a prefix.

| Object | Rule | Example |
|---|---|---|
| Primary key | `pk_<table>` | `pk_dim_customer` |
| Foreign key | `fk_<child>_<parent>` | `fk_fact_order_dim_customer` |
| Unique constraint | `uq_<table>_<columns>` | `uq_dim_customer_customer_id` |
| Check constraint | `ck_<table>_<rule>` | `ck_fact_order_amount_positive` |
| Default constraint | `df_<table>_<column>` | `df_load_log_started_at` |
| Nonclustered index | `ix_<table>_<columns>` | `ix_fact_order_customer_key_date_key` |
| Clustered columnstore | `cci_<table>` | `cci_fact_event` |
| Nonclustered columnstore | `ncci_<table>` | `ncci_fact_order` |

- `INCLUDE` columns are not part of an index name.
- Every index must be justified by a measured gain (E8). Record the reason in a comment above the `CREATE INDEX`.

---

## 7. Data types

- Dates: `date` or `datetime2`. Never `datetime` or `smalldatetime`.
- Money: `decimal(18,2)`. Never `float` or `money` for financial values.
- Text: `varchar` for codes and ASCII identifiers, `nvarchar` for free text that may contain non-ASCII characters.
- Flags: `bit`. Counters and keys: `int`, or `bigint` for the large event table.
- **Bronze:** columns hold raw text so a bad value never blocks a load. Typing and validation happen when moving to silver.
- Never store dates or numbers as text in silver or gold.

---

## 8. T-SQL code style

### Formatting
- **Keywords in UPPERCASE:** `SELECT`, `FROM`, `WHERE`, `JOIN`, `GROUP BY`.
- **Object names in lowercase snake_case**, exactly as defined.
- **Indent with 4 spaces**, never tabs.
- **One clause per line**, one column per line in `SELECT` lists, commas at the end of the line.
- **Always end statements with `;`.**
- Maximum line length: about 120 characters.

```sql
SELECT
    c.customer_key,
    c.customer_id,
    SUM(f.line_amount) AS monetary_amount
FROM gold.fact_order AS f
INNER JOIN gold.dim_customer AS c
    ON c.customer_key = f.customer_key
WHERE c.dwh_is_current = 1
GROUP BY
    c.customer_key,
    c.customer_id;
```

### Query rules
- Always use `AS` for aliases, with meaningful aliases (`f` for fact, `c` for customer). No `a`, `b`, `t1`.
- Use explicit `INNER JOIN` and `LEFT JOIN`. Never comma joins.
- **No `SELECT *`** in views, procedures or ETL. List the columns.
- **Explicit column lists** on every `INSERT`.
- **Never use `NOLOCK`** to fix a performance problem. Fix the cause.
- Prefer CTEs for readability, but check the execution plan on large data.
- Avoid functions on filtered columns in `WHERE` (for example `YEAR(order_date) = 2019`), because they prevent index use. Use a date range instead.

### Procedure template

```sql
CREATE OR ALTER PROCEDURE gold.calc_rfm
    @snapshot_date date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- work here

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        -- log to audit.etl_error here
        THROW;
    END CATCH;
END;
```

### Script rules
- **Re-runnable:** every script can run twice without error. Use `CREATE OR ALTER` for views, procedures and functions, and `IF NOT EXISTS` / `IF OBJECT_ID(...) IS NULL` checks for tables and indexes.
- Every script starts with `USE <database>;` followed by `GO` (`ecommerce_rfm_raw` for bronze scripts, `ecommerce_rfm_dwh` for everything else).
- Every script starts with a header comment:

```sql
/*
Purpose : what this script does
Task    : E4-05
Layer   : gold
*/
```
- Comments explain **why**, not what. No change logs inside files, since Git keeps the history.

---

## 9. Repository and Git conventions

- Folder numbers define the order of the layers.

| Old folder | New folder |
|---|---|
| `sql/01_staging` | `sql/01_bronze` |
| `sql/04_core` | `sql/04_silver` |
| `sql/05_mart` | `sql/05_gold` |

- **Commit message format:** `<TaskId>: <short description in the imperative>`
  - Examples: `E0-04: add naming conventions`, `E3-03: load the October file into bronze`.
- One task = one or more commits that start with the same task ID.
- Never commit `.env`, raw data files, backups (`.bak`) or credentials.
- Mark a task as done in Notion only when its Definition of Done is met and the work is pushed.

---

## 10. Review checklist

- [ ] Names are lowercase snake_case
- [ ] Table and column names follow sections 3 and 4
- [ ] Objects are schema-qualified
- [ ] No `SELECT *`, no `NOLOCK`
- [ ] Constraints and indexes are named
- [ ] Script runs twice without error
- [ ] Header comment present
- [ ] Commit message starts with the task ID
