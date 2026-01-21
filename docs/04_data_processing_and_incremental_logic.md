# Data Processing & Incremental Logic

## 4.1 Purpose of This Layer
This chapter defines how raw operational data is processed into the warehouse over time, with a focus on **daily incremental ingestion**, **idempotent re-runs**, and **late-arriving updates**. The objective is to ensure KPIs remain correct even when operational systems deliver incomplete or delayed data.

This layer does not define KPI queries (Chapter 5) or quality checks (Chapter 6). It defines the operational rules that make the warehouse reliable.

---

## 4.2 Processing Principles (Authoritative)

### Incremental, Daily Operation
Data is processed in daily cycles. Each cycle represents a new operational “drop” of:
- newly created records (orders, shipments, events)
- updates to existing records (promise updates, status changes)
- late-arriving tracking events

### Idempotency
All processing steps must be safe to re-run. If the same day is processed twice:
- the warehouse must not create duplicates
- the latest valid values must remain consistent
- results must not drift due to reruns

### Late-Arriving Data
Tracking events and promise updates may arrive after the day they occurred.
The pipeline must account for this by reprocessing a recent rolling window of days.

---

## 4.3 Pipeline Stages (Logical)

### Stage 1 — Staging Ingestion
Raw daily drops are loaded into staging tables (to be defined in Phase 5). This preserves raw structure and allows replay.

### Stage 2 — Warehouse Upserts
Staged data is merged into warehouse facts and dimensions using upserts:
- inserts for new entities
- updates for changed attributes (e.g., promises)

### Stage 3 — Reprocessing Window
A configurable reprocessing window (default: **last 7 days**) is used to:
- re-merge late-arriving events
- refresh affected order-line delivery outcomes

---

## 4.4 Change Data Patterns to Support

### Promise Updates
Promised delivery dates may change after order creation. In v1, the model stores one active promise per order line and the latest promise is treated as authoritative.

### Shipment Splits and Partial Fulfillment
Order lines can be fulfilled through multiple shipments. The processing must preserve shipment-line granularity to allow accurate in-full computation.

### Event Stream Irregularities
Events may:
- arrive late
- arrive out of order
- be missing
Processing must store events as received and allow downstream sequencing logic.

---

## 4.5 Reprocessing Window Policy (v1)
Default policy:
- Reprocess the last **7 days** on each run.
- This window is designed to capture late events and late promise updates without full rebuild.

The reprocessing window is a design control. It balances correctness with runtime.

---

## 4.6 Auditing Requirements
The pipeline must maintain an auditable record of each run, including:
- run timestamp
- processing window start/end
- row counts inserted/updated per table
- success/failure status

Audit records are required to demonstrate production discipline and support debugging.

---

## 4.7 Non-Goals for This Chapter
This chapter does not define:
- exact staging table designs
- KPI computations and views
- data quality check SQL
- automation scheduling

These are handled in later chapters.

---

## Chapter 4 — Definition of Done
This chapter is complete when:
- incremental processing principles are explicitly defined
- idempotency requirements are stated
- late-arriving data behavior is addressed via a reprocessing window policy
- audit requirements are defined
- no KPI logic is mixed into processing design

