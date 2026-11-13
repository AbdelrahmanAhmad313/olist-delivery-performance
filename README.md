# Olist Brazilian E-Commerce: Delivery Performance & Customer Experience Analytics

An end-to-end data analytics and business intelligence project evaluating logistics bottlenecks, delivery lateness, and their direct impact on customer satisfaction across Brazilian e-commerce.

---

## 📊 Executive Summary
In e-commerce, logistics reliability is a primary driver of customer retention and brand trust. This project analyzes **94,600+ orders** from the Olist Brazilian E-Commerce public dataset (spanning February 2017 to August 2018) to diagnose delivery delays, isolate operational bottlenecks between merchants (sellers) and third-party carriers (like Correios), quantify statistical significance, and measure the direct financial and satisfaction penalty of late deliveries.

---

## 🗄️ Project Architecture & Data Pipeline

Raw CSV Datasets (9 tables)
  --> SQL Data Quality Audit (Missing values, orphans, duplicates)
  --> Filtered Date Window (2017-02-01 to 2018-08-31)
  --> Star Schema & Fact Table (fact_orders)
  --> Statistical Validation (Python: Bootstrap CIs, Z-Test, Logistic Regression)
  --> Power BI Executive Dashboard & DAX Measures

1. **Data Quality Audit (`sql/01_data_quality_audit.sql`):** Validated row counts, checked foreign key orphan rates, identified duplicate reviews, and cleaned anomalous timestamps.
2. **Date Window Selection:** Restricted analysis to `2017-02-01` through `2018-08-31` to exclude the 2017-01 platform ramp-up and ensure complete monthly cohorts.
3. **Fact Table Design (`sql/02_fact_orders.sql`):** Built a consolidated grain-level fact table (`1 row per order_id`) computing key durations:
   - **Seller Handling Duration:** `approved_at` -> `carrier_delivery_start_date` (Avg: ~2.7 days)
   - **Carrier Transit Duration:** `carrier_delivery_start_date` -> `delivered_customer_date` (Avg: ~9.3 days)
   - **Lateness Flag (`is_late`):** `delivered_customer_date` > `estimated_delivery_date`

---

## 📈 Core Key Performance Indicators (KPIs)
| KPI | Definition | Baseline Value |
| :--- | :--- | :--- |
| **Late Rate** | % of delivered orders arriving after the estimated date | ~8.5% - 10% |
| **On-Time Rate** | % of delivered orders arriving on or before estimated date | ~90% - 91.5% |
| **Avg Seller Handling** | Mean days for sellers to hand off orders to carriers | ~2.7 days (Median: 2) |
| **Avg Carrier Transit** | Mean days for carriers to transport to customers | ~9.3 days (Median: 7) |
| **Avg Review Score** | Mean customer review score (1-5 scale) | ~4.1 / 5.0 |
| **Low Review Rate** | % of reviewed orders receiving 1 or 2 stars | ~15% - 18% |

---

## 🧪 Statistical Validation & Findings (Python)
Using Python (`scipy`, `statsmodels`, `numpy`), rigorous statistical checks were performed on the verified dataset:
- **Bootstrap Confidence Intervals (95%):** Computed robust CIs for late rates, review scores, and handling durations over 5,000 resamples.
- **Two-Proportion Z-Test:** Tested whether the low review rate (1-2 stars) differs significantly between late and on-time orders. The test confirmed a massive, statistically significant spike in dissatisfaction for late orders ($p < 0.001$).
- **Logistic Regression:** Modeled the odds of receiving a low review (`1-2 stars`) controlling for lateness, seller handling days, carrier transit days, order price, and product category. **Key Finding:** Late delivery significantly increases the odds of a low customer review by over **$2.5\times$**, dwarfing the impact of slight pricing variations or handling delays.

---

## 📊 Power BI Dashboard & DAX Measures
The executive Power BI report connects directly to the validated SQL data model and features four core analytical views:
1. **KPI Summary Cards:** Total Orders, Late Rate %, On-Time Rate %, Avg Seller Handling Days, Avg Carrier Transit Days.
2. **Trend Analysis (Line Chart):** Rolling 3-month late rate tracking logistics stability over time.
3. **Geographic Bottlenecks (Line & Clustered Column Chart):** Regional lane analysis (`seller_state` -> `customer_state`) comparing order volume against late rates.
4. **Customer Impact (Clustered Column Chart):** Direct comparison of average review scores for on-time vs. late deliveries.

### Key DAX Measures Implemented:
* **`Late Rate %`**:
  ```dax
  Late Rate % =
  DIVIDE(
      CALCULATE(COUNTROWS(fact_orders), fact_orders[is_late] = 1),
      COUNTROWS(fact_orders),
      0
  )
- Low Review Rate %:
dax
Low Review Rate % = DIVIDE(
    CALCULATE(COUNTROWS(fact_orders), fact_orders[review_score] = 1 || fact_orders[review_score] = 2),
    CALCULATE(COUNTROWS(fact_orders), NOT ISBLANK(fact_orders[review_score])),
    0
)

---

💡 Strategic Recommendations for Olist

1. Carrier SLA Enforcement: Since carrier transit duration (~9.3 days avg) accounts for over 75% of total delivery time, Olist must renegotiate SLAs with regional carriers (especially on interstate trunk lanes).
2. Seller Fulfillment Optimization: While handling time is shorter (~2.7 days), long-tail underperforming sellers drive local bottlenecks and should be enrolled in seller coaching or fulfillment center programs.
3. Customer Expectation Management: Dynamic estimated delivery dates incorporating historical lane performance will reduce perceived lateness and protect review scores.

---
Project developed as part of Advanced Data Analytics & Portfolio Roadmap.
