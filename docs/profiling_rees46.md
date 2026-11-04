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
| F4 | Missing `category_code` | Evidence: 182,034 rows (32.51%), while `category_id` is never missing (0 rows) | One third of the events have no category path, so a category hierarchy built from the code would miss them. Questions Q6 and Q11 (funnel and ranking by category) are affected | Build the category table from `category_id`, and keep the path when it exists. Test in section 7 whether the same products always lack the path |
| F5 | Missing `user_id` or `user_session` | Evidence: 0 rows missing either (also 0 missing `product_id`, `category_id` and `price`) | Customer KPIs and the session-based order rule have complete identifiers in the sample | Keep decision D4 as a safeguard, but expect it to apply rarely. Confirm on the full data in E3-07 |
| F6 | Empty values: NULL or empty text | Evidence: `brand` has 78,534 NULL and 0 empty-text values | `BULK INSERT` loads empty fields as NULL, so silver can test `IS NULL` | Keep a defensive `NULLIF(TRIM(column), '')` in silver, in case a column contains blanks that are not empty |
| F7 | Price: zero, negative, not numeric | Evidence: 0 not numeric, 0 negative, **1,252 rows with price 0** (0.22%). The breakdown by event type is in section 4b | A zero price can not be revenue. If purchases carry zero prices, revenue and AOV would be wrong | The valid purchase rule keeps `price > 0`. Zero-price rows are counted in K22. Decide after section 4b whether zero prices are a data error or a free item |
| F8 | Price: median, 99th percentile, maximum | Evidence: median 162.17, 99th percentile 1,698.86, maximum 2,574.07, average 289.36 (over all events) | No extreme outlier in the sample: the maximum is about 1.5 times the 99th percentile. The average is above the median, so prices are skewed. An average over all events mostly describes views, so revenue must use purchase events only | `decimal(18,2)` is much larger than needed. A narrower decimal such as `decimal(9,2)` is a candidate, decided after the full data (E3-07) shows the real maximum |
| F9 | Identical duplicate rows | Evidence: 323 groups of identical rows, 520 surplus rows (0.09%). By type: `cart` 497, `view` 23, `purchase` 0. Inference: about 100,000 surplus rows over 110 million events | Cart events are strongly over-represented (2.4% of cart rows against 0.004% of view rows). Event counts of carts would be inflated. Revenue is not affected, because no purchase is duplicated. Session-based KPIs (K17 to K20) count distinct sessions, so they are not affected either | Remove identical duplicates in silver with a rule and a count (K22). Note the risk: two identical cart events in the same second could be real double clicks, so the rule is documented as a decision, not as a certainty |
| F10 | Sessions with several users | | | |
| F11 | Purchases per session | | | |
| F12 | Purchase sessions without a view | | | |
| F13 | Products with several categories | | | |
| F14 | Products with several brands, or missing and present brand | | | |
| F15 | Products with several prices | | | |
| F16 | Depth of `category_code` | | | |
| F17 | Daily rhythm (events per hour) | | | |
| F18 | Longest values (column sizes) | | | |
| F19 | Purchase sessions without a cart event | | | |
| F20 | Several purchase events in one session: same second or not | | | |
| F21 | Products whose brand or category code is never, sometimes or always missing | | | |

---

## 3. Effect on earlier documents

List here every assumption in the metric dictionary, the RFM rules or the churn definition that this profiling supports or challenges (for example D3, the order rule, or the price rules). Updates are made in E3-09, after the full profiling.

| Document | Assumption | Supported or challenged | Note |
|---|---|---|---|
| | | | |
