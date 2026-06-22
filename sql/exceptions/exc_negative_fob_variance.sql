-- =============================================================================
-- MODULE:      Exception System
-- SCRIPT:      exc_negative_fob_variance.sql
-- INPUT:       Fact_SalesOrderLine, Dim_Customer, Dim_Product, Dim_Date
-- OUTPUT:      Exc_NegativeFOBVariance
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Fact_SalesOrderLine  (Module 3)
--   Dim_Customer         (Module 2)
--   Dim_Product          (Module 2)
--   Dim_Date             (Module 2)
-- =============================================================================
-- EXCEPTION RULE: NEGATIVE_FOB_VARIANCE
--   Description:  A sales order line has a TotalFOBVariance below zero,
--                 meaning the actual FOB price achieved is less than the
--                 contracted FOB price for that customer and item.
--   Inputs:       Fact_SalesOrderLine.TotalFOBVariance
--                 Fact_SalesOrderLine.Flag_NegativeFOBVariance
--   Condition:    TotalFOBVariance < 0
--   Output:       One exception row per affected SalesOrderLine
--   Severity:     HIGH — direct negative impact on ExcessSalesProfit
--   Resolution:   Review pricing at time of order; verify contract terms;
--                 confirm ActualFOB calculation inputs are correct
-- =============================================================================

CREATE OR REPLACE TABLE Exc_NegativeFOBVariance AS

SELECT
    -- Exception metadata
    'NEGATIVE_FOB_VARIANCE'                             AS ExceptionType,
    'HIGH'                                              AS Severity,
    'ActualFOB is less than ContractFOBPrice — negative variance on this sales line.' AS ExceptionDescription,

    -- Source identifiers
    f.SalesOrderLineKey,
    f.SalesOrderID,
    f.LoadID,
    f.ItemID,

    -- Customer context
    f.CustomerKey,
    dc.CustomerID,
    dc.CustomerName,
    dc.CustomerStatusCode,

    -- Product context
    f.ProductKey,
    dp.ItemID                                           AS ItemID_Dim,
    dp.ItemDescription,

    -- Period context
    f.ShipDateKey,
    d.CalendarYear,
    d.CalendarMonth,

    -- Variance detail
    f.QuantityCases,
    f.NetLineRevenue,
    f.ActualFOB,
    f.ContractFOBPrice,
    f.FOBVariancePerCase,
    f.TotalFOBVariance,
    f.ExcessSalesProfit,
    f.ContractMatchTier,

    -- Impact magnitude classification
    CASE
        WHEN f.TotalFOBVariance >= -100     THEN 'Low'
        WHEN f.TotalFOBVariance >= -1000    THEN 'Medium'
        WHEN f.TotalFOBVariance >= -10000   THEN 'High'
        ELSE                                     'Critical'
    END                                                 AS ImpactBand,

    -- Flags
    f.Flag_CandidateHierarchy_UNK001,

    -- Lineage
    f.SourceSystem,
    f.BatchID,
    CURRENT_TIMESTAMP                                   AS ExceptionLoadedAt

FROM Fact_SalesOrderLine f
JOIN Dim_Customer dc ON f.CustomerKey = dc.CustomerKey
JOIN Dim_Product  dp ON f.ProductKey  = dp.ProductKey
JOIN Dim_Date     d  ON f.ShipDateKey = d.DateKey
WHERE f.Flag_NegativeFOBVariance = 1
  AND f.CustomerKey <> -1
  AND f.ShipDateKey <> -1;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Impact band distribution
-- SELECT ImpactBand, COUNT(*) AS ExceptionCount, SUM(TotalFOBVariance) AS TotalImpact
-- FROM Exc_NegativeFOBVariance
-- GROUP BY ImpactBand ORDER BY TotalImpact ASC;
