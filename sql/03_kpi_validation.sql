use ecommerce_analytics;

/*
  Phase 4: KPI Validation Queries
  10 queries against fact_orders matching the KPI Dictionary definitions.
  Run each to validate fact table and get baseline numbers.
*/

-----------------------------------------------------------
-- KPI 1: Late Rate
-- What share of delivered orders arrive after the estimated delivery date?
-----------------------------------------------------------
SELECT
  'Late Rate' AS kpi_name,
  COUNT(*) AS total_orders,
  SUM(is_late) AS late_orders,
  CAST(100.0 * SUM(is_late) / COUNT(*) AS DECIMAL(5,2)) AS late_rate_pct
FROM fact_orders;

-----------------------------------------------------------
-- KPI 2: On-Time Rate
-- What share of delivered orders arrive on or before the estimated date?
-----------------------------------------------------------
SELECT
  'On-Time Rate' AS kpi_name,
  COUNT(*) AS total_orders,
  SUM(CASE WHEN is_late = 0 THEN 1 ELSE 0 END) AS on_time_orders,
  CAST(100.0 * SUM(CASE WHEN is_late = 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS on_time_rate_pct
FROM fact_orders;

-----------------------------------------------------------
-- KPI 3: Avg Review Score (Late vs On-Time)
-- How much lower is the average review score for late orders vs on-time?
-----------------------------------------------------------
SELECT
  'Avg Review Score' AS kpi_name,
  is_late,
  COUNT(review_score) AS reviewed_orders,
  AVG(CAST(review_score AS FLOAT)) AS avg_review_score,
  MIN(review_score) AS min_score,
  MAX(review_score) AS max_score
FROM fact_orders
WHERE review_score IS NOT NULL
GROUP BY is_late
ORDER BY is_late;

-----------------------------------------------------------
-- KPI 4: Low Review Rate (1-2 Stars) by Lateness
-- What share of reviewed orders get 1-2 stars, and how does it differ by lateness?
-----------------------------------------------------------
SELECT
  'Low Review Rate (1-2 Stars)' AS kpi_name,
  is_late,
  COUNT(review_score) AS reviewed_orders,
  SUM(CASE WHEN review_score IN (1,2) THEN 1 ELSE 0 END) AS low_review_count,
  CAST(100.0 * SUM(CASE WHEN review_score IN (1,2) THEN 1 ELSE 0 END) / COUNT(review_score) AS DECIMAL(5,2)) AS low_review_rate_pct
FROM fact_orders
WHERE review_score IS NOT NULL
GROUP BY is_late
ORDER BY is_late;

-----------------------------------------------------------
-- KPI 5: Seller Handling Duration (Avg/Median Days)
-- How long do sellers take to hand off to carrier (approved -> carrier pickup)?
-----------------------------------------------------------
WITH median_calc AS (
  SELECT  top 1
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY seller_handling_days) over() AS median_val
  FROM fact_orders
  WHERE seller_handling_days IS NOT NULL AND seller_handling_days >= 0
)
SELECT 
  'Seller Handling Duration' AS kpi_name,
  COUNT(seller_handling_days) AS orders_with_handoff,
  AVG(CAST(seller_handling_days AS FLOAT)) AS avg_handling_days,
  (SELECT median_val FROM median_calc) AS median_handling_days,
  MIN(seller_handling_days) AS min_days,
  MAX(seller_handling_days) AS max_days
FROM fact_orders;

-----------------------------------------------------------
-- KPI 6: Carrier Transit Duration (Avg/Median Days)
-- How long does carrier transit take (carrier pickup -> customer delivery)?
-----------------------------------------------------------
with median_cte as (
select top 1 
PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY carrier_transit_days) OVER () AS median_transit_days
from fact_orders
WHERE carrier_transit_days IS NOT NULL
  AND carrier_transit_days >= 0
)
SELECT
  'Carrier Transit Duration' AS kpi_name,
  COUNT(carrier_transit_days) AS orders_with_transit,
  AVG(CAST(carrier_transit_days AS FLOAT)) AS avg_transit_days,
  (select median_transit_days from median_cte) as median_transit_days,
  MIN(carrier_transit_days) AS min_days,
  MAX(carrier_transit_days) AS max_days
FROM fact_orders

-----------------------------------------------------------
-- KPI 7: Late Rate by Lane (Seller State -> Customer State)
-- Which geographic lanes have the highest late rates? (Min 100 orders per lane)
-----------------------------------------------------------
SELECT
  'Late Rate by Lane' AS kpi_name,
  lane,
  seller_state,
  customer_state,
  COUNT(*) AS lane_orders,
  SUM(is_late) AS late_orders,
  CAST(100.0 * SUM(is_late) / COUNT(*) AS DECIMAL(5,2)) AS late_rate_pct,
  AVG(CAST(days_late AS FLOAT)) AS avg_days_late
FROM fact_orders
WHERE lane IS NOT NULL
GROUP BY lane, seller_state, customer_state
HAVING COUNT(*) >= 100
ORDER BY late_rate_pct DESC;

-----------------------------------------------------------
-- KPI 8: Seller Late Rate (Ranked, Min 50 Orders)
-- Which sellers drive the most late orders, excluding low-volume noise?
-----------------------------------------------------------
WITH seller_stats AS (
  SELECT
    s.seller_id,
    COUNT(*) AS seller_orders,
    SUM(is_late) AS seller_late_orders,
    CAST(100.0 * SUM(is_late) / COUNT(*) AS DECIMAL(5,2)) AS late_rate_pct
  FROM fact_orders fo
  JOIN order_items oi ON fo.order_id = oi.order_id
  JOIN sellers s ON oi.seller_id = s.seller_id
  GROUP BY s.seller_id
  HAVING COUNT(*) >= 50
)
SELECT
  'Seller Late Rate (Min 50 Orders)' AS kpi_name,
  seller_id,
  seller_orders,
  seller_late_orders,
  late_rate_pct,
  ROW_NUMBER() OVER (ORDER BY late_rate_pct DESC) AS rank_by_late_rate
FROM seller_stats
ORDER BY late_rate_pct DESC;

-----------------------------------------------------------
-- KPI 9: Rolling 3-Month Late Rate
-- Is the late rate trend improving, stable, or worsening over time?
-----------------------------------------------------------
WITH monthly AS (
  SELECT
    order_month,
    COUNT(*) AS month_orders,
    SUM(is_late) AS month_late_orders,
    CAST(100.0 * SUM(is_late) / COUNT(*) AS DECIMAL(5,2)) AS month_late_rate_pct
  FROM fact_orders
  GROUP BY order_month
),
rolling AS (
  SELECT
    order_month,
    month_orders,
    month_late_orders,
    month_late_rate_pct,
    SUM(month_late_orders) OVER (ORDER BY order_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_3m_late,
    SUM(month_orders) OVER (ORDER BY order_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_3m_total,
    CAST(100.0 * SUM(month_late_orders) OVER (ORDER BY order_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
         / SUM(month_orders) OVER (ORDER BY order_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(5,2)) AS rolling_3m_late_rate_pct
  FROM monthly
)
SELECT
  'Rolling 3-Month Late Rate' AS kpi_name,
  order_month,
  month_orders,
  month_late_rate_pct AS monthly_late_rate_pct,
  rolling_3m_total AS rolling_3m_orders,
  rolling_3m_late_rate_pct AS rolling_3m_late_rate_pct
FROM rolling
ORDER BY order_month;

-----------------------------------------------------------
-- KPI 10: Sales Associated with Late Orders
-- How much revenue (price + freight) is associated with late deliveries?
-----------------------------------------------------------
SELECT
  'Sales Associated with Late Orders' AS kpi_name,
  is_late,
  COUNT(DISTINCT order_id) AS order_count,
  SUM(total_price) AS total_product_revenue,
  SUM(total_freight) AS total_freight_revenue,
  SUM(total_price + total_freight) AS total_associated_revenue
FROM fact_orders
GROUP BY is_late
ORDER BY is_late;

-----------------------------------------------------------
-- Summary: All KPIs at a glance
-----------------------------------------------------------
SELECT '=== KPI SUMMARY ===' AS header;

-- Overall late/on-time split
SELECT 'Overall' AS scope,
       COUNT(*) AS total_orders,
       SUM(is_late) AS late_orders,
       CAST(100.0 * SUM(is_late) / COUNT(*) AS DECIMAL(5,2)) AS late_rate_pct
FROM fact_orders;

-- Monthly volume
SELECT 'Monthly Volume' AS scope,
       order_month,
       COUNT(*) AS orders
FROM fact_orders
GROUP BY order_month
ORDER BY order_month;

-- Category distribution
SELECT 'Top 10 Categories' AS scope,
       primary_category,
       COUNT(*) AS orders,
       SUM(is_late) AS late_orders,
       CAST(100.0 * SUM(is_late) / COUNT(*) AS DECIMAL(5,2)) AS late_rate_pct
FROM fact_orders
WHERE primary_category IS NOT NULL
GROUP BY primary_category
ORDER BY orders DESC;