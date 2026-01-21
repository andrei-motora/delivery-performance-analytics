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
- Each order can contain multiple order lines
- Quantities are defined at line level
- Fulfillment and OTIF evaluation occur at this level

---

### Delivery Promises
Represents the committed ship and delivery dates agreed with the customer.

Characteristics:
- Defined at order or order-line level
- Dependent on service level (e.g. standard vs express)
- Can change after order creation due to replanning

---

### Shipments
Represents physical shipment executions.

Characteristics:
- One order can be split into multiple shipments
- Shipments may contain multiple order lines
- Shipment creation may occur after order creation

---

### Shipment Lines
Represents the quantity of a specific order line shipped in a given shipment.

Characteristics:
- Partial shipments are possible
- A single order line may appear in multiple shipment lines

---

### Tracking Events
Represents time-stamped operational events generated during fulfillment and transport.

Typical events include:
- Order picked
- Order packed
- Shipment dispatched
- In transit
- Out for delivery
- Delivered
- Exception (delay, damage, return)

Characteristics:
- Multiple events per shipment
- Events may arrive out of order
- Some events may be missing or delayed

---

## 2.3 Data Arrival Characteristics
Raw operational data exhibits the following behaviors:

- Data arrives incrementally on a daily basis
- Events may arrive late relative to the actual occurrence time
- Records may be updated after initial ingestion
- Data completeness is not guaranteed at ingestion time

These characteristics require downstream logic to handle late-arriving data and corrections.

---

## 2.4 Hybrid Data Approach
To balance realism and control, the project uses a hybrid data approach:

- Public reference data (e.g. geographic locations) to anchor realism
- Synthetic operational data to fully model required edge cases such as:
  - Partial deliveries
  - Late deliveries
  - Missing or delayed events
  - Replanned delivery promises

All data is treated as if sourced from operational systems.

---

## 2.5 Constraints and Non-Goals
This layer does not attempt to:
- Clean or standardize data
- Resolve duplicates
- Compute KPIs
- Enforce business rules

These responsibilities belong to downstream layers.

---

## Chapter 2 — Definition of Done
This chapter is complete when:
- All raw data domains are clearly defined
- Data arrival behavior is explicitly described
- Limitations and imperfections of raw data are acknowledged
- No analytical assumptions are applied at this stage
