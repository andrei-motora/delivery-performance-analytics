-- Delivery Performance Analytics
-- 02_seed_dimensions.sql
-- Seeds dimension tables with baseline reference data


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
-- =========================================
SET SESSION cte_max_recursion_depth = 5000;

INSERT INTO dim_date
  (date_id, calendar_date, `year`, `month`, month_name, week_of_year, day_of_month, day_of_week, is_weekend)
WITH RECURSIVE dates AS (
  SELECT DATE('2024-01-01') AS d
  UNION ALL
  SELECT d + INTERVAL 1 DAY
  FROM dates
  WHERE d < DATE('2026-12-31')
)
SELECT
  CAST(DATE_FORMAT(d, '%Y%m%d') AS UNSIGNED) AS date_id,
  d AS calendar_date,
  YEAR(d) AS `year`,
  MONTH(d) AS `month`,
  DATE_FORMAT(d, '%M') AS month_name,
  WEEK(d, 3) AS week_of_year,
  DAY(d) AS day_of_month,
  WEEKDAY(d) + 1 AS day_of_week,
  CASE WHEN WEEKDAY(d) IN (5,6) THEN TRUE ELSE FALSE END AS is_weekend
FROM dates
ON DUPLICATE KEY UPDATE
  `year` = VALUES(`year`),
  `month` = VALUES(`month`),
  month_name = VALUES(month_name),
  week_of_year = VALUES(week_of_year),
  day_of_month = VALUES(day_of_month),
  day_of_week = VALUES(day_of_week),
  is_weekend = VALUES(is_weekend);



-- =========================================
-- 3) Optional baseline entities (safe defaults)
-- =========================================
-- dim_carrier
INSERT INTO dim_carrier (carrier_code, carrier_name, carrier_type)
VALUES
  ('DHL',    'DHL',    'Parcel'),
  ('DPD',    'DPD',    'Parcel'),
  ('POSTNL', 'PostNL', 'Parcel'),
  ('GLS',    'GLS',    'Parcel'),
  ('UPS',    'UPS',    'Parcel'),
  ('BPOST',  'bpost',  'Parcel')
ON DUPLICATE KEY UPDATE
  carrier_name = VALUES(carrier_name),
  carrier_type = VALUES(carrier_type);
  
  
  
-- dim_warehouse
INSERT INTO dim_warehouse (warehouse_code, warehouse_name, country, region, city)
VALUES
  ('WH_NL_01','NL DC Eindhoven','Netherlands','Noord-Brabant','Eindhoven'),
  ('WH_NL_02','NL DC Venlo','Netherlands','Limburg','Venlo'),
  ('WH_NL_03','NL DC Rotterdam','Netherlands','Zuid-Holland','Rotterdam'),
  ('WH_NL_04','NL DC Utrecht','Netherlands','Utrecht','Utrecht'),
  ('WH_BE_01','BE DC Antwerp','Belgium','Flanders','Antwerp'),
  ('WH_DE_01','DE DC Duisburg','Germany','North Rhine-Westphalia','Duisburg')
ON DUPLICATE KEY UPDATE
  warehouse_name = VALUES(warehouse_name),
  country = VALUES(country),
  region = VALUES(region),
  city = VALUES(city);



-- dim_customer (basic)
INSERT INTO dim_customer (customer_code, customer_name, customer_segment, country, region)
WITH RECURSIVE seq AS (
  SELECT 1 AS n
  UNION ALL
  SELECT n + 1 FROM seq WHERE n < 75
)
SELECT
  CONCAT('CUST_', LPAD(n, 3, '0')) AS customer_code,
  CONCAT(
    CASE WHEN n <= 60 THEN 'Retail Customer ' ELSE 'B2B Customer ' END,
    LPAD(n, 3, '0')
  ) AS customer_name,
  CASE WHEN n <= 60 THEN 'Retail' ELSE 'B2B' END AS customer_segment,
  CASE
    WHEN n % 20 IN (1,2,3,4,5,6,7,8,9,10,11,12) THEN 'Netherlands'
    WHEN n % 20 IN (13,14,15,16,17)             THEN 'Belgium'
    ELSE                                             'Germany'
  END AS country,
  CASE
    -- Netherlands regions (~60%)
    WHEN n % 20 IN (1,2,3,4,5,6,7,8,9,10,11,12) AND n % 6 = 0 THEN 'Noord-Holland'
    WHEN n % 20 IN (1,2,3,4,5,6,7,8,9,10,11,12) AND n % 6 = 1 THEN 'Zuid-Holland'
    WHEN n % 20 IN (1,2,3,4,5,6,7,8,9,10,11,12) AND n % 6 = 2 THEN 'Noord-Brabant'
    WHEN n % 20 IN (1,2,3,4,5,6,7,8,9,10,11,12) AND n % 6 = 3 THEN 'Limburg'
    WHEN n % 20 IN (1,2,3,4,5,6,7,8,9,10,11,12) AND n % 6 = 4 THEN 'Utrecht'
    WHEN n % 20 IN (1,2,3,4,5,6,7,8,9,10,11,12)                  THEN 'Gelderland'

    -- Belgium regions (~25%)
    WHEN n % 20 IN (13,14,15,16,17) AND n % 3 = 0 THEN 'Flanders'
    WHEN n % 20 IN (13,14,15,16,17) AND n % 3 = 1 THEN 'Brussels-Capital'
    WHEN n % 20 IN (13,14,15,16,17)                THEN 'Wallonia'

    -- Germany regions (~15%)
    WHEN n % 3 = 0 THEN 'North Rhine-Westphalia'
    WHEN n % 3 = 1 THEN 'Hesse'
    ELSE               'Lower Saxony'
  END AS region
FROM seq
ON DUPLICATE KEY UPDATE
  customer_name = VALUES(customer_name),
  customer_segment = VALUES(customer_segment),
  country = VALUES(country),
  region = VALUES(region);


  
-- dim_product (basic)
INSERT INTO dim_product (sku, product_name, product_category, uom)
WITH RECURSIVE seq AS (
  SELECT 1 AS n
  UNION ALL
  SELECT n + 1 FROM seq WHERE n < 150
)
SELECT
  CONCAT('SKU_', LPAD(n, 3, '0')) AS sku,
  CONCAT('Product ', LPAD(n, 3, '0')) AS product_name,
  CASE
    WHEN n BETWEEN 1 AND 45   THEN 'Snacks'
    WHEN n BETWEEN 46 AND 85  THEN 'Beverages'
    WHEN n BETWEEN 86 AND 120 THEN 'Personal Care'
    ELSE                           'Household'
  END AS product_category,
  'pcs' AS uom
FROM seq
ON DUPLICATE KEY UPDATE
  product_name = VALUES(product_name),
  product_category = VALUES(product_category),
  uom = VALUES(uom);

-- dim_lane (basic Benelux lanes)
INSERT INTO dim_lane
  (origin_country, origin_region, origin_city, dest_country, dest_region, dest_city, distance_km)
WITH
warehouses AS (
  SELECT 'Netherlands' AS origin_country, 'Noord-Brabant' AS origin_region, 'Eindhoven' AS origin_city UNION ALL
  SELECT 'Netherlands', 'Limburg',        'Venlo' UNION ALL
  SELECT 'Netherlands', 'Zuid-Holland',   'Rotterdam' UNION ALL
  SELECT 'Netherlands', 'Utrecht',        'Utrecht' UNION ALL
  SELECT 'Belgium',     'Flanders',       'Antwerp' UNION ALL
  SELECT 'Germany',     'North Rhine-Westphalia', 'Duisburg'
),
dests AS (
  -- NL
  SELECT 'Netherlands' AS dest_country, 'Noord-Holland' AS dest_region, 'Amsterdam' AS dest_city UNION ALL
  SELECT 'Netherlands', 'Zuid-Holland', 'Rotterdam' UNION ALL
  SELECT 'Netherlands', 'Zuid-Holland', 'The Hague' UNION ALL
  SELECT 'Netherlands', 'Utrecht',      'Utrecht' UNION ALL
  SELECT 'Netherlands', 'Noord-Brabant','Tilburg' UNION ALL
  SELECT 'Netherlands', 'Gelderland',   'Arnhem' UNION ALL
  SELECT 'Netherlands', 'Overijssel',   'Zwolle' UNION ALL
  -- BE
  SELECT 'Belgium',     'Flanders',     'Ghent' UNION ALL
  SELECT 'Belgium',     'Flanders',     'Antwerp' UNION ALL
  SELECT 'Belgium',     'Brussels-Capital', 'Brussels' UNION ALL
  SELECT 'Belgium',     'Wallonia',     'Liège' UNION ALL
  -- DE
  SELECT 'Germany',     'North Rhine-Westphalia', 'Cologne' UNION ALL
  SELECT 'Germany',     'North Rhine-Westphalia', 'Düsseldorf' UNION ALL
  SELECT 'Germany',     'Hesse',        'Frankfurt'
),
lanes AS (
  SELECT
    w.origin_country, w.origin_region, w.origin_city,
    d.dest_country, d.dest_region, d.dest_city,
    -- Deterministic pseudo-distance 80..450 km (good enough for analytics demos)
    ROUND(80 + (ABS(CRC32(CONCAT(w.origin_city, '->', d.dest_city))) % 371), 0) AS distance_km
  FROM warehouses w
  CROSS JOIN dests d
  WHERE NOT (w.origin_country = d.dest_country AND w.origin_city = d.dest_city)
)
SELECT
  origin_country, origin_region, origin_city,
  dest_country, dest_region, dest_city,
  distance_km
FROM lanes
ON DUPLICATE KEY UPDATE
  origin_region = VALUES(origin_region),
  dest_region = VALUES(dest_region),
  distance_km = VALUES(distance_km);

