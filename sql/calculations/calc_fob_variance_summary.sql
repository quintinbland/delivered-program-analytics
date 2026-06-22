-- =============================================================================
-- MODULE:      Calculation Engine
-- SCRIPT:      calc_fob_variance_summary.sql
-- INPUT:       Fact_SalesOrderLine, Dim_Customer, Dim_Product, Dim_Date
-- OUTPUT:      Calc_FOBVarianceSummary
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Fact_SalesOrderLine  (Module 3)
--   Dim_Customer         (Module 2)
--   Dim_Product          (Module 2)
--   Dim_Date             (Module 2)
-- =============================================================================
-- BUSINESS RULES IMPLEMENTED:
--
--   RULE: ACTUAL_FOB
--     Inputs:       NetLineRevenue, QuantityCases
--     Condition:    QuantityCases IS NOT NULL AND QuantityCases > 0
--     Output:       ActualFOB = NetLineRevenue / QuantityCases
--     Edge Cases:   NULL if QuantityCases = 0 or NULL
--
--   RULE: FOB_VARIANCE_PER_CASE
--     Inputs:       ActualFOB, ContractFOBPrice
--     Condition:    ActualFOB IS NOT NULL AND ContractFOBPrice IS NOT NULL
--     Output:       FOBVariancePerCase = ActualFOB - ContractFOBPrice
--     Edge Cases:   NULL if either input is NULL
--
--   RULE: TOTAL_FOB_VARIANCE
--     Inputs:       FOBVariancePerCase, QuantityCases
--     Condition:    FOBVariancePerCase IS NOT NULL AND QuantityCases IS NOT NULL
--     Output:       TotalFOBVariance = FOBVariancePerCase * QuantityCases
--     Edge Cases:   NULL if either input is NULL
--
--   RULE: EXCESS_SALES_PROFIT
--     Inputs:       TotalFOBVariance
--     Condition:    TotalFOBVariance IS NOT NULL
--     Output:       ExcessSalesProfit = TotalFOBVariance
--     Edge Cases:   NULL if TotalFOBVariance is NULL
--
-- NOTE: Row-level calculations are sourced from Fact_SalesOrderLine.
--       This script aggregates pre-calculated row measures only.
--       No recalculation of ActualFOB at the summary level.
--
-- AGGREGATION GRAIN: CustomerKey + ProductKey + CalendarYear + CalendarMonth
-- =============================================================================

CREATE OR REPLACE TABLE Calc_FOBVarianceSummary AS

SELECT
    -- Dimension keys
    f.CustomerKey,
    dc.CustomerID,
    dc.CustomerName,
    dc.CustomerStatusCode,
    dc.CustomerHQID,

    f.ProductKey,
    dp.ItemID,
    dp.ItemDescription,
    dp.CommodityKey,

    d.CalendarYear,
    d.CalendarMonth,
    d.MonthName,
    d.FiscalYear,
    d.FiscalQuarter,
    d.FiscalPeriod,

    -- Contract matching tier distribution
    SUM(CASE WHEN f.ContractMatchTier = 'Tier1_CustomerItem' THEN 1 ELSE 0 END) AS LineCount_Tier1,
    SUM(CASE WHEN f.ContractMatchTier = 'Tier2_HQItem'       THEN 1 ELSE 0 END) AS LineCount_Tier2,
    SUM(CASE WHEN f.ContractMatchTier = 'Tier3_HQCommodity'  THEN 1 ELSE 0 END) AS LineCount_Tier3,
    SUM(CASE WHEN f.ContractMatchTier = 'NoMatch'            THEN 1 ELSE 0 END) AS LineCount_NoMatch,

    -- Volume
    COUNT(*)                                            AS TotalLineCount,
    SUM(f.QuantityCases)                                AS TotalQuantityCases,

    -- Revenue
    SUM(f.NetLineRevenue)                               AS TotalNetLineRevenue,

    -- FOB summary (rows with contract match only)
    SUM(CASE WHEN f.ContractFOBPrice IS NOT NULL
             THEN f.QuantityCases ELSE 0 END)           AS MatchedQuantityCases,

    -- Weighted average ActualFOB (revenue / matched cases)
    CASE
        WHEN SUM(CASE WHEN f.ActualFOB IS NOT NULL
                      THEN f.QuantityCases ELSE 0 END) = 0
        THEN NULL
        ELSE SUM(CASE WHEN f.ActualFOB IS NOT NULL
                      THEN f.NetLineRevenue ELSE 0 END)
           / SUM(CASE WHEN f.ActualFOB IS NOT NULL
                      THEN f.QuantityCases ELSE 0 END)
    END                                                 AS WeightedAvgActualFOB,

    -- Weighted average ContractFOB (across matched rows)
    CASE
        WHEN SUM(CASE WHEN f.ContractFOBPrice IS NOT NULL
                      THEN f.QuantityCases ELSE 0 END) = 0
        THEN NULL
        ELSE SUM(CASE WHEN f.ContractFOBPrice IS NOT NULL
                      THEN f.ContractFOBPrice * f.QuantityCases ELSE 0 END)
           / SUM(CASE WHEN f.ContractFOBPrice IS NOT NULL
                      THEN f.QuantityCases ELSE 0 END)
    END                                                 AS WeightedAvgContractFOB,

    -- Variance totals
    SUM(f.TotalFOBVariance)                             AS TotalFOBVariance,
    SUM(f.ExcessSalesProfit)                            AS TotalExcessSalesProfit,

    -- Average variance per case (total variance / matched cases)
    CASE
        WHEN SUM(CASE WHEN f.FOBVariancePerCase IS NOT NULL
                      THEN f.QuantityCases ELSE 0 END) = 0
        THEN NULL
        ELSE SUM(f.TotalFOBVariance)
           / SUM(CASE WHEN f.FOBVariancePerCase IS NOT NULL
                      THEN f.QuantityCases ELSE 0 END)
    END                                                 AS AvgFOBVariancePerCase,

    -- Exception counts
    SUM(f.Flag_NegativeFOBVariance)                     AS Count_NegativeFOBVarianceLines,
    SUM(f.Flag_NoContractMatch)                         AS Count_NoContractMatchLines,

    -- Candidate hierarchy flag (propagated)
    MAX(f.Flag_CandidateHierarchy_UNK001)               AS Flag_CandidateHierarchy_UNK001,

    CURRENT_TIMESTAMP                                   AS CalcLoadedAt

FROM Fact_SalesOrderLine f
JOIN Dim_Customer dc
    ON f.CustomerKey = dc.CustomerKey
JOIN Dim_Product dp
    ON f.ProductKey  = dp.ProductKey
JOIN Dim_Date d
    ON f.ShipDateKey = d.DateKey
WHERE f.ShipDateKey  <> -1
  AND f.CustomerKey  <> -1
  AND f.ProductKey   <> -1
GROUP BY
    f.CustomerKey,
    dc.CustomerID,
    dc.CustomerName,
    dc.CustomerStatusCode,
    dc.CustomerHQID,
    f.ProductKey,
    dp.ItemID,
    dp.ItemDescription,
    dp.CommodityKey,
    d.CalendarYear,
    d.CalendarMonth,
    d.MonthName,
    d.FiscalYear,
    d.FiscalQuarter,
    d.FiscalPeriod;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Total variance reconciliation
-- SELECT SUM(TotalFOBVariance) FROM Calc_FOBVarianceSummary;
-- SELECT SUM(TotalFOBVariance) FROM Fact_SalesOrderLine WHERE ShipDateKey <> -1;

-- Contract customers with no-match lines (exception candidates)
-- SELECT CustomerID, CustomerName, CustomerStatusCode,
--        SUM(Count_NoContractMatchLines) AS NoMatchLines
-- FROM Calc_FOBVarianceSummary
-- WHERE CustomerStatusCode = 'CONTRACT'
-- GROUP BY CustomerID, CustomerName, CustomerStatusCode
-- HAVING SUM(Count_NoContractMatchLines) > 0;
