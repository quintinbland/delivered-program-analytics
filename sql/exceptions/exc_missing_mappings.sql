-- =============================================================================
-- MODULE:      Exception System
-- SCRIPT:      exc_missing_mappings.sql
-- INPUT:       Stg_ProductMaster, Stg_SalesOrderLine, Dim_Customer
-- OUTPUT:      Exc_MissingMappings
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     1.0.1 — Removed MISSING_SHIPTO_MAPPING (2026-06-23)
-- =============================================================================
-- CHANGE LOG (v1.0.1):
--   - Removed EXCEPTION TYPE 3: MISSING_SHIPTO_MAPPING
--     ShipToID does not exist in Stg_SalesOrderLine v2.0 (real data has no
--     ShipTo source). All fact rows carry ShipToKey = -1 by design.
--     This exception type is not applicable with real data.
-- =============================================================================

CREATE OR REPLACE TABLE Exc_MissingMappings AS

-- ---------------------------------------------------------------------------
-- EXCEPTION TYPE 1: MISSING_COMMODITY_MAPPING
-- ---------------------------------------------------------------------------
SELECT
    'MISSING_COMMODITY_MAPPING'                         AS ExceptionType,
    'MEDIUM'                                            AS Severity,
    'ItemID exists in product master with no CommodityID — Tier 3 contract matching blocked for this item.' AS ExceptionDescription,
    p.ItemID                                            AS EntityID,
    'ItemID'                                            AS EntityType,
    p.ItemDescription                                   AS EntityDescription,
    CAST(NULL AS VARCHAR)                               AS TransactionContext,
    p.Flag_MissingCommodityMapping                      AS SourceFlag,
    'Stg_ProductMaster'                                 AS SourceTable,
    p.SourceSystem,
    p.BatchID,
    CURRENT_TIMESTAMP                                   AS ExceptionLoadedAt

FROM Stg_ProductMaster p
WHERE p.Flag_MissingCommodityMapping = 1

UNION ALL

-- ---------------------------------------------------------------------------
-- EXCEPTION TYPE 2: MISSING_CUSTOMER_MAPPING
-- ---------------------------------------------------------------------------
SELECT
    'MISSING_CUSTOMER_MAPPING'                          AS ExceptionType,
    'HIGH'                                              AS Severity,
    'CustomerID in sales transactions has no matching record in Dim_Customer — resolves to unknown member.' AS ExceptionDescription,
    s.CustomerID                                        AS EntityID,
    'CustomerID'                                        AS EntityType,
    CAST(NULL AS VARCHAR)                               AS EntityDescription,
    s.SalesOrderID                                      AS TransactionContext,
    s.Flag_MissingCustomerID                            AS SourceFlag,
    'Stg_SalesOrderLine'                                AS SourceTable,
    s.SourceSystem,
    s.BatchID,
    CURRENT_TIMESTAMP                                   AS ExceptionLoadedAt

FROM Stg_SalesOrderLine s
LEFT JOIN Dim_Customer dc ON s.CustomerID = dc.CustomerID
WHERE s.CustomerID IS NOT NULL
  AND dc.CustomerKey IS NULL;
