-- =============================================================================
-- IMPLEMENTATION: Phase 2 — Real Data Load
-- TARGET:         DuckDB
-- PURPOSE:        Load real source CSVs into raw tables
-- VERSION:        2.3.0 — Added Raw_CustomerReference + Raw_ProductMaster population (2026-06-24)
-- =============================================================================
-- CHANGE LOG (v2.3.0):
--   - Added Raw_CustomerReference population from Raw_Customer
--     CustomerID = shipTo, CustomerHQID/CustomerHQName = HQ_Name,
--     CustomerName = Name, CustomerStatus = CustomerProgramStatus
--     CustomerRegion/Segment/SalesRepID not in real source; defaulted NULL
--   - Raw_ProductMaster population retained from v2.2.0
--   - Raw_CommodityMapping load retained from v2.1.0
-- CHANGE LOG (v2.2.0):
--   - Added Raw_ProductMaster population from Raw_Item
-- CHANGE LOG (v2.1.0):
--   - Added Raw_CommodityMapping load from data/commodity_mapping.csv
-- CHANGE LOG (v2.0.0):
--   - Replaced synthetic data load with real CSV sources
-- =============================================================================
-- PREREQUISITES:
--   data/real/fact_base.csv
--   data/real/order_level_query.csv
--   data/real/contract_unified.csv
--   data/commodity_mapping.csv
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
-- ---------------------------------------------------------------------------
INSERT INTO Raw_SalesOrderLine
SELECT
    CAST(salesId    AS VARCHAR)                         AS salesId,
    CAST(FactKey    AS VARCHAR)                         AS FactKey,
    CAST(loadId     AS VARCHAR)                         AS loadId,
    CAST(shipTo     AS VARCHAR)                         AS shipTo,
    CAST("HQ Name"  AS VARCHAR)                         AS HQ_Name,
    CAST(Status     AS VARCHAR)                         AS CustomerProgramStatus,
    CAST(itemId     AS VARCHAR)                         AS Product_ID,
    -- checkOut is Excel serial date (double) → convert to DATE string
    CAST(
        DATE '1899-12-30' + CAST(CAST(checkOut AS BIGINT) AS INTEGER) * INTERVAL '1' DAY
        AS VARCHAR
    )                                                   AS checkOut,
    CAST(qty        AS DECIMAL(18,4))                   AS qty,
    COALESCE(
        CAST(FOB_Post_Adj AS DECIMAL(18,6)),
        CAST(price        AS DECIMAL(18,6))
    )                                                   AS FOB_Post_Adj,
    CAST(price      AS DECIMAL(18,6))                   AS price,
    'FACT_BASE'                                         AS SourceSystem,
    CAST(CURRENT_TIMESTAMP AS VARCHAR)                  AS BatchID
FROM read_csv_auto('data/real/fact_base.csv', header=true);

-- ---------------------------------------------------------------------------
-- 2. Raw_LoadFreight  ←  order_level_query.csv
-- ---------------------------------------------------------------------------
INSERT INTO Raw_LoadFreight
SELECT
    CAST(loadId     AS VARCHAR)                         AS loadId,
    CAST(carrierName AS VARCHAR)                        AS carrierName,
    CAST(warehouse  AS VARCHAR)                         AS warehouse,
    CAST(shipDate   AS VARCHAR)                         AS shipDate,
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
-- ---------------------------------------------------------------------------
INSERT INTO Raw_Customer
SELECT DISTINCT
    CAST(shipTo    AS VARCHAR)                          AS shipTo,
    CAST(Name      AS VARCHAR)                          AS Name,
    CAST("HQ Name" AS VARCHAR)                          AS HQ_Name,
    CAST(Status    AS VARCHAR)                          AS CustomerProgramStatus,
    'FACT_BASE'                                         AS SourceSystem,
    CAST(CURRENT_TIMESTAMP AS VARCHAR)                  AS BatchID
FROM read_csv_auto('data/real/fact_base.csv', header=true)
WHERE shipTo IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. Raw_Item  ←  fact_base.csv (distinct items)
-- ---------------------------------------------------------------------------
INSERT INTO Raw_Item
SELECT DISTINCT
    CAST(itemId          AS VARCHAR)                    AS Product_ID,
    CAST("Commodity Name" AS VARCHAR)                   AS Commodity_Name,
    CAST("Product Name"  AS VARCHAR)                    AS Product_Name,
    'FACT_BASE'                                         AS SourceSystem,
    CAST(CURRENT_TIMESTAMP AS VARCHAR)                  AS BatchID
FROM read_csv_auto('data/real/fact_base.csv', header=true)
WHERE itemId IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 6. Raw_CommodityMapping  ←  data/commodity_mapping.csv
-- Provides ItemID → canonical CommodityID lookup.
-- UNKNOWN values are loaded as-is; stg_product_master.sql converts to NULL.
-- ---------------------------------------------------------------------------
INSERT INTO Raw_CommodityMapping
SELECT
    CAST(ItemID      AS VARCHAR(50))    AS ItemID,
    CAST(CommodityID AS VARCHAR(100))   AS CommodityID_Mapped,
    'COMMODITY_MAPPING'                 AS SourceSystem,
    CAST(CURRENT_TIMESTAMP AS VARCHAR)  AS BatchID
FROM read_csv_auto('data/commodity_mapping.csv', header=true);

-- ---------------------------------------------------------------------------
-- 7. Raw_CustomerReference  ←  Raw_Customer
-- Raw_CustomerReference is the input to stg_customer_reference.sql.
-- Real source provides shipTo (CustomerID) and HQ_Name (CustomerHQID).
-- CustomerRegion, CustomerSegment, SalesRepID not in real source; NULL.
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
-- Raw_ProductMaster is the input to stg_product_master.sql.
-- Only ItemID and ItemDescription available from real source.
-- CommodityID resolved via Raw_CommodityMapping in stg_product_master.sql.
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
