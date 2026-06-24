-- =============================================================================
-- IMPLEMENTATION
-- SCRIPT:      load_real_data_csv.sql
-- PURPOSE:     Load real data CSVs into Raw tables for pipeline execution
-- DIALECT:     DuckDB
-- VERSION:     2.0.0 — Column names corrected from actual CSV inspection (2026-06-23)
-- =============================================================================
-- COLUMN MAPPING NOTES:
--   fact_base.csv:
--     - "HQ Name" has a space (not underscore) — quoted in SQL
--     - "Product ID" has a space — quoted in SQL
--     - checkOut is an Excel serial date (double) — converted to DATE here
--     - itemId (VARCHAR) used as ItemID, not "Product ID" (bigint/numeric)
--     - Status column = CustomerProgramStatus
--   order_level_query.csv:
--     - shipDate already arrives as DATE type — no conversion needed
--     - loadShippingCost / loadShippingCharged arrive as VARCHAR — cast to DECIMAL
--   contract_unified.csv:
--     - Contract_FOB arrives as VARCHAR — cast to DECIMAL
-- =============================================================================

-- ---------------------------------------------------------------------------
-- TRUNCATE all raw tables before reload (idempotent run support)
-- ---------------------------------------------------------------------------
DELETE FROM Raw_SalesOrderLine;
DELETE FROM Raw_LoadFreight;
DELETE FROM Raw_ContractPricing;
DELETE FROM Raw_Customer;
DELETE FROM Raw_Item;

-- ---------------------------------------------------------------------------
-- 1. Raw_SalesOrderLine  ←  fact_base.csv
-- ---------------------------------------------------------------------------
INSERT INTO Raw_SalesOrderLine
SELECT
    CAST(salesId            AS VARCHAR)     AS salesId,
    CAST(FactKey            AS VARCHAR)     AS FactKey,
    CAST(loadId             AS VARCHAR)     AS loadId,
    CAST(shipTo             AS VARCHAR)     AS shipTo,
    CAST("HQ Name"          AS VARCHAR)     AS HQ_Name,
    CAST(Status             AS VARCHAR)     AS CustomerProgramStatus,
    CAST(itemId             AS VARCHAR)     AS Product_ID,

    -- checkOut is an Excel serial date (double).
    -- Convert: DATE '1899-12-30' + integer part of serial number
    CAST(
        DATE '1899-12-30' + CAST(CAST(checkOut AS BIGINT) AS INTEGER) * INTERVAL '1' DAY
        AS VARCHAR
    )                                       AS checkOut,

    CAST(qty                AS DECIMAL(18,4)) AS qty,

    -- FOB_Post_Adj preferred; fallback to price
    COALESCE(
        CAST(FOB_Post_Adj   AS DECIMAL(18,6)),
        CAST(price          AS DECIMAL(18,6))
    )                                       AS FOB_Post_Adj,

    CAST(price              AS DECIMAL(18,6)) AS price,

    'FACT_BASE'                             AS SourceSystem,
    CAST(CURRENT_TIMESTAMP  AS VARCHAR)     AS BatchID

FROM read_csv_auto('data/real/fact_base.csv', header=true);

-- ---------------------------------------------------------------------------
-- 2. Raw_LoadFreight  ←  order_level_query.csv
-- ---------------------------------------------------------------------------
INSERT INTO Raw_LoadFreight
SELECT
    CAST(loadId             AS VARCHAR)     AS loadId,
    CAST(carrierName        AS VARCHAR)     AS carrierName,
    CAST(warehouse          AS VARCHAR)     AS warehouse,

    -- shipDate already arrives as DATE in this file
    CAST(shipDate           AS VARCHAR)     AS shipDate,

    -- loadShippingCharged / loadShippingCost arrive as VARCHAR (may contain $ or commas)
    -- REGEXP_REPLACE strips non-numeric characters before casting
    TRY_CAST(
        REGEXP_REPLACE(CAST(loadShippingCharged AS VARCHAR), '[^0-9.]', '', 'g')
        AS DECIMAL(18,4)
    )                                       AS loadShippingCharged,

    TRY_CAST(
        REGEXP_REPLACE(CAST(loadShippingCost AS VARCHAR), '[^0-9.]', '', 'g')
        AS DECIMAL(18,4)
    )                                       AS loadShippingCost,

    CAST(loadPallets        AS DECIMAL(10,2)) AS loadPallets,

    'ORDER_LEVEL_QUERY'                     AS SourceSystem,
    CAST(CURRENT_TIMESTAMP  AS VARCHAR)     AS BatchID

FROM read_csv_auto('data/real/order_level_query.csv', header=true);

-- ---------------------------------------------------------------------------
-- 3. Raw_ContractPricing  ←  contract_unified.csv
-- ---------------------------------------------------------------------------
INSERT INTO Raw_ContractPricing
SELECT
    CAST(Customer_HQ        AS VARCHAR)     AS Customer_HQ,
    CAST(Commodity          AS VARCHAR)     AS Commodity,

    -- Contract_FOB arrives as VARCHAR — strip any $ or commas before casting
    TRY_CAST(
        REGEXP_REPLACE(CAST(Contract_FOB AS VARCHAR), '[^0-9.]', '', 'g')
        AS DECIMAL(18,6)
    )                                       AS Contract_FOB,

    CAST(CustomerProgramStatus AS VARCHAR)  AS CustomerProgramStatus,

    'CONTRACT_UNIFIED'                      AS SourceSystem,
    CAST(CURRENT_TIMESTAMP  AS VARCHAR)     AS BatchID

FROM read_csv_auto('data/real/contract_unified.csv', header=true);

-- ---------------------------------------------------------------------------
-- 4. Raw_Customer  ←  fact_base.csv (distinct accounts)
-- ---------------------------------------------------------------------------
INSERT INTO Raw_Customer
SELECT DISTINCT
    CAST(shipTo             AS VARCHAR)     AS shipTo,
    CAST(Name               AS VARCHAR)     AS Name,
    CAST("HQ Name"          AS VARCHAR)     AS HQ_Name,
    CAST(Status             AS VARCHAR)     AS CustomerProgramStatus,
    'FACT_BASE'                             AS SourceSystem,
    CAST(CURRENT_TIMESTAMP  AS VARCHAR)     AS BatchID

FROM read_csv_auto('data/real/fact_base.csv', header=true)
WHERE shipTo IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. Raw_Item  ←  fact_base.csv (distinct items)
-- ---------------------------------------------------------------------------
INSERT INTO Raw_Item
SELECT DISTINCT
    CAST(itemId             AS VARCHAR)     AS Product_ID,
    CAST("Commodity Name"   AS VARCHAR)     AS Commodity_Name,
    CAST("Product Name"     AS VARCHAR)     AS Product_Name,
    'FACT_BASE'                             AS SourceSystem,
    CAST(CURRENT_TIMESTAMP  AS VARCHAR)     AS BatchID

FROM read_csv_auto('data/real/fact_base.csv', header=true)
WHERE itemId IS NOT NULL;

-- =============================================================================
-- POST-LOAD ROW COUNT VALIDATION
-- =============================================================================
SELECT 'Raw_SalesOrderLine'  AS TableName, COUNT(*) AS RowCount FROM Raw_SalesOrderLine
UNION ALL
SELECT 'Raw_LoadFreight',     COUNT(*) FROM Raw_LoadFreight
UNION ALL
SELECT 'Raw_ContractPricing', COUNT(*) FROM Raw_ContractPricing
UNION ALL
SELECT 'Raw_Customer',        COUNT(*) FROM Raw_Customer
UNION ALL
SELECT 'Raw_Item',            COUNT(*) FROM Raw_Item
ORDER BY TableName;
