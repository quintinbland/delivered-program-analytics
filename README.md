# Delivered Program Analytics System

A production-grade analytics pipeline for delivered produce distribution — rebuilt from a legacy workbook-based process into a normalized, modular, automation-ready data system.

---

## Overview

This project redesigns an operational analytics workflow used to manage the economics of a delivered produce program. The original system was a complex, formula-heavy workbook. This rebuild replaces it with a structured dimensional data model, a rule-based calculation engine, and a modular transformation pipeline designed for Power BI or any modern BI platform.

**Core business questions this system answers:**

- How profitable is each delivered load after freight cost?
- How does actual FOB price compare to contracted FOB by customer and commodity?
- Which customers, ship-to locations, and commodities are driving margin erosion?
- Where are contract pricing gaps, freight losses, and underutilized loads?

---

## System Architecture

```
RAW INPUTS
├── ERP sales/order line data
├── Load-level freight data
├── Contract pricing reference
├── Product master / commodity mapping
└── Customer / ship-to reference
        ↓
STAGING LAYER
└── Standardize, deduplicate, validate
        ↓
DIMENSIONAL MODEL
├── Facts:  SalesOrderLine · LoadFreight · ContractPrice
└── Dims:   Customer · ShipTo · Product · Commodity · Date · Carrier · CustomerStatus
        ↓
CALCULATION ENGINE
└── ActualFOB · FOBVariance · FreightMargin · ContractMatchRate · LoadUtilization
        ↓
EXCEPTION DETECTION
└── Missing contracts · Negative margins · Orphan records · Duplicate keys · Invalid data
        ↓
REPORTING LAYER
└── Executive KPIs · Customer HQ · Ship-To Drilldown · Commodity · Time Period
```

---

## Repository Structure

```
delivered-program-analytics/
│
├── README.md
│
├── data/
│   └── dummy/
│       └── DeliveredProgram_DummyDataset.xlsx   # Synthetic validation dataset
│
├── sql/
│   ├── staging/          # Raw → staging transformations
│   ├── dimensions/       # Dimension table builds
│   ├── facts/            # Fact table builds
│   ├── calculations/     # Business measure logic
│   ├── exceptions/       # Exception detection queries
│   └── reporting/        # Reporting layer aggregations
│
├── scripts/
│   └── generate_dummy_data.py    # Reproducible synthetic dataset generator
│
├── docs/
│   ├── data_model.md             # Entity definitions and relationships
│   ├── business_rules.md         # Full rule set documentation
│   ├── system_spec.md            # Complete system rebuild specification
│   └── unknowns_log.md           # Open items requiring business confirmation
│
└── .github/
    └── CHANGELOG.md
```

---

## Data Model

### Fact Tables

| Table | Grain | Primary Key | Row Count (Dummy) |
|---|---|---|---|
| `Fact_SalesOrderLine` | One row per order line / item / load | `SalesOrderLineKey` | ~366 |
| `Fact_LoadFreight` | One row per load | `LoadID` | ~121 |
| `Fact_ContractPrice` | One row per contract pricing rule | `ContractPriceKey` | ~55 |

### Dimension Tables

| Table | Description |
|---|---|
| `Dim_Customer` | Customer master with HQ grouping and status |
| `Dim_ShipTo` | Destination / DC level |
| `Dim_Product` | Item master with commodity mapping |
| `Dim_Commodity` | Governed commodity hierarchy |
| `Dim_Date` | Calendar with YTD, rolling 4-week, rolling 8-week flags |
| `Dim_CustomerStatus` | Contract / Open Market / Commit classification |
| `Dim_Carrier` | Freight carrier master |

### Key Relationships

```
Fact_SalesOrderLine.LoadID      → Fact_LoadFreight.LoadID
Fact_SalesOrderLine.ItemID      → Dim_Product.ItemID
Fact_SalesOrderLine.CustomerID  → Dim_Customer.CustomerID
Fact_SalesOrderLine.ShipToID    → Dim_ShipTo.ShipToID
Fact_SalesOrderLine.ShipDateKey → Dim_Date.DateKey
Fact_LoadFreight.CarrierID      → Dim_Carrier.CarrierID
Dim_Product.CommodityID         → Dim_Commodity.CommodityID
Dim_Customer.CustomerStatusKey  → Dim_CustomerStatus.CustomerStatusKey
```

---

## Business Rule Engine

All business logic is extracted into explicit, structured rule definitions. No logic is embedded in formulas or implicit in transformations.

### Pricing Rules

```
ActualFOB:
  IF QuantityCases > 0
  THEN ActualFOB = NetLineRevenue / QuantityCases
  ELSE ActualFOB = NULL

FOBVariancePerCase:
  IF ActualFOB IS NOT NULL AND ContractFOB IS NOT NULL
  THEN FOBVariancePerCase = ActualFOB - ContractFOB
  ELSE FOBVariancePerCase = NULL

TotalFOBVariance:
  IF FOBVariancePerCase IS NOT NULL
  THEN TotalFOBVariance = FOBVariancePerCase * QuantityCases
  ELSE TotalFOBVariance = NULL

PricingResult:
  IF TotalFOBVariance > 0  → 'Favorable'
  IF TotalFOBVariance = 0  → 'At Contract'
  IF TotalFOBVariance < 0  → 'Unfavorable'
  IF TotalFOBVariance IS NULL → 'No Contract Match'
```

### Freight Rules

```
FreightMargin    = FreightCharged - FreightPaid

FreightMarginPct:
  IF FreightCharged > 0
  THEN FreightMarginPct = FreightMargin / FreightCharged
  ELSE FreightMarginPct = NULL
```

### Load Utilization Rules

```
LoadUtilizationBand:
  IF LoadPallets >= 24  → 'Full'
  IF LoadPallets >= 18  → 'Partial'
  IF LoadPallets < 18   → 'Underutilized'

  NOTE: TargetFullTruckloadPallets = UNKNOWN — 24 used as candidate threshold
```

### Contract Matching Hierarchy (Candidate — Pending Confirmation)

```
1. CustomerID  + ItemID      + ShipDate within effective dates
2. CustomerHQID + ItemID     + ShipDate within effective dates
3. CustomerHQID + CommodityID + ShipDate within effective dates
4. No Match → ContractFOB = NULL, ContractMatchFlag = FALSE
```

---

## Exception Detection

| Exception | Rule |
|---|---|
| Missing Contract Pricing | `CustomerStatus = 'Contract' AND ContractFOB IS NULL` |
| Negative FOB Variance | `TotalFOBVariance < 0` |
| Negative Freight Margin | `FreightMargin < 0` |
| Missing Commodity Mapping | `ItemID IS NOT NULL AND CommodityID IS NULL` |
| Missing Customer Mapping | `CustomerID in transactions AND not in Dim_Customer` |
| Missing Ship-To Mapping | `ShipToID in transactions AND not in Dim_ShipTo` |
| Duplicate Sales Line Key | `COUNT(SalesOrderID + LoadID + ItemID) > 1` |
| Invalid Quantity | `QuantityCases <= 0 OR QuantityCases IS NULL` |
| Missing LoadID | `LoadID IS NULL` |
| Underutilized Load | `LoadPallets < TargetFullTruckloadPallets` |

---

## Reporting Outputs

| Report | Audience | Key Metrics |
|---|---|---|
| Executive KPI Overview | Leadership | Revenue, cases, FOB variance, freight margin, load count |
| Customer HQ Freight Performance | Sales / Ops | Freight charged, paid, margin %, avg pallets/load |
| Customer Status Freight Performance | Finance | Contract vs Open Market vs Commit freight economics |
| Customer HQ Sales Variance | Sales / Pricing | FOB variance by customer HQ, contract match rate |
| Ship-To Performance Drilldown | Account Mgmt | DC-level margin, cases, load metrics |
| Ship-To Commodity Pricing Detail | Pricing | Actual vs contract FOB by DC and commodity |
| Ship-To Load Metrics | Logistics | Load efficiency at DC level |
| Time Period Performance Summary | Leadership | Last 4W / Last 8W / YTD comparison |

---

## Synthetic Dataset

The `data/dummy/` directory contains a fully synthetic dataset generated by `scripts/generate_dummy_data.py`. It is not derived from any real operational data.

**Intentional data quality issues included for pipeline testing:**

| Issue | Location | Exception Triggered |
|---|---|---|
| NULL CommodityID | 2 product records | `Missing Commodity Mapping` |
| NULL ShipToID | 3 load records | `Missing ShipTo Mapping` |
| Duplicate LoadID (conflicting FreightCharged) | Fact_LoadFreight | `Duplicate LoadID` |
| Contract customer with no ContractFOB | 3 sales lines | `Missing Contract Pricing` |
| NULL QuantityCases | 3 sales lines | `Invalid Quantity` |
| Duplicate SalesOrderLineKey (conflicting UnitPrice) | Fact_SalesOrderLine | `Duplicate Transaction Key` |
| Negative FOB variance | 3 sales lines | `Negative FOB Variance` |
| Negative freight margin | ~15% of loads | `Negative Freight Margin` |
| Orphan ShipTo → ghost CustomerID | STO012 | Referential integrity stress test |
| Expired contract record | Fact_ContractPrice | Date filter boundary test |

---

## Open Items

The following items require business confirmation before production implementation. See `docs/unknowns_log.md` for full tracking.

- Contract matching hierarchy (exact priority order)
- Target full truckload pallet threshold
- `OnTargetFlag` exact row-level definition
- Rolling period date basis (system date vs. latest ship date vs. user-selected)
- Refresh cadence and credential ownership
- Whether freight charged represents billed, budgeted, allocated, or contractual amount
- Whether organic/conventional flag is a governed field or inferred

---

## Build Sequence

| Step | Module | Output |
|---|---|---|
| 1 | Data Ingestion | Staging tables |
| 2 | Dimension Build | Dim_* tables |
| 3 | Freight Fact | Fact_LoadFreight |
| 4 | Sales Line Fact | Fact_SalesOrderLine |
| 5 | Contract Pricing Fact | Fact_ContractPrice |
| 6 | Calculation Engine | Standard measures |
| 7 | Exception System | Exception tables |
| 8 | Reporting Layer | Dashboard outputs |
| 9 | Forecasting *(future)* | Fact_Forecast |
| 10 | Planting Readiness *(future)* | Fact_PlantingReadiness |

---

## Status

| Module | Status |
|---|---|
| System Specification | ✅ Complete |
| Dummy Dataset | ✅ Complete |
| SQL — Staging Layer | 🔲 In Progress |
| SQL — Dimension Build | 🔲 Planned |
| SQL — Fact Build | 🔲 Planned |
| SQL — Calculation Engine | 🔲 Planned |
| SQL — Exception Detection | 🔲 Planned |
| SQL — Reporting Layer | 🔲 Planned |
| Power BI Model | 🔲 Future |
| Forecasting Module | 🔲 Future |

---

## Technologies

- **Data Model:** Dimensional (star schema), production SQL-ready
- **Transformation Logic:** SQL (ANSI-compatible, tested against T-SQL / Snowflake dialect)
- **Synthetic Data:** Python (pandas, numpy, openpyxl)
- **Target BI Platform:** Power BI (semantic model)
- **Source System:** ERP (Dynamics AX / connected export)

---

*This project uses entirely synthetic data. No real customer, pricing, or operational data is included.*
