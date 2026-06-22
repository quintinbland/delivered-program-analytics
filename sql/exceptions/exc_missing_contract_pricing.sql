-- =============================================================================
-- MODULE:      Exception System
-- SCRIPT:      exc_missing_contract_pricing.sql
-- INPUT:       Fact_SalesOrderLine, Dim_Customer, Dim_CustomerStatus
-- OUTPUT:      Exc_MissingContractPricing
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Fact_SalesOrderLine  (Module 3)
--   Dim_Customer         (Module 2)
--   Dim_CustomerStatus   (Module 2)
-- =============================================================================
-- EXCEPTION RULE: MISSING_CONTRACT_PRICING
--   Description:  A contract customer has a sales order line with no resolved
--                 contract FOB price.
--   Inputs:       Fact_SalesOrderLine.Flag_NoContractMatch
--                 Dim_Customer.CustomerStatusCode
--   Condition:    CustomerStatusCode = 'CONTRACT'
--                 AND Fact_SalesOrderLine.ContractMatchTier = 'NoMatch'
--   Output:       One exception row per affected SalesOrderLine
--   Severity:     HIGH — affects profitability reporting and variance calculation
--   Resolution:   Requires contract record to be added to Raw_ContractPricing
--                 or customer status to be corrected
-- =============================================================================

CREATE OR REPLACE TABLE Exc_MissingContractPricing AS

SELECT
    -- Exception metadata
    'MISSING_CONTRACT_PRICING'                          AS ExceptionType,
    'HIGH'                                              AS Severity,
    'Contract customer has a sales line with no matching contract FOB price.' AS ExceptionDescription,

    -- Source identifiers
    f.SalesOrderLineKey,
    f.SalesOrderID,
    f.LoadID,
    f.ItemID,

    -- Customer context
    f.CustomerKey,
    dc.CustomerID,
    dc.CustomerName,
    dc.CustomerHQID,
    dc.CustomerStatusCode,

    -- Contract matching context
    f.ContractMatchTier,
    f.ContractPriceKey,
    f.ContractFOBPrice,

    -- Transaction context
    f.ShipDateKey,
    f.QuantityCases,
    f.NetLineRevenue,
    f.ActualFOB,

    -- Impact: variance cannot be calculated
    NULL                                                AS TotalFOBVariance,
    'ContractFOBPrice IS NULL — variance calculation blocked'
                                                        AS ImpactNote,

    -- Flags
    f.Flag_CandidateHierarchy_UNK001,

    -- Lineage
    f.SourceSystem,
    f.BatchID,
    CURRENT_TIMESTAMP                                   AS ExceptionLoadedAt

FROM Fact_SalesOrderLine f
JOIN Dim_Customer dc
    ON f.CustomerKey = dc.CustomerKey
WHERE f.Flag_NoContractMatch = 1
  AND dc.CustomerStatusCode = 'CONTRACT'
  AND f.CustomerKey <> -1;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Exception count by customer
-- SELECT dc.CustomerID, dc.CustomerName, COUNT(*) AS ExceptionCount
-- FROM Exc_MissingContractPricing e
-- JOIN Dim_Customer dc ON e.CustomerKey = dc.CustomerKey
-- GROUP BY dc.CustomerID, dc.CustomerName
-- ORDER BY ExceptionCount DESC;
