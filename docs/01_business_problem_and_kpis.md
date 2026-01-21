# Business Problem & KPIs

## 1.1 Business Context
This project models a mid-sized logistics operation serving multiple customers across the Benelux region. The organization fulfills customer orders from centralized warehouses, hands shipments over to external carriers, and commits to delivery promises based on predefined service levels.

While delivery performance is tracked at an aggregate level, management lacks visibility into the operational drivers behind late or incomplete deliveries. Existing reporting focuses on outcomes, not causes, limiting the organization’s ability to take targeted corrective action.

---

## 1.2 Core Business Problem
The organization lacks a reliable and explainable view of **On-Time In-Full (OTIF)** performance across the full order-to-delivery lifecycle.

Specifically:
- Delivery failures are observed, but the root causes (warehouse operations vs transport execution) are unclear.
- Partial deliveries are inconsistently reported and not systematically linked to OTIF.
- Performance variation across carriers, lanes, service levels, and customers is not transparent.
- Aggregate reporting hides deterioration or improvement for specific groups of orders over time.

As a result, operational decisions are reactive and not supported by data-driven insights.

---

## 1.3 Decisions the System Must Support
The analytics system is designed to support the following decisions:

1. **Carrier and lane performance management**  
   Identify carriers or routes that consistently underperform on OTIF.

2. **Operational bottleneck identification**  
   Determine whether delays originate in warehouse operations or during transport.

3. **Service-level governance**  
   Evaluate whether express and standard services perform according to expectations.

4. **Customer impact assessment**  
   Identify customers most affected by late or incomplete deliveries.

5. **Performance trend monitoring**  
   Track whether OTIF performance improves or deteriorates for cohorts of orders promised in the same time period.

All KPIs and analytics must directly support one or more of these decisions.

---

## 1.4 KPI Definitions

### 1.4.1 Evaluation Grain
OTIF is evaluated at the **order-line level**.  
An order is considered OTIF-compliant only if **all associated order lines** are OTIF-compliant.

This approach prevents overstating performance when partial deliveries occur.

---

### 1.4.2 On-Time
An order line is considered **On-Time** if the delivery date is **on or before the promised delivery date**.

Rules:
- Calendar days are used for evaluation.
- Weekend delivery is not allowed; weekends are excluded from delivery days.

---

### 1.4.3 In-Full
An order line is considered **In-Full** if the delivered quantity equals the ordered quantity.

Partial deliveries, shortages, or backorders result in an In-Full failure, even if delivery occurs on time.

---

### 1.4.4 OTIF
An order line is **OTIF-compliant** if it is both:
- On-Time  
- In-Full  

The OTIF rate is defined as:

OTIF Rate = (Number of OTIF-compliant order lines) / (Total number of order lines)

---

## 1.5 Supporting Metrics
To diagnose OTIF outcomes, the system must also provide:

- On-Time rate
- In-Full rate
- Lead-time metrics:
  - Order to pick
  - Pick to ship
  - Ship to deliver
- Backlog of open orders past promised delivery date
- Aging of overdue orders
- Counts of delivery exceptions and incomplete shipments

These metrics support root-cause analysis rather than high-level reporting.

---

## 1.6 Time-Based Analysis Requirements
The analytics system must support time-based analysis, including:

- Daily OTIF tracking
- Rolling performance windows (e.g., last 7 and 28 days)
- Cohort analysis, grouping orders by promised delivery period and tracking final outcomes

---

## 1.7 Assumptions & Scope
The following assumptions apply throughout the project:

- Geography: Benelux
- Service levels:
  - Standard: D+3
  - Express: D+1
- OTIF evaluated at the order-line level
- On-Time defined as delivery on or before promised date
- In-Full defined as full quantity delivered
- Weekend delivery excluded
- Data arrives incrementally, with late-arriving updates handled downstream

---

## Chapter 1 — Definition of Done
This chapter is complete when:
- The business problem is clearly articulated.
- KPI definitions are precise and unambiguous.
- Evaluation grain is explicitly stated.
- Assumptions and scope are documented and fixed.
- All KPIs map directly to concrete business decisions.

