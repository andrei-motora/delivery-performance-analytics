-- Delivery Performance Analytics
-- 06_sample_data.sql
-- Generates realistic sample data for testing and demonstration
-- 
-- Prerequisites: Run scripts 01-05 first
-- Run order: 01_schema.sql → 02_seed_dimensions.sql → 03_incremental_load.sql 
--            → 04_kpi_views.sql → 05_data_quality_checks.sql → THIS SCRIPT
--
-- Generated data:
--   - ~1,050 orders across 21 days (configurable)
--   - ~1,890 order lines (1-4 lines per order)
--   - ~1,009 shipments with full tracking event sequences
--   - ~85% on-time delivery rate, ~10% one day late, ~5% two+ days late

-- ============================================================
-- CONFIGURATION
-- Adjust these variables to control data volume and date range
-- ============================================================
SET @start_date = '2025-01-01';
SET @end_date = '2025-01-21';
SET @orders_per_day = 50;
SET SESSION cte_max_recursion_depth = 5000;

-- ============================================================
-- CLEANUP (optional - uncomment to clear existing data)
-- ============================================================
-- SET FOREIGN_KEY_CHECKS = 0;
-- TRUNCATE TABLE fact_tracking_events;
-- TRUNCATE TABLE fact_shipment_lines;
-- TRUNCATE TABLE fact_shipments;
-- TRUNCATE TABLE fact_promises;
-- TRUNCATE TABLE fact_order_lines;
-- TRUNCATE TABLE fact_orders;
-- TRUNCATE TABLE stg_tracking_events;
-- TRUNCATE TABLE stg_shipment_lines;
-- TRUNCATE TABLE stg_shipments;
-- TRUNCATE TABLE stg_promises;
-- TRUNCATE TABLE stg_order_lines;
-- TRUNCATE TABLE stg_orders;
-- TRUNCATE TABLE etl_table_audit;
-- TRUNCATE TABLE etl_run_audit;
-- SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- HELPER: Sequence table for data generation
-- ============================================================
DROP TEMPORARY TABLE IF EXISTS tmp_seq;
CREATE TEMPORARY TABLE tmp_seq (n INT NOT NULL PRIMARY KEY);
INSERT INTO tmp_seq (n)
WITH RECURSIVE seq AS (
  SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 2000
)
SELECT n FROM seq;

-- ============================================================
-- STAGE 1: Populate staging tables
-- ============================================================

-- 1.1) stg_orders
TRUNCATE TABLE stg_orders;
INSERT INTO stg_orders (order_id, customer_code, service_level_code, order_created_at, order_status, run_date)
WITH date_range AS (
  SELECT calendar_date FROM dim_date 
  WHERE calendar_date BETWEEN @start_date AND @end_date
)
SELECT
  (CAST(DATE_FORMAT(dr.calendar_date, '%Y%m%d') AS UNSIGNED) * 10000 + s.n) AS order_id,
  CONCAT('CUST_', LPAD(FLOOR(1 + (s.n * 7 + DATEDIFF(dr.calendar_date, @start_date) * 13) % 75), 3, '0')) AS customer_code,
  CASE WHEN (s.n + DATEDIFF(dr.calendar_date, @start_date)) % 10 < 7 THEN 'STANDARD' ELSE 'EXPRESS' END AS service_level_code,
  ADDTIME(dr.calendar_date, SEC_TO_TIME(21600 + ((s.n * 1234 + DATEDIFF(dr.calendar_date, @start_date) * 5678) % 57600))) AS order_created_at,
  'CLOSED' AS order_status,
  dr.calendar_date AS run_date
FROM date_range dr
CROSS JOIN tmp_seq s
WHERE s.n <= @orders_per_day;

SELECT CONCAT('stg_orders: ', COUNT(*), ' rows') AS status FROM stg_orders;

-- 1.2) stg_order_lines (1-4 lines per order based on order_id)
TRUNCATE TABLE stg_order_lines;
INSERT INTO stg_order_lines (order_id, line_number, sku, ordered_qty, line_status, order_line_created_at, run_date)
WITH lines_per_order AS (
  SELECT 
    order_id, order_created_at, run_date,
    CASE 
      WHEN order_id % 10 < 5 THEN 1
      WHEN order_id % 10 < 8 THEN 2
      WHEN order_id % 10 < 9 THEN 3
      ELSE 4
    END AS num_lines
  FROM stg_orders
)
SELECT
  lpo.order_id,
  s.n AS line_number,
  CONCAT('SKU_', LPAD(((lpo.order_id * 7 + s.n * 13) % 150) + 1, 3, '0')) AS sku,
  ((lpo.order_id * 3 + s.n * 17) % 20) + 1 AS ordered_qty,
  'CLOSED' AS line_status,
  lpo.order_created_at AS order_line_created_at,
  lpo.run_date
FROM lines_per_order lpo
CROSS JOIN tmp_seq s
WHERE s.n <= lpo.num_lines;

SELECT CONCAT('stg_order_lines: ', COUNT(*), ' rows') AS status FROM stg_order_lines;

-- 1.3) stg_promises
TRUNCATE TABLE stg_promises;
INSERT INTO stg_promises (order_id, line_number, promised_ship_date, promised_delivery_date, promise_updated_at, run_date)
SELECT
  ol.order_id,
  ol.line_number,
  DATE_ADD(DATE(ol.order_line_created_at), INTERVAL (ol.line_number % 2) DAY) AS promised_ship_date,
  DATE_ADD(
    DATE_ADD(DATE(ol.order_line_created_at), INTERVAL (ol.line_number % 2) DAY),
    INTERVAL CASE WHEN o.service_level_code = 'EXPRESS' THEN 1 ELSE 3 END DAY
  ) AS promised_delivery_date,
  ol.order_line_created_at AS promise_updated_at,
  ol.run_date
FROM stg_order_lines ol
JOIN stg_orders o ON o.order_id = ol.order_id AND o.run_date = ol.run_date;

SELECT CONCAT('stg_promises: ', COUNT(*), ' rows') AS status FROM stg_promises;

-- 1.4) stg_shipments
TRUNCATE TABLE stg_shipments;
INSERT INTO stg_shipments (
  shipment_id, carrier_code, warehouse_code,
  origin_country, origin_region, origin_city,
  dest_country, dest_region, dest_city, distance_km,
  shipment_created_at, actual_ship_at, run_date
)
WITH warehouse_mapping AS (
  SELECT 1 AS wh_idx, 'WH_NL_01' AS warehouse_code, 'Netherlands' AS origin_country, 'Noord-Brabant' AS origin_region, 'Eindhoven' AS origin_city UNION ALL
  SELECT 2, 'WH_NL_02', 'Netherlands', 'Limburg', 'Venlo' UNION ALL
  SELECT 3, 'WH_NL_03', 'Netherlands', 'Zuid-Holland', 'Rotterdam' UNION ALL
  SELECT 4, 'WH_NL_04', 'Netherlands', 'Utrecht', 'Utrecht' UNION ALL
  SELECT 5, 'WH_BE_01', 'Belgium', 'Flanders', 'Antwerp' UNION ALL
  SELECT 6, 'WH_DE_01', 'Germany', 'North Rhine-Westphalia', 'Duisburg'
),
carrier_mapping AS (
  SELECT 1 AS c_idx, 'DHL' AS carrier_code UNION ALL
  SELECT 2, 'DPD' UNION ALL
  SELECT 3, 'POSTNL' UNION ALL
  SELECT 4, 'GLS' UNION ALL
  SELECT 5, 'UPS' UNION ALL
  SELECT 6, 'BPOST'
),
dest_mapping AS (
  SELECT 1 AS d_idx, 'Netherlands' AS dest_country, 'Noord-Holland' AS dest_region, 'Amsterdam' AS dest_city UNION ALL
  SELECT 2, 'Netherlands', 'Zuid-Holland', 'Rotterdam' UNION ALL
  SELECT 3, 'Netherlands', 'Zuid-Holland', 'The Hague' UNION ALL
  SELECT 4, 'Netherlands', 'Utrecht', 'Utrecht' UNION ALL
  SELECT 5, 'Netherlands', 'Noord-Brabant', 'Tilburg' UNION ALL
  SELECT 6, 'Netherlands', 'Gelderland', 'Arnhem' UNION ALL
  SELECT 7, 'Netherlands', 'Overijssel', 'Zwolle' UNION ALL
  SELECT 8, 'Belgium', 'Flanders', 'Ghent' UNION ALL
  SELECT 9, 'Belgium', 'Flanders', 'Antwerp' UNION ALL
  SELECT 10, 'Belgium', 'Brussels-Capital', 'Brussels' UNION ALL
  SELECT 11, 'Germany', 'North Rhine-Westphalia', 'Cologne' UNION ALL
  SELECT 12, 'Germany', 'North Rhine-Westphalia', 'Düsseldorf' UNION ALL
  SELECT 13, 'Germany', 'Hesse', 'Frankfurt'
)
SELECT DISTINCT
  (o.order_id * 10 + 1) AS shipment_id,
  cm.carrier_code,
  wm.warehouse_code,
  wm.origin_country, wm.origin_region, wm.origin_city,
  dm.dest_country, dm.dest_region, dm.dest_city,
  ROUND(80 + (o.order_id % 371), 0) AS distance_km,
  DATE_ADD(o.order_created_at, INTERVAL (2 + o.order_id % 6) HOUR) AS shipment_created_at,
  DATE_ADD(o.order_created_at, INTERVAL (3 + o.order_id % 5) HOUR) AS actual_ship_at,
  o.run_date
FROM stg_orders o
JOIN warehouse_mapping wm ON wm.wh_idx = (o.order_id % 6) + 1
JOIN carrier_mapping cm ON cm.c_idx = (o.order_id % 6) + 1
JOIN dest_mapping dm ON dm.d_idx = (o.order_id % 13) + 1
WHERE NOT (wm.origin_city = dm.dest_city AND wm.origin_country = dm.dest_country);

SELECT CONCAT('stg_shipments: ', COUNT(*), ' rows') AS status FROM stg_shipments;

-- 1.5) stg_shipment_lines
TRUNCATE TABLE stg_shipment_lines;
INSERT INTO stg_shipment_lines (shipment_id, order_id, line_number, shipped_qty, run_date)
SELECT
  (ol.order_id * 10 + 1) AS shipment_id,
  ol.order_id,
  ol.line_number,
  ol.ordered_qty AS shipped_qty,
  ol.run_date
FROM stg_order_lines ol
WHERE EXISTS (
  SELECT 1 FROM stg_shipments s 
  WHERE s.shipment_id = (ol.order_id * 10 + 1) AND s.run_date = ol.run_date
);

SELECT CONCAT('stg_shipment_lines: ', COUNT(*), ' rows') AS status FROM stg_shipment_lines;

-- 1.6) stg_tracking_events
TRUNCATE TABLE stg_tracking_events;
INSERT INTO stg_tracking_events (shipment_id, event_type, event_time, event_city, event_country, ingested_at, run_date)
WITH event_defs AS (
  SELECT 1 AS seq, 'PICKED_UP' AS event_type, 0 AS hours_add UNION ALL
  SELECT 2, 'IN_TRANSIT', 4 UNION ALL
  SELECT 3, 'AT_HUB', 12 UNION ALL
  SELECT 4, 'OUT_FOR_DELIVERY', 24 UNION ALL
  SELECT 5, 'DELIVERED', 28
)
SELECT
  s.shipment_id,
  ed.event_type,
  DATE_ADD(s.actual_ship_at, INTERVAL (
    ed.hours_add + 
    CASE 
      WHEN ed.event_type = 'DELIVERED' AND s.shipment_id % 100 >= 85 AND s.shipment_id % 100 < 95 THEN 24
      WHEN ed.event_type = 'DELIVERED' AND s.shipment_id % 100 >= 95 THEN 48
      ELSE 0
    END
  ) HOUR) AS event_time,
  CASE 
    WHEN ed.seq <= 2 THEN s.origin_city
    WHEN ed.seq = 3 THEN 'Distribution Hub'
    ELSE s.dest_city
  END AS event_city,
  CASE 
    WHEN ed.seq <= 2 THEN s.origin_country
    ELSE s.dest_country
  END AS event_country,
  DATE_ADD(s.actual_ship_at, INTERVAL (
    ed.hours_add + 
    CASE 
      WHEN ed.event_type = 'DELIVERED' AND s.shipment_id % 100 >= 85 AND s.shipment_id % 100 < 95 THEN 24
      WHEN ed.event_type = 'DELIVERED' AND s.shipment_id % 100 >= 95 THEN 48
      ELSE 0
    END + (s.shipment_id % 30) / 60.0
  ) HOUR) AS ingested_at,
  s.run_date
FROM stg_shipments s
CROSS JOIN event_defs ed;

SELECT CONCAT('stg_tracking_events: ', COUNT(*), ' rows') AS status FROM stg_tracking_events;

-- ============================================================
-- STAGE 2: Run ETL stored procedure for each day
-- ============================================================
DROP PROCEDURE IF EXISTS sp_load_all_days;
DELIMITER $$
CREATE PROCEDURE sp_load_all_days(IN p_start DATE, IN p_end DATE)
BEGIN
  DECLARE v_date DATE DEFAULT p_start;
  WHILE v_date <= p_end DO
    CALL sp_run_daily_load(v_date, 3);
    SET v_date = DATE_ADD(v_date, INTERVAL 1 DAY);
  END WHILE;
END$$
DELIMITER ;

CALL sp_load_all_days(@start_date, @end_date);
DROP PROCEDURE IF EXISTS sp_load_all_days;

-- ============================================================
-- STAGE 3: Add tracking events directly to fact table
-- (Ensures all shipments have complete event sequences)
-- ============================================================

-- PICKED_UP events
INSERT INTO fact_tracking_events 
  (shipment_id, event_type, event_time, ingested_at, event_city, event_country, event_date_id)
SELECT 
  s.shipment_id, 'PICKED_UP', s.actual_ship_at,
  DATE_ADD(s.actual_ship_at, INTERVAL 5 MINUTE),
  l.origin_city, l.origin_country,
  CAST(DATE_FORMAT(s.actual_ship_at, '%Y%m%d') AS UNSIGNED)
FROM fact_shipments s
JOIN dim_lane l ON l.lane_id = s.lane_id
WHERE NOT EXISTS (
  SELECT 1 FROM fact_tracking_events te 
  WHERE te.shipment_id = s.shipment_id AND te.event_type = 'PICKED_UP'
);

-- IN_TRANSIT events
INSERT INTO fact_tracking_events 
  (shipment_id, event_type, event_time, ingested_at, event_city, event_country, event_date_id)
SELECT 
  s.shipment_id, 'IN_TRANSIT',
  DATE_ADD(s.actual_ship_at, INTERVAL 4 HOUR),
  DATE_ADD(s.actual_ship_at, INTERVAL 245 MINUTE),
  l.origin_city, l.origin_country,
  CAST(DATE_FORMAT(DATE_ADD(s.actual_ship_at, INTERVAL 4 HOUR), '%Y%m%d') AS UNSIGNED)
FROM fact_shipments s
JOIN dim_lane l ON l.lane_id = s.lane_id
WHERE NOT EXISTS (
  SELECT 1 FROM fact_tracking_events te 
  WHERE te.shipment_id = s.shipment_id AND te.event_type = 'IN_TRANSIT'
);

-- AT_HUB events
INSERT INTO fact_tracking_events 
  (shipment_id, event_type, event_time, ingested_at, event_city, event_country, event_date_id)
SELECT 
  s.shipment_id, 'AT_HUB',
  DATE_ADD(s.actual_ship_at, INTERVAL 12 HOUR),
  DATE_ADD(s.actual_ship_at, INTERVAL 725 MINUTE),
  'Distribution Hub', l.dest_country,
  CAST(DATE_FORMAT(DATE_ADD(s.actual_ship_at, INTERVAL 12 HOUR), '%Y%m%d') AS UNSIGNED)
FROM fact_shipments s
JOIN dim_lane l ON l.lane_id = s.lane_id
WHERE NOT EXISTS (
  SELECT 1 FROM fact_tracking_events te 
  WHERE te.shipment_id = s.shipment_id AND te.event_type = 'AT_HUB'
);

-- OUT_FOR_DELIVERY events
INSERT INTO fact_tracking_events 
  (shipment_id, event_type, event_time, ingested_at, event_city, event_country, event_date_id)
SELECT 
  s.shipment_id, 'OUT_FOR_DELIVERY',
  DATE_ADD(s.actual_ship_at, INTERVAL 24 HOUR),
  DATE_ADD(s.actual_ship_at, INTERVAL 1445 MINUTE),
  l.dest_city, l.dest_country,
  CAST(DATE_FORMAT(DATE_ADD(s.actual_ship_at, INTERVAL 24 HOUR), '%Y%m%d') AS UNSIGNED)
FROM fact_shipments s
JOIN dim_lane l ON l.lane_id = s.lane_id
WHERE NOT EXISTS (
  SELECT 1 FROM fact_tracking_events te 
  WHERE te.shipment_id = s.shipment_id AND te.event_type = 'OUT_FOR_DELIVERY'
);

-- DELIVERED events (with delay distribution: 85% on-time, 10% +1 day, 5% +2 days)
INSERT INTO fact_tracking_events 
  (shipment_id, event_type, event_time, ingested_at, event_city, event_country, event_date_id)
SELECT 
  s.shipment_id, 'DELIVERED',
  DATE_ADD(s.actual_ship_at, INTERVAL (28 + 
    CASE 
      WHEN s.shipment_id % 100 >= 85 AND s.shipment_id % 100 < 95 THEN 24
      WHEN s.shipment_id % 100 >= 95 THEN 48
      ELSE 0
    END) HOUR),
  DATE_ADD(s.actual_ship_at, INTERVAL (28 + 
    CASE 
      WHEN s.shipment_id % 100 >= 85 AND s.shipment_id % 100 < 95 THEN 24
      WHEN s.shipment_id % 100 >= 95 THEN 48
      ELSE 0
    END + 0.1) HOUR),
  l.dest_city, l.dest_country,
  CAST(DATE_FORMAT(DATE_ADD(s.actual_ship_at, INTERVAL (28 + 
    CASE 
      WHEN s.shipment_id % 100 >= 85 AND s.shipment_id % 100 < 95 THEN 24
      WHEN s.shipment_id % 100 >= 95 THEN 48
      ELSE 0
    END) HOUR), '%Y%m%d') AS UNSIGNED)
FROM fact_shipments s
JOIN dim_lane l ON l.lane_id = s.lane_id
WHERE NOT EXISTS (
  SELECT 1 FROM fact_tracking_events te 
  WHERE te.shipment_id = s.shipment_id AND te.event_type = 'DELIVERED'
);

-- ============================================================
-- CLEANUP
-- ============================================================
DROP TEMPORARY TABLE IF EXISTS tmp_seq;

-- ============================================================
-- VERIFICATION
-- ============================================================
SELECT '========================================' AS '';
SELECT 'SAMPLE DATA POPULATION COMPLETE' AS status;
SELECT '========================================' AS '';

SELECT 'FACT TABLE ROW COUNTS' AS report;
SELECT 'fact_orders' AS table_name, COUNT(*) AS row_count FROM fact_orders
UNION ALL SELECT 'fact_order_lines', COUNT(*) FROM fact_order_lines
UNION ALL SELECT 'fact_promises', COUNT(*) FROM fact_promises  
UNION ALL SELECT 'fact_shipments', COUNT(*) FROM fact_shipments
UNION ALL SELECT 'fact_shipment_lines', COUNT(*) FROM fact_shipment_lines
UNION ALL SELECT 'fact_tracking_events', COUNT(*) FROM fact_tracking_events;

SELECT 'TRACKING EVENTS BY TYPE' AS report;
SELECT event_type, COUNT(*) AS event_count 
FROM fact_tracking_events 
GROUP BY event_type 
ORDER BY event_type;

SELECT 'SAMPLE OTIF METRICS (first 10 days)' AS report;
SELECT * FROM vw_kpi_otif 
WHERE order_lines > 0 
ORDER BY promised_delivery_date 
LIMIT 10;

SELECT 'CARRIER PERFORMANCE' AS report;
SELECT * FROM vw_carrier_performance ORDER BY otif_rate DESC;

SELECT 'WAREHOUSE PERFORMANCE' AS report;
SELECT * FROM vw_warehouse_performance ORDER BY otif_rate DESC;

SELECT 'DATA QUALITY SUMMARY' AS report;
SELECT * FROM dq_kpi_risk_summary;
