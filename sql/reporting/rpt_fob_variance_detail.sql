-- =============================================================================
-- MODULE:      Reporting Layer
-- SCRIPT:      rpt_fob_variance_detail.sql
-- INPUT:       Calc_FOBVarianceSummary, Dim_Customer, Dim_Product,
--              Dim_Commodity, Dim_CustomerStatus
-- OUTPUT:      Rpt_FOBVarianceDetail
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Calc_FOBVarianceSummary  (Module 4)
--   Dim_Customer             (Module 2)
--   Dim_Product              (Module 2)
--   Dim_Commodity            (Module 2)
--   Dim_CustomerStatus       (Module 2)
-- =============================================================================
-- PURPOSE:
--   Customer + item + period level FOB variance detail for pricing review.
--   Grain: CustomerKey + ProductKey + CalendarYear + CalendarMonth.
--   Includes contract match tier breakdown, variance ranking, and
--   enriched dimension attributes for filtering in BI tools.
--
-- ASSUMPTIONS:
--   A1: Variance ranking (RANK()) is within CalendarYear + CalendarMonth.
--       Rank 1 = largest negative variance (worst performers first).
--   A2: ContractMatchTier distribution columns are sourced from
--       Calc_FOBVarianceSummary and reflect candidate hierarchy (UNK-001).
--   A3: CommodityGroup and CommodityCategory are included for commodity-level
--       rollup in BI tools without requiring an additional join.
-- =============================================================================

CREATE OR REPLACE TABLE Rpt_FOBVarianceDetail AS

SELECT
    -- Period
    v.CalendarYear,
    v.CalendarMonth,
    v.FiscalYear,
    v.FiscalQuarter,
    v.FiscalPeriod,

    -- Customer attributes
    v.CustomerKey,
    v.CustomerID,
    v.CustomerName,
    v.CustomerHQID,
    v.CustomerStatusCode,
    cs.CustomerStatusLabel,
    dc.CustomerRegion,
    dc.CustomerSegment,

    -- Product attributes
    v.ProductKey,
    v.ItemID,
    v.ItemDescription,
    dp.ItemCategory,
    dp.PackSize,
    dp.UnitOfMeasure,
    dp.OrganicConventionalFlag,

    -- Commodity attributes (denormalized for BI)
    v.CommodityKey,
    dcom.CommodityID,
    dcom.CommodityName,
    dcom.CommodityGroup,
    dcom.CommodityCategory,

    -- Volume
    v.TotalLineCount,
    v.TotalQuantityCases,
    v.TotalNetLineRevenue,
    v.MatchedQuantityCases,

    -- FOB pricing
    v.WeightedAvgActualFOB,
    v.WeightedAvgContractFOB,
    v.AvgFOBVariancePerCase,

    -- Variance totals
    v.TotalFOBVariance,
    v.TotalExcessSalesProfit,

    -- Contract tier breakdown
    v.LineCount_Tier1,
    v.LineCount_Tier2,
    v.LineCount_Tier3,
    v.LineCount_NoMatch,

    -- Variance ranking within period (worst first)
    RANK() OVER (
        PARTITION BY v.CalendarYear, v.CalendarMonth
        ORDER BY COALESCE(v.TotalFOBVariance, 0) ASC
    )                                                   AS VarianceRank_Period,

    -- Variance ranking within customer across all periods
    RANK() OVER (
        PARTITION BY v.CustomerKey
        ORDER BY COALESCE(v.TotalFOBVariance, 0) ASC
    )                                                   AS VarianceRank_Customer,

    -- Exception counts
    v.Count_NegativeFOBVarianceLines,
    v.Count_NoContractMatchLines,

    -- Candidate flag
    v.Flag_CandidateHierarchy_UNK001,

    CURRENT_TIMESTAMP                                   AS ReportLoadedAt

FROM Calc_FOBVarianceSummary v
JOIN Dim_Customer dc
    ON v.CustomerKey = dc.CustomerKey
JOIN Dim_CustomerStatus cs
    ON dc.CustomerStatusKey = cs.CustomerStatusKey
JOIN Dim_Product dp
    ON v.ProductKey = dp.ProductKey
LEFT JOIN Dim_Commodity dcom
    ON v.CommodityKey = dcom.CommodityKey
WHERE v.CustomerKey <> -1
  AND v.ProductKey  <> -1;
