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
- `service
