# Automation & Ops

## 7.1 Purpose
This chapter defines how the analytics system is executed, monitored, and recovered in a
production-like environment.

The goal is not tooling sophistication, but **operational clarity**:
- how the pipeline runs
- how failures are handled
- how reruns are performed safely
- how trust in KPIs is maintained over time

---

## 7.2 Execution Model
The system follows a **daily batch execution model**.

Each daily run consists of:
1. loading that day’s data into staging tables
2. executing the incremental load procedure
3. validating results via audit and quality views

The single operational entry point is the stored procedure:
CALL sp_run_daily_load(p_run_date, p_reprocess_days);

---

## 7.3 Scheduling Options
The system is scheduler-agnostic. Valid execution options include:

- **MySQL Event Scheduler**
- **OS-level cron job**
- **Manual execution (development/testing)**

The scheduler’s responsibility is limited to triggering the stored procedure with
the correct parameters.

---

## 7.4 Standard Run Configuration (v1)
Recommended defaults:
- run frequency: daily
- run date: previous calendar day
- reprocess window: 7 days

Example operational behavior:
- every run re-evaluates the last 7 days to capture late-arriving events
- rerunning the same day produces identical results (idempotent)

---

## 7.5 Failure Handling
Failures are detected via:
- `etl_run_audit.status = 'FAILED'`
- missing or incomplete audit records
- unexpected spikes in data quality violations

On failure:
1. inspect `etl_run_audit.error_message`
2. correct upstream data or logic
3. rerun the affected day(s)

No manual cleanup is required due to idempotent design.

---

## 7.6 Rerun and Backfill Strategy
Reruns are safe and supported.

Common scenarios:
- late-arriving tracking events
- corrected promise dates
- upstream data fixes

Backfills are executed by:
- loading historical data into staging with appropriate `run_date`
- rerunning the procedure for affected dates

---

## 7.7 Monitoring and Health Signals
System health is assessed through:
- audit success rate
- row count stability across runs
- trend of data quality violations

KPIs must not be interpreted in isolation without reviewing quality signals.

---

## 7.8 Operational Scope Boundary
This chapter does not define:
- business KPI logic (Chapter 5)
- data quality rules (Chapter 6)
- visualization tooling
- infrastructure provisioning

---

## Chapter 7 — Definition of Done
This chapter is complete when:
- execution flow is clearly documented
- rerun and backfill procedures are explicit
- failure handling is defined
- operational responsibilities are unambiguous

