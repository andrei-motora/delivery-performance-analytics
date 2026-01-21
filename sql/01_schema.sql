-- Delivery Performance Analytics
-- 01_schema.sql
-- Creates the warehouse schema (dimensions + facts) per docs/03_data_modeling.md

-- Recommended: run in a dedicated database/schema.
-- Example:
-- CREATE DATABASE delivery_performance_analytics;
-- USE delivery_performance_analytics;

SET FOREIGN_KEY_CHECKS = 0;

-- Drop facts first (depend on dimensions)
DROP TABLE IF EXISTS fact_tracking_events;
DROP TABLE IF EXISTS fact_shipment_lines;
DROP TABLE IF EXISTS fact_shipments;
DROP TABLE IF EXISTS fact_promises;
DROP TABLE IF EXISTS fact_order_lines;
DROP TABLE IF EXISTS fact_orders;

-- Drop dimensions
DROP TABLE IF EXISTS dim_lane;
DROP TABLE IF EXISTS dim_service_level;
DROP TABLE IF EXISTS dim_carrier;
DROP TABLE IF EXISTS dim_warehouse;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_date;

SET FOREIGN_KEY_CHECKS = 1;

-- =========================
-- Dimensions
-- =========================

CREATE TABLE dim_date (
  date_id INT NOT NULL,
  calendar_date DATE NOT NULL,
  year SMALLINT NOT NULL,
  month TINYINT NOT NULL,
  month_name VARCHAR(12) NOT NULL,
  week_of_year TINYINT NOT NULL,
  day_of_month TINYINT NOT NULL,
  day_of_week TINYINT NOT NULL,  -- 1=Mon..7=Sun
  is_weekend BOOLEAN NOT NULL,
  PRIMARY KEY (date_id),
  UNIQUE KEY uq_dim_date_calendar_date (calendar_date)
) ENGINE=InnoDB;

CREATE TABLE dim_customer (
  customer_id INT NOT NULL AUTO_INCREMENT,
  customer_code VARCHAR(20) NOT NULL,
  customer_name VARCHAR(120) NOT NULL,
  customer_segment VARCHAR(50) NULL,
  country VARCHAR(60) NULL,
  region VARCHAR(60) NULL,
  PRIMARY KEY (customer_id),
  UNIQUE KEY uq_dim_customer_code (customer_code)
) ENGINE=InnoDB;

CREATE TABLE dim_product (
  product_id INT NOT NULL AUTO_INCREMENT,
  sku VARCHAR(30) NOT NULL,
  product_name VARCHAR(120) NOT NULL,
  product_category VARCHAR(60) NULL,
  uom VARCHAR(20) NULL,
  PRIMARY KEY (product_id),
  UNIQUE KEY uq_dim_product_sku (sku)
) ENGINE=InnoDB;

CREATE TABLE dim_warehouse (
  warehouse_id INT NOT NULL AUTO_INCREMENT,
  warehouse_code VARCHAR(20) NOT NULL,
  warehouse_name VARCHAR(120) NOT NULL,
  country VARCHAR(60) NULL,
  region VARCHAR(60) NULL,
  city VARCHAR(80) NULL,
  PRIMARY KEY (warehouse_id),
  UNIQUE KEY uq_dim_warehouse_code (warehouse_code)
) ENGINE=InnoDB;

CREATE TABLE dim_carrier (
  carrier_id INT NOT NULL AUTO_INCREMENT,
  carrier_code VARCHAR(20) NOT NULL,
  carrier_name VARCHAR(120) NOT NULL,
  carrier_type VARCHAR(50) NULL,
  PRIMARY KEY (carrier_id),
  UNIQUE KEY uq_dim_carrier_code (carrier_code)
) ENGINE=InnoDB;

CREATE TABLE dim_service_level (
  service_level_id INT NOT NULL AUTO_INCREMENT,
  service_level_code VARCHAR(20) NOT NULL,
  service_level_name VARCHAR(50) NOT NULL, -- Standard/Express
  promised_days TINYINT NOT NULL,
  PRIMARY KEY (service_level_id),
  UNIQUE KEY uq_dim_service_level_code (service_level_code)
) ENGINE=InnoDB;

CREATE TABLE dim_lane (
  lane_id INT NOT NULL AUTO_INCREMENT,
  origin_country VARCHAR(60) NOT NULL,
  origin_region VARCHAR(60) NULL,
  origin_city VARCHAR(80) NOT NULL,
  dest_country VARCHAR(60) NOT NULL,
  dest_region VARCHAR(60) NULL,
  dest_city VARCHAR(80) NOT NULL,
  distance_km DECIMAL(8,2) NULL,
  PRIMARY KEY (lane_id),
  UNIQUE KEY uq_dim_lane_od (origin_country, origin_city, dest_country, dest_city)
) ENGINE=InnoDB;

-- =========================
-- Facts
-- =========================

CREATE TABLE fact_orders (
  order_id BIGINT NOT NULL,
  customer_id INT NOT NULL,
  service_level_id INT NOT NULL,
  order_created_at DATETIME NOT NULL,
  order_status VARCHAR(30) NOT NULL, -- CREATED/CANCELLED/CLOSED
  created_date_id INT NOT NULL,
  PRIMARY KEY (order_id),
  KEY idx_fact_orders_customer_id (customer_id),
  KEY idx_fact_orders_service_level_id (service_level_id),
  KEY idx_fact_orders_created_date_id (created_date_id),
  KEY idx_fact_orders_order_created_at (order_created_at),
  CONSTRAINT fk_fact_orders_customer
    FOREIGN KEY (customer_id) REFERENCES dim_customer(customer_id),
  CONSTRAINT fk_fact_orders_service_level
    FOREIGN KEY (service_level_id) REFERENCES dim_service_level(service_level_id),
  CONSTRAINT fk_fact_orders_created_date
    FOREIGN KEY (created_date_id) REFERENCES dim_date(date_id)
) ENGINE=InnoDB;

CREATE TABLE fact_order_lines (
  order_line_id BIGINT NOT NULL AUTO_INCREMENT,
  order_id BIGINT NOT NULL,
  line_number INT NOT NULL,
  product_id INT NOT NULL,
  ordered_qty INT NOT NULL,
  line_status VARCHAR(30) NOT NULL, -- OPEN/CANCELLED/CLOSED
  order_line_created_at DATETIME NOT NULL,
  created_date_id INT NOT NULL,
  PRIMARY KEY (order_line_id),
  UNIQUE KEY uq_fact_order_lines_order_line (order_id, line_number),
  KEY idx_fact_order_lines_order_id (order_id),
  KEY idx_fact_order_lines_product_id (product_id),
  KEY idx_fact_order_lines_created_date_id (created_date_id),
  CONSTRAINT fk_fact_order_lines_order
    FOREIGN KEY (order_id) REFERENCES fact_orders(order_id),
  CONSTRAINT fk_fact_order_lines_product
    FOREIGN KEY (product_id) REFERENCES dim_product(product_id),
  CONSTRAINT fk_fact_order_lines_created_date
    FOREIGN KEY (created_date_id) REFERENCES dim_date(date_id)
) ENGINE=InnoDB;

CREATE TABLE fact_promises (
  promise_id BIGINT NOT NULL AUTO_INCREMENT,
  order_line_id BIGINT NOT NULL,
  promised_ship_date DATE NOT NULL,
  promised_delivery_date DATE NOT NULL,
  promise_updated_at DATETIME NOT NULL,
  promised_ship_date_id INT NOT NULL,
  promised_delivery_date_id INT NOT NULL,
  PRIMARY KEY (promise_id),
  UNIQUE KEY uq_fact_promises_order_line_id (order_line_id),
  KEY idx_fact_promises_promised_delivery_date_id (promised_delivery_date_id),
  KEY idx_fact_promises_promise_updated_at (promise_updated_at),
  CONSTRAINT fk_fact_promises_order_line
    FOREIGN KEY (order_line_id) REFERENCES fact_order_lines(order_line_id),
  CONSTRAINT fk_fact_promises_ship_date
    FOREIGN KEY (promised_ship_date_id) REFERENCES dim_date(date_id),
  CONSTRAINT fk_fact_promises_delivery_date
    FOREIGN KEY (promised_delivery_date_id) REFERENCES dim_date(date_id)
) ENGINE=InnoDB;

CREATE TABLE fact_shipments (
  shipment_id BIGINT NOT NULL,
  carrier_id INT NOT NULL,
  warehouse_id INT NOT NULL,
  lane_id INT NOT NULL,
  shipment_created_at DATETIME NOT NULL,
  actual_ship_at DATETIME NULL,
  created_date_id INT NOT NULL,
  PRIMARY KEY (shipment_id),
  KEY idx_fact_shipments_carrier_id (carrier_id),
  KEY idx_fact_shipments_warehouse_id (warehouse_id),
  KEY idx_fact_shipments_lane_id (lane_id),
  KEY idx_fact_shipments_created_date_id (created_date_id),
  KEY idx_fact_shipments_shipment_created_at (shipment_created_at),
  CONSTRAINT fk_fact_shipments_carrier
    FOREIGN KEY (carrier_id) REFERENCES dim_carrier(carrier_id),
  CONSTRAINT fk_fact_shipments_warehouse
    FOREIGN KEY (warehouse_id) REFERENCES dim_warehouse(warehouse_id),
  CONSTRAINT fk_fact_shipments_lane
    FOREIGN KEY (lane_id) REFERENCES dim_lane(lane_id),
  CONSTRAINT fk_fact_shipments_created_date
    FOREIGN KEY (created_date_id) REFERENCES dim_date(date_id)
) ENGINE=InnoDB;

CREATE TABLE fact_shipment_lines (
  shipment_line_id BIGINT NOT NULL AUTO_INCREMENT,
  shipment_id BIGINT NOT NULL,
  order_line_id BIGINT NOT NULL,
  shipped_qty INT NOT NULL,
  PRIMARY KEY (shipment_line_id),
  UNIQUE KEY uq_fact_shipment_lines_ship_order_line (shipment_id, order_line_id),
  KEY idx_fact_shipment_lines_shipment_id (shipment_id),
  KEY idx_fact_shipment_lines_order_line_id (order_line_id),
  CONSTRAINT fk_fact_shipment_lines_shipment
    FOREIGN KEY (shipment_id) REFERENCES fact_shipments(shipment_id),
  CONSTRAINT fk_fact_shipment_lines_order_line
    FOREIGN KEY (order_line_id) REFERENCES fact_order_lines(order_line_id)
) ENGINE=InnoDB;

CREATE TABLE fact_tracking_events (
  event_id BIGINT NOT NULL AUTO_INCREMENT,
  shipment_id BIGINT NOT NULL,
  event_type VARCHAR(40) NOT NULL,
  event_time DATETIME NOT NULL,
  ingested_at DATETIME NOT NULL,
  event_city VARCHAR(80) NULL,
  event_country VARCHAR(60) NULL,
  event_date_id INT NOT NULL,
  PRIMARY KEY (event_id),
  KEY idx_fact_tracking_events_shipment_time (shipment_id, event_time),
  KEY idx_fact_tracking_events_event_type (event_type),
  KEY idx_fact_tracking_events_event_date_id (event_date_id),
  KEY idx_fact_tracking_events_ingested_at (ingested_at),
  CONSTRAINT fk_fact_tracking_events_shipment
    FOREIGN KEY (shipment_id) REFERENCES fact_shipments(shipment_id),
  CONSTRAINT fk_fact_tracking_events_event_date
    FOREIGN KEY (event_date_id) REFERENCES dim_date(date_id)
) ENGINE=InnoDB;

