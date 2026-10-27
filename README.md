# E-commerce Customer Retention & RFM: SQL Server Data Platform

A production-style data platform in SQL Server that answers one business question: **who are our best customers, who is at risk of leaving, and how well do we retain customers over time?**

> **Status:** work in progress. Results, benchmarks and the Power BI report will be added as each phase is completed.

## Architecture

Two databases separate the raw data from the clean data. A database is the unit of backup and recovery, and only the clean data needs protection.

![Database and schema architecture](docs/database_architecture.svg)

| Database | Schemas | Purpose |
|---|---|---|
| `ecommerce_rfm_raw` | `bronze`, `audit` | Raw copy of the source files. `SIMPLE` recovery, disposable, rebuilt from the files |
| `ecommerce_rfm_dwh` | `silver`, `gold`, `audit`, `serving` | Cleaned and modeled data, protected and backed up. `serving` holds the views used by Power BI |

Data flows one way: **bronze, silver, gold, serving**. Naming rules are in [`docs/conventions.md`](docs/conventions.md).

## Data sources

| Source | Role |
|---|---|
| Online Retail II (UCI) | Real UK store transactions: RFM, cohorts, churn and data quality work |
| REES46 eCommerce behavior (Kaggle) | Large clickstream: performance engineering, bulk loading and funnel analysis |

Raw data is **not** included in this repository. Links, licenses and the data policy are in [`docs/data_sources.md`](docs/data_sources.md).

## Scope

**Part 1: SQL Server**
- Multi-source ingestion, layered architecture, star schema with SCD Type 2
- Incremental ETL with audit and error logging
- Automated data quality checks with quarantine
- RFM, cohort retention, churn, CLV and funnel analysis
- Performance tuning with measured before/after results (indexes, columnstore, partitioning, Query Store)
- Security (roles, row-level security, masking), backup and a tested restore
- tSQLt tests and a GitHub Actions pipeline

**Part 2: Power BI**
- Semantic model and a documented DAX measure library
- Model performance and row-level security
- A report with insights and recommendations

## Repository structure

```
sql/            database scripts, one folder per layer
tests/          tSQLt tests
scripts/        PowerShell scripts (data download, deployment)
docs/           documentation, diagrams, design decisions
powerbi/        Power BI project (PBIP)
data/sample/    small sample data for tests
```

## Run it locally

SQL Server runs in Docker. You need Docker Desktop and a `.env` file with your own password.

```powershell
copy .env.example .env      # then edit the password in .env
docker compose up -d
```

Connect with SSMS to `localhost,1434` (login `sa`). More setup steps will be added as the project grows.

## License

The code is released under the MIT license (see `LICENSE`). The datasets keep their own licenses, listed in `docs/data_sources.md`.
