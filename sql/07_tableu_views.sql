-- Delivery Performance Analytics
-- 07_tableau_views.sql
-- Denormalized views optimized for Tableau visualization
-- Run AFTER all other scripts

-- ============================================================
-- 1) MAIN FACT VIEW: Order Delivery Details
--    One row per order line with all dimensions denormalized
--    This is the primary data source for most Tableau dashboards
-- ============================================================

CREATE OR REPLACE VIEW vw_tableau_order_delivery AS
SELECT
  -- Order identifiers
  ol.order_line_id,
  ol.order_id,
  ol.line_number,
  
  -- Date dimensions
  d_order.calendar_date AS order_date,
  d_order.year AS order_year,
  d_order.month AS order_month,
  d_order.month_name AS order_month_name,
  d_order.week_of_year AS order_week,
  d_order.day_of_week AS order_day_of_week,
  d_order.is_weekend AS order_is_weekend,
  
  d_promise.calendar_date AS promised_delivery_date,
  d_promise.year AS promise_year,
  d_promise.month AS promise_month,
  d_promise.month_name AS promise_month_name,
  
  -- Customer dimensions
  c.customer_id,
  c.customer_code,
  c.customer_name,
  c.customer_segment,
  c.country AS customer_country,
  c.region AS customer_region,
  
  -- Product dimensions
  p.product_id,
  p.sku,
  p.product_name,
  p.product_category,
  
  -- Service level
  sl.service_level_code,
  sl.service_level_name,
  sl.promised_days AS service_level_days,
  
  -- Order metrics
  ol.ordered_qty,
  ol.line_status,
  
  -- Shipment dimensions
  s.shipment_id,
  s.shipment_created_at,
  s.actual_ship_at,
  
  -- Carrier dimensions
  ca.carrier_id,
  ca.carrier_code,
  ca.carrier_name,
  ca.carrier_type,
  
  -- Warehouse dimensions
  w.warehouse_id,
  w.warehouse_code,
  w.warehouse_name,
  w.country AS warehouse_country,
  w.region AS warehouse_region,
  w.city AS warehouse_city,
  
  -- Lane dimensions
  l.lane_id,
  l.origin_country,
  l.origin_region,
  l.origin_city,
  l.dest_country,
  l.dest_region,
  l.dest_city,
  l.distance_km,
  CONCAT(l.origin_city, ' → ', l.dest_city) AS lane_name,
  
  -- Shipment metrics
  shl.shipped_qty,
  
  -- Delivery metrics
  v.actual_delivery_at,
  DATE(v.actual_delivery_at) AS actual_delivery_date,
  
  -- Promise metrics
  pr.promised_ship_date,
  pr.promised_delivery_date AS promised_date,
  
  -- Calculated: Days metrics
  DATEDIFF(DATE(v.actual_delivery_at), pr.promised_delivery_date) AS days_late,
  DATEDIFF(DATE(s.actual_ship_at), pr.promised_ship_date) AS ship_days_late,
  DATEDIFF(DATE(v.actual_delivery_at), DATE(s.actual_ship_at)) AS transit_days,
  
  -- Calculated: OTIF flags
  v.is_on_time,
  v.is_in_full,
  v.is_otif,
  
  -- Calculated: Status labels
  CASE 
    WHEN v.actual_delivery_at IS NULL THEN 'Not Delivered'
    WHEN v.is_otif = 1 THEN 'OTIF'
    WHEN v.is_on_time = 1 AND v.is_in_full = 0 THEN 'On Time - Short Ship'
    WHEN v.is_on_time = 0 AND v.is_in_full = 1 THEN 'Late - Full'
    ELSE 'Late - Short Ship'
  END AS delivery_status,
  
  CASE
    WHEN v.actual_delivery_at IS NULL THEN 'Pending'
    WHEN DATEDIFF(DATE(v.actual_delivery_at), pr.promised_delivery_date) <= 0 THEN 'On Time'
    WHEN DATEDIFF(DATE(v.actual_delivery_at), pr.promised_delivery_date) = 1 THEN '1 Day Late'
    WHEN DATEDIFF(DATE(v.actual_delivery_at), pr.promised_delivery_date) <= 3 THEN '2-3 Days Late'
    ELSE '4+ Days Late'
  END AS lateness_bucket

FROM fact_order_lines ol
JOIN fact_orders o ON o.order_id = ol.order_id
JOIN dim_date d_order ON d_order.date_id = ol.created_date_id
JOIN dim_customer c ON c.customer_id = o.customer_id
JOIN dim_product p ON p.product_id = ol.product_id
JOIN dim_service_level sl ON sl.service_level_id = o.service_level_id
LEFT JOIN fact_promises pr ON pr.order_line_id = ol.order_line_id
LEFT JOIN dim_date d_promise ON d_promise.calendar_date = pr.promised_delivery_date
LEFT JOIN vw_order_line_delivery_status v ON v.order_line_id = ol.order_line_id
LEFT JOIN fact_shipment_lines shl ON shl.order_line_id = ol.order_line_id
LEFT JOIN fact_shipments s ON s.shipment_id = shl.shipment_id
LEFT JOIN dim_carrier ca ON ca.carrier_id = s.carrier_id
LEFT JOIN dim_warehouse w ON w.warehouse_id = s.warehouse_id
LEFT JOIN dim_lane l ON l.lane_id = s.lane_id;

-- ============================================================
-- 2) DAILY METRICS VIEW: Aggregated daily performance
--    Perfect for time series charts
-- ============================================================

CREATE OR REPLACE VIEW vw_tableau_daily_metrics AS
SELECT
  d.calendar_date,
  d.year,
  d.month,
  d.month_name,
  d.week_of_year,
  d.day_of_week,
  d.is_weekend,
  
  -- Volume metrics
  COUNT(DISTINCT t.order_id) AS total_orders,
  COUNT(t.order_line_id) AS total_order_lines,
  SUM(t.ordered_qty) AS total_units_ordered,
  SUM(t.shipped_qty) AS total_units_shipped,
  
  -- OTIF metrics
  SUM(t.is_otif) AS otif_lines,
  SUM(t.is_on_time) AS on_time_lines,
  SUM(t.is_in_full) AS in_full_lines,
  
  -- Rates
  ROUND(SUM(t.is_otif) / NULLIF(COUNT(t.order_line_id), 0), 4) AS otif_rate,
  ROUND(SUM(t.is_on_time) / NULLIF(COUNT(t.order_line_id), 0), 4) AS on_time_rate,
  ROUND(SUM(t.is_in_full) / NULLIF(COUNT(t.order_line_id), 0), 4) AS in_full_rate,
  
  -- Lateness metrics
  ROUND(AVG(t.days_late), 2) AS avg_days_late,
  MAX(t.days_late) AS max_days_late,
  ROUND(AVG(t.transit_days), 2) AS avg_transit_days

FROM vw_tableau_order_delivery t
JOIN dim_date d ON d.calendar_date = t.promised_delivery_date
WHERE t.promised_delivery_date IS NOT NULL
GROUP BY 
  d.calendar_date, d.year, d.month, d.month_name, 
  d.week_of_year, d.day_of_week, d.is_weekend;

-- ============================================================
-- 3) CARRIER METRICS VIEW: Performance by carrier
-- ============================================================

CREATE OR REPLACE VIEW vw_tableau_carrier_metrics AS
SELECT
  t.carrier_id,
  t.carrier_code,
  t.carrier_name,
  t.carrier_type,
  d.calendar_date AS promised_delivery_date,
  d.year,
  d.month,
  d.month_name,
  d.week_of_year,
  
  -- Volume
  COUNT(DISTINCT t.order_id) AS total_orders,
  COUNT(t.order_line_id) AS total_order_lines,
  SUM(t.shipped_qty) AS total_units_shipped,
  
  -- OTIF
  SUM(t.is_otif) AS otif_lines,
  ROUND(SUM(t.is_otif) / NULLIF(COUNT(t.order_line_id), 0), 4) AS otif_rate,
  ROUND(SUM(t.is_on_time) / NULLIF(COUNT(t.order_line_id), 0), 4) AS on_time_rate,
  
  -- Lateness
  ROUND(AVG(t.days_late), 2) AS avg_days_late,
  ROUND(AVG(t.transit_days), 2) AS avg_transit_days

FROM vw_tableau_order_delivery t
JOIN dim_date d ON d.calendar_date = t.promised_delivery_date
WHERE t.carrier_id IS NOT NULL
  AND t.promised_delivery_date IS NOT NULL
GROUP BY 
  t.carrier_id, t.carrier_code, t.carrier_name, t.carrier_type,
  d.calendar_date, d.year, d.month, d.month_name, d.week_of_year;

-- ============================================================
-- 4) WAREHOUSE METRICS VIEW: Performance by warehouse
-- ============================================================

CREATE OR REPLACE VIEW vw_tableau_warehouse_metrics AS
SELECT
  t.warehouse_id,
  t.warehouse_code,
  t.warehouse_name,
  t.warehouse_country,
  t.warehouse_region,
  t.warehouse_city,
  d.calendar_date AS promised_delivery_date,
  d.year,
  d.month,
  d.month_name,
  
  -- Volume
  COUNT(DISTINCT t.order_id) AS total_orders,
  COUNT(t.order_line_id) AS total_order_lines,
  
  -- OTIF
  SUM(t.is_otif) AS otif_lines,
  ROUND(SUM(t.is_otif) / NULLIF(COUNT(t.order_line_id), 0), 4) AS otif_rate,
  ROUND(SUM(t.is_on_time) / NULLIF(COUNT(t.order_line_id), 0), 4) AS on_time_rate,
  
  -- Lateness
  ROUND(AVG(t.days_late), 2) AS avg_days_late

FROM vw_tableau_order_delivery t
JOIN dim_date d ON d.calendar_date = t.promised_delivery_date
WHERE t.warehouse_id IS NOT NULL
  AND t.promised_delivery_date IS NOT NULL
GROUP BY 
  t.warehouse_id, t.warehouse_code, t.warehouse_name,
  t.warehouse_country, t.warehouse_region, t.warehouse_city,
  d.calendar_date, d.year, d.month, d.month_name;

-- ============================================================
-- 5) LANE METRICS VIEW: Performance by shipping lane
-- ============================================================

CREATE OR REPLACE VIEW vw_tableau_lane_metrics AS
SELECT
  t.lane_id,
  t.lane_name,
  t.origin_country,
  t.origin_city,
  t.dest_country,
  t.dest_city,
  t.distance_km,
  d.calendar_date AS promised_delivery_date,
  d.year,
  d.month,
  
  -- Volume
  COUNT(t.order_line_id) AS total_order_lines,
  
  -- OTIF
  SUM(t.is_otif) AS otif_lines,
  ROUND(SUM(t.is_otif) / NULLIF(COUNT(t.order_line_id), 0), 4) AS otif_rate,
  
  -- Lateness
  ROUND(AVG(t.days_late), 2) AS avg_days_late,
  ROUND(AVG(t.transit_days), 2) AS avg_transit_days

FROM vw_tableau_order_delivery t
JOIN dim_date d ON d.calendar_date = t.promised_delivery_date
WHERE t.lane_id IS NOT NULL
  AND t.promised_delivery_date IS NOT NULL
GROUP BY 
  t.lane_id, t.lane_name, t.origin_country, t.origin_city,
  t.dest_country, t.dest_city, t.distance_km,
  d.calendar_date, d.year, d.month;

-- ============================================================
-- 6) CUSTOMER METRICS VIEW: Performance by customer segment
-- ============================================================

CREATE OR REPLACE VIEW vw_tableau_customer_metrics AS
SELECT
  t.customer_segment,
  t.customer_country,
  t.customer_region,
  d.calendar_date AS promised_delivery_date,
  d.year,
  d.month,
  d.month_name,
  
  -- Volume
  COUNT(DISTINCT t.customer_id) AS unique_customers,
  COUNT(DISTINCT t.order_id) AS total_orders,
  COUNT(t.order_line_id) AS total_order_lines,
  SUM(t.ordered_qty) AS total_units_ordered,
  
  -- OTIF
  SUM(t.is_otif) AS otif_lines,
  ROUND(SUM(t.is_otif) / NULLIF(COUNT(t.order_line_id), 0), 4) AS otif_rate,
  
  -- Lateness
  ROUND(AVG(t.days_late), 2) AS avg_days_late

FROM vw_tableau_order_delivery t
JOIN dim_date d ON d.calendar_date = t.promised_delivery_date
WHERE t.promised_delivery_date IS NOT NULL
GROUP BY 
  t.customer_segment, t.customer_country, t.customer_region,
  d.calendar_date, d.year, d.month, d.month_name;

-- ============================================================
-- 7) SERVICE LEVEL METRICS VIEW: Performance by service tier
-- ============================================================

CREATE OR REPLACE VIEW vw_tableau_service_level_metrics AS
SELECT
  t.service_level_code,
  t.service_level_name,
  t.service_level_days,
  d.calendar_date AS promised_delivery_date,
  d.year,
  d.month,
  
  -- Volume
  COUNT(DISTINCT t.order_id) AS total_orders,
  COUNT(t.order_line_id) AS total_order_lines,
  
  -- OTIF
  SUM(t.is_otif) AS otif_lines,
  ROUND(SUM(t.is_otif) / NULLIF(COUNT(t.order_line_id), 0), 4) AS otif_rate,
  ROUND(SUM(t.is_on_time) / NULLIF(COUNT(t.order_line_id), 0), 4) AS on_time_rate,
  
  -- Lateness
  ROUND(AVG(t.days_late), 2) AS avg_days_late,
  ROUND(AVG(t.transit_days), 2) AS avg_transit_days

FROM vw_tableau_order_delivery t
JOIN dim_date d ON d.calendar_date = t.promised_delivery_date
WHERE t.promised_delivery_date IS NOT NULL
GROUP BY 
  t.service_level_code, t.service_level_name, t.service_level_days,
  d.calendar_date, d.year, d.month;

-- ============================================================
-- 8) TRACKING EVENTS VIEW: For shipment journey visualization
-- ============================================================

CREATE OR REPLACE VIEW vw_tableau_tracking_events AS
SELECT
  te.event_id,
  te.shipment_id,
  te.event_type,
  te.event_time,
  te.event_city,
  te.event_country,
  d.calendar_date AS event_date,
  d.year AS event_year,
  d.month AS event_month,
  d.day_of_week AS event_day_of_week,
  HOUR(te.event_time) AS event_hour,
  
  -- Shipment info
  s.shipment_created_at,
  s.actual_ship_at,
  
  -- Carrier
  ca.carrier_name,
  
  -- Warehouse
  w.warehouse_name,
  
  -- Lane
  l.origin_city,
  l.dest_city,
  CONCAT(l.origin_city, ' → ', l.dest_city) AS lane_name,
  
  -- Time since shipment
  TIMESTAMPDIFF(HOUR, s.actual_ship_at, te.event_time) AS hours_since_ship

FROM fact_tracking_events te
JOIN dim_date d ON d.date_id = te.event_date_id
JOIN fact_shipments s ON s.shipment_id = te.shipment_id
JOIN dim_carrier ca ON ca.carrier_id = s.carrier_id
JOIN dim_warehouse w ON w.warehouse_id = s.warehouse_id
JOIN dim_lane l ON l.lane_id = s.lane_id;

-- ============================================================
-- 9) DATA QUALITY VIEW: For monitoring dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_tableau_data_quality AS
SELECT 'Missing Promise' AS issue_type, COUNT(*) AS issue_count, 'High' AS severity
FROM dq_missing_or_invalid_promise
UNION ALL
SELECT 'Missing Delivery Event', COUNT(*), 'Medium'
FROM vw_order_line_delivery_status WHERE actual_delivery_at IS NULL
UNION ALL
SELECT 'Invalid Order Qty', COUNT(*), 'High'
FROM dq_invalid_ordered_qty
UNION ALL
SELECT 'Orphaned Order Line', COUNT(*), 'Critical'
FROM dq_order_line_without_order
UNION ALL
SELECT 'Delivered Before Shipped', COUNT(*), 'Critical'
FROM dq_delivered_before_shipped
UNION ALL
SELECT 'Duplicate Tracking Event', COUNT(*), 'Low'
FROM dq_duplicate_tracking_events;

-- ============================================================
-- VERIFICATION
-- ============================================================
SELECT '=== TABLEAU VIEWS CREATED ===' AS status;

SELECT 'vw_tableau_order_delivery' AS view_name, COUNT(*) AS row_count FROM vw_tableau_order_delivery
UNION ALL SELECT 'vw_tableau_daily_metrics', COUNT(*) FROM vw_tableau_daily_metrics
UNION ALL SELECT 'vw_tableau_carrier_metrics', COUNT(*) FROM vw_tableau_carrier_metrics
UNION ALL SELECT 'vw_tableau_warehouse_metrics', COUNT(*) FROM vw_tableau_warehouse_metrics
UNION ALL SELECT 'vw_tableau_lane_metrics', COUNT(*) FROM vw_tableau_lane_metrics
UNION ALL SELECT 'vw_tableau_customer_metrics', COUNT(*) FROM vw_tableau_customer_metrics
UNION ALL SELECT 'vw_tableau_service_level_metrics', COUNT(*) FROM vw_tableau_service_level_metrics
UNION ALL SELECT 'vw_tableau_tracking_events', COUNT(*) FROM vw_tableau_tracking_events
UNION ALL SELECT 'vw_tableau_data_quality', COUNT(*) FROM vw_tableau_data_quality;
