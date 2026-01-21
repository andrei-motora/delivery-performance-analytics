# Source & Raw Data

## 2.1 Purpose of This Layer
This chapter defines the raw operational data that feeds the Delivery Performance Analytics system.
It focuses on *what data exists*, *where it originates*, and *how it behaves* before any transformation,
modeling, or KPI computation occurs.

The goal of this layer is not analytical readiness, but faithful representation of operational reality.

---

## 2.2 Operational Data Domains
The system models the full order-to-delivery lifecycle using the following raw data domains.

### Orders
Represents customer purchase orders placed with the organization.

Characteristics:
- Created at order time
- Can contain multiple order lines
- May be modified after creation (e.g. cancellations, quantity changes)

---

### Order Lines
Represents individual product-level line items within an order.

Characteristics:
- Each

