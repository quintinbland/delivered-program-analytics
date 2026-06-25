# Delivered Program Analytics

Produce distribution analytics pipeline — dimensional data model, business rule engine, and transformation pipeline built with synthetic data.

---

## Project Status

**Pipeline: COMPLETE — All 6 modules built and committed.**

| Module | Scripts | Status |
|---|---|---|
| 1 — Staging Layer | 5 | ✅ Complete |
| 2 — Dimension Build | 7 | ✅ Complete |
| 3 — Fact Tables | 3 | ✅ Complete |
| 4 — Calculation Engine | 4 | ✅ Complete |
| 5 — Exception System | 6 | ✅ Complete |
| 6 — Reporting Layer | 5 | ✅ Complete |
| 7 — Forecasting | — | 🔲 Future |
| 8 — Planting Readiness | — | 🔲 Future |

---

## Overview

This repository rebuilds a legacy Excel-based delivered produce program analytics system into a production-grade dimensional data model and SQL transformation pipeline. All data is fully synthetic — no real customer, pricing, or operational data is used.

**Purpose:** Professional portfolio demonstration of end-to-end data engineering practices including dimensional modeling, business rule extraction, exception handling, and reporting layer design.

---

## Repository Structure

```
delivered-program-analytics/
├── README.md
├── LICENSE
├── .gitignore
├── .github/
│   └── CHANGELOG.md
├── data/
│   └── dummy/
│       └── DeliveredProgram_DummyDataset.xlsx
├── docs/
│   ├── data_model.md
│   ├── business_rules.md
│   └── unknowns_log.md
└── sql/
    ├── staging/
    │   ├── stg_sales_order_line.sql
    │   ├── stg_load_freight.sql
    │   ├── stg_contract_pricing.sql
    │   ├── stg_product_master.sql
    │   └── stg_customer_reference.sql
    ├── dimensions/
    │   ├── dim_customer_status.sql
    │   ├── dim_commodity.sql
    │   ├── dim_date.sql
    │   ├── dim_carrier.sql
    │   ├── dim_product.sql
    │   ├── dim_shipto.sql
    │   └── dim_customer.sql
    ├── facts/
    │   ├── fact_load_freight.sql
    │   ├── fact_contract_price.sql
    │   └── fact_sales_order_line.sql
    ├── calculations/
    │   ├── calc_freight_summary.sql
    │   ├── calc_fob_variance_summary.sql
    │   ├── calc_customer_performance.sql
    │   └── calc_load_utilization.sql
    ├── exceptions/
    │   ├── exc_missing_contract_pricing.sql
    │   ├── exc_negative_fob_variance.sql
    │   ├── exc_negative_freight_margin.sql
    │   ├── exc_missing_mappings.sql
    │   ├── exc_data_quality.sql
    │   └── exc_master.sql
    └── reporting/
        ├── rpt_executive_summary.sql
        ├── rpt_fob_variance_detail.sql
        ├── rpt_freight_performance.sql
        ├── rpt_exception_dashboard.sql
        └── rpt_customer_scorecard.sql
    ├── implementation/
    │   └── duckdb_patches/
    │       ├── phase1_create_raw_tables.sql  ← Raw DDL (env-specific paths)
    │       ├── phase2_load_raw_data.sql      ← CSV load scripts (local paths)
    │       ├── dim_date_duckdb.sql           ← STRFTIME patch (DuckDB only; swap for dim_date.sql on Snowflake)
    │       └── phase9_reconciliation.sql    ← Reconciliation with env-specific row count baselines
```

---

## Data Architecture

### Source Inputs (6 raw sources)

| Source Table | Description |
|---|---|
| Raw_SalesOrderLine | Sales order transaction lines |
| Raw_LoadFreight | Load and freight records |
| Raw_ContractPricing | Contract FOB pricing rules |
| Raw_ProductMaster | Item and commodity reference |
| Raw_CustomerReference | Customer and HQ reference |
| Raw_ShipToReference | Ship-to location reference |

### Dimensional Model

**Fact Tables**

| Table | Grain | Primary Key |
|---|---|---|
| Fact_SalesOrderLine | One row per SalesOrderID + LoadID + ItemID | SalesOrderLineKey |
| Fact_LoadFreight | One row per LoadID | LoadID |
| Fact_ContractPrice | One row per contract pricing rule | ContractPriceKey |

**Dimension Tables**

| Table | Primary Key | Description |
|---|---|---|
| Dim_Customer | CustomerKey | Customer master with HQ grouping |
| Dim_ShipTo | ShipToKey | Ship-to location master |
| Dim_Product | ProductKey | Item master with commodity FK |
| Dim_Commodity | CommodityKey | Commodity reference |
| Dim_Date | DateKey (YYYYMMDD) | Generated calendar and fiscal date dimension |
| Dim_CustomerStatus | CustomerStatusKey | Contract / OpenMarket / Commit classification |
| Dim_Carrier | CarrierKey | Carrier reference derived from freight data |

**Key Relationships**

- `Fact_SalesOrderLine.LoadID` → `Fact_LoadFreight.LoadID`
- `Fact_SalesOrderLine.ItemID` → `Dim_Product.ItemID`
- `Fact_SalesOrderLine.CustomerID` → `Dim_Customer.CustomerID`
- `Fact_SalesOrderLine.ShipToID` → `Dim_ShipTo.ShipToID`
- `Fact_SalesOrderLine.ShipDateKey` → `Dim_Date.DateKey`
- `Fact_LoadFreight.CarrierID` → `Dim_Carrier.CarrierID`
- `Dim_Product.CommodityID` → `Dim_Commodity.CommodityID`
- `Dim_Customer.CustomerStatusKey` → `Dim_CustomerStatus.CustomerStatusKey`

---

## Build Sequence

Scripts must be executed in dependency order. All scripts within a module are independently deployable within module constraints.

### Module 1 — Staging Layer

No dependencies. Run in any order.

```
sql/staging/stg_customer_reference.sql
sql/staging/stg_product_master.sql
sql/staging/stg_sales_order_line.sql
sql/staging/stg_load_freight.sql
sql/staging/stg_contract_pricing.sql
```

### Module 2 — Dimension Build

Depends on Module 1. Build in dependency order:

```
sql/dimensions/dim_customer_status.sql   -- No dependencies
sql/dimensions/dim_commodity.sql         -- No dependencies
sql/dimensions/dim_date.sql              -- No dependencies
sql/dimensions/dim_carrier.sql           -- Requires Stg_LoadFreight
sql/dimensions/dim_shipto.sql            -- No dependencies
sql/dimensions/dim_product.sql           -- Requires Dim_Commodity
sql/dimensions/dim_customer.sql          -- Requires Dim_CustomerStatus
```

### Module 3 — Fact Tables

Depends on Modules 1 and 2. Build in order:

```
sql/facts/fact_load_freight.sql          -- Requires Dim_Carrier, Dim_ShipTo, Dim_Date
sql/facts/fact_contract_price.sql        -- Requires Dim_Customer, Dim_Product, Dim_Commodity, Dim_Date
sql/facts/fact_sales_order_line.sql      -- Requires all dimensions + Stg_ContractPricing + Fact_LoadFreight
```

### Module 4 — Calculation Engine

Depends on Module 3. Run in any order:

```
sql/calculations/calc_freight_summary.sql
sql/calculations/calc_fob_variance_summary.sql
sql/calculations/calc_load_utilization.sql
sql/calculations/calc_customer_performance.sql
```

### Module 5 — Exception System

Depends on Modules 1–3. Run individual scripts before master:

```
sql/exceptions/exc_missing_contract_pricing.sql
sql/exceptions/exc_negative_fob_variance.sql
sql/exceptions/exc_negative_freight_margin.sql
sql/exceptions/exc_missing_mappings.sql
sql/exceptions/exc_data_quality.sql
sql/exceptions/exc_master.sql            -- Run last; depends on all above
```

### Module 6 — Reporting Layer

Depends on Modules 4 and 5. Run in any order:

```
sql/reporting/rpt_executive_summary.sql
sql/reporting/rpt_fob_variance_detail.sql
sql/reporting/rpt_freight_performance.sql
sql/reporting/rpt_exception_dashboard.sql
sql/reporting/rpt_customer_scorecard.sql
```

---

## Key Business Logic

### Pricing

| Measure | Formula | Null Condition |
|---|---|---|
| ActualFOB | `NetLineRevenue / QuantityCases` | NULL if QuantityCases = 0 or NULL |
| FOBVariancePerCase | `ActualFOB - ContractFOBPrice` | NULL if either input is NULL |
| TotalFOBVariance | `FOBVariancePerCase * QuantityCases` | NULL if either input is NULL |
| ExcessSalesProfit | `TotalFOBVariance` | Explicit alias — always equals TotalFOBVariance |

### Freight

| Measure | Formula | Null Condition |
|---|---|---|
| FreightMargin | `FreightCharged - FreightPaid` | NULL if either input is NULL |
| FreightMarginPct | `FreightMargin / FreightCharged` | NULL if FreightCharged = 0 or NULL |

### Contract Matching Hierarchy (CANDIDATE — UNK-001)

| Tier | Match Keys |
|---|---|
| Tier 1 | CustomerID + ItemID + ShipDate within effective range |
| Tier 2 | CustomerHQID + ItemID + ShipDate within effective range |
| Tier 3 | CustomerHQID + CommodityID + ShipDate within effective range |
| Tier 4 | No match → ContractFOBPrice = NULL |

All contract-matched rows carry `Flag_CandidateHierarchy_UNK001 = 1`.

### Load Utilization (CANDIDATE — UNK-002)

| Band | Condition |
|---|---|
| Full | LoadPallets >= 24 |
| Partial | LoadPallets >= 18 AND < 24 |
| Underutilized | LoadPallets < 18 |
| UNKNOWN | LoadPallets IS NULL |

Threshold of 24 is a candidate value. All rows carry `Flag_CandidateThreshold_UNK002 = 1`.

---

## Exception Types

| Exception | Rule | Severity |
|---|---|---|
| MISSING_CONTRACT_PRICING | CustomerStatus = CONTRACT AND ContractFOBPrice IS NULL | HIGH |
| NEGATIVE_FOB_VARIANCE | TotalFOBVariance < 0 | HIGH |
| NEGATIVE_FREIGHT_MARGIN | FreightMargin < 0 | HIGH |
| MISSING_COMMODITY_MAPPING | ItemID IS NOT NULL AND CommodityID IS NULL | MEDIUM |
| MISSING_CUSTOMER_MAPPING | CustomerID in transactions NOT IN Dim_Customer | HIGH |
| MISSING_SHIPTO_MAPPING | ShipToID in transactions NOT IN Dim_ShipTo | MEDIUM |
| DUPLICATE_SALES_LINE_KEY | COUNT(SalesOrderID + LoadID + ItemID) > 1 | HIGH |
| INVALID_QUANTITY | QuantityCases <= 0 OR QuantityCases IS NULL | HIGH |
| MISSING_LOAD_ID | LoadID IS NULL on sales order line | HIGH |
| DUPLICATE_LOAD_ID | COUNT(LoadID) > 1 in Stg_LoadFreight | HIGH |
| DUPLICATE_CONTRACT_KEY | COUNT(ContractPriceKey) > 1 in Stg_ContractPricing | HIGH |
| INVERTED_CONTRACT_DATE | EffectiveDate > ExpirationDate | HIGH |

All exceptions are unified in `Exc_Master` with owner domain, resolution guidance, and resolution status tracking.

---

## SQL Dialect

ANSI SQL (T-SQL / Snowflake compatible). All dialect-specific syntax is marked inline with `[DIALECT NOTE]`. The `dim_date.sql` script includes both a Snowflake primary block and a commented T-SQL equivalent.

---

## Open Unknowns

See `docs/unknowns_log.md` for full tracking. Top open items affecting pipeline behavior:

| ID | Item | Impact | Affected Scripts |
|---|---|---|---|
| UNK-001 | Contract matching hierarchy — candidate applied | HIGH | fact_sales_order_line, fact_contract_price, all calc/rpt scripts |
| UNK-002 | Target full truckload pallet threshold = 24 (candidate) | MEDIUM | stg_load_freight, fact_load_freight, calc_freight_summary, calc_load_utilization, rpt_freight_performance |
| UNK-003 | OnTargetFlag row-level definition | HIGH | Excluded from all scripts pending confirmation |
| UNK-004 | Rolling period date basis / fiscal year start | MEDIUM | dim_date fiscal calendar fields |
| UNK-007 | FreightCharged semantics (billed / budgeted / allocated) | HIGH | stg_load_freight, fact_load_freight, exc_negative_freight_margin |

---

## Synthetic Dataset

Located at `data/dummy/DeliveredProgram_DummyDataset.xlsx`.

12 entities covering all tables in the canonical data model. Intentional data quality issues baked in for pipeline and exception testing including: missing commodity mappings, duplicate keys, invalid quantities, NULL LoadIDs, negative margin transactions, and contract customers with no matching contract records.

---

## License

MIT
