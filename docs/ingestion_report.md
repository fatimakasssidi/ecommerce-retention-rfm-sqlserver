# Ingestion and Profiling Report (bronze)

Project: E-commerce Customer Retention & RFM (SQL Server)
Tasks: E3-03, E3-04, E3-05, E3-06, E3-07, E3-08

---

## 1. Reconciliation (E3-06)

| File | Lines in file (`wc -l`) | Data rows (lines - 1 header) | Rows in bronze | Difference |
|---|---|---|---|---|
| 2019-Oct.csv | 42,448,765 | 42,448,764 | 42,448,764 | **0** |
| 2019-Nov.csv | 67,501,980 | 67,501,979 | 67,501,979 | **0** |
| **Total** | | **109,950,743** | **109,950,743** | **0** |

Result: no row lost, no row duplicated by the load.

---

## 2. Load options (E3-08)

Same file (October, 42,448,764 rows), three batch settings:

| Option | Batch size | Duration (s) | Rows per second | Result |
|---|---|---|---|---|
| A | 1,000,000 | 240.3 | **176,657** | **Chosen** |
| B | 100,000 | 337.9 | 125,624 | Slowest: too many commits |
| C | 0 (one batch) | 314.3 | 135,050 | Slower, and one huge transaction |

**Decision:** batch size 1,000,000 (the current default of `bronze.load_bronze`).

Note: the test script comment said "1,000,000 rows", but the procedure always loads the whole file. The three runs loaded full October each time.

---

## 3. Full-volume profiling (E3-07)

| Question | Result | Comment |
|---|---|---|
| Period | 2019-10-01 00:00:00 to 2019-11-30 23:59:59 | 61 days, as expected |
| Event types | view 104,335,509 (94.89%), cart 3,955,446 (3.60%), purchase 1,659,788 (1.51%) | `remove_from_cart` **not present** in the full data |
| Missing brand | 15,331,243 (13.9%) | Same order as the sample (14.0%) |
| Missing category code | 35,413,780 (32.2%) | Same order as the sample (32.5%) |
| Missing user_id | 0 | |
| Missing user_session | **12** | New: the sample had none. Issue I-18 |
| Missing price | 0 | |
| Zero price | view 252,203, cart 4,558, **purchase 0** | Same pattern as the sample |
| Negative price | 0 | |
| Price range | 0.00 to 2,574.07 (purchases: min 0.77) | No outliers |
| Duplicate rows | 130,739 surplus rows in 75,652 groups (0.12%) | Sample said 0.09% |
| Purchase sessions without a cart | **462,538 of 1,402,758 (32.97%)** | Sample said 44.73%. The sample overstated it, because sessions were cut by its windows |
| Sessions with several users | 940 | Sample said 8 out of 170,000: the same rare pattern |
| Rhythm by hour | Low at night (hour 0 has 755,539 events), rising through the morning (hour 5 has 5,569,872) | Hours 6 to 23 to be read in the SQL result |

---

## 4. Load log (E3-05)

`audit.load_log` records each run: who (`ORIGINAL_LOGIN`), from which machine (`HOST_NAME`), with which application (`APP_NAME`), start, end, duration, rows, rows per second, status. Runs 101 to 103 (the batch test) are logged. The first October and November loads were made before the log existed, so they are not in it.

---

## 5. Decisions and open items

| ID | Item | Status |
|---|---|---|
| D8 | Funnel: each stage counts its own sessions. Full data: 33% of purchase sessions have no cart | Proposed. Still needed, the share is large |
| I-07 | Order count bounds (sample) | To re-measure: sample bounds of 8,456 to 9,412 are kept until the full order rule is measured |
| I-15 | Encoding (non-ASCII characters) | **Open**: the two `grep` checks are not done yet |
| I-16 | `remove_from_cart` | **Closed on the full data**: not present in 110 million rows |
| I-18 | 12 events without `user_session` | New. Keep the rows, count them in K22 (data quality) |
