-- Delivery Performance Analytics
-- 02_seed_dimensions.sql
-- Seeds dimension tables with baseline reference data

-- Assumes you already ran: sql/01_schema.sql

-- =========================================
-- 1) dim_service_level (authoritative)
-- =========================================
INSERT INTO dim_service_level (service_level_code, service_level_name, promised_days)
VALUES
  ('STANDARD', 'Standard', 3),
  ('EXPRESS',  'Express',  1)
ON DUPLICATE KEY UPDATE
  service_level_name = VALUES(service_level_name),
  promised_days = VALUES(promised_days);

-- =========================================
-- 2) dim_date (generate a usable range)
--    Range: 2024-01-01 to 2026-12-31
--    MySQL 8+ required (recursive CTE)
-- =========================================
WITH RECURSIVE dates AS (
  SELECT DATE('2024-01-01') AS d
  UNION ALL
  SELECT d + INTERVAL 1 DAY FROM dates WHERE d < DATE('2026-12-31')
)
INSERT INTO dim_date
  (date_id, calendar_date, year, month, month_name, week_of_year, day_of_month, day_of_week, is_weekend)
SELECT
  CAST(DATE_FORMAT(d, '%Y%m%d') AS UNSIGNED) AS date_id,
  d AS calendar_date,
  YEAR(d) AS year,
  MONTH(d) AS month,
  DATE_FORMAT(d, '%M') AS month_name,
  WEEK(d, 3) AS week_of_year,
  DAY(d) AS day_of_month,
  WEEKDAY(d) + 1 AS day_of_week,                -- 1=Mon..7=Sun
  CASE WHEN WEEKDAY(d) IN (5,6) THEN TRUE ELSE FALSE END AS is_weekend
FROM dates
ON DUPLICATE KEY UPDATE
  year = VALUES(year),
  month = VALUES(month),
  month_name = VALUES(month_name),
  week_of_year = VALUES(week_of_year),
  day_of_month = VALUES(day_of_month),
  day_of_week = VALUES(day_of_week),
  is_weekend = VALUES(is_weekend);

-- =========================================
-- 3) Optional small baseline entities (safe defaults)
--    You can replace/extend later; these are purely to get started.
-- =========================================

-- dim_carrier
INSERT INTO dim_carrier (carrier_code, carrier_name, carrier_type)
VALUES
  ('DHL',   'DHL',   'Parcel'),
  ('DPD',   'DPD',   'Parcel'),
  ('POSTNL','PostNL','Parcel')
ON DUPLICATE KEY UPDATE
  carrier_name = VALUES(carrier_name),
  carrier_type = VALUES(carrier_type);

-- dim_warehouse
INSERT INTO dim_warehouse (warehouse_code, warehouse_name, country, region, city)
VALUES
  ('WH_NL_01','NL Warehouse 01','Netherlands','Noord-Brabant','Eindhoven'),
  ('WH_NL_02','NL Warehouse 02','Netherlands','Limburg','Venlo')
ON DUPLICATE KEY UPDATE
  warehouse_name = VALUES(warehouse_name),
  country = VALUES(country),
  region = VALUES(region),
  city = VALUES(city);

-- dim_customer (basic)
INSERT INTO dim_customer (customer_code, customer_name, customer_segment, country, region)
VALUES
  ('CUST_001','Customer 001','Retail','Netherlands','Zuid-Holland'),
  ('CUST_002','Customer 002','Retail','Belgium','Flanders'),
  ('CUST_003','Customer 003','B2B','Netherlands','Noord-Holland')
ON DUPLICATE KEY UPDATE
  customer_name = VALUES(customer_name),
  customer_segment = VALUES(customer_segment),
  country = VALUES(country),
  region = VALUES(region);

-- dim_product (basic)
INSERT INTO dim_product (sku, product_name, product_category, uom)
VALUES
  ('SKU_001','Product 001','Snacks','pcs'),
  ('SKU_002','Product 002','Snacks','pcs'),
  ('SKU_003','Product 003','Beverages','pcs'),
  ('SKU_004','Product 004','Beverages','pcs')
ON DUPLICATE KEY UPDATE
  product_name = VALUES(product_name),
  product_category = VALUES(product_category),
  uom = VALUES(uom);

-- dim_lane (basic Benelux lanes)
INSERT INTO dim_lane (origin_country, origin_region, origin_city, dest_country, dest_region, dest_city, distance_km)
VALUES
  ('Netherlands','Noord-Brabant','Eindhoven','Netherlands','Zuid-Holland','Rotterdam',110.0),
  ('Netherlands','Limburg','Venlo','Netherlands','Noord-Holland','Amsterdam',140.0),
  ('Netherlands','Limburg','Venlo','Belgium','Flanders','Antwerp',95.0),
  ('Netherlands','Noord-Brabant','Eindhoven','Belgium','Brussels-Capital','Brussels',125.0)
ON DUPLICATE KEY UPDATE
  origin_region = VALUES(origin_region),
  dest_region = VALUES(dest_region),
  distance_km = VALUES(distance_km);

