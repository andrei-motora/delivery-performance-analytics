# Delivery Performance Analytics Data Warehouse

A complete MySQL data warehouse solution for tracking and analyzing logistics delivery performance, built to demonstrate real-world data engineering skills.

## Project Summary

This project solves a common business problem in logistics: **measuring On-Time In-Full (OTIF) delivery performance** across carriers, warehouses, and shipping lanes. OTIF is a critical KPI that measures whether orders arrive on time and with the correct quantity.

### What I Built

- **Dimensional data warehouse** using star schema design principles
- **Automated ETL pipeline** with staging tables, stored procedures, and audit logging
- **KPI analytics layer** with pre-built views for business reporting
- **Data quality framework** to ensure metric trustworthiness
- **Sample data generator** producing realistic test data with configurable parameters

### Technologies Used

- MySQL 8.0
- SQL (DDL, DML, CTEs, Window Functions, Stored Procedures)
- Dimensional Modeling (Star Schema)
- ETL Design Patterns

---

## Business Context

In logistics and e-commerce, delivery performance directly impacts customer satisfaction and operational costs. This warehouse answers questions like:

- What percentage of orders are delivered on time and in full?
- Which carriers perform best/worst?
- Which warehouses have fulfillment issues?
- Which shipping lanes are problematic?
- Are there data quality issues affecting our metrics?

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SOURCE SYSTEMS                           │
│         (Orders, Shipments, Tracking Events, etc.)              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       STAGING LAYER                             │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌─────────────────┐  │
│  │stg_orders │ │stg_order_ │ │stg_promises│ │stg_shipments   │  │
│  │           │ │lines      │ │           │ │                 │  │
│  └───────────┘ └───────────┘ └───────────┘ └─────────────────┘  │
│  ┌─────────────────┐ ┌─────────────────────┐                    │
│  │stg_shipment_    │ │stg_tracking_events  │                    │
│  │lines            │ │                     │                    │
│  └─────────────────┘ └─────────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼ sp_run_daily_load()
┌─────────────────────────────────────────────────────────────────┐
│                      DATA WAREHOUSE                             │
│                                                                 │
│   DIMENSIONS                      FACTS                         │
│  ┌────────────────┐            ┌─────────────────────┐          │
│  │ dim_date       │            │ fact_orders         │          │
│  │ dim_customer   │            │ fact_order_lines    │          │
│  │ dim_product    │◄──────────►│ fact_promises       │          │
│  │ dim_warehouse  │            │ fact_shipments      │          │
│  │ dim_carrier    │            │ fact_shipment_lines │          │
│  │ dim_service_   │            │ fact_tracking_events│          │
│  │   level        │            └─────────────────────┘          │
│  │ dim_lane       │                                             │
│  └────────────────┘                                             │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ANALYTICS LAYER                            │
│                                                                 │
│   KPI VIEWS                        DATA QUALITY VIEWS           │
│  ┌────────────────────────┐      ┌────────────────────────────┐ │
│  │ vw_kpi_otif            │      │ dq_missing_or_invalid_     │ │
│  │ vw_carrier_performance │      │   promise                  │ │
│  │ vw_warehouse_performance│     │ dq_shipment_line_integrity │ │
│  │ vw_lane_performance    │      │ dq_kpi_risk_summary        │ │
│  └────────────────────────┘      └────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Database Schema

### Dimension Tables

| Table | Description |
|-------|-------------|
| `dim_date` | Calendar dimension with year, month, week, day attributes |
| `dim_customer` | Customer master data with segmentation (Retail/B2B) |
| `dim_product` | Product catalog with categories |
| `dim_warehouse` | Fulfillment center locations |
| `dim_carrier` | Shipping carriers (DHL, UPS, DPD, etc.) |
| `dim_service_level` | Service tiers (Standard: 3 days, Express: 1 day) |
| `dim_lane` | Origin-destination shipping routes with distances |

### Fact Tables

| Table | Description | Grain |
|-------|-------------|-------|
| `fact_orders` | Order headers | One row per order |
| `fact_order_lines` | Order line items | One row per product per order |
| `fact_promises` | Delivery promises | One row per order line |
| `fact_shipments` | Shipment records | One row per shipment |
| `fact_shipment_lines` | Shipment-to-order mapping | One row per order line per shipment |
| `fact_tracking_events` | Carrier tracking milestones | One row per event per shipment |

### Key Relationships

```
fact_orders (1) ──── (N) fact_order_lines (1) ──── (1) fact_promises
                              │
                              │ (N)
                              ▼
                     fact_shipment_lines
                              │
                              │ (N)
                              ▼
fact_shipments (1) ──── (N) fact_tracking_events
```

---

## ETL Pipeline

### Daily Load Process

The `sp_run_daily_load` stored procedure handles incremental data loading:

1. **Dimension upserts** - New customers, products, carriers, lanes are added automatically
2. **Fact upserts** - Orders, shipments, promises are merged (insert or update)
3. **Event deduplication** - Tracking events use natural key checks to prevent duplicates
4. **Audit logging** - Every run is logged with row counts and status

### Features

- **Idempotent** - Safe to re-run without creating duplicates
- **Reprocessing window** - Configurable lookback period for late-arriving data
- **Error handling** - Failed runs are logged with error messages
- **Audit trail** - Full visibility into ETL history

```sql
-- Example: Run daily load for January 15, 2025 with 3-day reprocessing window
CALL sp_run_daily_load('2025-01-15', 3);
```

---

## Analytics & KPIs

### OTIF Calculation

OTIF (On-Time In-Full) measures perfect order fulfillment:

- **On-Time**: Delivered on or before the promised delivery date
- **In-Full**: Shipped quantity meets or exceeds ordered quantity
- **OTIF**: Both conditions met

```sql
-- Core OTIF logic from vw_order_line_delivery_status
CASE
  WHEN actual_delivery_at IS NOT NULL
   AND DATE(actual_delivery_at) <= promised_delivery_date
   AND shipped_qty >= ordered_qty
  THEN 1 ELSE 0
END AS is_otif
```

### Available KPI Views

| View | Description | Sample Output |
|------|-------------|---------------|
| `vw_kpi_otif` | Daily OTIF rates | Date, order_lines, otif_lines, otif_rate |
| `vw_carrier_performance` | OTIF by carrier | Carrier, order_lines, otif_rate |
| `vw_warehouse_performance` | OTIF by warehouse | Warehouse, order_lines, otif_rate |
| `vw_lane_performance` | OTIF by shipping lane | Lane, order_lines, otif_rate |

---

## Data Quality Framework

Proactive data quality checks ensure trustworthy metrics:

| Check | Rule ID | Description |
|-------|---------|-------------|
| `dq_order_line_without_order` | DQ_ORD_001 | Orphaned order lines |
| `dq_invalid_ordered_qty` | DQ_ORD_002 | Zero or negative quantities |
| `dq_missing_or_invalid_promise` | DQ_PRM_001 | Missing or illogical promise dates |
| `dq_shipment_line_integrity` | DQ_SHP_001 | Broken shipment references |
| `dq_delivered_before_shipped` | DQ_EVT_001 | Impossible delivery timestamps |
| `dq_duplicate_tracking_events` | DQ_EVT_002 | Duplicate tracking records |
| `dq_kpi_risk_summary` | - | Aggregated risk exposure for KPIs |

---

## Installation & Setup

### Prerequisites

- MySQL 8.0 or higher

### Quick Start

Run the scripts in order:

```bash
# 1. Create schema
mysql -u <user> -p <database> < sql/01_schema.sql

# 2. Seed reference data
mysql -u <user> -p <database> < sql/02_seed_dimensions.sql

# 3. Create ETL pipeline
mysql -u <user> -p <database> < sql/03_incremental_load.sql

# 4. Create KPI views
mysql -u <user> -p <database> < sql/04_kpi_views.sql

# 5. Create data quality views
mysql -u <user> -p <database> < sql/05_data_quality_checks.sql

# 6. Load sample data (optional)
mysql -u <user> -p <database> < sql/06_sample_data.sql
```

---

## Sample Data

The `06_sample_data.sql` script generates realistic test data:

| Metric | Value |
|--------|-------|
| Orders | ~1,050 |
| Order Lines | ~1,890 |
| Shipments | ~1,009 |
| Tracking Events | ~5,045 |
| Date Range | 21 days |
| OTIF Distribution | ~85% on-time, ~10% one day late, ~5% two+ days late |

### Configuration

```sql
-- Adjust these parameters at the top of 06_sample_data.sql
SET @start_date = '2025-01-01';
SET @end_date = '2025-01-21';
SET @orders_per_day = 50;
```

---

## Sample Queries

### Daily OTIF Trend

```sql
SELECT 
  promised_delivery_date,
  order_lines,
  otif_lines,
  CONCAT(ROUND(otif_rate * 100, 1), '%') AS otif_pct
FROM vw_kpi_otif
ORDER BY promised_delivery_date;
```

### Worst Performing Carriers

```sql
SELECT 
  carrier_name,
  order_lines,
  CONCAT(ROUND(otif_rate * 100, 1), '%') AS otif_pct
FROM vw_carrier_performance
ORDER BY otif_rate ASC
LIMIT 5;
```

### Data Quality Health Check

```sql
SELECT * FROM dq_kpi_risk_summary;
```

---

## Sample Results

### Carrier Performance
| carrier_name | order_lines | otif_lines | otif_rate |
|--------------|-------------|------------|-----------|
| DHL          | 280         | 272        | 0.9714    |
| UPS          | 258         | 250        | 0.9690    |
| POSTNL       | 254         | 245        | 0.9646    |
| DPD          | 350         | 308        | 0.8800    |
| GLS          | 326         | 285        | 0.8742    |
| BPOST        | 350         | 304        | 0.8686    |

### Warehouse Performance
| warehouse_name | order_lines | otif_lines | otif_rate |
|----------------|-------------|------------|-----------|
| WH_NL_01       | 280         | 272        | 0.9714    |
| WH_BE_01       | 258         | 250        | 0.9690    |
| WH_NL_03       | 254         | 245        | 0.9646    |
| WH_NL_02       | 350         | 308        | 0.8800    |
| WH_NL_04       | 326         | 285        | 0.8742    |
| WH_DE_01       | 350         | 304        | 0.8686    |

---

## Project Structure

```
├── sql/
│   ├── 01_schema.sql              # Table definitions (dimensions + facts)
│   ├── 02_seed_dimensions.sql     # Reference data (dates, carriers, warehouses)
│   ├── 03_incremental_load.sql    # Staging tables + ETL stored procedure
│   ├── 04_kpi_views.sql           # Analytics views for OTIF metrics
│   ├── 05_data_quality_checks.sql # Data quality validation views
│   └── 06_sample_data.sql         # Sample data generator
├── diagrams/                      # Architecture diagrams
└── README.md
```

---

## Skills Demonstrated

- **Data Modeling**: Star schema design, fact/dimension separation, grain definition
- **SQL Development**: Complex queries, CTEs, aggregations, stored procedures
- **ETL Design**: Staging patterns, idempotent loads, error handling, audit logging
- **Data Quality**: Validation rules, referential integrity checks, risk assessment
- **Documentation**: Clear technical writing for both technical and business audiences

---

## Future Enhancements

- [ ] Add slowly changing dimension (SCD Type 2) support for customer/product history
- [ ] Create materialized views for large-scale performance optimization
- [ ] Add time-to-delivery metrics (average days early/late)
- [ ] Build exception reporting for late deliveries
- [ ] Add carrier cost analysis dimensions

---

## License

MIT

---

## Contact

Feel free to reach out with questions or feedback!
