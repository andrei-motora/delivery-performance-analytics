-- Delivery Performance Analytics
-- 04_kpi_views.sql
-- Analytical KPI views built on warehouse facts

-- ============================================================
-- 1) Order-line delivery status (authoritative base view)
-- ============================================================

CREATE OR REPLACE VIEW vw_order_line_delivery_status AS
WITH delivered_events AS (
  SELECT
    te.shipment_id,
    MIN(te.event_time) AS delivered_at
  FROM fact_tracking_events te
  WHERE te.event_type = 'DELIVERED'
  GROUP BY te.shipment_id
),
shipment_delivery AS (
  SELECT
    sl.order_line_id,
    MIN(de.delivered_at) AS actual_delivery_at,
    SUM(sl.shipped_qty) AS total_shipped_qty
  FROM fact_shipment_lines sl
  LEFT JOIN delivered_events de
    ON de.shipment_id = sl.shipment_id
  GROUP BY sl.order_line_id
)
SELECT
  ol.order_line_id,
  ol.order_id,
  ol.line_number,
  ol.ordered_qty,
  sd.total_shipped_qty,
  sd.actual_delivery_at,
  pr.promised_delivery_date,
  CASE
    WHEN sd.actual_delivery_at IS NOT NULL
     AND DATE(sd.actual_delivery_at) <= pr.promised_delivery_date
    THEN 1 ELSE 0
  END AS is_on_time,
  CASE
    WHEN sd.total_shipped_qty >= ol.ordered_qty
    THEN 1 ELSE 0
  END AS is_in_full,
  CASE
    WHEN
      sd.actual_delivery_at IS NOT NULL
      AND DATE(sd.actual_delivery_at) <= pr.promised_delivery_date
      AND sd.total_shipped_qty >= ol.ordered_qty
    THEN 1 ELSE 0
  END AS is_otif
FROM fact_order_lines ol
LEFT JOIN shipment_delivery sd
  ON sd.order_line_id = ol.order_line_id
LEFT JOIN fact_promises pr
  ON pr.order_line_id = ol.order_line_id;

-- ============================================================
-- 2) Overall OTIF KPI
-- ============================================================

CREATE OR REPLACE VIEW vw_kpi_otif AS
SELECT
  dd.calendar_date AS promised_delivery_date,
  COUNT(*) AS order_lines,
  SUM(is_otif) AS otif_lines,
  ROUND(SUM(is_otif) / NULLIF(COUNT(*), 0), 4) AS otif_rate
FROM vw_order_line_delivery_status v
JOIN dim_date dd
  ON dd.calendar_date = v.promised_delivery_date
GROUP BY dd.calendar_date;

-- ============================================================
-- 3) Carrier performance
-- ============================================================

CREATE OR REPLACE VIEW vw_carrier_performance AS
SELECT
  c.carrier_name,
  COUNT(DISTINCT v.order_line_id) AS order_lines,
  SUM(v.is_otif) AS otif_lines,
  ROUND(SUM(v.is_otif) / NULLIF(COUNT(DISTINCT v.order_line_id), 0), 4) AS otif_rate
FROM vw_order_line_delivery_status v
JOIN fact_shipment_lines sl
  ON sl.order_line_id = v.order_line_id
JOIN fact_shipments s
  ON s.shipment_id = sl.shipment_id
JOIN dim_carrier c
  ON c.carrier_id = s.carrier_id
GROUP BY c.carrier_name;

-- ============================================================
-- 4) Lane performance
-- ============================================================

CREATE OR REPLACE VIEW vw_lane_performance AS
SELECT
  CONCAT(l.origin_city, ' → ', l.dest_city) AS lane,
  COUNT(DISTINCT v.order_line_id) AS order_lines,
  SUM(v.is_otif) AS otif_lines,
  ROUND(SUM(v.is_otif) / NULLIF(COUNT(DISTINCT v.order_line_id), 0), 4) AS otif_rate
FROM vw_order_line_delivery_status v
JOIN fact_shipment_lines sl
  ON sl.order_line_id = v.order_line_id
JOIN fact_shipments s
  ON s.shipment_id = sl.shipment_id
JOIN dim_lane l
  ON l.lane_id = s.lane_id
GROUP BY l.origin_city, l.dest_city;

-- ============================================================
-- 5) Warehouse performance
-- ============================================================

CREATE OR REPLACE VIEW vw_warehouse_performance AS
SELECT
  w.warehouse_name,
  COUNT(DISTINCT v.order_line_id) AS order_lines,
  SUM(v.is_otif) AS otif_lines,
  ROUND(SUM(v.is_otif) / NULLIF(COUNT(DISTINCT v.order_line_id), 0), 4) AS otif_rate
FROM vw_order_line_delivery_status v
JOIN fact_shipment_lines sl
  ON sl.order_line_id = v.order_line_id
JOIN fact_shipments s
  ON s.shipment_id = sl.shipment_id
JOIN dim_warehouse w
  ON w.warehouse_id = s.warehouse_id
GROUP BY w.warehouse_name;

