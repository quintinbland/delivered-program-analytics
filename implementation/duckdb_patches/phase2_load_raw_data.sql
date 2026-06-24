-- =============================================================================
-- IMPLEMENTATION: Phase 2 — Real Data Load
-- TARGET:         DuckDB
-- PURPOSE:        Load real source CSVs into raw tables
-- VERSION:        2.4.0 — Updated column mapping for new fact_base.csv export (2026-06-24)
-- =============================================================================
-- CHANGE LOG (v2.4.0):
--   - Raw_SalesOrderLine: removed FactKey (not in new export)
--   - Raw_SalesOrderLine: HQ Name → HQ_Name (column renamed in new export)
--   - Raw_SalesOrderLine: Status → CustomerProgramStatus (column renamed)
--   - Raw_SalesOrderLine: checkOut no longer requires Excel serial conversion
--     (Power Query exports as VARCHAR date string directly)
--   - Raw_SalesOrderLine: Mode_of_Delivery added (new column from AX source)
--   - Raw_Customer: Name → HQ_Name fallback (Name not in new export)
--   - Raw_Customer: HQ Name → HQ_Name, Status → CustomerProgramStatus
--   - Raw_SalesOrderLine baseline updated to 28,348 rows
-- CHANGE LOG (v2.3.0):
--   - Added Raw_CustomerReference + Raw_ProductMaster population
-- CHANGE LOG (v2.2.0):
--   - Added Raw_ProductMaster population from Raw_Item
-- CHANGE LOG (v2.1.0):
--   - Added Raw_CommodityMapping load from data/commodity_mapping.csv
-- CHANGE LOG (v2.0.0):
--   - Replaced synthetic data load with real CSV sources
-- =============================================================================
-- PREREQUISITES:
--   data/real/fact_base.csv          (STG_LineLevel_1 export — 28,348 rows)
--   data/real/order_level_query.csv  (Order Level Query export — 2,277 rows)
--   data/real/contract_unified.csv   (Contract Unified export — 306 rows)
--   data/commodity_mapping.csv       (ItemID → CommodityID mapping — 3,789 rows)
-- =============================================================================

-- Truncate before reload (idempotent)
DELETE FROM Raw_SalesOrderLine;
DELETE FROM Raw_LoadFreight;
DELETE FROM Raw_ContractPricing;
DELETE FROM Raw_Customer;
DELETE FROM Raw_Item;
DELETE FROM Raw_CommodityMapping;
DELETE FROM Raw_CustomerReference;
DELETE FROM Raw_ProductMaster;

-- ---------------------------------------------------------------------------
-- 1. Raw_SalesOrderLine  ←  fact_base.csv
-- Source: STG_LineLevel_1 Power Query export
-- Columns mapped from new export format (v2.4.0):
--   salesId               → salesId
--   loadId                → loadId
--   shipTo                → shipTo
--   HQ_Name               → HQ_Name        (was "HQ Name" with space in v2.x)
--   CustomerProgramStatus → CustomerProgramStatus (was Status in v2.x)
--   itemId                → Product_ID
--   checkOut              → checkOut        (VARCHAR date string; no serial conversion needed)
--   qty                   → qty
--   FOB_Post_Adj          → FOB_Post_Adj    (from BI_FactTable merge; COALESCE to price)
--   price                 → price
--   Mode_of_Delivery      → Mode_of_Delivery (new — from AX DlvMode field)
-- Removed: FactKey (not present in new export)
-- ---------------------------------------------------------------------------
INSERT INTO Raw_SalesOrderLine
SELECT
    CAST(salesId               AS VARCHAR)              AS salesId,
    CAST(loadId                AS VARCHAR)              AS loadId,
    CAST(shipTo                AS VARCHAR)              AS shipTo,
    CAST(HQ_Name               AS VARCHAR)              AS HQ_Name,
    CAST(CustomerProgramStatus AS VARCHAR)              AS CustomerProgramStatus,
    CAST(itemId                AS VARCHAR)              AS Product_ID,
    CAST(checkOut              AS VARCHAR)              AS checkOut,
    CAST(qty                   AS DECIMAL(18,4))        AS qty,
    COALESCE(
        TRY_CAST(FOB_Post_Adj  AS DECIMAL(18,6)),
        TRY_CAST(price         AS DECIMAL(18,6))
    )                                                   AS FOB_Post_Adj,
    CAST(price                 AS DECIMAL(18,6))        AS price,
    CAST(Mode_of_Delivery      AS VARCHAR)              AS Mode_of_Delivery,
    'FACT_BASE'                                         AS SourceSystem,
    CAST(CURRENT_TIMESTAMP     AS VARCHAR)              AS BatchID
FROM read_csv_auto('data/real/fact_base.csv', header=true)
WHERE CAST(salesId AS VARCHAR) IS NOT NULL
  AND CAST(loadId  AS VARCHAR) IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. Raw_LoadFreight  ←  order_level_query.csv
-- ---------------------------------------------------------------------------
INSERT INTO Raw_LoadFreight
SELECT
    CAST(loadId      AS VARCHAR)                        AS loadId,
    CAST(carrierName AS VARCHAR)                        AS carrierName,
    CAST(warehouse   AS VARCHAR)                        AS warehouse,
    CAST(shipDate    AS VARCHAR)                        AS shipDate,
    TRY_CAST(
        REGEXP_REPLACE(CAST(loadShippingCharged AS VARCHAR), '[^0-9.]', '', 'g')
        AS DECIMAL(18,4)
    )                                                   AS loadShippingCharged,
    TRY_CAST(
        REGEXP_REPLACE(CAST(loadShippingCost AS VARCHAR), '[^0-9.]', '', 'g')
        AS DECIMAL(18,4)
    )                                                   AS loadShippingCost,
    CAST(loadPallets AS DECIMAL(10,2))                  AS loadPallets,
    'ORDER_LEVEL_QUERY'                                 AS SourceSystem,
    CAST(CURRENT_TIMESTAMP AS VARCHAR)                  AS BatchID
FROM read_csv_auto('data/real/order_level_query.csv', header=true);

-- ---------------------------------------------------------------------------
-- 3. Raw_ContractPricing  ←  contract_unified.csv
-- ---------------------------------------------------------------------------
INSERT INTO Raw_ContractPricing
SELECT
    CAST(Customer_HQ AS VARCHAR)                        AS Customer_HQ,
    CAST(Commodity   AS VARCHAR)                        AS Commodity,
    TRY_CAST(
        REGEXP_REPLACE(CAST(Contract_FOB AS VARCHAR), '[^0-9.]', '', 'g')
        AS DECIMAL(18,6)
    )                                                   AS Contract_FOB,
    CAST(CustomerProgramStatus AS VARCHAR)              AS CustomerProgramStatus,
    'CONTRACT_UNIFIED'                                  AS SourceSystem,
    CAST(CURRENT_TIMESTAMP AS VARCHAR)                  AS BatchID
FROM read_csv_auto('data/real/contract_unified.csv', header=true);

-- ---------------------------------------------------------------------------
-- 4. Raw_Customer  ←  fact_base.csv (distinct accounts)
-- Note: Customer name not available in new export; HQ_Name used as fallback.
-- ---------------------------------------------------------------------------
INSERT INTO Raw_Customer
SELECT DISTINCT
    CAST(shipTo                AS VARCHAR)              AS shipTo,
    CAST(HQ_Name               AS VARCHAR)              AS Name,
    CAST(HQ_Name               AS VARCHAR)              AS HQ_Name,
    CAST(CustomerProgramStatus AS VARCHAR)              AS CustomerProgramStatus,
    'FACT_BASE'                                         AS SourceSystem,
    CAST(CURRENT_TIMESTAMP     AS VARCHAR)              AS BatchID
FROM read_csv_auto('data/real/fact_base.csv', header=true)
WHERE shipTo IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. Raw_Item  ←  fact_base.csv (distinct items)
-- ---------------------------------------------------------------------------
INSERT INTO Raw_Item
SELECT DISTINCT
    CAST(itemId              AS VARCHAR)                AS Product_ID,
    CAST("Commodity Name"    AS VARCHAR)                AS Commodity_Name,
    CAST("Product Name"      AS VARCHAR)                AS Product_Name,
    'FACT_BASE'                                         AS SourceSystem,
    CAST(CURRENT_TIMESTAMP   AS VARCHAR)                AS BatchID
FROM read_csv_auto('data/real/fact_base.csv', header=true)
WHERE itemId IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 6. Raw_CommodityMapping  ←  data/commodity_mapping.csv
-- ---------------------------------------------------------------------------
INSERT INTO Raw_CommodityMapping
SELECT
    CAST(ItemID      AS VARCHAR(50))                    AS ItemID,
    CAST(CommodityID AS VARCHAR(100))                   AS CommodityID_Mapped,
    'COMMODITY_MAPPING'                                 AS SourceSystem,
    CAST(CURRENT_TIMESTAMP AS VARCHAR)                  AS BatchID
FROM read_csv_auto('data/commodity_mapping.csv', header=true);

-- ---------------------------------------------------------------------------
-- 7. Raw_CustomerReference  ←  Raw_Customer
-- ---------------------------------------------------------------------------
INSERT INTO Raw_CustomerReference
SELECT
    shipTo                  AS CustomerID,
    HQ_Name                 AS CustomerHQID,
    Name                    AS CustomerName,
    HQ_Name                 AS CustomerHQName,
    CustomerProgramStatus   AS CustomerStatusKey,
    CustomerProgramStatus   AS CustomerStatus,
    NULL                    AS CustomerRegion,
    NULL                    AS CustomerSegment,
    NULL                    AS SalesRepID,
    'Y'                     AS ActiveFlag,
    SourceSystem,
    BatchID
FROM Raw_Customer
WHERE shipTo IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 8. Raw_ProductMaster  ←  Raw_Item
-- ---------------------------------------------------------------------------
INSERT INTO Raw_ProductMaster
SELECT
    ri.Product_ID                       AS ItemID,
    NULL                                AS CommodityID,
    ri.Product_Name                     AS ItemDescription,
    NULL                                AS ItemCategory,
    NULL                                AS PackSize,
    NULL                                AS UnitOfMeasure,
    NULL                                AS OrganicConventionalFlag,
    'Y'                                 AS ActiveFlag,
    NULL                                AS WeightPerCase,
    'FACT_BASE'                         AS SourceSystem,
    CAST(CURRENT_TIMESTAMP AS VARCHAR)  AS BatchID
FROM Raw_Item ri
WHERE ri.Product_ID IS NOT NULL;

-- =============================================================================
-- VALIDATION: Row counts per raw table
-- =============================================================================
SELECT 'Raw_CommodityMapping'  AS TableName, COUNT(*) AS RowCount FROM Raw_CommodityMapping
UNION ALL
SELECT 'Raw_ContractPricing',   COUNT(*) FROM Raw_ContractPricing
UNION ALL
SELECT 'Raw_Customer',          COUNT(*) FROM Raw_Customer
UNION ALL
SELECT 'Raw_CustomerReference', COUNT(*) FROM Raw_CustomerReference
UNION ALL
SELECT 'Raw_Item',              COUNT(*) FROM Raw_Item
UNION ALL
SELECT 'Raw_LoadFreight',       COUNT(*) FROM Raw_LoadFreight
UNION ALL
SELECT 'Raw_ProductMaster',     COUNT(*) FROM Raw_ProductMaster
UNION ALL
SELECT 'Raw_SalesOrderLine',    COUNT(*) FROM Raw_SalesOrderLine
ORDER BY TableName;
