-- =============================================================================
-- MODULE:      Exception System
-- SCRIPT:      exc_data_quality.sql
-- INPUT:       Stg_SalesOrderLine, Stg_LoadFreight, Stg_ContractPricing,
--              Stg_ProductMaster, Stg_CustomerReference
-- OUTPUT:      Exc_DataQuality
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   All staging tables (Module 1)
-- =============================================================================
-- EXCEPTION RULES COVERED:
--
--   RULE: DUPLICATE_SALES_LINE_KEY
--     Condition:    COUNT(SalesOrderID + LoadID + ItemID) > 1 in staging
--     Severity:     HIGH — fact table grain violation
--
--   RULE: INVALID_QUANTITY
--     Condition:    QuantityCases <= 0 OR QuantityCases IS NULL
--     Severity:     HIGH — blocks ActualFOB calculation
--
--   RULE: MISSING_LOAD_ID
--     Condition:    LoadID IS NULL on a sales order line
--     Severity:     HIGH — breaks load-to-sales bridge
--
--   RULE: DUPLICATE_LOAD_ID
--     Condition:    COUNT(LoadID) > 1 in Stg_LoadFreight
--     Severity:     HIGH — fact table grain violation
--
--   RULE: DUPLICATE_CONTRACT_KEY
--     Condition:    COUNT(ContractPriceKey) > 1 in Stg_ContractPricing
--     Severity:     HIGH — contract matching ambiguity
--
--   RULE: INVERTED_CONTRACT_DATE
--     Condition:    EffectiveDate > ExpirationDate
--     Severity:     HIGH — contract rule is unusable
-- =============================================================================

CREATE OR REPLACE TABLE Exc_DataQuality AS

-- ---------------------------------------------------------------------------
-- RULE: DUPLICATE_SALES_LINE_KEY
-- ---------------------------------------------------------------------------
SELECT
    'DUPLICATE_SALES_LINE_KEY'                          AS ExceptionType,
    'HIGH'                                              AS Severity,
    'SalesOrderID + LoadID + ItemID appears more than once in staging — fact grain violation.' AS ExceptionDescription,
    s.SalesOrderID                                      AS EntityID,
    'SalesOrderLine'                                    AS EntityType,
    CONCAT(s.SalesOrderID, '|', COALESCE(s.LoadID,'NULL'), '|', COALESCE(s.ItemID,'NULL')) AS EntityDetail,
    s.DuplicateCount                                    AS DuplicateCount,
    s.DeduplicationRank                                 AS DeduplicationRank,
    'Stg_SalesOrderLine'                                AS SourceTable,
    s.SourceSystem,
    s.BatchID,
    CURRENT_TIMESTAMP                                   AS ExceptionLoadedAt
FROM Stg_SalesOrderLine s
WHERE s.Flag_DuplicateKey = 1

UNION ALL

-- ---------------------------------------------------------------------------
-- RULE: INVALID_QUANTITY
-- ---------------------------------------------------------------------------
SELECT
    'INVALID_QUANTITY',
    'HIGH',
    'QuantityCases is NULL, zero, or negative — ActualFOB calculation blocked.',
    s.SalesOrderID,
    'SalesOrderLine',
    CONCAT(s.SalesOrderID, '|', COALESCE(s.LoadID,'NULL'), '|', COALESCE(s.ItemID,'NULL')),
    NULL,
    NULL,
    'Stg_SalesOrderLine',
    s.SourceSystem,
    s.BatchID,
    CURRENT_TIMESTAMP
FROM Stg_SalesOrderLine s
WHERE s.Flag_InvalidQuantity = 1

UNION ALL

-- ---------------------------------------------------------------------------
-- RULE: MISSING_LOAD_ID
-- ---------------------------------------------------------------------------
SELECT
    'MISSING_LOAD_ID',
    'HIGH',
    'LoadID is NULL on a sales order line — load-to-sales bridge cannot be established.',
    s.SalesOrderID,
    'SalesOrderLine',
    CONCAT(s.SalesOrderID, '|NULL|', COALESCE(s.ItemID,'NULL')),
    NULL,
    NULL,
    'Stg_SalesOrderLine',
    s.SourceSystem,
    s.BatchID,
    CURRENT_TIMESTAMP
FROM Stg_SalesOrderLine s
WHERE s.Flag_MissingLoadID = 1

UNION ALL

-- ---------------------------------------------------------------------------
-- RULE: DUPLICATE_LOAD_ID
-- ---------------------------------------------------------------------------
SELECT
    'DUPLICATE_LOAD_ID',
    'HIGH',
    'LoadID appears more than once in Stg_LoadFreight — freight fact grain violation.',
    l.LoadID,
    'LoadFreight',
    l.LoadID,
    l.DuplicateCount,
    l.DeduplicationRank,
    'Stg_LoadFreight',
    l.SourceSystem,
    l.BatchID,
    CURRENT_TIMESTAMP
FROM Stg_LoadFreight l
WHERE l.Flag_DuplicateLoadID = 1

UNION ALL

-- ---------------------------------------------------------------------------
-- RULE: DUPLICATE_CONTRACT_KEY
-- ---------------------------------------------------------------------------
SELECT
    'DUPLICATE_CONTRACT_KEY',
    'HIGH',
    'ContractPriceKey appears more than once in Stg_ContractPricing — contract matching ambiguity.',
    cp.ContractPriceKey,
    'ContractPricing',
    cp.ContractPriceKey,
    cp.DuplicateCount,
    cp.DeduplicationRank,
    'Stg_ContractPricing',
    cp.SourceSystem,
    cp.BatchID,
    CURRENT_TIMESTAMP
FROM Stg_ContractPricing cp
WHERE cp.Flag_DuplicateKey = 1;

-- INVERTED_CONTRACT_DATE rule removed v2.1.0 (2026-06-24):
-- EffectiveDate/ExpirationDate are open-ended defaults (1900-01-01 to 9999-12-31).
-- Inverted date range is structurally impossible with real data. Rule retired.

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Exception count by type and severity
-- SELECT ExceptionType, Severity, COUNT(*) AS ExceptionCount
-- FROM Exc_DataQuality
-- GROUP BY ExceptionType, Severity
-- ORDER BY ExceptionCount DESC;
