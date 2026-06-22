-- =============================================================================
-- MODULE:      Exception System
-- SCRIPT:      exc_missing_mappings.sql
-- INPUT:       Stg_ProductMaster, Stg_SalesOrderLine, Dim_Customer, Dim_ShipTo
-- OUTPUT:      Exc_MissingMappings
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Stg_ProductMaster    (Module 1)
--   Stg_SalesOrderLine   (Module 1)
--   Dim_Customer         (Module 2)
--   Dim_ShipTo           (Module 2)
-- =============================================================================
-- EXCEPTION RULES COVERED:
--
--   RULE: MISSING_COMMODITY_MAPPING
--     Description:  An ItemID exists in the product master with no CommodityID.
--     Inputs:       Stg_ProductMaster.Flag_MissingCommodityMapping
--     Condition:    ItemID IS NOT NULL AND CommodityID IS NULL
--     Severity:     MEDIUM — blocks Tier 3 contract matching for this item
--
--   RULE: MISSING_CUSTOMER_MAPPING
--     Description:  A CustomerID appears in sales order lines but has no
--                   matching record in Dim_Customer.
--     Inputs:       Stg_SalesOrderLine.CustomerID, Dim_Customer.CustomerID
--     Condition:    CustomerID in transactions NOT IN Dim_Customer
--     Severity:     HIGH — customer dimension cannot be resolved; line
--                   routes to CustomerKey = -1 in fact table
--
--   RULE: MISSING_SHIPTO_MAPPING
--     Description:  A ShipToID appears in sales order lines but has no
--                   matching record in Dim_ShipTo.
--     Inputs:       Stg_SalesOrderLine.ShipToID, Dim_ShipTo.ShipToID
--     Condition:    ShipToID in transactions NOT IN Dim_ShipTo
--     Severity:     MEDIUM — ShipTo dimension cannot be resolved; line
--                   routes to ShipToKey = -1 in fact table
-- =============================================================================

CREATE OR REPLACE TABLE Exc_MissingMappings AS

-- ---------------------------------------------------------------------------
-- EXCEPTION TYPE 1: MISSING_COMMODITY_MAPPING
-- Source: Stg_ProductMaster
-- ---------------------------------------------------------------------------
SELECT
    'MISSING_COMMODITY_MAPPING'                         AS ExceptionType,
    'MEDIUM'                                            AS Severity,
    'ItemID exists in product master with no CommodityID — Tier 3 contract matching blocked for this item.' AS ExceptionDescription,
    p.ItemID                                            AS EntityID,
    'ItemID'                                            AS EntityType,
    p.ItemDescription                                   AS EntityDescription,
    NULL                                                AS TransactionContext,
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
-- Source: Stg_SalesOrderLine — CustomerIDs with no Dim_Customer record
-- ---------------------------------------------------------------------------
SELECT
    'MISSING_CUSTOMER_MAPPING'                          AS ExceptionType,
    'HIGH'                                              AS Severity,
    'CustomerID in sales transactions has no matching record in Dim_Customer — resolves to unknown member.' AS ExceptionDescription,
    s.CustomerID                                        AS EntityID,
    'CustomerID'                                        AS EntityType,
    NULL                                                AS EntityDescription,
    s.SalesOrderID                                      AS TransactionContext,
    s.Flag_MissingCustomerID                            AS SourceFlag,
    'Stg_SalesOrderLine'                                AS SourceTable,
    s.SourceSystem,
    s.BatchID,
    CURRENT_TIMESTAMP                                   AS ExceptionLoadedAt

FROM Stg_SalesOrderLine s
LEFT JOIN Dim_Customer dc ON s.CustomerID = dc.CustomerID
WHERE s.CustomerID IS NOT NULL
  AND dc.CustomerKey IS NULL

UNION ALL

-- ---------------------------------------------------------------------------
-- EXCEPTION TYPE 3: MISSING_SHIPTO_MAPPING
-- Source: Stg_SalesOrderLine — ShipToIDs with no Dim_ShipTo record
-- ---------------------------------------------------------------------------
SELECT
    'MISSING_SHIPTO_MAPPING'                            AS ExceptionType,
    'MEDIUM'                                            AS Severity,
    'ShipToID in sales transactions has no matching record in Dim_ShipTo — resolves to unknown member.' AS ExceptionDescription,
    s.ShipToID                                          AS EntityID,
    'ShipToID'                                          AS EntityType,
    NULL                                                AS EntityDescription,
    s.SalesOrderID                                      AS TransactionContext,
    s.Flag_MissingShipToID                              AS SourceFlag,
    'Stg_SalesOrderLine'                                AS SourceTable,
    s.SourceSystem,
    s.BatchID,
    CURRENT_TIMESTAMP                                   AS ExceptionLoadedAt

FROM Stg_SalesOrderLine s
LEFT JOIN Dim_ShipTo dst ON s.ShipToID = dst.ShipToID
WHERE s.ShipToID IS NOT NULL
  AND dst.ShipToKey IS NULL;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Exception count by type
-- SELECT ExceptionType, Severity, COUNT(*) AS ExceptionCount
-- FROM Exc_MissingMappings
-- GROUP BY ExceptionType, Severity
-- ORDER BY ExceptionCount DESC;
