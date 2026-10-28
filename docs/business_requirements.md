# Business Requirements

Project: E-commerce Customer Retention & RFM (SQL Server)

> This document grows during epic E1. Sections 1 to 4 are written in task E1-01. Sections 5 to 9 are placeholders for the next tasks.

---

## 1. Business context

**FatKasMarket** (fictional) is an e-commerce group that grew by merging two platforms:

| Platform | What it is | Data available |
|---|---|---|
| **Giftware retail shop** | A UK-based online retailer selling gifts and home goods, with many wholesale customers | Online Retail II transactions (invoices, products, customers) |
| **Multi-category online store** | A large consumer store (electronics, appliances and more) with heavy website traffic | REES46 clickstream events (views, carts, purchases) |

Each platform has its own system and its own data. Leadership has no single view of who the best customers are, who is about to stop buying, or how well the group keeps its customers over time.

**The problem:** the company spends on acquiring new customers, but nobody can say how many existing customers come back, which ones are the most valuable, or which ones are drifting away. Retention is often the cheapest growth lever, and today it is invisible.

**The goal of this project:** build one reliable data platform that answers three questions:

1. **Who are our best customers?** (value and loyalty segments)
2. **Who is at risk of leaving?** (churn risk and at-risk lists)
3. **How well do we keep customers over time?** (retention by cohort)

The platform feeds a Power BI report that marketing and management use to decide whom to target and what action to take.

---

## 2. Stakeholders

| Stakeholder | What they need | How they use the output |
|---|---|---|
| **Marketing manager** | Customer segments (RFM) and lists of at-risk and high-value customers | Plans campaigns per segment, for example win-back offers for at-risk customers |
| **CRM / retention team** | Retention by cohort, churn rate, repeat purchase rate | Measures whether retention actions work, month after month |
| **Head of e-commerce / finance** | Revenue, average order value, customer value, revenue share per segment | Decides budgets and reports to leadership |
| **Data platform owner (the author)** | A reliable, tested, documented platform and consistent metric definitions | Maintains the pipeline, answers "why is this number different?" |

**Refresh frequency (assumed):** daily load, reports reviewed weekly.

---

## 3. Scope

**In scope**
- Ingest and integrate the two data sources into one platform
- Data quality checks with documented cleaning decisions
- RFM segmentation, cohort retention, churn, simple customer lifetime value, funnel analysis
- Performance engineering, security, tests and CI on the SQL Server platform
- A Power BI semantic model and report

**Out of scope**
- Predictive models and machine learning (churn is defined by rules, not predicted)
- Real-time streaming
- Marketing automation or sending campaigns
- Linking customers across the two platforms (the datasets share no customer identifier)

---

## 4. Assumptions and limitations

- **The story is fictional.** The two datasets come from different companies, countries and years (Online Retail II covers 2009 to 2011, REES46 covers 2019). They are used as if they were two platforms of one group so the project can show multi-source integration. Results must not be read as real business findings about one company.
- **No shared customers.** A customer on one platform cannot be matched to the other, so each customer is identified by the pair (`source_system`, `customer_id`), and segments are computed per source.
- **Analysis date.** Reports use a fixed snapshot date per source, set in task E1-04, instead of today's date.
- **No personal data.** Both datasets use anonymous identifiers, and no personal information is added.
- **Missing customer IDs.** Some transactions have no customer ID. They count toward revenue but cannot be used for customer-level analysis such as RFM. The exact rule is documented in E6.

---

## 5. Key business questions

*To be written in task E1-02.*

## 6. KPIs and metric definitions

*To be written in task E1-03. Full definitions go in `docs/metric_dictionary.md`.*

## 7. RFM scoring rules

*To be written in task E1-04. Full rules go in `docs/rfm_rules.md`.*

## 8. Churn definition

*To be written in task E1-05, after profiling (E2). Full definition goes in `docs/churn_definition.md`.*

## 9. Success criteria

*To be written in task E1-06.*
