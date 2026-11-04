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
| Rows in the sample | *(fill in: section 1 of `profile_sample.sql`)* |
| Time covered | *(fill in: first and last event, number of days)* |
| Line ending of the files | *(fill in: LF or CRLF)* |

**Limits of the sample:** sessions longer than a block are cut, so session-level numbers are approximate. Rare problems may not appear, and a clean sample does not prove the whole file is clean.

---

## 2. Findings

| # | Topic | Finding (count and share) | Suspected impact | Decision or next step |
|---|---|---|---|---|
| F1 | Timestamps | *(rows with a bad timestamp, rows without ` UTC`)* | | |
| F2 | Event types | *(types found and their shares, is `remove_from_cart` present?)* | | |
| F3 | Missing `brand` | | | |
| F4 | Missing `category_code` | | | |
| F5 | Missing `user_id` or `user_session` | | | |
| F6 | Empty values: NULL or empty text | | | |
| F7 | Price: zero, negative, not numeric | | | |
| F8 | Price: median, 99th percentile, maximum | | | |
| F9 | Identical duplicate rows | | | |
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

---

## 3. Effect on earlier documents

List here every assumption in the metric dictionary, the RFM rules or the churn definition that this profiling supports or challenges (for example D3, the order rule, or the price rules). Updates are made in E3-09, after the full profiling.

| Document | Assumption | Supported or challenged | Note |
|---|---|---|---|
| | | | |
