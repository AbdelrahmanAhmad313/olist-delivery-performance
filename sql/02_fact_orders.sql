use ecommerce_analytics;
SET NOCOUNT ON;

/*
  fact_orders — One row per delivered order (2017-02-01 to 2018-08-31)
  Grain: 1 row per order_id
  All KPIs in Phase 4+ query this table.
  Optimized with temp tables for performance.
*/

-- 1. Base delivered orders in window (materialize first)
SELECT
  order_id,
  customer_id,
  order_purchase_timestamp,
  order_approved_at,
  order_delivered_carrier_date,
  order_delivered_customer_date,
  order_estimated_delivery_date
INTO #base_orders
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_purchase_timestamp >= '2017-02-01'
  AND order_purchase_timestamp <= '2018-08-31';

-- 2. Clean impossible timestamps
DELETE FROM #base_orders
WHERE order_delivered_customer_date < order_delivered_carrier_date
   OR order_delivered_carrier_date < order_approved_at
   OR order_approved_at < order_purchase_timestamp
   OR order_estimated_delivery_date < order_purchase_timestamp;

-- 3. Seller state (pre-aggregate: one row per seller)
SELECT s.seller_id, g.geolocation_state AS seller_state
INTO #seller_state
FROM sellers s
JOIN geolocation g ON s.seller_zip_code_prefix = g.geolocation_zip_code_prefix;

-- 4. Customer state (pre-aggregate: one row per customer)
SELECT c.customer_id, c.customer_state
INTO #customer_state
FROM customers c;

-- 5. Lane per order (join via order_items -> seller_state, customer_state)
SELECT DISTINCT
  d.order_id,
  ss.seller_state,
  cs.customer_state
INTO #order_lane
FROM #base_orders d
JOIN order_items oi ON d.order_id = oi.order_id
JOIN #seller_state ss ON oi.seller_id = ss.seller_id
JOIN #customer_state cs ON d.customer_id = cs.customer_id;

-- 6. Order items aggregation (only windowed orders)
SELECT
  oi.order_id,
  COUNT(oi.order_item_id) AS item_count,
  SUM(oi.price) AS total_price,
  SUM(oi.freight_value) AS total_freight
INTO #order_items_agg
FROM order_items oi
JOIN #base_orders d ON oi.order_id = d.order_id
GROUP BY oi.order_id;

-- 7. Primary category per order (category with max revenue)
SELECT
  oi.order_id,
  p.product_category_name AS primary_category
INTO #order_primary_category
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN #base_orders d ON oi.order_id = d.order_id
GROUP BY oi.order_id, p.product_category_name
HAVING SUM(oi.price) = (
  SELECT MAX(category_sum)
  FROM (
    SELECT SUM(oi2.price) AS category_sum
    FROM order_items oi2
    JOIN products p2 ON oi2.product_id = p2.product_id
    WHERE oi2.order_id = oi.order_id
    GROUP BY p2.product_category_name
  ) t
);

-- 8. Review score (deduped, only windowed orders)
SELECT r.order_id, r.review_score
INTO #order_reviews_clean
FROM (
  SELECT order_id, review_score,
         ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_creation_date) AS rn
  FROM order_reviews
  WHERE order_id IN (SELECT order_id FROM #base_orders)
) r
WHERE r.rn = 1;

-- 9. Payments (only windowed orders)
SELECT order_id, SUM(payment_value) AS total_payment
INTO #order_payments_agg
FROM order_payments
WHERE order_id IN (SELECT order_id FROM #base_orders)
GROUP BY order_id;

-- 10. FINAL: Assemble fact_orders (fast joins on temp tables)
SELECT
  co.order_id,
  co.customer_id,
  co.order_purchase_timestamp,
  co.order_approved_at,
  co.order_delivered_carrier_date,
  co.order_delivered_customer_date,
  co.order_estimated_delivery_date,

  -- Fast date parts (no FORMAT)
  CONVERT(CHAR(7), co.order_purchase_timestamp, 126) AS order_month,  -- 'yyyy-MM'
  DATEPART(weekday, co.order_purchase_timestamp) AS order_dow,

  -- Durations
  DATEDIFF(day, co.order_approved_at, co.order_delivered_carrier_date) AS seller_handling_days,
  DATEDIFF(day, co.order_delivered_carrier_date, co.order_delivered_customer_date) AS carrier_transit_days,
  DATEDIFF(day, co.order_purchase_timestamp, co.order_delivered_customer_date) AS total_delivery_days,
  DATEDIFF(day, co.order_estimated_delivery_date, co.order_delivered_customer_date) AS days_late,

  CASE WHEN DATEDIFF(day, co.order_estimated_delivery_date, co.order_delivered_customer_date) > 0 THEN 1 ELSE 0 END AS is_late,

  -- Lane
  ol.seller_state,
  ol.customer_state,
  ol.seller_state + '->' + ol.customer_state AS lane,

  -- Order items
  oia.item_count,
  oia.total_price,
  oia.total_freight,
  opc.primary_category,
  ct.column2 AS primary_category_english,

  -- Review
  orc.review_score,

  -- Payment
  opa.total_payment

INTO fact_orders  -- Creates the table
FROM #base_orders co
LEFT JOIN #order_lane ol ON co.order_id = ol.order_id
LEFT JOIN #order_items_agg oia ON co.order_id = oia.order_id
LEFT JOIN #order_primary_category opc ON co.order_id = opc.order_id
LEFT JOIN category_translation ct ON opc.primary_category = ct.column1
LEFT JOIN #order_reviews_clean orc ON co.order_id = orc.order_id
LEFT JOIN #order_payments_agg opa ON co.order_id = opa.order_id;

-- Indexes for Phase 4 queries
CREATE INDEX IX_fact_orders_month ON fact_orders(order_month);
CREATE INDEX IX_fact_orders_lane ON fact_orders(lane);
CREATE INDEX IX_fact_orders_seller_state ON fact_orders(seller_state);
CREATE INDEX IX_fact_orders_category ON fact_orders(primary_category);

-- Cleanup
DROP TABLE #base_orders, #seller_state, #customer_state, #order_lane,
           #order_items_agg, #order_primary_category, #order_reviews_clean, #order_payments_agg;

SELECT COUNT(*) AS fact_orders_row_count FROM fact_orders;
          
SELECT TOP 10 * FROM fact_orders;           
SELECT order_month, COUNT(*) FROM fact_orders GROUP BY order_month ORDER BY order_month;  