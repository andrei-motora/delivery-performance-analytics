# Analytics & KPI Layer

## 5.1 Purpose
This chapter defines the analytical layer that converts processed warehouse facts into
decision-ready KPIs for delivery performance and logistics reliability.

The analytics layer:
- exposes stable KPI views
- enforces consistent metric definitions
- supports slicing by carrier, lane, warehouse, service level, and time
- separates KPI logic from data ingestion and processing

---

## 5.2 KPI Evaluation Grain (Authoritative)
All service-level KPIs are evaluated at **order-line grain**.

Rationale:
- OTIF correctness requires line-level quantity and timing evaluation
- shipment-level metrics would hide partial fulfillment and split shipments

All KPI views must aggregate **from order-line level upward**.

---

## 5.3 KPI Definitions (Authoritative)

### On-Time
An order line is **On-Time** if:
- actual delivery date ≤ promised delivery date

### In-Full
An order line is **In-Full** if:
- total shipped quantity ≥ ordered quantity

### OTIF
An order line is **OTIF** if:
- On-Time = TRUE
- In-Full = TRUE

OTIF is a **binary outcome per order line**.

---

## 5.4 Supporting Measures

### Actual Delivery Date
Derived from tracking events:
- the earliest `DELIVERED` event per shipment
- aggregated to order-line level via shipment lines

### Shipped Quantity
Derived from:
- sum of `shipped_qty` across all shipment lines per order line

---

## 5.5 Analytical Views (Public Contract)
The following views constitute the analytics contract:

- `vw_order_line_delivery_status`
- `vw_kpi_otif`
- `vw_carrier_performance`
- `vw_lane_performance`
- `vw_warehouse_performance`

Downstream tools (BI, notebooks, interviews) must query **only these views**.

---

## 5.6 Time Semantics
All KPI views:
- join to `dim_date` via promised delivery date
- allow time slicing by day, week, month

This ensures consistent temporal aggregation.

---

## 5.7 Scope Boundary
This chapter does not define:
- data quality validation (Chapter 6)
- automation and scheduling (Chapter 7)
- visualization tooling

---

## Chapter 5 — Definition of Done
This chapter is complete when:
- OTIF logic is unambiguous and reproducible
- KPIs are exposed as stable SQL views
- all metrics roll up cleanly from order-line grain
- business slicing dimensions are supported

