# Profiling of the REES46 Events (sample)

Project: E-commerce Customer Retention & RFM (SQL Server)
Task: E2-05

This file records what the sample showed. Every finding has a count, a suspected impact on the project, and what we do about it. The sample is a **first look**: the full-volume profiling in E3-07 confirms or corrects every number.

---

## 1. The sample

| Item | Value |
|---|---|
| How it was made | 20,000-line blocks taken every 4,000,000 lines from both files, plus the header. Created inside the container with `awk` |
| Why blocks | The files are sorted by time. The first lines alone cover only the first hours of 1 October. Blocks spread over the whole period keep the local structure (duplicates, sessions) |
| Rows in the sample | 560,000 (28 windows of 20,000 events) |
| Time covered | First event 2019-10-01 00:00:00, last event of the sample 2019-11-29 03:40:46, 27 distinct days. These numbers describe the **sample design** (28 windows), not the data: the files run to 30 November, and the 61 days are not all covered |
| Line ending of the files | LF (verified in E2-03) |

**Estimated size of the data (inference, exact count in E3-06):** 28 windows were found, and each window stands for up to 4 million lines, so the two files hold roughly 104 to 112 million events together.

**Limits of the sample:** the last window ends on 29 November at 03:40, so the sample contains **no Black Friday daytime**. Findings about prices and purchase share may differ on that day. sessions longer than a block are cut, so session-level numbers are approximate. Rare problems may not appear, and a clean sample does not prove the whole file is clean.

---

## 2. Findings

| # | Topic | Finding (count and share) | Suspected impact | Decision or next step |
|---|---|---|---|---|
| F1 | Timestamps | Evidence: 0 rows with a timestamp that cannot be parsed, 0 rows without the ` UTC` suffix | None found. The parsing rule is safe on the sample | Keep the rule (`TRY_CONVERT` on the first 19 characters) and keep a data quality check that counts failures, because the full files may contain rare bad values |
| F2 | Event types | Evidence: `view` 530,255 (94.69%), `cart` 20,333 (3.63%), `purchase` 9,412 (1.68%). `remove_from_cart` not present in the sample | Purchases are rare: revenue and orders come from under 2% of the rows, and the event table is mostly views. This favours columnstore and partitioning for the event fact | A small lookup table for event types, plus an "unknown" value. Check whether `remove_from_cart` exists in E3-07 |
| F3 | Missing `brand` | Evidence: 78,534 rows (14.02%) | Brand analysis would ignore or mislabel one event in seven | Keep the rows and group them as "unknown". Test in section 7 whether other events of the same product carry the brand, because then it can be filled |
| F4 | Missing `category_code` | Evidence: 182,034 rows (32.51%), while `category_id` is never missing (0 rows). The gap follows the category: of 648 categories, 388 (59.9%) never have a code and 260 (40.1%) always have one. No category has several different codes (0) | One third of the events belong to categories without a path, so a category hierarchy built from the code would miss them. Questions Q6 and Q11 (funnel and ranking by category) are affected. The path **cannot** be recovered through the `category_id`, because an uncoded category has no code on any event | Build the category table from `category_id`, with the code as an optional column. Events of uncoded categories are grouped as "unclassified" and their share is reported next to every category result |
| F5 | Missing `user_id` or `user_session` | Evidence: 0 rows missing either (also 0 missing `product_id`, `category_id` and `price`) | Customer KPIs and the session-based order rule have complete identifiers in the sample | Keep decision D4 as a safeguard, but expect it to apply rarely. Confirm on the full data in E3-07 |
| F6 | Empty values: NULL or empty text | Evidence: `brand` has 78,534 NULL and 0 empty-text values | `BULK INSERT` loads empty fields as NULL, so silver can test `IS NULL` | Keep a defensive `NULLIF(TRIM(column), '')` in silver, in case a column contains blanks that are not empty |
| F7 | Price: zero, negative, not numeric | Evidence: 0 not numeric, 0 negative, 1,252 zero prices (0.22%): 1,238 on `view`, 14 on `cart`, **0 on `purchase`**. 688 products have a zero price, and 287 of them also have a positive price elsewhere. The first rows seen are views with an empty brand and an empty category code | Revenue is not affected, because no purchase has a zero price. Inference: a zero price on a view means "price unknown", for items with little catalogue information, not a free item | The valid purchase rule keeps `price > 0`. In silver, a zero price on a view or cart is treated as unknown (NULL) and left out of price statistics. Counted in K22 |
| F8 | Price: median, 99th percentile, maximum | Evidence: median 162.17, 99th percentile 1,698.86, maximum 2,574.07, average 289.36 (over all events) | No extreme outlier in the sample: the maximum is about 1.5 times the 99th percentile. The average is above the median, so prices are skewed. An average over all events mostly describes views, so revenue must use purchase events only | `decimal(18,2)` is much larger than needed. A narrower decimal such as `decimal(9,2)` is a candidate, decided after the full data (E3-07) shows the real maximum |
| F9 | Identical duplicate rows | Evidence: 323 groups of identical rows, 520 surplus rows (0.09%). By type: `cart` 497, `view` 23, `purchase` 0. Inference: about 100,000 surplus rows over 110 million events | Cart events are strongly over-represented (2.4% of cart rows against 0.004% of view rows). Event counts of carts would be inflated. Revenue is not affected, because no purchase is duplicated. Session-based KPIs (K17 to K20) count distinct sessions, so they are not affected either | Remove identical duplicates in silver with a rule and a count (K22). Note the risk: two identical cart events in the same second could be real double clicks, so the rule is documented as a decision, not as a certainty |
| F10 | Sessions with several users | Evidence: 8 sessions out of 169,988 (0.005%) are linked to more than one `user_id`. In the 3 sessions seen so far, the gap between the two ids is 1, 1 and 5 (563492414 and 563492415, 565594878 and 565594879, 555463292 and 555463297), and the events are minutes apart. The other 5 sessions are not seen yet | Inference: the same visitor probably received a new `user_id` during the session (for example after a login or a cookie change), so one person can have several ids. The ids are close but not always consecutive. The effect is tiny here, and the limitation is already listed | The customer of an order is the `user_id` of its purchase event. The cases are listed as a data quality rule. The remaining 5 sessions are checked by running query 6b (id gap) alone |
| F11 | Purchases per session | Evidence: 8,456 sessions have a purchase: 7,736 with 1 purchase event (91.5%), 571 with 2 (6.8%), 149 with 3 or more (1.8%) | Most orders are single-item. Sessions with several purchase events exist, so one purchase event is probably one order line | Keep D3 (order = session with a purchase). Model `fact_order` (one row per such session) and `fact_order_item` (one row per purchase event) |
| F12 | Purchase sessions without a view | Evidence: 1,282 of 8,456 (15.16%) in the sample | Inference: partly caused by sessions cut by the sampling windows | Re-measured on the full data in E3-07, where sessions are complete |
| F13 | Products with several categories | Evidence: 3 products out of 65,649 (0.005%) | Negligible | Take the most frequent category for these products, and list them as a data quality rule |
| F14 | Products with several brands, or missing and present brand | Evidence: 17 products have several brands (0.03%). Brand status per product: 50,121 never missing (76.35%), 447 sometimes missing (0.68%), 15,081 always missing (22.97%) | Filling the brand from other events of the same product helps only 447 products. 15,081 products have no brand anywhere in the sample | Product brand = the single non-empty brand if there is one, the most frequent if several (17 cases listed), otherwise "unknown". Re-measure on the full data, where products appear more often |
| F15 | Products with several prices | Evidence: 14,471 products out of 65,649 (22.04%) have more than one price in the sample | Price is not a fixed attribute of a product. It changes over time (promotions, Black Friday), and the sample windows are days apart | Keep the price on the facts (event and purchase line). The price history of a product is a natural candidate for SCD Type 2, decided in E4-05 |
| F16 | Depth of `category_code` | | | |
| F17 | Daily rhythm (events per hour) | | | |
| F18 | Longest values (column sizes) | | | |
| F19 | Purchase sessions without a cart event | Evidence: 3,782 of 8,456 purchase sessions (44.73%) have no cart event in the sample | A funnel that requires a cart before a purchase would drop almost half of the purchase sessions. Part of this share comes from sessions cut by the windows (see F12), so the true share is lower but probably still large | Proposed decision D8: a funnel stage counts the sessions that reached it, without requiring the earlier stages, and the share of purchases without a cart is reported. To confirm on the full data (E3-07), then update K17 to K20 in E3-09 |
| F20 | Several purchase events in one session: same second or not | Evidence: 720 sessions have several purchase events. None has them all in the same second. Time between first and last purchase: up to 10 seconds 1 session, 11 to 60 seconds 70, 1 to 10 minutes **626 (86.9%)**, more than 10 minutes 23 | The purchases of a session are spread over minutes, so they look like separate purchases, not one basket checked out at once. My first hypothesis (items of one order share a timestamp) is rejected | The two real examples show the **same product** bought 2 or 3 times at the same price, about a minute apart. Query 6d measures how often that happens. D3 (order = session with a purchase, one unit per event) stays provisional until then |
| F21 | Products whose brand or category code is never, sometimes or always missing | Evidence: category code per product: 33,366 always missing (50.82%), 32,283 never missing (49.18%), 0 sometimes missing. Category id to code: 260 categories always coded, 388 never coded, 0 partly coded, 0 ids with several codes. Brand: see F14 | The missing path is a gap of the category (and so of its products), not of single events. It cannot be repaired from other events of the same product or the same category. The `category_id` to code mapping is clean wherever a code exists | Repair idea rejected. The category dimension keeps the code when it exists and labels the others "unclassified" |
| F22 | Same product repeated inside a multi-purchase session | Evidence: of 720 sessions with several purchase events, 288 contain the same product only (40.0%), 371 only different products (51.5%) and 61 a mix with some repeats (8.5%). The sample has 9,412 purchase events in 8,456 purchase sessions | Both patterns exist, so the data cannot tell a quantity above 1 from several separate orders. The impact is limited: multi-purchase sessions are 8.5% of purchase sessions. The order count (K02) lies **between 8,456** (one order per session, decision D3) **and 9,412** (every purchase event an order), an uncertainty of at most 11.3%. Revenue is not affected | Keep D3 as the working rule, which gives the lower bound of K02. State the bounds next to K02 and K03 in the metric dictionary (update in E3-09). Re-measure on the full data in E3-07 |

---

## 3. Effect on earlier documents

List here every assumption in the metric dictionary, the RFM rules or the churn definition that this profiling supports or challenges (for example D3, the order rule, or the price rules). Updates are made in E3-09, after the full profiling.

| Document | Assumption | Supported or challenged | Note |
|---|---|---|---|
| | | | |
