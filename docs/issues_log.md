# Data Issues Log (v1)

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E2-06

Every issue has an **impact** and a **decision**. The numbers come from the 560,000-row sample (`profiling_rees46.md`, finding in the second column) and are re-measured on the full data in E3-07.

**Decision vocabulary**

| Decision | Meaning |
|---|---|
| **Fix** | Correct the value or derive it, by a documented rule |
| **Exclude** | Leave the row out of the KPI calculations. It is counted in K22 and never silently dropped |
| **Keep** | Keep the data as it is, and document the limit |
| **Open** | Not enough information yet. The task that decides it is named |

---

## 1. Issues

| ID | Finding | Issue | Evidence | Impact | Decision | Rule and where | Status |
|---|---|---|---|---|---|---|---|
| I-01 | F1 | The timestamp ends with ` UTC`, so it is not a standard date | 0 unparseable rows, 0 rows without the suffix | None if parsed correctly | **Fix** | Parse the first 19 characters with `TRY_CONVERT`, count failures (E5-01, E6) | Decided |
| I-02 | F3, F14 | Missing `brand` | 78,534 events (14.02%). 447 products (0.68%) have it only on some events, 15,081 (22.97%) never | Brand analysis would miss one event in seven | **Fix** the 447 repairable products, **Keep** the rest as `unknown` | Brand of a product = its single non-empty brand (E5-02) | Decided |
| I-03 | F4, F21 | Missing `category_code` | 182,034 events (32.51%). 388 of 648 categories never have a code. No category is partly coded | Category questions (Q6, Q11) miss one third of the events. The path cannot be recovered | **Keep** | Build categories from `category_id`, label uncoded ones `unclassified`, report their share next to every category result (E4-04) | Decided |
| I-04 | F7 | Price of 0 | 1,252 rows (0.22%): 1,238 views, 14 carts, 0 purchases. Mostly rows with no brand and no category | None on revenue. Price statistics would be wrong | **Fix** | Treat a zero price on a view or cart as unknown (NULL). Purchases need `price > 0`. Count in K22 (E5-01, E6) | Decided |
| I-05 | F9 | Identical duplicate rows, and no event ID | 520 surplus rows (0.09%), 497 of them carts, none purchases | Cart event counts are inflated. Revenue and session-based KPIs are not | **Exclude** | Keep one row per identical group, count the removed rows. Risk: two identical cart events in one second may be real clicks (E5-01, E6) | Decided, to re-measure |
| I-06 | F10 | A session linked to two users | 8 sessions out of 169,988 (0.005%). The two ids are close, 6 of 8 consecutive | Negligible | **Keep** | The customer of an order is the `user_id` of its purchase event. Data quality rule lists the cases (E6) | Decided |
| I-07 | F11, F22 | No order ID | 8,456 purchase sessions and 9,412 purchase events in the sample | The order count lies between 8,456 and 9,412 (up to 11.3% apart). AOV carries the same uncertainty. Revenue does not | **Fix** (derive) | Order = session with a purchase (D3), the lower bound. State the bounds next to K02 and K03 (E3-09) | Decided, to re-measure |
| I-08 | F20, F22 | No quantity | The same product is repeated in 48.5% of multi-purchase sessions, minutes apart | A quantity above 1 may be logged as repeated events, or as several orders. It cannot be told | **Keep** | One unit per purchase event (D3). Documented as an assumption | Decided, to re-measure |
| I-09 | F12, F19 | Purchases with no cart event or no view in the session | 44.73% without a cart, 15.16% without a view. Part comes from sessions cut by the sampling windows | The strict funnel rule would drop up to almost half of the purchase sessions | **Open** | Proposed D8: each funnel stage counts its own sessions, and the share of purchases without a cart is reported. Decided in E3-09 | Open |
| I-10 | F13, F14 | A product with several categories or brands | 3 products with several categories, 17 with several brands | Negligible | **Fix** | Use the most frequent value, and list the products in a data quality rule (E5-02, E6) | Decided |
| I-11 | F15 | The price of a product changes | 14,471 products (22.04%) have more than one price | Price cannot be a fixed product attribute | **Keep** | The price stays on the facts. A price history of products is a candidate for SCD Type 2 (E4-05) | Decided |
| I-12 | F8 | The currency is not stated | Not given by the source | Amounts are not money in a known currency | **Keep** | Report "currency units" (decision D7) | Decided |
| I-13 | F10 | One person may have several ids | Seen in I-06, and not detectable in general | Customer counts are slightly overestimated | **Keep** | Listed as a limitation of all customer KPIs | Decided |
| I-14 | F17 | Partial first and last weeks, and Black Friday in the last week | The data runs from Tuesday 1 October to Saturday 30 November | Weekly retention and churn would look wrong in partial weeks | **Keep** | Partial weeks are flagged in the date dimension and excluded from retention and churn (D5) | Decided |
| I-15 | F18 | Encoding not verified. `BULK INSERT` on Linux cannot be told the file is UTF-8 | No non-ASCII check done yet | A special character could be stored wrongly | **Open** | Run the two `grep` checks for non-ASCII characters. If none, no impact. Decided in E3-02 | Open |
| I-16 | F2 | `remove_from_cart` not seen in the sample | The sample has only `view`, `cart`, `purchase` | If it exists, cart counts and the abandonment rule change | **Open** | Check on the full data (E3-07) | Open |
| I-17 | F1, F2, F5 | Problems that did not appear in the sample but may exist in the full data | 0 bad timestamps, 0 unknown event types, 0 missing ids in the sample | A clean sample does not prove clean files | **Keep** | Keep the rules and data quality checks for them anyway (E6) | Decided |

---

## 2. Summary

| Decision | Issues |
|---|---|
| Fix | I-01, I-02 (partly), I-04, I-07, I-10 |
| Exclude | I-05 |
| Keep | I-02 (partly), I-03, I-06, I-08, I-11, I-12, I-13, I-14, I-17 |
| Open | I-09, I-15, I-16 |

The three open issues are closed in E3-02 (I-15) and E3-07 and E3-09 (I-09, I-16).
