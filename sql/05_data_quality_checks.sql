-- Delivery Performance Analytics
-- 05_data_quality_checks.sql
-- Data quality and KPI trust checks (read-only views)

-- ============================================================
-- 1) Order-line without order
-- ============================================================

CREATE OR REPLACE VIEW dq_order_line_without_order AS
SELECT
  'DQ_ORD_001' AS rule_id,
  'Order line without matching order' AS rule_description,
  ol.order_line_id,
  ol.order_id
FROM fact_order_lines ol
LEFT JOIN fact_orders o
  ON o.order_id = ol.order_id
WHERE o.order_id IS NULL;

-- ============================================================
-- 2) Invalid ordered quantity
-- ============================================================

CREATE OR REPLACE VIEW dq_invalid_ordered_qty AS
SELECT
  'DQ_ORD_002' AS rule_id,
  'Ordered quantity is zero or negative' AS rule_description,
  order_line_id,
  ordered_qty
FROM fact_order_lines
WHERE ordered_qty <= 0;

-- ============================================================
-- 3) Missing or invalid promise
-- ============================================================

CREATE OR REPLACE VIEW dq_missing_or_invalid_promise AS
SELECT
  'DQ_PRM_001' AS rule_id,
  'Missing or invalid promise dates' AS rule_description,
  ol.order_line_id,
  pr.promised_ship_date,
  pr.promised_delivery_date
FROM fact_order_lines ol
LEFT JOIN fact_promises pr
  ON pr.order_line_id = ol.order_line_id
WHERE pr.order_line_id IS NULL
   OR pr.promised_delivery_date < pr.promised_ship_date;

-- ============================================================
-- 4) Shipment line without valid links
-- ============================================================

CREATE OR REPLACE VIEW dq_shipment_line_integrity AS
SELECT
  'DQ_SHP_001' AS rule_id,
  'Shipment line without valid shipment or order line' AS rule_description,
  sl.shipment_line_id,
  sl.shipment_id,
  sl.order_line_id
FROM fact_shipment_lines sl
LEFT JOIN fact_shipments s
  ON s.shipment_id = sl.shipment_id
LEFT JOIN fact_order_lines ol
  ON ol.order_line_id = sl.order_line_id
WHERE s.shipment_id IS NULL
   OR ol.order_line_id IS NULL;

-- ============================================================
-- 5) Delivered event before shipment creation
-- ============================================================

CREATE OR REPLACE VIEW dq_delivered_before_shipped AS
SELECT
  'DQ_EVT_001' AS rule_id,
  'Delivered event occurs before shipment creation' AS rule_description,
  te.shipment_id,
  te.event_time,
  s.shipment_created_at
FROM fact_tracking_events te
JOIN fact_shipments s
  ON s.shipment_id = te.shipment_id
WHERE te.event_type = 'DELIVERED'
  AND te.event_time < s.shipment_created_at;

-- ============================================================
-- 6) Duplicate tracking events (natural key violation)
-- ============================================================

CREATE OR REPLACE VIEW dq_duplicate_tracking_events AS
SELECT
  'DQ_EVT_002' AS rule_id,
  'Duplicate tracking events detected' AS rule_description,
  shipment_id,
  event_type,
  event_time,
  COUNT(*) AS duplicate_count
FROM fact_tracking_events
GROUP BY shipment_id, event_type, event_time
HAVING COUNT(*) > 1;

-- ============================================================
-- 7) KPI risk exposure summary
-- ============================================================

CREATE OR REPLACE VIEW dq_kpi_risk_summary AS
SELECT 'MISSING_PROMISE' AS risk_type, COUNT(*) AS affected_rows
FROM dq_missing_or_invalid_promise
UNION ALL
SELECT 'MISSING_DELIVERY_EVENT', COUNT(*)
FROM vw_order_line_delivery_status
WHERE actual_delivery_at IS NULL
UNION ALL
SELECT 'INVALID_ORDER_QTY', COUNT(*)
FROM dq_invalid_ordered_qty;

