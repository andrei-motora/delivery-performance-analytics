-- Delivery Performance Analytics
-- 03_incremental_load.sql
-- Creates staging + audit tables and a stored procedure for daily incremental loads

-- Requires:
--   sql/01_schema.sql (warehouse tables)
--   sql/02_seed_dimensions.sql (at least service levels + dates)

-- ============================================================
-- 1) Audit tables
-- ============================================================

CREATE TABLE IF NOT EXISTS etl_run_audit (
  run_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  run_date DATE NOT NULL,
  reprocess_days INT NOT NULL,
  started_at DATETIME NOT NULL,
  finished_at DATETIME NULL,
  status VARCHAR(20) NOT NULL,         -- STARTED/SUCCESS/FAILED
  error_message TEXT NULL,
  UNIQUE KEY uq_etl_run_audit (run_date, started_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS etl_table_audit (
  table_audit_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  run_id BIGINT NOT NULL,
  table_name VARCHAR(64) NOT NULL,
  inserted_rows INT NOT NULL,
  updated_rows INT NOT NULL,
  notes VARCHAR(255) NULL,
  created_at DATETIME NOT NULL,
  KEY idx_etl_table_audit_run (run_id),
  CONSTRAINT fk_etl_table_audit_run
    FOREIGN KEY (run_id) REFERENCES etl_run_audit(run_id)
) ENGINE=InnoDB;

-- ============================================================
-- 2) Staging tables (daily drops)
-- ============================================================

CREATE TABLE IF NOT EXISTS stg_orders (
  order_id BIGINT NOT NULL,
  customer_code VARCHAR(20) NOT NULL,
  service_level_code VARCHAR(20) NOT NULL,
  order_created_at DATETIME NOT NULL,
  order_status VARCHAR(30) NOT NULL,
  run_date DATE NOT NULL,
  PRIMARY KEY (order_id, run_date),
  KEY idx_stg_orders_run_date (run_date)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stg_order_lines (
  order_id BIGINT NOT NULL,
  line_number INT NOT NULL,
  sku VARCHAR(30) NOT NULL,
  ordered_qty INT NOT NULL,
  line_status VARCHAR(30) NOT NULL,
  order_line_created_at DATETIME NOT NULL,
  run_date DATE NOT NULL,
  PRIMARY KEY (order_id, line_number, run_date),
  KEY idx_stg_order_lines_run_date (run_date),
  KEY idx_stg_order_lines_sku (sku)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stg_promises (
  order_id BIGINT NOT NULL,
  line_number INT NOT NULL,
  promised_ship_date DATE NOT NULL,
  promised_delivery_date DATE NOT NULL,
  promise_updated_at DATETIME NOT NULL,
  run_date DATE NOT NULL,
  PRIMARY KEY (order_id, line_number, run_date),
  KEY idx_stg_promises_run_date (run_date),
  KEY idx_stg_promises_delivery_date (promised_delivery_date)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stg_shipments (
  shipment_id BIGINT NOT NULL,
  carrier_code VARCHAR(20) NOT NULL,
  warehouse_code VARCHAR(20) NOT NULL,
  origin_country VARCHAR(60) NOT NULL,
  origin_region VARCHAR(60) NULL,
  origin_city VARCHAR(80) NOT NULL,
  dest_country VARCHAR(60) NOT NULL,
  dest_region VARCHAR(60) NULL,
  dest_city VARCHAR(80) NOT NULL,
  distance_km DECIMAL(8,2) NULL,
  shipment_created_at DATETIME NOT NULL,
  actual_ship_at DATETIME NULL,
  run_date DATE NOT NULL,
  PRIMARY KEY (shipment_id, run_date),
  KEY idx_stg_shipments_run_date (run_date),
  KEY idx_stg_shipments_carrier (carrier_code),
  KEY idx_stg_shipments_wh (warehouse_code)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stg_shipment_lines (
  shipment_id BIGINT NOT NULL,
  order_id BIGINT NOT NULL,
  line_number INT NOT NULL,
  shipped_qty INT NOT NULL,
  run_date DATE NOT NULL,
  PRIMARY KEY (shipment_id, order_id, line_number, run_date),
  KEY idx_stg_shipment_lines_run_date (run_date)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stg_tracking_events (
  shipment_id BIGINT NOT NULL,
  event_type VARCHAR(40) NOT NULL,
  event_time DATETIME NOT NULL,
  event_city VARCHAR(80) NULL,
  event_country VARCHAR(60) NULL,
  ingested_at DATETIME NOT NULL,
  run_date DATE NOT NULL,
  PRIMARY KEY (shipment_id, event_type, event_time, run_date),
  KEY idx_stg_events_run_date (run_date),
  KEY idx_stg_events_event_time (event_time),
  KEY idx_stg_events_ingested_at (ingested_at)
) ENGINE=InnoDB;

-- ============================================================
-- 3) Daily load stored procedure
-- ============================================================

DROP PROCEDURE IF EXISTS sp_run_daily_load;

DELIMITER $$

CREATE PROCEDURE sp_run_daily_load(IN p_run_date DATE, IN p_reprocess_days INT)
BEGIN
  DECLARE v_run_id BIGINT;
  DECLARE v_window_start DATE;
  DECLARE v_now DATETIME;

  SET v_now = NOW();
  SET v_window_start = DATE_SUB(p_run_date, INTERVAL (p_reprocess_days - 1) DAY);

  -- Start audit
  INSERT INTO etl_run_audit (run_date, reprocess_days, started_at, status)
  VALUES (p_run_date, p_reprocess_days, v_now, 'STARTED');

  SET v_run_id = LAST_INSERT_ID();

  -- Use a handler to mark failures
  BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
      UPDATE etl_run_audit
      SET status = 'FAILED',
          finished_at = NOW(),
          error_message = 'SQL exception occurred during sp_run_daily_load'
      WHERE run_id = v_run_id;
      RESIGNAL;
    END;

    -- ============================================================
    -- 3.1 Upsert dimensions from staging (only what appears in window)
    -- ============================================================

    -- Customers
    INSERT INTO dim_customer (customer_code, customer_name)
    SELECT DISTINCT o.customer_code, o.customer_code
    FROM stg_orders o
    WHERE o.run_date = p_run_date
    ON DUPLICATE KEY UPDATE customer_name = VALUES(customer_name);

    -- Products
    INSERT INTO dim_product (sku, product_name)
    SELECT DISTINCT l.sku, l.sku
    FROM stg_order_lines l
    WHERE l.run_date = p_run_date
    ON DUPLICATE KEY UPDATE product_name = VALUES(product_name);

    -- Warehouses
    INSERT INTO dim_warehouse (warehouse_code, warehouse_name)
    SELECT DISTINCT s.warehouse_code, s.warehouse_code
    FROM stg_shipments s
    WHERE s.run_date = p_run_date
    ON DUPLICATE KEY UPDATE warehouse_name = VALUES(warehouse_name);

    -- Carriers
    INSERT INTO dim_carrier (carrier_code, carrier_name)
    SELECT DISTINCT s.carrier_code, s.carrier_code
    FROM stg_shipments s
    WHERE s.run_date = p_run_date
    ON DUPLICATE KEY UPDATE carrier_name = VALUES(carrier_name);

    -- Lanes
    INSERT INTO dim_lane (origin_country, origin_region, origin_city, dest_country, dest_region, dest_city, distance_km)
    SELECT DISTINCT
      s.origin_country, s.origin_region, s.origin_city,
      s.dest_country, s.dest_region, s.dest_city,
      s.distance_km
    FROM stg_shipments s
    WHERE s.run_date = p_run_date
    ON DUPLICATE KEY UPDATE
      origin_region = VALUES(origin_region),
      dest_region = VALUES(dest_region),
      distance_km = VALUES(distance_km);

    -- ============================================================
    -- 3.2 Upsert facts (orders, lines, promises, shipments, ship lines)
    -- ============================================================

    -- Orders
    INSERT INTO fact_orders (order_id, customer_id, service_level_id, order_created_at, order_status, created_date_id)
    SELECT
      o.order_id,
      c.customer_id,
      sl.service_level_id,
      o.order_created_at,
      o.order_status,
      CAST(DATE_FORMAT(o.order_created_at, '%Y%m%d') AS UNSIGNED) AS created_date_id
    FROM stg_orders o
    JOIN dim_customer c ON c.customer_code = o.customer_code
    JOIN dim_service_level sl ON sl.service_level_code = o.service_level_code
    WHERE o.run_date = p_run_date
    ON DUPLICATE KEY UPDATE
      customer_id = VALUES(customer_id),
      service_level_id = VALUES(service_level_id),
      order_created_at = VALUES(order_created_at),
      order_status = VALUES(order_status),
      created_date_id = VALUES(created_date_id);

    INSERT INTO etl_table_audit (run_id, table_name, inserted_rows, updated_rows, notes, created_at)
    VALUES (v_run_id, 'fact_orders', ROW_COUNT(), 0, 'Upsert (ROW_COUNT includes affected rows)', NOW());

    -- Order lines
    INSERT INTO fact_order_lines (order_id, line_number, product_id, ordered_qty, line_status, order_line_created_at, created_date_id)
    SELECT
      l.order_id,
      l.line_number,
      p.product_id,
      l.ordered_qty,
      l.line_status,
      l.order_line_created_at,
      CAST(DATE_FORMAT(l.order_line_created_at, '%Y%m%d') AS UNSIGNED) AS created_date_id
    FROM stg_order_lines l
    JOIN dim_product p ON p.sku = l.sku
    WHERE l.run_date = p_run_date
    ON DUPLICATE KEY UPDATE
      product_id = VALUES(product_id),
      ordered_qty = VALUES(ordered_qty),
      line_status = VALUES(line_status),
      order_line_created_at = VALUES(order_line_created_at),
      created_date_id = VALUES(created_date_id);

    INSERT INTO etl_table_audit (run_id, table_name, inserted_rows, updated_rows, notes, created_at)
    VALUES (v_run_id, 'fact_order_lines', ROW_COUNT(), 0, 'Upsert (ROW_COUNT includes affected rows)', NOW());

    -- Promises (active promise per order line)
    INSERT INTO fact_promises
      (order_line_id, promised_ship_date, promised_delivery_date, promise_updated_at, promised_ship_date_id, promised_delivery_date_id)
    SELECT
      ol.order_line_id,
      pr.promised_ship_date,
      pr.promised_delivery_date,
      pr.promise_updated_at,
      CAST(DATE_FORMAT(pr.promised_ship_date, '%Y%m%d') AS UNSIGNED) AS promised_ship_date_id,
      CAST(DATE_FORMAT(pr.promised_delivery_date, '%Y%m%d') AS UNSIGNED) AS promised_delivery_date_id
    FROM stg_promises pr
    JOIN fact_order_lines ol
      ON ol.order_id = pr.order_id AND ol.line_number = pr.line_number
    WHERE pr.run_date = p_run_date
    ON DUPLICATE KEY UPDATE
      promised_ship_date = VALUES(promised_ship_date),
      promised_delivery_date = VALUES(promised_delivery_date),
      promise_updated_at = VALUES(promise_updated_at),
      promised_ship_date_id = VALUES(promised_ship_date_id),
      promised_delivery_date_id = VALUES(promised_delivery_date_id);

    INSERT INTO etl_table_audit (run_id, table_name, inserted_rows, updated_rows, notes, created_at)
    VALUES (v_run_id, 'fact_promises', ROW_COUNT(), 0, 'Upsert (ROW_COUNT includes affected rows)', NOW());

    -- Shipments
    INSERT INTO fact_shipments
      (shipment_id, carrier_id, warehouse_id, lane_id, shipment_created_at, actual_ship_at, created_date_id)
    SELECT
      s.shipment_id,
      ca.carrier_id,
      wh.warehouse_id,
      ln.lane_id,
      s.shipment_created_at,
      s.actual_ship_at,
      CAST(DATE_FORMAT(s.shipment_created_at, '%Y%m%d') AS UNSIGNED) AS created_date_id
    FROM stg_shipments s
    JOIN dim_carrier ca ON ca.carrier_code = s.carrier_code
    JOIN dim_warehouse wh ON wh.warehouse_code = s.warehouse_code
    JOIN dim_lane ln
      ON ln.origin_country = s.origin_country AND ln.origin_city = s.origin_city
     AND ln.dest_country = s.dest_country AND ln.dest_city = s.dest_city
    WHERE s.run_date = p_run_date
    ON DUPLICATE KEY UPDATE
      carrier_id = VALUES(carrier_id),
      warehouse_id = VALUES(warehouse_id),
      lane_id = VALUES(lane_id),
      shipment_created_at = VALUES(shipment_created_at),
      actual_ship_at = VALUES(actual_ship_at),
      created_date_id = VALUES(created_date_id);

    INSERT INTO etl_table_audit (run_id, table_name, inserted_rows, updated_rows, notes, created_at)
    VALUES (v_run_id, 'fact_shipments', ROW_COUNT(), 0, 'Upsert (ROW_COUNT includes affected rows)', NOW());

    -- Shipment lines
    INSERT INTO fact_shipment_lines (shipment_id, order_line_id, shipped_qty)
    SELECT
      sl.shipment_id,
      ol.order_line_id,
      sl.shipped_qty
    FROM stg_shipment_lines sl
    JOIN fact_order_lines ol
      ON ol.order_id = sl.order_id AND ol.line_number = sl.line_number
    WHERE sl.run_date = p_run_date
    ON DUPLICATE KEY UPDATE
      shipped_qty = VALUES(shipped_qty);

    INSERT INTO etl_table_audit (run_id, table_name, inserted_rows, updated_rows, notes, created_at)
    VALUES (v_run_id, 'fact_shipment_lines', ROW_COUNT(), 0, 'Upsert (ROW_COUNT includes affected rows)', NOW());

    -- ============================================================
    -- 3.3 Tracking events (idempotent insert via NOT EXISTS)
    --     Use event_time window to capture late arrivals
    -- ============================================================

    INSERT INTO fact_tracking_events
      (shipment_id, event_type, event_time, ingested_at, event_city, event_country, event_date_id)
    SELECT
      e.shipment_id,
      e.event_type,
      e.event_time,
      e.ingested_at,
      e.event_city,
      e.event_country,
      CAST(DATE_FORMAT(e.event_time, '%Y%m%d') AS UNSIGNED) AS event_date_id
    FROM stg_tracking_events e
    WHERE e.run_date = p_run_date
      AND DATE(e.event_time) BETWEEN v_window_start AND p_run_date
      AND NOT EXISTS (
        SELECT 1
        FROM fact_tracking_events f
        WHERE f.shipment_id = e.shipment_id
          AND f.event_type = e.event_type
          AND f.event_time = e.event_time
      );

    INSERT INTO etl_table_audit (run_id, table_name, inserted_rows, updated_rows, notes, created_at)
    VALUES (v_run_id, 'fact_tracking_events', ROW_COUNT(), 0, 'Insert-only; idempotent via NOT EXISTS natural key', NOW());

    -- Finish audit
    UPDATE etl_run_audit
    SET status = 'SUCCESS',
        finished_at = NOW(),
        error_message = NULL
    WHERE run_id = v_run_id;

  END;
END$$

DELIMITER ;

