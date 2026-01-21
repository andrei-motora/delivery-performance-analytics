# Trust, Quality & Reliability

## 6.1 Purpose
This chapter defines how data quality and KPI trust are enforced in the analytics system.
The goal is to ensure that OTIF and delivery KPIs are:
- correct
- explainable
- resistant to bad or incomplete data

This layer does not modify business logic. It **detects, surfaces, and documents risk**.

---

## 6.2 Trust Principles (Authoritative)

### Fail Loud, Not Silent
Quality issues must be visible. Missing or inconsistent data should surface as failed checks,
not quietly distort KPIs.

### KPI Trust over KPI Availability
It is preferable to flag unreliable metrics than to report misleading values.

### Deterministic Checks
All quality rules must be deterministic, reproducible, and executable in SQL.

---

## 6.3 Quality Dimensions Covered

This chapter enforces checks across:

- **Completeness** (required fields present)
- **Validity** (values in expected ranges)
- **Consistency** (relationships hold across tables)
- **Timeliness** (events occur within reasonable windows)
- **Referential integrity** (foreign keys resolvable)

---

## 6.4 Critical Quality Rules

### Order & Line Integrity
- Every order line must belong to a valid order.
- Ordered quantity must be positive.

### Promise Integrity
- Each order line must have exactly one active promise.
- Promised delivery date must be on or after promised ship date.

### Shipment Integrity
- Shipment lines must reference existing shipments and order lines.
- Shipped quantity must be positive.

### Event Integrity
- Delivered events must not precede shipment creation.
- Duplicate tracking events must not exist.

---

## 6.5 KPI Risk Conditions
The following conditions invalidate OTIF interpretation and must be flagged:

- missing promised delivery date
- missing delivered event
- zero or null ordered quantity
- shipment without order-line linkage

These do not block KPI computation but **must be surfaced alongside results**.

---

## 6.6 Quality Reporting Contract
Quality checks are exposed as SQL views that:
- return row-level violations
- include a rule identifier
- include a human-readable description

Downstream tools may surface counts or samples, but **must not suppress failures**.

---

## 6.7 Scope Boundary
This chapter does not define:
- automated scheduling or alerting (Chapter 7)
- business KPI logic (Chapter 5)
- data ingestion mechanics (Chapter 4)

---

## Chapter 6 — Definition of Done
This chapter is complete when:
- quality rules are explicit and executable
- violations are queryable via SQL
- KPI risk conditions are documented
- no quality logic is embedded inside KPI views

