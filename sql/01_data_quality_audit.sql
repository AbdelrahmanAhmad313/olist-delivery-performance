use ecommerce_analytics


WITH
-- 1. Raw table row counts
raw_counts AS (
  SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM orders
  UNION ALL
  SELECT 'order_items', COUNT(*) FROM order_items
  UNION ALL
  SELECT 'order_reviews', COUNT(*) FROM order_reviews
  UNION ALL
  SELECT 'customers', COUNT(*) FROM customers
  UNION ALL
  SELECT 'sellers', COUNT(*) FROM sellers
  UNION ALL
  SELECT 'products', COUNT(*) FROM products
  UNION ALL
  SELECT 'category_translation', COUNT(*) FROM category_translation
  UNION ALL
  SELECT 'order_payments', COUNT(*) FROM order_payments
  UNION ALL
  SELECT 'geolocation', COUNT(*) FROM geolocation
),

-- 2. Delivered orders only (fact grain)
delivered AS (
  SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
  FROM orders
  WHERE order_status = 'delivered'
    AND order_delivered_customer_date IS NOT NULL
),

-- 3. Join reconciliation: orders → items (fan-out check)
items_recon AS (
  SELECT
    d.order_id,
    COUNT(i.order_item_id) AS items_per_order,
    SUM(i.price) AS total_price,
    SUM(i.freight_value) AS total_freight
  FROM delivered d
  LEFT JOIN order_items i ON d.order_id = i.order_id
  GROUP BY d.order_id
),

-- 4. Orphan keys (items/reviews/customers/sellers with no matching delivered order)
orphans AS (
  SELECT 'items' AS table_name, COUNT(*) AS orphan_count
  FROM order_items i
  LEFT JOIN delivered d ON i.order_id = d.order_id
  WHERE d.order_id IS NULL

  UNION ALL

  SELECT 'reviews', COUNT(*)
  FROM order_reviews r
  LEFT JOIN delivered d ON r.order_id = d.order_id
  WHERE d.order_id IS NULL

  UNION ALL

  SELECT 'customers', COUNT(*)
  FROM customers c
  LEFT JOIN delivered d ON c.customer_id = d.customer_id
  WHERE d.customer_id IS NULL

  UNION ALL

  SELECT 'sellers', COUNT(*)
  FROM sellers s
  LEFT JOIN order_items i ON s.seller_id = i.seller_id
  LEFT JOIN delivered d ON i.order_id = d.order_id
  WHERE d.order_id IS NULL
),

-- 5. Duplicate reviews per order
dup_reviews AS (
  SELECT
    order_id,
    COUNT(*) AS review_count
  FROM order_reviews
  GROUP BY order_id
  HAVING COUNT(*) > 1
),

-- 6. Impossible timestamps
bad_timestamps AS (
  SELECT
    order_id,
    CASE
      WHEN order_delivered_customer_date < order_delivered_carrier_date THEN 'delivery_before_carrier'
      WHEN order_delivered_carrier_date < order_approved_at THEN 'carrier_before_approved'
      WHEN order_approved_at < order_purchase_timestamp THEN 'approved_before_purchase'
      WHEN order_estimated_delivery_date < order_purchase_timestamp THEN 'estimated_before_purchase'
    END AS violation_type
  FROM delivered
  WHERE order_delivered_customer_date < order_delivered_carrier_date
     OR order_delivered_carrier_date < order_approved_at
     OR order_approved_at < order_purchase_timestamp
     OR order_estimated_delivery_date < order_purchase_timestamp
),

-- 7. Null patterns in key columns
null_checks AS (
  SELECT
    'order_approved_at' AS column_name,
    SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS null_count,
    COUNT(*) AS total_count
  FROM delivered
  UNION ALL
  SELECT 'order_delivered_carrier_date',
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END),
    COUNT(*)
  FROM delivered
  UNION ALL
  SELECT 'order_estimated_delivery_date',
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END),
    COUNT(*)
  FROM delivered
  UNION ALL
  SELECT 'review_score',
    SUM(CASE WHEN r.review_score IS NULL THEN 1 ELSE 0 END),
    COUNT(*)
  FROM delivered d
  LEFT JOIN order_reviews r ON d.order_id = r.order_id
),

-- 8. Date window analysis (monthly counts to pick defensible window)
date_window AS (
  SELECT
    FORMAT(order_purchase_timestamp, 'yyyy-MM') AS order_month,
    COUNT(*) AS order_count
  FROM delivered
  GROUP BY FORMAT(order_purchase_timestamp, 'yyyy-MM')
),

-- 9. Volume thresholds (lane, seller, category minimums)
volume_checks AS (
  -- Lanes (seller_state -> customer_state) with < 30 orders
  SELECT 'lane' AS level, c_seller.customer_state + '->' + c_customer.customer_state AS entity, COUNT(*) AS order_count
  FROM delivered d
  JOIN order_items oi ON d.order_id = oi.order_id
  JOIN sellers s ON oi.seller_id = s.seller_id
  JOIN customers c_seller ON s.seller_zip_code_prefix = c_seller.customer_zip_code_prefix
  JOIN customers c_customer ON d.customer_id = c_customer.customer_id
  GROUP BY c_seller.customer_state, c_customer.customer_state
  HAVING COUNT(*) < 30

  UNION ALL

  -- Sellers with < 50 orders
  SELECT 'seller', s.seller_id, COUNT(*)
  FROM delivered d
  JOIN order_items oi ON d.order_id = oi.order_id
  JOIN sellers s ON oi.seller_id = s.seller_id
  GROUP BY s.seller_id
  HAVING COUNT(*) < 50

  UNION ALL

  -- Categories with < 100 orders
  SELECT 'category', p.product_category_name, COUNT(*)
  FROM delivered d
  JOIN order_items oi ON d.order_id = oi.order_id
  JOIN products p ON oi.product_id = p.product_id
  GROUP BY p.product_category_name
  HAVING COUNT(*) < 100
)

-- FINAL: Union all checks into one results table
SELECT * FROM (
  -- 1. Raw counts
  SELECT 'raw_counts' AS check_name,
         table_name + ': ' + CAST(row_count AS VARCHAR(30)) AS status,
         'Row count per table' AS notes
  FROM raw_counts

  UNION ALL

  -- 2. Delivered order count
  SELECT 'delivered_count',
         CAST(COUNT(*) AS VARCHAR(30)) + ' delivered orders',
         'Fact grain: one row per delivered order with delivery date'
  FROM delivered

  UNION ALL

  -- 3. Items reconciliation
  SELECT 'items_recon',
         'avg items/order: ' + CAST(AVG(items_per_order * 1.0) AS VARCHAR(20)) +
         ', orders w/ 0 items: ' + CAST(SUM(CASE WHEN items_per_order = 0 THEN 1 ELSE 0 END) AS VARCHAR(30)) +
         ', max items: ' + CAST(MAX(items_per_order) AS VARCHAR(30)),
         'Fan-out check: orders -> items'
  FROM items_recon

  UNION ALL

  -- 4. Orphans
  SELECT 'orphans',
         table_name + ': ' + CAST(orphan_count AS VARCHAR(30)),
         'Rows in child tables with no matching delivered order'
  FROM orphans

  UNION ALL

  -- 5. Duplicate reviews
  SELECT 'dup_reviews',
         CAST(COUNT(*) AS VARCHAR(30)) + ' orders with duplicate reviews',
         'Orders having >1 review (data quality issue)'
  FROM dup_reviews

  UNION ALL

  -- 6. Bad timestamps
  SELECT 'bad_timestamps',
         violation_type + ': ' + CAST(COUNT(*) AS VARCHAR(30)),
         'Impossible timestamp sequences'
  FROM bad_timestamps
  GROUP BY violation_type

  UNION ALL

  -- 7. Null checks
  SELECT 'null_checks',
         column_name + ': ' + CAST(null_count AS VARCHAR(30)) + '/' + CAST(total_count AS VARCHAR(30)) + ' NULL',
         'NULL rate: ' + CAST(100.0 * null_count / NULLIF(total_count, 0) AS VARCHAR(30)) + '%'
  FROM null_checks

  UNION ALL

  -- 8. Date window (show all months)
  SELECT 'date_window',
         order_month + ': ' + CAST(order_count AS VARCHAR(30)),
         'Monthly order volume for window selection'
  FROM date_window

  UNION ALL

  -- 9. Volume checks (counts below threshold)
  SELECT 'volume_checks',
         level + ': ' + CAST(COUNT(*) AS VARCHAR(30)) + ' entities below threshold',
         'Min thresholds: lane=30, seller=50, category=100'
  FROM volume_checks
  GROUP BY level
) all_checks
ORDER BY check_name;

-----


SELECT
    FORMAT(order_purchase_timestamp, 'yyyy-MM') AS order_month,
    COUNT(DISTINCT order_id) AS order_count
FROM orders
WHERE order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp < '2018-08-31'
GROUP BY FORMAT(order_purchase_timestamp, 'yyyy-MM')
ORDER BY order_month;

-----
with 
category as(
SELECT COUNT(*) AS category_count
FROM (
    SELECT
        p.product_category_name
    FROM products p
    JOIN order_items oi
        ON p.product_id = oi.product_id
    JOIN orders o
        ON o.order_id = oi.order_id
    GROUP BY p.product_category_name
    HAVING COUNT(DISTINCT o.order_id) < 100
) AS category_summary),

seller as(
select count(*) as seller_count
from (
select count(distinct s.seller_id) as sellers_count , count(distinct o.order_id) as order_count
from order_items oi
join orders o
on o.order_id = oi.order_id
join sellers s
on s.seller_id = oi.seller_id
group by oi.seller_id
having count(distinct o.order_id) < 50
) as seller_summery),
lane as (
select count(*) as lane_count
from(
select count(distinct customer_state) as customer_state , count(distinct o.order_id) as order_count
from customers c 
join orders o 
on c.customer_id = o.customer_id
group by c.customer_state 
having count(distinct o.order_id) < 100
)
as lane_summery)
select * 
from (
select category_count  AS entity_count, CAST(category_count AS VARCHAR(20)) +' has less than 100 order' as entities_below_threshold
from category 
union all 
select seller_count, CAST(seller_count AS VARCHAR(20)) + ' has less than 50 order' 
from seller
union all 
select  lane_count , CAST(lane_count AS VARCHAR(20)) +' has less than 100 order' 
from lane)
as threshold;