# Data Modeling (Warehouse)

## 3.1 Purpose of This Layer
This chapter defines how raw operational data is structured into an analytics-oriented warehouse model.
The objective is to enable accurate OTIF and delivery performance analytics while preventing common errors such as double counting, grain mismatches, and ambiguous joins.

The warehouse model is designed for:
- consistent KPI computation
- flexible slicing (carrier, lane, warehouse, service level, customer)
- event-based time analysis (sequencing and lead-time decomposition)
- incremental, production-style processing

---

## 3.2 Modeling Approach
The project uses an analytics-first warehouse design with:
- **Dimensions**: descriptive entities used for filtering and grouping
- **Facts**: measurable operational records at explicit grains

Key principle: **every fact table has one clearly defined grain**, and KPI calculations are performed at the appropriate grain.

---

## 3.3 Grain Definitions (Authoritative)
The following grains are used throughout the model:

### Order (Header) Grain
- **1 row = 1 customer order**
- Contains customer, order date, service level, and high-level status attributes.

### Order Line Grain (Primary KPI Grain)
- **1 row = 1 order line (order_id + line_number)**
- Contains product, ordered quantity, and the unit of OTIF evaluation.

### Shipment (Header) Grain
- **1 row = 1 shipment**
- Represents the physical shipment execution, linked to carrier, origin warehouse, and destination.

### Shipment Line Grain
- **1 row = 1 shipment line**
- Represents how much of a given order line is included in a given shipment (supports split/partial deliveries).

### Tracking Event Grain
- **1 row = 1 tracking event**
- Represents one time-stamped operational event associated with a shipment.

### Promise Grain
- **1 row = 1 promise per order line**
- Stores committed ship and delivery dates for OTIF evaluation, including changes over time if needed.

---

## 3.4 Core Dimensions
Dimensions provide stable descriptive context for slicing KPIs.

### dim_date
Purpose: time slicing and rolling windows.

Key fields (conceptual):
- date_id, calendar_date, year, month, week, day_of_week, is_weekend

### dim_customer
Purpose: customer segmentation.

Key fields:
- customer_id, customer_name, customer_segment, country/region

### dim_product
Purpose: product-level analysis.

Key fields:
- product_id, sku, product_category, unit_of_measure

### dim_warehouse
Purpose: warehouse operations slicing.

Key fields:
- warehouse_id, warehouse_name, city/region, warehouse_type

### dim_carrier
Purpose: carrier performance slicing.

Key fields:
- carrier_id, carrier_name, carrier_type

### dim_lane
Purpose: origin-destination performance slicing.

Key fields:
- lane_id, origin_region, destination_region, distance_km (if available)

### dim_service_level
Purpose: SLA definitions.

Key fields:
- service_level_id, service_level_name (Standard/Express), promised_days

---

## 3.5 Core Facts (Warehouse Tables)

### fact_orders
Grain: 1 row per order.

Contains:
- order identifiers
- customer reference
- order date
- service level reference
- order status (created/cancelled/closed)

### fact_order_lines
Grain: 1 row per order line.

Contains:
- product reference
- ordered quantity
- line status

This is the **primary grain** for OTIF evaluation.

### fact_promises
Grain: 1 row per order line promise.

Contains:
- promised_ship_date
- promised_delivery_date
- promise_version or effective dates (if promise updates are modeled)

### fact_shipments
Grain: 1 row per shipment.

Contains:
- carrier reference
- origin warehouse
- destination lane
- shipment creation date
- actual ship date (if available)

### fact_shipment_lines
Grain: 1 row per shipment line.

Contains:
- link to order line
- shipped quantity (supports partial/split fulfillment)

### fact_tracking_events
Grain: 1 row per event.

Contains:
- shipment reference
- event type
- event timestamp
- event location (optional)
- ingestion timestamp (optional, for late-arrival analysis)

---

## 3.6 Relationship Rules (Conceptual)
The following relationships are central to analytical correctness:

- **fact_orders** 1-to-many **fact_order_lines**
- **fact_order_lines** 1-to-many **fact_shipment_lines**
- **fact_shipments** 1-to-many **fact_shipment_lines**
- **fact_shipments** 1-to-many **fact_tracking_events**
- **fact_order_lines** 1-to-1 **fact_promises** (for v1)

Important note: OTIF is evaluated at **order-line grain** and must not be computed directly at shipment grain without careful aggregation.

---

## 3.7 OTIF Computation Implications (Design Constraints)
The model must support:

- On-time evaluation: delivered date vs promised delivery date
- In-full evaluation: sum(delivered_qty) vs ordered_qty at order-line level
- Handling split shipments: multiple shipment lines per order line
- Delivery confirmation: derived from tracking events (delivered) or shipment completion logic

---

## 3.8 Non-Goals for This Chapter
This chapter does not define:
- how incremental loading is performed
- how late-arriving events are handled technically
- KPI queries and views
- data quality checks

Those belong to Chapters 4–6.

---

## Chapter 3 — Definition of Done
This chapter is complete when:
- Each fact and dimension has a clear purpose and grain
- Relationships between tables are explicit and consistent
- The model supports OTIF evaluation at order-line level
- No processing or KPI logic is mixed into modeling decisions

