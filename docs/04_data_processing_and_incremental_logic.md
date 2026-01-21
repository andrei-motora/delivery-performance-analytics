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

---

## Appendix A — Staging and Incremental Load Implementation

### A.1 Purpose
This appendix documents the **technical implementation** of the incremental data-processing rules defined in Chapter 4.

While Chapter 4 specifies *what the processing layer must do* (incremental ingestion, idempotency, late-arriving data handling), this appendix explains *how those rules are implemented* using staging tables, audit tables, and a single execution interface.

This appendix is intentionally implementation-focused and subordinate to the main chapter.

---

### A.2 Staging Layer Concept
Staging tables represent **raw daily operational drops**. They simulate how data arrives from operational systems and are designed to be:

- append-only  
- replayable  
- keyed by a logical `run_date`  
- free of warehouse surrogate keys  

All staging tables store **business identifiers and codes** (e.g. `order_id`, `sku`, `carrier_code`) to mirror real ingestion patterns.

---

### A.3 Staging Table Contracts
The incremental pipeline expects the following staging inputs:

- **stg_orders**  
  Order header records for the processing date.

- **stg_order_lines**  
  Line-level order data including product and ordered quantity.

- **stg_promises**  
  Delivery promise updates per order line.

- **stg_shipments**  
  Shipment execution records, including carrier, warehouse, and origin–destination attributes.

- **stg_shipment_lines**  
  Mapping between shipments and order lines, enabling split and partial fulfillment.

- **stg_tracking_events**  
  Time-stamped operational events generated during warehouse handling and transport.

Each staging table includes a `run_date` column that defines the logical processing date.

---

### A.4 Audit and Observability
To demonstrate production discipline and enable traceability, the pipeline records metadata in audit tables:

- **etl_run_audit**  
  One row per pipeline execution, recording start time, end time, status, and error context.

- **etl_table_audit**  
  Row-count metrics per table per run, supporting verification and debugging.

Audit records allow confirmation that:
- the pipeline ran successfully  
- reruns did not create duplicates  
- changes in row counts are explainable  

---

### A.5 Daily Execution Interface
The processing layer is executed through a single stored procedure.

Example invocation:

CALL sp_run_daily_load(p_run_date, p_reprocess_days);

Parameters:
- `p_run_date` — logical business date being processed  
- `p_reprocess_days` — rolling window length for late-arriving data (default: 7)

This procedure:
1. initializes audit logging  
2. upserts dimension records discovered in staging  
3. upserts warehouse fact tables  
4. inserts tracking events idempotently  
5. finalizes audit status  

This interface represents the **single operational entry point** to the data-processing layer.

---

### A.6 Idempotency Guarantees
Idempotency is enforced as follows:

- Fact tables use primary keys and unique constraints with upserts.  
- Tracking events are inserted only if an identical event does not already exist.  
- Reprocessing the same day multiple times produces the same warehouse state.  

These guarantees allow safe reruns without data corruption.

---

### A.7 Late-Arriving Data Handling
Late-arriving events and promise updates are handled using a **rolling reprocessing window**.

On each run:
- events whose `event_time` falls within the reprocessing window are reconsidered  
- promise updates overwrite the active promise per order line  

This approach balances correctness with performance and avoids full reloads.

---

### A.8 Scope Boundary
This appendix does not define:
- KPI calculations or analytical views  
- data quality validation rules  
- automation or scheduling mechanisms  

Those concerns are addressed in subsequent chapters.
