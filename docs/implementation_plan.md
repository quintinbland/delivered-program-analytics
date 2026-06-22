# Implementation Plan
## Delivered Program Analytics Pipeline

**Version:** 1.0.0  
**Status:** Ready for execution  
**Prerequisites:** All 30 SQL scripts built and committed to GitHub

---

## OPEN DECISIONS — RESOLVE BEFORE PROCEEDING

These three decisions gate the entire implementation. Each has tradeoffs documented below. No implementation steps can begin until all three are resolved.

---

### DECISION 1 — Target Execution Environment

| Option | Tradeoffs | Recommendation |
|---|---|---|
| **Snowflake** | Free trial available (30 days / $400 credit). `CREATE OR REPLACE TABLE` syntax matches scripts exactly. Web UI for immediate execution. No local install. | **Recommended for this project.** Scripts are Snowflake-primary. |
| **SQL Server (T-SQL)** | Requires local install (SQL Server Express is free). `dim_date.sql` T-SQL block must be swapped in. `TRY_CAST` is compatible. `TO_CHAR` date formatting must be replaced with `CONVERT`. | Valid if Snowflake is unavailable. Requires 8–10 syntax patches. |
| **DuckDB (local)** | Free, runs in-process, no server required. ANSI SQL compatible. Best option for fully local execution with no cloud account. `TRY_CAST` not supported — requires `TRY_CAST` → `TRY_CAST` workaround via `CAST` + error handling. | Valid fallback for local-only with no cloud. |

**ACTION REQUIRED:** Select one environment before Phase 1.

---

### DECISION 2 — Synthetic Data Loading Method

| Option | Description |
|---|---|
| **Direct load from Excel** | Load `DeliveredProgram_DummyDataset.xlsx` sheets directly into raw tables using platform UI or CLI tool |
| **CSV export + COPY** | Export each sheet to CSV, load via `COPY INTO` (Snowflake) or `BULK INSERT` (T-SQL) or `.import` (DuckDB) |
| **Python loader script** | Script reads Excel, writes to raw tables via database connector. Most portable, most repeatable. |

**ACTION REQUIRED:** Select one method. Python loader script is recommended for repeatability and is buildable in a future session.

---

### DECISION 3 — Execution Method

| Option | Description | Effort |
|---|---|---|
| **Manual (script by script)** | Open SQL client, run each script in dependency order. No tooling required. | Low setup, high manual effort per run |
| **Shell script runner** | Single `.bat` (Windows) or `.sh` file that executes all scripts in order. Buildable now. | Low setup, fully repeatable |
| **dbt** | Transform scripts rewritten as dbt models. Full lineage, documentation, testing. | High setup, production-grade |
| **Airflow / Prefect** | Full orchestration with scheduling and monitoring. | Very high setup, overkill for current scope |

**ACTION REQUIRED:** Shell script runner is recommended as the immediate path. dbt is the upgrade path if this moves toward production.

---

## IMPLEMENTATION PHASES

Phases are sequential. Each phase has entry criteria, steps, validation gates, and exit criteria.

---

## PHASE 0 — Environment Setup

**Entry criteria:** DECISION 1 resolved.  
**Estimated effort:** 1–2 hours

---

### PHASE 0A — Snowflake Path

| Step | Action | Detail |
|---|---|---|
| 0A-1 | Create Snowflake trial account | https://signup.snowflake.com — select AWS US-East or your region |
| 0A-2 | Select warehouse size | X-Small is sufficient for synthetic dataset volume |
| 0A-3 | Create database | `CREATE DATABASE delivered_program_analytics;` |
| 0A-4 | Create schema | `CREATE SCHEMA delivered_program_analytics.pipeline;` |
| 0A-5 | Set default context | `USE DATABASE delivered_program_analytics; USE SCHEMA pipeline;` |
| 0A-6 | Verify access | Run `SELECT CURRENT_USER(), CURRENT_WAREHOUSE(), CURRENT_DATABASE();` — confirm all three return values |

**Validation gate:** Step 0A-6 returns values without error. Do not proceed until confirmed.

---

### PHASE 0B — SQL Server Express Path (if Snowflake not selected)

| Step | Action | Detail |
|---|---|---|
| 0B-1 | Download SQL Server Express | https://www.microsoft.com/en-us/sql-server/sql-server-downloads |
| 0B-2 | Install with default settings | Note instance name (default: `SQLEXPRESS`) |
| 0B-3 | Install SQL Server Management Studio (SSMS) | https://aka.ms/ssmsfullsetup |
| 0B-4 | Create database | `CREATE DATABASE DeliveredProgramAnalytics;` |
| 0B-5 | Apply T-SQL dialect patches | See APPENDIX A — list of required script modifications |
| 0B-6 | Verify connection | Run `SELECT @@VERSION;` — confirm SQL Server version returns |

**Validation gate:** Step 0B-6 returns version string. Do not proceed until confirmed.

---

### PHASE 0C — DuckDB Path (if local-only, no cloud)

| Step | Action | Detail |
|---|---|---|
| 0C-1 | Install DuckDB CLI | https://duckdb.org/docs/installation — download CLI for Windows |
| 0C-2 | Create persistent database file | `duckdb delivered_program_analytics.duckdb` |
| 0C-3 | Apply DuckDB dialect patches | See APPENDIX B — list of required script modifications |
| 0C-4 | Verify connection | Run `SELECT version();` — confirm DuckDB version returns |

**Validation gate:** Step 0C-4 returns version string. Do not proceed until confirmed.

---

## PHASE 1 — Raw Table Creation

**Entry criteria:** Phase 0 complete. Environment verified.  
**Estimated effort:** 1–2 hours  
**Dependency:** None

Raw tables must exist before data can be loaded. These tables are not part of the pipeline SQL — they are the landing zone for the synthetic dataset.

---

### Step 1-1 — Create Raw Tables

Execute the following `CREATE TABLE` statements in your SQL environment. One table per source entity.

```sql
CREATE OR REPLACE TABLE Raw_SalesOrderLine (
    SalesOrderID        VARCHAR(50),
    LoadID              VARCHAR(50),
    ItemID              VARCHAR(50),
    CustomerID          VARCHAR(50),
    ShipToID            VARCHAR(50),
    ShipDate            VARCHAR(20),
    OrderDate           VARCHAR(20),
    QuantityCases       VARCHAR(50),
    NetLineRevenue      VARCHAR(50),
    UnitPrice           VARCHAR(50),
    ContractID          VARCHAR(50),
    OrderType           VARCHAR(50),
    SalesChannel        VARCHAR(50),
    SourceSystem        VARCHAR(100),
    BatchID             VARCHAR(100)
);

CREATE OR REPLACE TABLE Raw_LoadFreight (
    LoadID              VARCHAR(50),
    CarrierID           VARCHAR(50),
    LoadDate            VARCHAR(20),
    DeliveryDate        VARCHAR(20),
    FreightCharged      VARCHAR(50),
    FreightPaid         VARCHAR(50),
    LoadPallets         VARCHAR(50),
    LoadWeight          VARCHAR(50),
    OriginWarehouse     VARCHAR(50),
    ShipToID            VARCHAR(50),
    SourceSystem        VARCHAR(100),
    BatchID             VARCHAR(100)
);

CREATE OR REPLACE TABLE Raw_ContractPricing (
    ContractPriceKey    VARCHAR(50),
    CustomerID          VARCHAR(50),
    CustomerHQID        VARCHAR(50),
    ItemID              VARCHAR(50),
    CommodityID         VARCHAR(50),
    ContractFOBPrice    VARCHAR(50),
    EffectiveDate       VARCHAR(20),
    ExpirationDate      VARCHAR(20),
    ContractType        VARCHAR(50),
    ContractStatus      VARCHAR(50),
    SourceSystem        VARCHAR(100),
    BatchID             VARCHAR(100)
);

CREATE OR REPLACE TABLE Raw_ProductMaster (
    ItemID              VARCHAR(50),
    CommodityID         VARCHAR(50),
    ItemDescription     VARCHAR(500),
    ItemCategory        VARCHAR(100),
    PackSize            VARCHAR(50),
    UnitOfMeasure       VARCHAR(20),
    OrganicConventionalFlag VARCHAR(20),
    ActiveFlag          VARCHAR(10),
    WeightPerCase       VARCHAR(50),
    SourceSystem        VARCHAR(100),
    BatchID             VARCHAR(100)
);

CREATE OR REPLACE TABLE Raw_CustomerReference (
    CustomerID          VARCHAR(50),
    CustomerHQID        VARCHAR(50),
    CustomerName        VARCHAR(500),
    CustomerHQName      VARCHAR(500),
    CustomerStatusKey   VARCHAR(50),
    CustomerStatus      VARCHAR(50),
    CustomerRegion      VARCHAR(100),
    CustomerSegment     VARCHAR(100),
    SalesRepID          VARCHAR(50),
    ActiveFlag          VARCHAR(10),
    SourceSystem        VARCHAR(100),
    BatchID             VARCHAR(100)
);

CREATE OR REPLACE TABLE Raw_ShipToReference (
    ShipToID            VARCHAR(50),
    CustomerID          VARCHAR(50),
    ShipToName          VARCHAR(500),
    AddressLine1        VARCHAR(200),
    AddressLine2        VARCHAR(200),
    City                VARCHAR(100),
    StateProvince       VARCHAR(50),
    ZipPostalCode       VARCHAR(20),
    Country             VARCHAR(50),
    Region              VARCHAR(100),
    DeliveryDayOfWeek   VARCHAR(50),
    ActiveFlag          VARCHAR(10),
    SourceSystem        VARCHAR(100),
    BatchID             VARCHAR(100)
);

CREATE OR REPLACE TABLE Raw_CommodityReference (
    CommodityID         VARCHAR(50),
    CommodityName       VARCHAR(200),
    CommodityGroup      VARCHAR(100),
    CommodityCategory   VARCHAR(100),
    SeasonalityWindow   VARCHAR(200),
    ActiveFlag          VARCHAR(10)
);
```

**All columns are VARCHAR at this layer.** Type casting occurs in Module 1 staging scripts. This is intentional — raw tables absorb source data as-is without rejection.

**Validation gate:** Run `SHOW TABLES;` (Snowflake / DuckDB) or `SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES` (T-SQL). Confirm all 7 raw tables exist.

---

## PHASE 2 — Synthetic Data Load

**Entry criteria:** Phase 1 complete. All 7 raw tables exist.  
**Estimated effort:** 1–3 hours depending on load method selected (DECISION 2)  
**Dependency:** Raw tables from Phase 1

---

### Step 2-1 — Export Synthetic Dataset to CSV

Open `data/dummy/DeliveredProgram_DummyDataset.xlsx`. Export each entity to a separate CSV file using the naming convention below.

| Source Entity | CSV Filename |
|---|---|
| SalesOrderLine entity | `raw_sales_order_line.csv` |
| LoadFreight entity | `raw_load_freight.csv` |
| ContractPricing entity | `raw_contract_pricing.csv` |
| ProductMaster entity | `raw_product_master.csv` |
| CustomerReference entity | `raw_customer_reference.csv` |
| ShipToReference entity | `raw_shipto_reference.csv` |
| CommodityReference entity | `raw_commodity_reference.csv` |

Save all CSVs to a single folder, e.g., `C:\Users\Quintin.Bland\Documents\delivered-program-analytics-repo\data\load\`

**Note:** Column headers in the CSV must exactly match the column names in the Raw tables defined in Phase 1. If headers differ, correct them in the CSV before loading.

---

### Step 2-2 — Load CSVs into Raw Tables

**Snowflake path:**

```sql
-- Stage the CSV files (run once per session or use a named stage)
-- Option A: Load via Snowflake Web UI
--   Databases → delivered_program_analytics → pipeline → Tables
--   Select table → Load Data button → upload CSV → map columns → load

-- Option B: Load via SnowSQL CLI
PUT file://C:\Users\Quintin.Bland\Documents\delivered-program-analytics-repo\data\load\raw_sales_order_line.csv @~/staged_files;
COPY INTO Raw_SalesOrderLine FROM @~/staged_files/raw_sales_order_line.csv
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);
-- Repeat for each table
```

**SQL Server path:**
```sql
BULK INSERT Raw_SalesOrderLine
FROM 'C:\Users\Quintin.Bland\Documents\delivered-program-analytics-repo\data\load\raw_sales_order_line.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK);
-- Repeat for each table
```

**DuckDB path:**
```sql
COPY Raw_SalesOrderLine FROM 'C:/Users/Quintin.Bland/Documents/delivered-program-analytics-repo/data/load/raw_sales_order_line.csv' (HEADER TRUE);
-- Repeat for each table
```

---

### Step 2-3 — Validate Raw Load

Run these counts after loading all 7 tables. Record the row counts — they are your baseline for pipeline reconciliation.

```sql
SELECT 'Raw_SalesOrderLine'    AS TableName, COUNT(*) AS RowCount FROM Raw_SalesOrderLine    UNION ALL
SELECT 'Raw_LoadFreight',                    COUNT(*)             FROM Raw_LoadFreight                      UNION ALL
SELECT 'Raw_ContractPricing',               COUNT(*)             FROM Raw_ContractPricing               UNION ALL
SELECT 'Raw_ProductMaster',                 COUNT(*)             FROM Raw_ProductMaster                 UNION ALL
SELECT 'Raw_CustomerReference',             COUNT(*)             FROM Raw_CustomerReference             UNION ALL
SELECT 'Raw_ShipToReference',               COUNT(*)             FROM Raw_ShipToReference               UNION ALL
SELECT 'Raw_CommodityReference',            COUNT(*)             FROM Raw_CommodityReference;
```

**Validation gate:** All 7 tables return row counts > 0. Record counts here before proceeding.

---

## PHASE 3 — Module 1: Staging Layer

**Entry criteria:** Phase 2 complete. All raw tables loaded and validated.  
**Estimated effort:** 30 minutes  
**Dependency:** All Raw_* tables

Execute staging scripts in any order — no inter-dependencies.

| Step | Script | Validates Against |
|---|---|---|
| 3-1 | `sql/staging/stg_customer_reference.sql` | Raw_CustomerReference |
| 3-2 | `sql/staging/stg_product_master.sql` | Raw_ProductMaster |
| 3-3 | `sql/staging/stg_contract_pricing.sql` | Raw_ContractPricing |
| 3-4 | `sql/staging/stg_sales_order_line.sql` | Raw_SalesOrderLine |
| 3-5 | `sql/staging/stg_load_freight.sql` | Raw_LoadFreight |

**Post-execution validation — run after all 5 scripts:**

```sql
-- Row count reconciliation: staging should equal or exceed raw (no rows dropped)
SELECT 'Stg_SalesOrderLine'    AS TableName, COUNT(*) AS RowCount FROM Stg_SalesOrderLine    UNION ALL
SELECT 'Stg_LoadFreight',                    COUNT(*)             FROM Stg_LoadFreight                      UNION ALL
SELECT 'Stg_ContractPricing',               COUNT(*)             FROM Stg_ContractPricing               UNION ALL
SELECT 'Stg_ProductMaster',                 COUNT(*)             FROM Stg_ProductMaster                 UNION ALL
SELECT 'Stg_CustomerReference',             COUNT(*)             FROM Stg_CustomerReference;

-- DQ flag summary across all staging tables
SELECT 'SalesOrderLine' AS Source, SUM(Flag_DuplicateKey) AS Dups, SUM(Flag_InvalidQuantity) AS InvalidQty, SUM(Flag_MissingLoadID) AS MissingLoad FROM Stg_SalesOrderLine UNION ALL
SELECT 'LoadFreight',               SUM(Flag_DuplicateLoadID), NULL, NULL FROM Stg_LoadFreight UNION ALL
SELECT 'ContractPricing',           SUM(Flag_DuplicateKey),    NULL, NULL FROM Stg_ContractPricing UNION ALL
SELECT 'ProductMaster',             SUM(Flag_DuplicateKey),    NULL, NULL FROM Stg_ProductMaster UNION ALL
SELECT 'CustomerReference',         SUM(Flag_DuplicateKey),    NULL, NULL FROM Stg_CustomerReference;
```

**Validation gate:** All staging tables return row counts matching raw sources. DQ flags are populated. Do not proceed to Phase 4 until confirmed.

---

## PHASE 4 — Module 2: Dimension Build

**Entry criteria:** Phase 3 complete. All staging tables validated.  
**Estimated effort:** 30 minutes  
**Dependency:** Staging tables; build in dependency order below

| Step | Script | Dependency |
|---|---|---|
| 4-1 | `sql/dimensions/dim_customer_status.sql` | None |
| 4-2 | `sql/dimensions/dim_commodity.sql` | None |
| 4-3 | `sql/dimensions/dim_date.sql` | None |
| 4-4 | `sql/dimensions/dim_carrier.sql` | Stg_LoadFreight |
| 4-5 | `sql/dimensions/dim_shipto.sql` | Raw_ShipToReference |
| 4-6 | `sql/dimensions/dim_product.sql` | Dim_Commodity |
| 4-7 | `sql/dimensions/dim_customer.sql` | Dim_CustomerStatus |

**Post-execution validation:**

```sql
-- All dimensions must include default member (Key = -1)
SELECT 'Dim_CustomerStatus' AS Dim, COUNT(*) AS RowCount, MIN(CustomerStatusKey) AS MinKey FROM Dim_CustomerStatus UNION ALL
SELECT 'Dim_Commodity',             COUNT(*),              MIN(CommodityKey)      FROM Dim_Commodity      UNION ALL
SELECT 'Dim_Date',                  COUNT(*),              MIN(DateKey)           FROM Dim_Date           UNION ALL
SELECT 'Dim_Carrier',               COUNT(*),              MIN(CarrierKey)        FROM Dim_Carrier        UNION ALL
SELECT 'Dim_ShipTo',                COUNT(*),              MIN(ShipToKey)         FROM Dim_ShipTo         UNION ALL
SELECT 'Dim_Product',               COUNT(*),              MIN(ProductKey)        FROM Dim_Product        UNION ALL
SELECT 'Dim_Customer',              COUNT(*),              MIN(CustomerKey)       FROM Dim_Customer;
```

**Validation gate:** All 7 dimensions return MinKey = -1 (default member present). RowCount > 1 on all tables. Do not proceed to Phase 5 until confirmed.

---

## PHASE 5 — Module 3: Fact Tables

**Entry criteria:** Phase 4 complete. All dimensions validated.  
**Estimated effort:** 30 minutes  
**Dependency:** All staging tables + all dimension tables; build in order below

| Step | Script | Dependency |
|---|---|---|
| 5-1 | `sql/facts/fact_load_freight.sql` | Stg_LoadFreight, Dim_Carrier, Dim_ShipTo, Dim_Date |
| 5-2 | `sql/facts/fact_contract_price.sql` | Stg_ContractPricing, Dim_Customer, Dim_Product, Dim_Commodity, Dim_Date |
| 5-3 | `sql/facts/fact_sales_order_line.sql` | Stg_SalesOrderLine, Stg_ContractPricing, all dimensions, Fact_LoadFreight |

**Post-execution validation:**

```sql
-- Row counts
SELECT 'Fact_LoadFreight'      AS Fact, COUNT(*) AS RowCount FROM Fact_LoadFreight      UNION ALL
SELECT 'Fact_ContractPrice',            COUNT(*)             FROM Fact_ContractPrice     UNION ALL
SELECT 'Fact_SalesOrderLine',           COUNT(*)             FROM Fact_SalesOrderLine;

-- Contract match tier distribution (key pipeline health indicator)
SELECT ContractMatchTier, COUNT(*) AS LineCount
FROM Fact_SalesOrderLine
GROUP BY ContractMatchTier
ORDER BY LineCount DESC;

-- Calculated measure integrity
SELECT COUNT(*) AS MismatchCount
FROM Fact_SalesOrderLine
WHERE TotalFOBVariance <> ExcessSalesProfit
  AND TotalFOBVariance IS NOT NULL;
-- EXPECTED: 0 rows
```

**Validation gate:** All 3 fact tables return row counts > 0. MismatchCount = 0. Contract tier distribution shows at least some Tier 1 matches — if all rows are NoMatch, contract data loading or matching logic requires investigation.

---

## PHASE 6 — Module 4: Calculation Engine

**Entry criteria:** Phase 5 complete. All fact tables validated.  
**Estimated effort:** 15 minutes  
**Dependency:** Fact tables + dimension tables; run in any order

| Step | Script |
|---|---|
| 6-1 | `sql/calculations/calc_freight_summary.sql` |
| 6-2 | `sql/calculations/calc_fob_variance_summary.sql` |
| 6-3 | `sql/calculations/calc_load_utilization.sql` |
| 6-4 | `sql/calculations/calc_customer_performance.sql` |

**Post-execution validation:**

```sql
-- Revenue reconciliation: calc must match fact total
SELECT SUM(TotalRevenue) AS Calc_Revenue FROM Calc_CustomerPerformance;
SELECT SUM(NetLineRevenue) AS Fact_Revenue FROM Fact_SalesOrderLine WHERE CustomerKey <> -1 AND ShipDateKey <> -1;
-- EXPECTED: both values equal

-- Freight margin reconciliation
SELECT SUM(TotalFreightMargin) AS Calc_Margin FROM Calc_FreightSummary;
SELECT SUM(FreightMargin) AS Fact_Margin FROM Fact_LoadFreight WHERE LoadDateKey <> -1 AND CarrierKey <> -1;
-- EXPECTED: both values equal
```

**Validation gate:** Revenue and freight margin reconcile between calc and fact layers. Any discrepancy indicates a filter mismatch and must be resolved before proceeding.

---

## PHASE 7 — Module 5: Exception System

**Entry criteria:** Phase 6 complete.  
**Estimated effort:** 15 minutes  
**Dependency:** Fact tables + staging tables + dimension tables; run exc_master.sql last

| Step | Script |
|---|---|
| 7-1 | `sql/exceptions/exc_missing_contract_pricing.sql` |
| 7-2 | `sql/exceptions/exc_negative_fob_variance.sql` |
| 7-3 | `sql/exceptions/exc_negative_freight_margin.sql` |
| 7-4 | `sql/exceptions/exc_missing_mappings.sql` |
| 7-5 | `sql/exceptions/exc_data_quality.sql` |
| 7-6 | `sql/exceptions/exc_master.sql` |

**Post-execution validation:**

```sql
-- Exception summary
SELECT ExceptionType, Severity, COUNT(*) AS ExceptionCount,
       SUM(COALESCE(FinancialImpact, 0)) AS TotalFinancialImpact
FROM Exc_Master
GROUP BY ExceptionType, Severity
ORDER BY CASE Severity WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END, ExceptionCount DESC;
```

**Validation gate:** Exc_Master returns rows. The synthetic dataset has intentional data quality issues — if Exc_Master returns 0 rows, the exception scripts are not firing correctly and must be investigated before proceeding.

---

## PHASE 8 — Module 6: Reporting Layer

**Entry criteria:** Phase 7 complete.  
**Estimated effort:** 15 minutes  
**Dependency:** Calc_* tables + Exc_Master + dimension tables; run in any order

| Step | Script |
|---|---|
| 8-1 | `sql/reporting/rpt_executive_summary.sql` |
| 8-2 | `sql/reporting/rpt_fob_variance_detail.sql` |
| 8-3 | `sql/reporting/rpt_freight_performance.sql` |
| 8-4 | `sql/reporting/rpt_exception_dashboard.sql` |
| 8-5 | `sql/reporting/rpt_customer_scorecard.sql` |

**Post-execution validation:**

```sql
-- Confirm all reporting tables are populated
SELECT 'Rpt_ExecutiveSummary'          AS Table_Name, COUNT(*) AS RowCount FROM Rpt_ExecutiveSummary          UNION ALL
SELECT 'Rpt_FOBVarianceDetail',                        COUNT(*)             FROM Rpt_FOBVarianceDetail         UNION ALL
SELECT 'Rpt_FreightPerformance',                       COUNT(*)             FROM Rpt_FreightPerformance        UNION ALL
SELECT 'Rpt_ExceptionDashboard_Summary',               COUNT(*)             FROM Rpt_ExceptionDashboard_Summary UNION ALL
SELECT 'Rpt_ExceptionDashboard_Open',                  COUNT(*)             FROM Rpt_ExceptionDashboard_Open   UNION ALL
SELECT 'Rpt_CustomerScorecard',                        COUNT(*)             FROM Rpt_CustomerScorecard;
```

**Validation gate:** All 6 reporting tables return row counts > 0. Pipeline is fully operational.

---

## PHASE 9 — End-to-End Reconciliation

**Entry criteria:** All phases complete.  
**Estimated effort:** 30 minutes  
**Purpose:** Confirm data integrity across the full pipeline from raw to reporting.

```sql
-- RECONCILIATION REPORT
-- Run this as a single query to confirm pipeline integrity end to end

SELECT
    'Raw → Staging'             AS CheckPoint,
    (SELECT COUNT(*) FROM Raw_SalesOrderLine)   AS InputCount,
    (SELECT COUNT(*) FROM Stg_SalesOrderLine)   AS OutputCount,
    CASE WHEN (SELECT COUNT(*) FROM Raw_SalesOrderLine) = (SELECT COUNT(*) FROM Stg_SalesOrderLine) THEN 'PASS' ELSE 'INVESTIGATE' END AS Status

UNION ALL SELECT
    'Staging → Fact (clean rows only)',
    (SELECT COUNT(*) FROM Stg_SalesOrderLine WHERE IsCleanRow = 1 AND DeduplicationRank = 1),
    (SELECT COUNT(*) FROM Fact_SalesOrderLine),
    CASE WHEN (SELECT COUNT(*) FROM Stg_SalesOrderLine WHERE IsCleanRow = 1 AND DeduplicationRank = 1) = (SELECT COUNT(*) FROM Fact_SalesOrderLine) THEN 'PASS' ELSE 'INVESTIGATE' END

UNION ALL SELECT
    'Fact Revenue → Calc Revenue',
    NULL,
    NULL,
    CASE WHEN ABS(
        (SELECT COALESCE(SUM(NetLineRevenue),0) FROM Fact_SalesOrderLine WHERE CustomerKey <> -1 AND ShipDateKey <> -1)
        - (SELECT COALESCE(SUM(TotalRevenue),0) FROM Calc_CustomerPerformance)
    ) < 0.01 THEN 'PASS' ELSE 'INVESTIGATE' END

UNION ALL SELECT
    'Exceptions Detected',
    (SELECT COUNT(*) FROM Exc_Master),
    (SELECT COUNT(*) FROM Exc_Master WHERE Severity = 'HIGH'),
    CASE WHEN (SELECT COUNT(*) FROM Exc_Master) > 0 THEN 'PASS — exceptions present as expected' ELSE 'INVESTIGATE — synthetic data should produce exceptions' END;
```

**Final validation gate:** All checkpoint rows return PASS or PASS with note. Any INVESTIGATE result must be diagnosed before declaring the pipeline operational.

---

## APPENDIX A — T-SQL Dialect Patches

Required if SQL Server path is selected. Apply to scripts before execution.

| Script | Change Required |
|---|---|
| All staging scripts | Replace `TRY_CAST(x AS DATE)` with `TRY_CONVERT(DATE, x)` |
| All staging scripts | Replace `CURRENT_TIMESTAMP` with `GETDATE()` |
| `dim_date.sql` | Remove Snowflake block; uncomment T-SQL block; add `OPTION (MAXRECURSION 5000)` |
| All scripts using `TO_CHAR(date, 'YYYYMMDD')` | Replace with `CONVERT(VARCHAR, date, 112)` |
| All scripts using `CAST(TO_CHAR(...) AS INTEGER)` | Replace with `CAST(CONVERT(VARCHAR, date, 112) AS INT)` |

---

## APPENDIX B — DuckDB Dialect Patches

Required if DuckDB path is selected. Apply to scripts before execution.

| Script | Change Required |
|---|---|
| All staging scripts | Replace `TRY_CAST` with `TRY_CAST` — DuckDB supports this natively; no change needed |
| `dim_date.sql` | Replace Snowflake `GENERATOR` block with DuckDB equivalent: `SELECT UNNEST(generate_series(DATE '2020-01-01', DATE '2030-12-31', INTERVAL '1 day')) AS CalendarDate` |
| All scripts using `TO_CHAR(date, 'YYYYMMDD')` | Replace with `STRFTIME(date, '%Y%m%d')` |
| All scripts using `CREATE OR REPLACE TABLE x AS` | Supported natively in DuckDB — no change |

---

## APPENDIX C — Execution Order Reference (Complete)

```
PHASE 0:  Environment setup
PHASE 1:  Raw table creation (7 CREATE TABLE statements)
PHASE 2:  Synthetic data load (7 CSV imports)
PHASE 3:  stg_customer_reference → stg_product_master → stg_contract_pricing → stg_sales_order_line → stg_load_freight
PHASE 4:  dim_customer_status → dim_commodity → dim_date → dim_carrier → dim_shipto → dim_product → dim_customer
PHASE 5:  fact_load_freight → fact_contract_price → fact_sales_order_line
PHASE 6:  calc_freight_summary → calc_fob_variance_summary → calc_load_utilization → calc_customer_performance
PHASE 7:  exc_missing_contract_pricing → exc_negative_fob_variance → exc_negative_freight_margin → exc_missing_mappings → exc_data_quality → exc_master
PHASE 8:  rpt_executive_summary → rpt_fob_variance_detail → rpt_freight_performance → rpt_exception_dashboard → rpt_customer_scorecard
PHASE 9:  End-to-end reconciliation query
```

---

## FAILURE MODE REFERENCE

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Staging row count < raw row count | Script has a WHERE filter removing rows | Review staging script — no rows should be dropped at staging |
| All Fact_SalesOrderLine rows = NoMatch | Contract date ranges do not overlap with ShipDates in synthetic data | Check EffectiveDate / ExpirationDate in Raw_ContractPricing against ShipDate range in Raw_SalesOrderLine |
| Dim_Date MinKey > -1 | Default member INSERT failed | Re-run `dim_date.sql`; confirm UNION ALL syntax is supported in your environment |
| Exc_Master = 0 rows | Individual exception scripts returned 0 rows | Run each exc_*.sql independently and check row counts; confirm synthetic data DQ issues are present |
| Revenue reconciliation fails | Calc script has additional filter not present in fact script | Compare WHERE clauses in `calc_customer_performance.sql` against `Fact_SalesOrderLine` |
