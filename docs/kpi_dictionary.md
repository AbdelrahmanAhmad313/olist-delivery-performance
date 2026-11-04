# KPI Dictionary — Olist Delivery Performance & Customer Experience

**Project:** Olist Delivery Performance and Customer Experience
**Stakeholder:** Head of Marketplace Operations (simulated)
**Decision:** Where to focus delivery improvements — seller handling, carrier transit, lanes, or delivery-date promises
**Dataset:** Olist Brazilian E-Commerce (Kaggle), ~100k orders, 2016-2018
**Grain of fact table (`fact_orders`):** One row per **delivered order**

---

## KPI Definitions

### 1. Late Rate

| Field                 | Definition                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------- |
| **Business Question** | What share of delivered orders arrive after the estimated delivery date?                    |
| **Numerator**         | `COUNT(order_id) WHERE days_late > 0`                                                       |
| **Denominator**       | `COUNT(order_id) WHERE order_status = 'delivered'`                                          |
| **Grain**             | One row per delivered order (`fact_orders`)                                                 |
| **Filters**           | Date window: [DEFINE YOUR DEFENSIBLE WINDOW HERE]; exclude orders with null delivery dates  |
| **Caveats**           | Estimated date set by platform — "late" may reflect optimistic promise, not carrier failure |

### 2. On-Time Rate

| Field                 | Definition                                                             |
| --------------------- | ---------------------------------------------------------------------- |
| **Business Question** | What share of delivered orders arrive on or before the estimated date? |
| **Numerator**         | `COUNT(order_id) WHERE days_late <= 0`                                 |
| **Denominator**       | `COUNT(order_id) WHERE order_status = 'delivered'`                     |
| **Grain**             | One row per delivered order                                            |
| **Filters**           | Same as Late Rate                                                      |
| **Caveats**           | Complement of Late Rate; same promise-bias caveat                      |

### 3. Avg Review Score (Late vs On-Time)

| Field                 | Definition                                                                             |
| --------------------- | -------------------------------------------------------------------------------------- |
| **Business Question** | How much lower is the average review score for late orders vs on-time?                 |
| **Numerator**         | `SUM(review_score) WHERE days_late > 0` / `SUM(review_score) WHERE days_late <= 0`     |
| **Denominator**       | `COUNT(review_score) WHERE days_late > 0` / `COUNT(review_score) WHERE days_late <= 0` |
| **Grain**             | One row per delivered order **with a review**                                          |
| **Filters**           | Only orders with `review_score IS NOT NULL`; same date window                          |
| **Caveats**           | Review selection bias — voluntary reviews over-represent extremes                      |

### 4. Low Review Rate (1-2 Stars)

| Field                 | Definition                                                                                                                         |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Business Question** | What share of reviewed orders get 1-2 stars, and how does it differ by lateness?                                                   |
| **Numerator**         | `COUNT(order_id) WHERE review_score IN (1,2) AND days_late > 0` / `COUNT(order_id) WHERE review_score IN (1,2) AND days_late <= 0` |
| **Denominator**       | `COUNT(order_id) WHERE review_score IS NOT NULL AND days_late > 0` / same for on-time                                              |
| **Grain**             | One row per delivered order with a review                                                                                          |
| **Filters**           | Same date window; min review count per segment for reliability                                                                     |
| **Caveats**           | Binary outcome for logistic regression; small sample in some lanes                                                                 |

### 5. Seller Handling Duration (Avg/Median Days)

| Field                 | Definition                                                                   |
| --------------------- | ---------------------------------------------------------------------------- |
| **Business Question** | How long do sellers take to hand off to carrier (approved → carrier pickup)? |
| **Numerator**         | `SUM(DATEDIFF(day, order_approved_at, order_delivered_carrier_date))`        |
| **Denominator**       | `COUNT(order_id) WHERE order_delivered_carrier_date IS NOT NULL`             |
| **Grain**             | One row per delivered order with carrier handoff date                        |
| **Filters**           | Exclude impossible timestamps (carrier < approved); same date window         |
| **Caveats**           | Only captures seller-controlled stage; no carrier ID to separate further     |

### 6. Carrier Transit Duration (Avg/Median Days)

| Field                 | Definition                                                                        |
| --------------------- | --------------------------------------------------------------------------------- |
| **Business Question** | How long does carrier transit take (carrier pickup → customer delivery)?          |
| **Numerator**         | `SUM(DATEDIFF(day, order_delivered_carrier_date, order_delivered_customer_date))` |
| **Denominator**       | `COUNT(order_id) WHERE order_delivered_customer_date IS NOT NULL`                 |
| **Grain**             | One row per delivered order with both dates                                       |
| **Filters**           | Exclude impossible timestamps (delivery < carrier); same date window              |
| **Caveats**           | No carrier identifier — mixes all carriers per lane                               |

### 7. Late Rate by Lane (Seller State → Customer State)

| Field                 | Definition                                                                          |
| --------------------- | ----------------------------------------------------------------------------------- |
| **Business Question** | Which geographic lanes (seller_state → customer_state) have the highest late rates? |
| **Numerator**         | `COUNT(order_id) WHERE days_late > 0` grouped by `seller_state`, `customer_state`   |
| **Denominator**       | `COUNT(order_id)` grouped by `seller_state`, `customer_state`                       |
| **Grain**             | One row per delivered order, aggregated to lane level                               |
| **Filters**           | Min 30 orders per lane (noise filter); same date window                             |
| **Caveats**           | Lane = state-to-state; city-level not available; volume varies widely               |

### 8. Seller Late Rate (Ranked, Min 50 Orders)

| Field                 | Definition                                                               |
| --------------------- | ------------------------------------------------------------------------ |
| **Business Question** | Which sellers drive the most late orders, excluding low-volume noise?    |
| **Numerator**         | `COUNT(order_id) WHERE days_late > 0` per `seller_id`                    |
| **Denominator**       | `COUNT(order_id)` per `seller_id`                                        |
| **Grain**             | One row per seller (aggregated from `fact_orders`)                       |
| **Filters**           | `HAVING COUNT(order_id) >= 50`; same date window; rank by late rate DESC |
| **Caveats**           | Seller may have multiple products/categories; no carrier control         |

### 9. Rolling 3-Month Late Rate

| Field                 | Definition                                                                         |
| --------------------- | ---------------------------------------------------------------------------------- |
| **Business Question** | Is the late rate trend improving, stable, or worsening over time?                  |
| **Numerator**         | `SUM(late_flag) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)`    |
| **Denominator**       | `SUM(total_orders) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)` |
| **Grain**             | Monthly aggregate (one row per month)                                              |
| **Filters**           | Full date window; first 2 months have partial windows (document)                   |
| **Caveats**           | Edge months have smaller windows; use `RANGE` for calendar-aware if needed         |

### 10. Sales Associated with Late Orders

| Field                 | Definition                                                                                     |
| --------------------- | ---------------------------------------------------------------------------------------------- |
| **Business Question** | How much revenue (price + freight) is associated with late deliveries?                         |
| **Numerator**         | `SUM(price + freight_value) FROM order_items JOIN fact_orders ON order_id WHERE days_late > 0` |
| **Denominator**       | N/A (absolute value, not a rate)                                                               |
| **Grain**             | Order-item level joined to order-level lateness — **reconcile to avoid fan-out inflation**     |
| **Filters**           | Only delivered orders with items; same date window                                             |
| **Caveats**           | **Sales ≠ profit** — no cost/margin data; "associated" not "caused by" lateness                |

---

## Date Window Decision (fill in after data audit)

| Item              | Value                                                       |
| ----------------- | ----------------------------------------------------------- |
| **Start date**    | [e.g., 2017-01-01 — after sparse early months]              |
| **End date**      | [e.g., 2018-08-31 — before truncated tail]                  |
| **Justification** | [Explain: month completeness, order volume stability, etc.] |

## Minimum Volume Thresholds (fill in after data audit)

| Level                  | Threshold                                                   | Reason            |
| ---------------------- | ----------------------------------------------------------- | ----------------- |
| **Lane (state→state)** | [e.g., 30 orders]                                           | [Why this number] |
| **Seller**             | [e.g., 50 orders]                                           | [Why this number] |
| **Start date**         | [e.g., 2017-01-01 — after sparse early months]              |
| **End date**           | [e.g., 2018-08-31 — before truncated tail]                  |
| **Justification**      | [Explain: month completeness, order volume stability, etc.] |

## Minimum Volume Thresholds (fill in after data audit)

| Level                  | Threshold          | Reason            |
| ---------------------- | ------------------ | ----------------- |
| **Lane (state→state)** | [e.g., 30 orders]  | [Why this number] |
| **Seller**             | [e.g., 50 orders]  | [Why this number] |
| **Category**           | [e.g., 100 orders] | [Why this number] |

---

## Notes for Later Phases

- Every KPI here must map to: a SQL query (Phase 2-3), a Python check (Phase 4), a DAX measure (Phase 5), and a dashboard visual (Phase 6).
- If a KPI definition changes, update this file **and** commit with message: `docs: update KPI dictionary - [what changed]`.

---
