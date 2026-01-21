# Data Modeling (Warehouse)

## 3.1 Purpose of This Layer
This chapter defines how raw operational data is structured into an analytics-oriented warehouse model to support accurate delivery performance analysis, especially OTIF, while preventing double counting, grain mismatches, and ambiguous joins.

The warehouse design must support:
- OTIF computation at order-line level
- flexible slicing (carrier, lane, warehouse, service level, customer)
- event-based time analysis (sequencing and lead-time decomposition)
- incremental, production-style processing

---

## 3.2 Modeling Approach
The project uses an analytics-first warehouse design with a clear separation between:
- **Dimensions**: descriptive entities used for filtering and grouping
- **Facts**: measurable operational records at explicit grains

Key principle: **each fact table has exactly one grain**, and KPIs are computed at the appropriate grain.

---

## 3.3 Authoritative Grains (Conceptual)
### Order (Header)
- **1 row = 1 customer order**
- Stores customer, service level, creation timestamp, and order status.

### Order Line (Primary KPI Grain)
- **1 row = 1 order line (order_id + line_number)**
- Stores product and ordered quantity.
- OTIF is evaluated at this grain.

### Shipment (Header)
- **1 row = 1 shipment**
- Physical shipment execution linked to carrier, origin warehouse, and lane.

### Shipment Line
- **1 row = 1 shipment line**
- Quantity of an order line allocated to a shipment (supports split/partial fulfillment).

### Tracking Event
- **1 row = 1 tracking event**
- Time-stamped event associated with a shipment; can arrive late or out-of-order.

### Promise
- **1 row = 1 active promise per order line (v1)**
- Stores committed ship and delivery dates used for OTIF evaluation.

---

## 3.4 Logical Entities
### Dimensions (Logical)
- Date
- Customer
- Product
- Warehouse
- Carrier
- Lane (origin → destination)
- Service Level

### Facts (Logical)
- Orders
- Order Lines
- Promises
- Shipments
- Shipment Lines
- Tracking Events

---

## 3.5 Conceptual Relationship Rules
- One order → many order lines  
- One order → many shipments  
- One shipment → many shipment lines  
- One order line → many shipment lines  
- One shipment → many tracking events  
- One order line → one active promise (v1)

Design constraint: OTIF must be computed at **order-line grain**; shipment-level computation requires careful aggregation and is not used as the primary KPI grain.

---

## 3.6 Physical Schema Conventions (MySQL)
- Surrogate keys use `*_id` (INT or BIGINT depending on scale).
- Business identifiers are preserved (e.g., `order_id`, `shipment_id`) and used as primary keys where appropriate.
- Timestamps use `DATETIME`.
- Quantities use `INT` in v1 (upgradeable to `DECIMAL` if needed).

---

## 3.7 Dimensions (Physical Specification)

### dim_date
**Grain:** 1 row per calendar date  
**Primary key:** `date_id` (INT, YYYYMMDD)

Fields:
- `date_id` INT NOT NULL
- `calendar_date` DATE NOT NULL
- `year` SMALLINT NOT NULL
- `month` TINYINT NOT NULL
- `month_name` VARCHAR(12) NOT NULL
- `week_of_year` TINYINT NOT NULL
- `day_of_month` TINYINT NOT NULL
- `day_of_week` TINYINT NOT NULL
- `is_weekend` BOOLEAN NOT NULL

Constraints / Indexes:
- PRIMARY KEY (`date_id`)
- UNIQUE (`calendar_date`)

---

### dim_customer
- `customer_id` INT AUTO_INCREMENT PRIMARY KEY
- `customer_code` VARCHAR(20) NOT NULL UNIQUE
- `customer_name` VARCHAR(120) NOT NULL
- `customer_segment` VARCHAR(50) NULL
- `country` VARCHAR(60) NULL
- `region` VARCHAR(60) NULL

---

### dim_product
- `product_id` INT AUTO_INCREMENT PRIMARY KEY
- `sku` VARCHAR(30) NOT NULL UNIQUE
- `product_name` VARCHAR(120) NOT NULL
- `product_category` VARCHAR(60) NULL
- `uom` VARCHAR(20) NULL

---

### dim_warehouse
- `warehouse_id` INT AUTO_INCREMENT PRIMARY KEY
- `warehouse_code` VARCHAR(20) NOT NULL UNIQUE
- `warehouse_name` VARCHAR(120) NOT NULL
- `country` VARCHAR(60) NULL
- `region` VARCHAR(60) NULL
- `city` VARCHAR(80) NULL

---

### dim_carrier
- `carrier_id` INT AUTO_INCREMENT PRIMARY KEY
- `carrier_code` VARCHAR(20) NOT NULL UNIQUE
- `carrier_name` VARCHAR(120) NOT NULL
- `carrier_type` VARCHAR(50) NULL

---

### dim_service_level
- `service_level_id` INT AUTO_INCREMENT PRIMARY KEY
- `service_level_code` VARCHAR(20) NOT NULL UNIQUE
- `service_level_name` VARCHAR(50) NOT NULL
- `promised_days` TINYINT NOT NULL

---

### dim_lane
- `lane_id` INT AUTO_INCREMENT PRIMARY KEY
- `origin_country` VARCHAR(60) NOT NULL
- `origin_region` VARCHAR(60) NULL
- `origin_city` VARCHAR(80) NOT NULL
- `dest_country` VARCHAR(60) NOT NULL
- `dest_region` VARCHAR(60) NULL
- `dest_city` VARCHAR(80) NOT NULL
- `distance_km` DECIMAL(8,2) NULL

Constraints:
- UNIQUE (`origin_country`,`origin_city`,`dest_country`,`dest_city`)

---

## 3.8 Facts (Physical Specification)

### fact_orders
**Grain:** 1 row per order  
**Primary key:** `order_id` (BIGINT)

Fields:
- `order_id` BIGINT NOT NULL PRIMARY KEY
- `customer_id` INT NOT NULL
- `service_level_id` INT NOT NULL
- `order_created_at` DATETIME NOT NULL
- `order_status` VARCHAR(30) NOT NULL
- `created_date_id` INT NOT NULL

Indexes:
- INDEX (`customer_id`)
- INDEX (`service_level_id`)
- INDEX (`created_date_id`)
- INDEX (`order_created_at`)

---

### fact_order_lines
**Grain:** 1 row per order line (order_id + line_number)  
**Primary key:** `order_line_id` (BIGINT)

Fields:
- `order_line_id` BIGINT AUTO_INCREMENT PRIMARY KEY
- `order_id` BIGINT NOT NULL
- `line_number` INT NOT NULL
- `product_id` INT NOT NULL
- `ordered_qty` INT NOT NULL
- `line_status` VARCHAR(30) NOT NULL
- `order_line_created_at` DATETIME NOT NULL
- `created_date_id` INT NOT NULL

Constraints / Indexes:
- UNIQUE (`order_id`,`line_number`)
- INDEX (`order_id`)
- INDEX (`product_id`)
- INDEX (`created_date_id`)

---

### fact_promises
**Grain:** 1 row per order line (v1: one active promise)  
**Primary key:** `promise_id` (BIGINT)

Fields:
- `promise_id` BIGINT AUTO_INCREMENT PRIMARY KEY
- `order_line_id` BIGINT NOT NULL UNIQUE
- `promised_ship_date` DATE NOT NULL
- `promised_delivery_date` DATE NOT NULL
- `promise_updated_at` DATETIME NOT NULL
- `promised_ship_date_id` INT NOT NULL
- `promised_delivery_date_id` INT NOT NULL

Indexes:
- INDEX (`promised_delivery_date_id`)
- INDEX (`promise_updated_at`)

---

### fact_shipments
**Grain:** 1 row per shipment  
**Primary key:** `shipment_id` (BIGINT)

Fields:
- `shipment_id` BIGINT NOT NULL PRIMARY KEY
- `carrier_id` INT NOT NULL
- `warehouse_id` INT NOT NULL
- `lane_id` INT NOT NULL
- `shipment_created_at` DATETIME NOT NULL
- `actual_ship_at` DATETIME NULL
- `created_date_id` INT NOT NULL

Indexes:
- INDEX (`carrier_id`)
- INDEX (`warehouse_id`)
- INDEX (`lane_id`)
- INDEX (`created_date_id`)
- INDEX (`shipment_created_at`)

---

### fact_shipment_lines
**Grain:** 1 row per shipment line  
**Primary key:** `shipment_line_id` (BIGINT)

Fields:
- `shipment_line_id` BIGINT AUTO_INCREMENT PRIMARY KEY
- `shipment_id` BIGINT NOT NULL
- `order_line_id` BIGINT NOT NULL
- `shipped_qty` INT NOT NULL

Constraints / Indexes:
- UNIQUE (`shipment_id`,`order_line_id`)
- INDEX (`shipment_id`)
- INDEX (`order_line_id`)

---

### fact_tracking_events
**Grain:** 1 row per tracking event  
**Primary key:** `event_id` (BIGINT)

Fields:
- `event_id` BIGINT AUTO_INCREMENT PRIMARY KEY
- `shipment_id` BIGINT NOT NULL
- `event_type` VARCHAR(40) NOT NULL
- `event_time` DATETIME NOT NULL
- `ingested_at` DATETIME NOT NULL
- `event_city` VARCHAR(80) NULL
- `event_country` VARCHAR(60) NULL
- `event_date_id` INT NOT NULL

Indexes:
- INDEX (`shipment_id`,`event_time`)
- INDEX (`event_type`)
- INDEX (`event_date_id`)
- INDEX (`ingested_at`)

---

## 3.9 Foreign Keys (Physical)
Foreign keys are required for analytical correctness and join safety:

- `fact_orders.customer_id` → `dim_customer.customer_id`
- `fact_orders.service_level_id` → `dim_service_level.service_level_id`
- `fact_orders.created_date_id` → `dim_date.date_id`

- `fact_order_lines.order_id` → `fact_orders.order_id`
- `fact_order_lines.product_id` → `dim_product.product_id`
- `fact_order_lines.created_date_id` → `dim_date.date_id`

- `fact_promises.order_line_id` → `fact_order_lines.order_line_id`
- `fact_promises.promised_ship_date_id` → `dim_date.date_id`
- `fact_promises.promised_delivery_date_id` → `dim_date.date_id`

- `fact_shipments.carrier_id` → `dim_carrier.carrier_id`
- `fact_shipments.warehouse_id` → `dim_warehouse.warehouse_id`
- `fact_shipments.lane_id` → `dim_lane.lane_id`
- `fact_shipments.created_date_id` → `dim_date.date_id`

- `fact_shipment_lines.shipment_id` → `fact_shipments.shipment_id`
- `fact_shipment_lines.order_line_id` → `fact_order_lines.order_line_id`

- `fact_tracking_events.shipment_id` → `fact_shipments.shipment_id`
- `fact_tracking_events.event_date_id` → `dim_date.date_id`

---

## 3.10 Event Types (Controlled Vocabulary)
A stable event vocabulary is required for KPI logic (v1):
- `PICKED`
- `PACKED`
- `DISPATCHED`
- `IN_TRANSIT`
- `OUT_FOR_DELIVERY`
- `DELIVERED`
- `EXCEPTION`

---

## Chapter 3 — Definition of Done
This chapter is complete when:
- Conceptual and physical models are consistent
- Every table has an explicit grain and key
- Relationships are unambiguous and align to KPI grain (order-line)
- The physical schema can be implemented without guessing
