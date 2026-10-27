# Data Sources and Data Policy

Project: E-commerce Customer Retention & RFM (SQL Server)

This project uses two public datasets. Raw data is **never committed** to this repository. Every file is downloaded by script into `data/raw/` (ignored by Git), and only a small sample lives in `data/sample/`.

---

## 1. Sources

### 1.1 Online Retail II (UCI Machine Learning Repository)

| Item | Value |
|---|---|
| Role in the project | Core source for RFM, cohorts, churn and data quality work |
| Source page | https://archive.ics.uci.edu/dataset/502/online+retail+ii |
| Content | Real transactions of a UK-based online retailer, December 2009 to December 2011 |
| Size | About 1.07 million rows |
| Format | Excel workbook with two sheets (one per period) |
| License | CC BY 4.0 (attribution required) |
| Creator and citation | The creator name:Daqing Chen, date: 9/20/2019 |
| Saved as | `data/raw/online_retail_ii/` |
| Known issues | Cancellations (invoice numbers starting with "C"), missing customer IDs, negative quantities, zero prices, non-product stock codes, duplicate rows, inconsistent descriptions |

### 1.2 REES46 eCommerce Behavior Data (Kaggle)

| Item | Value |
|---|---|
| Role in the project | Large-scale source for performance engineering, bulk loading and funnel analysis |
| Source page | https://www.kaggle.com/datasets/mkechinov/ecommerce-behavior-data-from-multi-category-store |
| Content | Clickstream events (view, cart, purchase) of a multi-category online store, one CSV file per month |
| Size | Dataset contains 285 million users' events from eCommerce website |
| Format | CSV |
| License | Data files © Original Authors |
| Creator and citation | Michael Kechinov |
| Saved as | `data/raw/rees46/` |
| Known issues | Identical duplicate rows, missing brand and category values, purchases are a small share of all events |

---

## 2. Data policy

1. **No raw data in Git.** `data/raw/` is ignored. Anyone who clones the repository downloads the data with `scripts/download_data.ps1` (task E2-01) and agrees to the dataset terms themselves.
2. **Sample data only.** `data/sample/` holds a tiny dataset used for tests and CI.
   - The Online Retail II sample can be a small subset of real rows, because the license allows redistribution with attribution.
   - The REES46 sample must be **synthetic** (generated from the file structure, with no real rows) unless the license is confirmed to allow redistribution.
3. **Attribution.** The README credits each dataset, its creator and its license.
4. **Code and data are licensed separately.** The code in this repository is MIT licensed (see `LICENSE`). The datasets keep their own licenses, listed above.
5. **No personal data.** Both datasets use anonymized identifiers. The project makes no attempt to identify individuals, and no real contact details are added or invented.
6. **Secrets.** Credentials live in `.env` (ignored). `.env.example` holds placeholders only.

---

## 3. Checklist for adding a new dataset

- [ ] Source page and license recorded in this file
- [ ] License allows the intended use (learning and portfolio)
- [ ] Download is scripted and does not commit the data
- [ ] Citation added to the README
- [ ] Known quality issues listed
