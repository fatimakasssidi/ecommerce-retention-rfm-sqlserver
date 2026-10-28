# Business Requirements

Project: E-commerce Customer Retention & RFM (SQL Server)

> This document grows during epic E1. Sections 1 to 4 are written in task E1-01 and section 5 in task E1-02. Sections 6 to 9 are placeholders for the next tasks.

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

Each question has an owner, the source(s) that can answer it, and the planned output. They are grouped by the three project questions.

### Who are our best customers?

| ID | Question | Asked by | Source | Planned output |
|---|---|---|---|---|
| Q1 | Which customers generate the most revenue, and what share of total revenue do the top 20% represent? | Marketing, Finance | Both | Pareto analysis (E7) |
| Q2 | How many customers are in each RFM segment, and how much revenue does each segment contribute? | Marketing, Finance | Both | `gold.report_customer_rfm` and segment summary (E7) |
| Q3 | What is the historical customer lifetime value, by segment and by first-purchase cohort? | Finance | Both | CLV view (E7) |

### Who is at risk of leaving?

| ID | Question | Asked by | Source | Planned output |
|---|---|---|---|---|
| Q4 | Which customers have stopped buying (churned) under the agreed rule, and which of them used to be high value? | Marketing | Both | Churn flag and at-risk list (E7) |
| Q5 | What is the monthly churn rate, and how does it change over time? | CRM | Both | Churn trend (E7) |
| Q6 | Where do shoppers drop out of the funnel (view, cart, purchase), by category? | Marketing | REES46 | Funnel analysis (E7) |

### How well do we keep customers over time?

| ID | Question | Asked by | Source | Planned output |
|---|---|---|---|---|
| Q7 | What share of customers buy again, and how quickly after their first purchase? | CRM | Both | Repeat purchase rate (E7) |
| Q8 | How does retention evolve for each monthly cohort (month 1, 2, 3, and so on)? | CRM | Both | Cohort retention matrix (E7) |
| Q9 | How do revenue, orders and average order value trend over time, including seasonality? | Finance | Both | Time analysis (E7) |
| Q10 | How do customer behavior and value differ between the two platforms? | Leadership | Both | Source comparison (E7, E14) |

### Trust in the numbers

| ID | Question | Asked by | Source | Planned output |
|---|---|---|---|---|
| Q11 | How reliable is the data behind these answers (rows excluded, quality pass rate per source)? | Data platform owner | Both | DQ scorecard (E6) |

**Notes**
- **REES46 has no order table.** For this source, an order will be approximated from purchase events. The exact rule is decided in E1-03 and confirmed after profiling in E2.
- **Segments and cohorts are computed per source,** because customers cannot be linked across the two platforms.
- Every question must be answerable with a measurable number. If a question cannot be tested with a query, it is rewritten or dropped.

## 6. KPIs and metric definitions

*To be written in task E1-03. Full definitions go in `docs/metric_dictionary.md`.*

## 7. RFM scoring rules

*To be written in task E1-04. Full rules go in `docs/rfm_rules.md`.*

## 8. Churn definition

*To be written in task E1-05, after profiling (E2). Full definition goes in `docs/churn_definition.md`.*

## 9. Success criteria

*To be written in task E1-06.*
