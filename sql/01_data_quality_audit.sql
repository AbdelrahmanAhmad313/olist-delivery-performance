-- 01_data_quality_audit.sql
-- Data quality audit for Olist Delivery Performance project
-- Run on SQL Server database where Olist tables are loaded

WITH
-- 1. Raw table row counts
raw_counts AS (
  -- TODO: SELECT table_name, COUNT(*) FROM each of the 9 tables
),

-- 2. Delivered orders only (fact grain)
delivered AS (
  -- TODO: SELECT key columns FROM olist_orders_dataset WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
),

-- 3. Join reconciliation: orders → items (fan-out check)
items_recon AS (
  -- TODO: Join delivered to olist_order_items_dataset, compute items_per_order
),

-- 4. Orphan keys (items/reviews/customers/sellers with no matching delivered order)
orphans AS (
  -- TODO: LEFT JOIN each child table to delivered, count WHERE parent IS NULL
),

-- 5. Duplicate reviews per order
dup_reviews AS (
  -- TODO: GROUP BY order_id HAVING COUNT(*) > 1 on olist_
),

-- 6. Impossible timestamps
bad_timestamps AS (
  -- TODO: Check delivery < carrier < approved < purchase, estimated < purchase
),

-- 7. Null patterns in key columns
null_checks AS (
  -- TODO: Count NULLs in approved_at, carrier_date, estimated_date, review_score
),

-- 8. Date window analysis (monthly counts to pick defensible window)
date_window AS (
  -- TODO: Monthly order counts from delivered, ordered by month
),

-- 9. Volume thresholds (lane, seller, category minimums)
volume_checks AS (
  -- TODO: Count lanes/sellers/categories below threshold
)

-- FINAL: Union all checks into one results table
SELECT * FROM (
  -- TODO: SELECT from each CTE above with columns: check_ctual, status, notes
) all_checks
ORDER BY check_name;