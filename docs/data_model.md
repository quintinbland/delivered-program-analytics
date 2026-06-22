# Data Model

## Design Principles

- **Star schema** — fact tables at center, dimensions at edges
- **Single grain per fact table** — no mixed granularity
- **Surrogate keys** — all primary keys are system-generated, not dependent on source system stability
- **Business keys preserved** — source IDs retained as separate fields for traceability
- **No logic in the model** — all calculations live in the transformation/calculation layer

---

## Entity Definitions

### Fact_SalesOrderLine

**Grain:** One row per SalesOrderID + LoadID + ItemID  
**Primary Key:** `SalesOrderLineKey`  
**Description:** Item-level sales, order, and shipment activity. Core fact for revenue, FOB variance, and contract compliance analysis.

| Field | Type | Description |
|---|---|---|
| SalesOrderLineKey | VARCHAR | Surrogate key |
| SalesOrderID | VARCHAR | Source sales order identifier |
| LoadID | VARCHAR | FK → Fact_LoadFreight |
| ItemID | VARCHAR | FK → Dim_Product |
| CustomerID | VARCHAR | FK → Dim_Customer |
| ShipToID | VARCHAR | FK → Dim_ShipTo |
| ShipDateKey | INTEGER | FK → Dim_Date |
| ShipDate | DATE | Actual ship date |
| QuantityCases | NUMERIC | Cases shipped |
| UnitPrice | NUMERIC | Price per case at order |
| GrossLineRevenue | NUMERIC | QuantityCases × UnitPrice |
| AdjustmentAmount | NUMERIC | Line-level price adjustment |
| NetLineRevenue | NUMERIC | GrossLineRevenue + AdjustmentAmount |
| ActualFOB | NUMERIC | NetLineRevenue / QuantityCases |
| ContractFOB | NUMERIC | Matched contract price (NULL if no match) |
| FOBVariancePerCase | NUMERIC | ActualFOB − ContractFOB |
| TotalFOBVariance | NUMERIC | FOBVariancePerCase × QuantityCases |
| ContractMatchFlag | BOOLEAN | TRUE if contract price was matched |
| ContractMatchLevel | VARCHAR | Matching tier used |
| SourceSystem | VARCHAR | Origin system identifier |
| RefreshBatchID | VARCHAR | ETL batch reference |

---

### Fact_LoadFreight

**Grain:** One row per LoadID  
**Primary Key:** `LoadID`  
**Description:** Load-level freight economics. One row per shipment. Connects to sales lines via LoadID.

| Field | Type | Description |
|---|---|---|
| LoadID | VARCHAR | Primary key — unique load identifier |
| ShipDateKey | INTEGER | FK → Dim_Date |
| ShipDate | DATE | Load ship date |
| CustomerID | VARCHAR | FK → Dim_Customer |
| ShipToID | VARCHAR | FK → Dim_ShipTo |
| CarrierID | VARCHAR | FK → Dim_Carrier |
| LoadPallets | INTEGER | Pallet count for load |
| FreightCharged | NUMERIC | Freight amount charged/budgeted to customer |
| FreightPaid | NUMERIC | Freight cost paid to carrier |
| FreightMargin | NUMERIC | FreightCharged − FreightPaid |
| FreightMarginPct | NUMERIC | FreightMargin / FreightCharged |
| LoadUtilizationBand | VARCHAR | Full / Partial / Underutilized |
| IsDeliveredProgram | BOOLEAN | Delivered program flag |
| SourceSystem | VARCHAR | Origin system |
| RefreshBatchID | VARCHAR | ETL batch reference |

---

### Fact_ContractPrice

**Grain:** One row per contract pricing rule  
**Primary Key:** `ContractPriceKey`  
**Description:** Contract FOB and delivered pricing terms by customer, product/commodity, and effective date range.

| Field | Type | Description |
|---|---|---|
| ContractPriceKey | VARCHAR | Surrogate key |
| CustomerID | VARCHAR | FK → Dim_Customer |
| CustomerHQID | VARCHAR | HQ-level contract scope |
| ShipToID | VARCHAR | Ship-to level (NULL if HQ-level) |
| ItemID | VARCHAR | Item-level (NULL if commodity-level) |
| CommodityID | VARCHAR | Commodity-level scope |
| ContractFOB | NUMERIC | Contract FOB price per case |
| ContractDeliveredPrice | NUMERIC | Delivered price if applicable |
| EffectiveStartDateKey | INTEGER | FK → Dim_Date |
| EffectiveEndDateKey | INTEGER | FK → Dim_Date |
| ContractStatus | VARCHAR | Active / Expired / Pending |
| PricingLevel | VARCHAR | Customer+Item / CustomerHQ+Commodity / etc. |
| SourceSystem | VARCHAR | Origin system |

---

### Dim_Customer

**Primary Key:** `CustomerID`  
**Description:** Customer master with HQ grouping and program classification.

| Field | Type | Description |
|---|---|---|
| CustomerID | VARCHAR | Primary key |
| CustomerName | VARCHAR | Standardized customer name |
| CustomerHQID | VARCHAR | Parent HQ identifier |
| CustomerHQName | VARCHAR | Parent HQ name |
| CustomerStatusKey | VARCHAR | FK → Dim_CustomerStatus |
| CustomerType | VARCHAR | Retailer / Distributor / Club |
| ActiveFlag | BOOLEAN | Active/inactive |

---

### Dim_ShipTo

**Primary Key:** `ShipToID`  
**Foreign Keys:** `CustomerID`, `CustomerHQID`  
**Description:** Destination / DC / ship-to location dimension.

| Field | Type | Description |
|---|---|---|
| ShipToID | VARCHAR | Primary key |
| ShipToName | VARCHAR | Location name |
| CustomerID | VARCHAR | FK → Dim_Customer |
| CustomerHQID | VARCHAR | Parent HQ |
| City | VARCHAR | City |
| State | VARCHAR | State |
| Region | VARCHAR | Regional grouping |
| ActiveFlag | BOOLEAN | Active/inactive |

---

### Dim_Product

**Primary Key:** `ItemID`  
**Foreign Keys:** `CommodityID`  
**Description:** Item master with commodity mapping, organic flag, and manager assignments.

| Field | Type | Description |
|---|---|---|
| ItemID | VARCHAR | Primary key |
| ProductID | VARCHAR | Product master identifier |
| ItemName | VARCHAR | Item description |
| ProductName | VARCHAR | Full product name |
| CommodityID | VARCHAR | FK → Dim_Commodity |
| OrganicFlag | BOOLEAN | Organic / conventional |
| PackSize | VARCHAR | Pack size descriptor |
| Brand | VARCHAR | Brand name |
| HarvestManagerID | VARCHAR | Harvest owner |
| ProductManagerID | VARCHAR | Product owner |
| ActiveFlag | BOOLEAN | Active/inactive |

---

### Dim_Commodity

**Primary Key:** `CommodityID`  
**Description:** Governed commodity hierarchy for rollup reporting.

| Field | Type | Description |
|---|---|---|
| CommodityID | VARCHAR | Primary key |
| CommodityName | VARCHAR | Commodity name |
| CommodityFamily | VARCHAR | Higher-level grouping (Berries, Citrus, etc.) |
| OrganicFlag | BOOLEAN | Organic classification |
| SeasonalityGroup | VARCHAR | Seasonal demand profile |
| ActiveFlag | BOOLEAN | Active/inactive |

---

### Dim_Date

**Primary Key:** `DateKey`  
**Description:** Full calendar spine with reporting period flags.

| Field | Type | Description |
|---|---|---|
| DateKey | INTEGER | Primary key (YYYYMMDD) |
| Date | DATE | Calendar date |
| Year | INTEGER | Calendar year |
| Quarter | INTEGER | Quarter number |
| MonthNumber | INTEGER | Month number |
| MonthName | VARCHAR | Month name |
| WeekNumber | INTEGER | ISO week number |
| YearWeek | VARCHAR | Year-Week label |
| IsYTD | BOOLEAN | Within current year-to-date range |
| IsRolling4Weeks | BOOLEAN | Within last 28 days of report date |
| IsRolling8Weeks | BOOLEAN | Within last 56 days of report date |

---

### Dim_CustomerStatus

**Primary Key:** `CustomerStatusKey`  
**Description:** Customer program classification with pricing implications.

| Field | Type | Description |
|---|---|---|
| CustomerStatusKey | VARCHAR | Primary key |
| CustomerStatus | VARCHAR | Contract / Open Market / Commit |
| Definition | VARCHAR | Business definition |
| PricingImplication | VARCHAR | How status affects pricing logic |
| SortOrder | INTEGER | Report display order |

---

### Dim_Carrier

**Primary Key:** `CarrierID`  
**Description:** Freight carrier master.

| Field | Type | Description |
|---|---|---|
| CarrierID | VARCHAR | Primary key |
| CarrierName | VARCHAR | Carrier name |
| CarrierType | VARCHAR | TL / LTL |
| ActiveFlag | BOOLEAN | Active/inactive |

---

## Relationship Diagram

```
                        Dim_Date
                           │
              ┌────────────┼────────────┐
              │            │            │
   Fact_SalesOrderLine  Fact_LoadFreight  Fact_ContractPrice
       │    │    │    └───────┘
       │    │    │
       │    │    └──→ Dim_Product ──→ Dim_Commodity
       │    │
       │    └──→ Dim_ShipTo
       │
       └──→ Dim_Customer ──→ Dim_CustomerStatus
                    │
              Dim_Carrier (via Fact_LoadFreight)
```

**Bridge relationship:**
`Fact_SalesOrderLine.LoadID → Fact_LoadFreight.LoadID`  
Sales lines connect to freight economics through LoadID. This is the primary join for delivered program profitability analysis.

---

## Grain Constraints

| Constraint | Rule |
|---|---|
| Fact_LoadFreight | Must contain exactly one row per LoadID |
| Fact_SalesOrderLine | Unique on SalesOrderID + LoadID + ItemID |
| Fact_ContractPrice | Unique on CustomerID/HQD + ItemID/CommodityID + effective date range |
| Dim_* | All dimension tables must have unique primary keys |
