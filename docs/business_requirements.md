# Business Requirements

Project: E-commerce Customer Retention & RFM (SQL Server)

> This document grows during epic E1. Sections 1 to 5 are written in tasks E1-01 and E1-02. Sections 6 to 9 point to the documents of the next tasks.

---

## 1. Business context

**FatKasMarket** (fictional) is a large multi-category online store selling electronics, appliances and other products, with heavy website traffic. Every visit leaves a trail of events: products viewed, products added to the cart, and purchases.

The company can see its **traffic**, but not its **customers**. Leadership cannot say which buyers are the most valuable, which ones have stopped coming back, how well the store keeps the customers it wins, or where shoppers give up on the way to a purchase.

**The problem:** the store pays to attract visitors, but most of them never buy, and many buyers never return. Retention is often the cheapest growth lever, and today it is invisible.

**The goal of this project:** build one reliable data platform that answers four questions:

1. **Who are our best customers?** (value and loyalty segments, RFM)
2. **Who is at risk of leaving?** (slipping and churned buyers)
3. **How well do we keep customers over time?** (retention by weekly cohort)
4. **Where do shoppers drop out?** (funnel from view to cart to purchase, and abandoned carts)

The platform feeds a Power BI report that marketing and management use to decide whom to target and what action to take.

---

## 2. Stakeholders

| Stakeholder | What they need | How they use the output |
|---|---|---|
| **Marketing manager** | RFM segments, at-risk lists, abandoned-cart lists | Plans campaigns per segment, for example win-back offers and cart reminders |
| **CRM / retention team** | Retention by weekly cohort, repeat purchase rate, churn | Measures whether retention actions work, week after week |
| **Head of e-commerce / finance** | Revenue, average order value, value per segment, category performance | Decides budgets and reports to leadership |
| **Data platform owner (the author)** | A reliable, tested, documented platform and consistent metric definitions | Maintains the pipeline, answers "why is this number different?" |

**Refresh frequency (assumed):** daily load, reports reviewed weekly.

---

## 3. Scope

**In scope**
- Load and clean the event data in a layered SQL Server platform
- Data quality checks with documented cleaning decisions
- RFM segmentation, weekly cohort retention, churn, customer value, funnel and cart abandonment
- Performance engineering, security, tests and CI on the SQL Server platform
- A Power BI semantic model and report

**Out of scope**
- Predictive models and machine learning (churn is defined by rules, not predicted)
- Real-time streaming
- Marketing automation or sending campaigns
- Retention over months or years (the data covers about two months)

---

## 4. Assumptions and limitations

- **The company is fictional.** The data comes from a real online store (REES46 eCommerce behavior data, Kaggle), anonymized. The story gives the data a business purpose, and the results must not be read as findings about a specific real company.
- **Short period.** The data covers about two months (October and November 2019, to confirm in E3-07). Retention and churn are therefore measured in **weeks**, with windows of days, not months.
- **Black Friday.** The end of November includes the Black Friday period, which can inflate sales and reactivate users. It is flagged and analyzed separately.
- **No order ID.** An order is approximated as a session that contains at least one purchase (decision D3).
- **No quantity.** Each purchase event counts as one unit.
- **No cancellations or returns** are recorded, so revenue is gross.
- **Currency is not stated,** so amounts are in "currency units".
- **Customers are `user_id` values.** One person may have several IDs (several devices or accounts), which cannot be detected.
- **No personal data.** Identifiers are anonymous, and no personal information is added.

---

## 5. Key business questions

Each question has an owner and a planned output.

### Who are our best customers?

| ID | Question | Asked by | Planned output |
|---|---|---|---|
| Q1 | Which buyers generate the most revenue, and what share of revenue do the top 20% represent? | Marketing, Finance | Pareto analysis (E7) |
| Q2 | How many buyers are in each RFM segment, and how much revenue does each segment contribute? | Marketing, Finance | `gold.report_customer_rfm` and segment summary (E7) |
| Q3 | How much value has a buyer generated so far, by segment and by first-purchase week? | Finance | Customer value view (E7) |

### Who is at risk of leaving?

| ID | Question | Asked by | Planned output |
|---|---|---|---|
| Q4 | Which buyers are Slipping or Churned under the agreed rule, and which of them used to be high value? | Marketing | Churn status and at-risk list (E7) |
| Q5 | What is the weekly churn rate, and how many churned buyers come back? | CRM | Churn and reactivation trend (E7) |
| Q6 | Where do shoppers drop out of the funnel (view, cart, purchase) by category, and which carts were abandoned, how many and worth how much? | Marketing | Funnel and cart abandonment analysis (E7) |

### How well do we keep customers over time?

| ID | Question | Asked by | Planned output |
|---|---|---|---|
| Q7 | What share of buyers buy again, and how quickly after their first purchase? | CRM | Repeat purchase rate and days to second order (E7) |
| Q8 | How does purchase retention evolve for each weekly cohort of first-time buyers? | CRM | Cohort retention matrix (E7) |
| Q9 | Do new visitors come back in the following weeks? | CRM, Marketing | Engagement retention (E7) |
| Q10 | How do revenue, orders and average order value evolve by day and week, including the Black Friday effect? | Finance | Time analysis (E7) |
| Q11 | Which categories and brands drive the most revenue and the best conversion? | Finance, Marketing | Category and brand ranking (E7) |

### Trust in the numbers

| ID | Question | Asked by | Planned output |
|---|---|---|---|
| Q12 | How reliable is the data behind these answers (rows excluded, quality pass rate)? | Data platform owner | DQ scorecard (E6) |

Every question must be answerable with a measurable number. If a question cannot be tested with a query, it is rewritten or dropped.

---

## 6. KPIs and metric definitions

Defined in [`metric_dictionary.md`](metric_dictionary.md) (task E1-03).

## 7. RFM scoring rules

Defined in [`rfm_rules.md`](rfm_rules.md) (task E1-04).

## 8. Churn definition

Defined in [`churn_definition.md`](churn_definition.md) (task E1-05). The value of the churn window is confirmed after profiling.

## 9. Success criteria

The project is successful when **every High criterion** below is met and documented with a measured result. Numeric targets are **initial**: they are reviewed once after profiling (E3-07) and once after the performance baseline (E8-01), and any change is written down with its reason.

| Priority | Area | Criterion | Target | Measured in |
|---|---|---|---|---|
| High | Business | Every key question (Q1 to Q12) has an answer from a view or query, with a result | 12 of 12 | E7, E14 |
| High | Business | Every valid buyer receives an RFM segment | 100% of buyers with a `user_id` | E7-02 |
| High | Business | The churn window is justified by the reactivation test | Test documented | E7-13 |
| High | Data quality | No row is lost without an explanation | Bronze rows = silver rows + removed duplicates + quarantined rows | E6-05 |
| High | Data quality | Every exclusion has a rule, a count and a reason | 100% of exclusions | E6-06 |
| Medium | Data quality | Pass rate of critical rules (valid event type, valid timestamp, valid price) | 99% or more, adjusted after profiling | E6-04 |
| High | ETL | The full pipeline can run twice with the same result | Identical row counts both times | E5-06 |
| High | ETL | Loading the second month adds only the new rows | 0 duplicates after loading November | E5-04 |
| Medium | ETL | A forced failure is logged and a re-run recovers | Test passes | E5-09 |
| High | Performance | Heavy analytical queries are measured before and after tuning | 5 or more queries documented | E8-01, E8-09 |
| High | Performance | Improvement on the tuned queries | At least 3 times faster each, and at least 2 of them 10 times faster | E8-09 |
| Medium | Performance | Queries on the serving views | Under 5 seconds on the author's machine | E11-06 |
| High | Testing | Every load and calculation procedure has at least one tSQLt test | 100% of procedures | E10-02 |
| High | Testing | RFM and churn logic are tested on small known data | Tests pass | E10-02 |
| High | Testing | The CI pipeline builds both databases and runs the tests | Green on `main` | E10-06 |
| High | Reliability | A backup is restored under a new name and checked | Row counts match | E9-05 |
| Medium | Security | A restricted role sees only what it is allowed to see | Role test passes | E9-01, E9-02 |
| High | Security | No secret and no raw data in the repository | 0 findings in the final review | E15-07 |
| High | Power BI | Key measures match the SQL results | Revenue, orders and buyers match exactly. Ratios match within rounding | E12-04 |
| Medium | Power BI | Each report page opens quickly | Under 5 seconds | E13-02 |
| High | Documentation | Someone can run the project from the README | Working database in about 15 minutes on a clean machine, after the downloads | E15-06 |
| High | Documentation | The README shows measured results first | Real numbers, no placeholders | E15-01 |

**How the targets were chosen**
- Performance targets are relative (3 times, 10 times) because absolute times depend on the hardware. They are written as goals and checked against the real baseline.
- Data quality thresholds depend on how clean the data really is, so they are revisited after profiling.
- "Test coverage" for SQL means the share of procedures that have at least one test, which is measurable and honest, unlike a line-coverage percentage.
