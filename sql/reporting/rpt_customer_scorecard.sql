-- =============================================================================
-- MODULE:      Reporting Layer
-- SCRIPT:      rpt_customer_scorecard.sql
-- INPUT:       Calc_CustomerPerformance, Exc_Master, Dim_Customer,
--              Dim_CustomerStatus
-- OUTPUT:      Rpt_CustomerScorecard
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Calc_CustomerPerformance  (Module 4)
--   Exc_Master                (Module 5)
--   Dim_Customer              (Module 2)
--   Dim_CustomerStatus        (Module 2)
-- =============================================================================
-- PURPOSE:
--   Customer-level scorecard combining performance metrics and exception
--   counts into a single ranked BI-ready surface.
--   Grain: CustomerKey (one row per customer, all-period aggregate).
--   Includes period trend via rolling 3-month metrics.
--
-- ASSUMPTIONS:
--   A1: All-period aggregate uses full history in Calc_CustomerPerformance.
--       No date filter applied — full pipeline history included.
--   A2: Rolling 3-month window uses MAX(CalendarYear + CalendarMonth)
--       as the anchor. Periods with no activity are excluded.
--   A3: Customer health tier classification:
--       HEALTHY:     TotalFOBVariance >= 0 AND Count_NoContractMatchLines = 0
--       AT_RISK:     TotalFOBVariance < 0  OR  Count_NoContractMatchLines > 0
--       CRITICAL:    TotalFOBVariance < 0  AND Count_NoContractMatchLines > 0
--       These are CANDIDATE definitions — no confirmed thresholds in unknowns log.
--       Flag_CandidateHealthTier = 1 on all rows.
--   A4: ExceptionCount sourced from Exc_Master using CustomerID as SecondaryEntityID
--       for contract/variance exceptions, and PrimaryEntityID for others.
--       Only OPEN exceptions are counted.
-- =============================================================================

CREATE OR REPLACE TABLE Rpt_CustomerScorecard AS

WITH

-- All-period performance rollup per customer
all_period AS (
    SELECT
        CustomerKey,
        CustomerID,
        CustomerName,
        CustomerHQID,
        CustomerStatusCode,
        CustomerRegion,
        CustomerSegment,
        SUM(TotalRevenue)                               AS AllPeriod_TotalRevenue,
        SUM(TotalQuantityCases)                         AS AllPeriod_TotalCases,
        SUM(TotalFOBVariance)                           AS AllPeriod_TotalFOBVariance,
        SUM(TotalExcessSalesProfit)                     AS AllPeriod_ExcessSalesProfit,
        SUM(AllocatedFreightMargin)                     AS AllPeriod_AllocatedFreightMargin,
        SUM(TotalCombinedMargin)                        AS AllPeriod_TotalCombinedMargin,
        SUM(LoadCount)                                  AS AllPeriod_LoadCount,
        SUM(TotalLineCount)                             AS AllPeriod_LineCount,
        SUM(Count_NegativeFOBVarianceLines)             AS AllPeriod_NegVarianceLines,
        SUM(Count_NoContractMatchLines)                 AS AllPeriod_NoContractMatchLines,
        COUNT(DISTINCT CalendarYear * 100 + CalendarMonth) AS ActivePeriodCount,
        MAX(Flag_CandidateHierarchy_UNK001)             AS Flag_CandidateHierarchy_UNK001
    FROM Calc_CustomerPerformance
    WHERE CustomerKey <> -1
    GROUP BY CustomerKey, CustomerID, CustomerName, CustomerHQID,
             CustomerStatusCode, CustomerRegion, CustomerSegment
),

-- Rolling 3-month window — most recent 3 periods with data
period_anchor AS (
    SELECT MAX(CalendarYear * 100 + CalendarMonth) AS MaxPeriod
    FROM Calc_CustomerPerformance
),

rolling_3m AS (
    SELECT
        cp.CustomerKey,
        SUM(cp.TotalRevenue)                            AS R3M_Revenue,
        SUM(cp.TotalFOBVariance)                        AS R3M_FOBVariance,
        SUM(cp.TotalCombinedMargin)                     AS R3M_CombinedMargin,
        SUM(cp.Count_NegativeFOBVarianceLines)          AS R3M_NegVarianceLines,
        SUM(cp.Count_NoContractMatchLines)              AS R3M_NoContractMatchLines
    FROM Calc_CustomerPerformance cp
    CROSS JOIN period_anchor pa
    WHERE cp.CustomerKey <> -1
      AND (cp.CalendarYear * 100 + cp.CalendarMonth) <=  pa.MaxPeriod
      AND (cp.CalendarYear * 100 + cp.CalendarMonth) >= (pa.MaxPeriod - 2)
    GROUP BY cp.CustomerKey
),

-- Open exception counts from Exc_Master per customer
exception_counts AS (
    SELECT
        SecondaryEntityID                               AS CustomerID,
        COUNT(*)                                        AS OpenExceptionCount,
        SUM(COALESCE(FinancialImpact, 0))               AS OpenExceptionFinancialImpact
    FROM Exc_Master
    WHERE ResolutionStatus = 'OPEN'
      AND SecondaryEntityType = 'Customer'
    GROUP BY SecondaryEntityID
)

SELECT
    a.CustomerKey,
    a.CustomerID,
    a.CustomerName,
    a.CustomerHQID,
    a.CustomerStatusCode,
    cs.CustomerStatusLabel,
    a.CustomerRegion,
    a.CustomerSegment,

    -- All-period metrics
    a.AllPeriod_TotalRevenue,
    a.AllPeriod_TotalCases,
    a.AllPeriod_TotalFOBVariance,
    a.AllPeriod_ExcessSalesProfit,
    a.AllPeriod_AllocatedFreightMargin,
    a.AllPeriod_TotalCombinedMargin,
    a.AllPeriod_LoadCount,
    a.AllPeriod_LineCount,
    a.AllPeriod_NegVarianceLines,
    a.AllPeriod_NoContractMatchLines,
    a.ActivePeriodCount,

    -- Rolling 3-month metrics
    r.R3M_Revenue,
    r.R3M_FOBVariance,
    r.R3M_CombinedMargin,
    r.R3M_NegVarianceLines,
    r.R3M_NoContractMatchLines,

    -- Average per active period
    CASE WHEN a.ActivePeriodCount > 0
         THEN a.AllPeriod_TotalRevenue / a.ActivePeriodCount
         ELSE NULL
    END                                                 AS AvgMonthlyRevenue,
    CASE WHEN a.ActivePeriodCount > 0
         THEN a.AllPeriod_TotalFOBVariance / a.ActivePeriodCount
         ELSE NULL
    END                                                 AS AvgMonthlyFOBVariance,

    -- Open exceptions
    COALESCE(e.OpenExceptionCount, 0)                   AS OpenExceptionCount,
    COALESCE(e.OpenExceptionFinancialImpact, 0)         AS OpenExceptionFinancialImpact,

    -- Health tier (CANDIDATE — no confirmed thresholds)
    CASE
        WHEN a.AllPeriod_TotalFOBVariance <  0
         AND a.AllPeriod_NoContractMatchLines > 0       THEN 'Critical'
        WHEN a.AllPeriod_TotalFOBVariance <  0
          OR a.AllPeriod_NoContractMatchLines > 0       THEN 'At_Risk'
        ELSE                                                 'Healthy'
    END                                                 AS CustomerHealthTier,

    -- Candidate flag for health tier
    1                                                   AS Flag_CandidateHealthTier,

    -- Revenue rank across all customers
    RANK() OVER (ORDER BY a.AllPeriod_TotalRevenue DESC)    AS RevenueRank,

    -- FOB variance rank (worst first)
    RANK() OVER (ORDER BY COALESCE(a.AllPeriod_TotalFOBVariance, 0) ASC) AS FOBVarianceRank,

    -- Candidate flags
    a.Flag_CandidateHierarchy_UNK001,

    CURRENT_TIMESTAMP                                   AS ReportLoadedAt

FROM all_period a
JOIN Dim_CustomerStatus cs
    ON a.CustomerStatusCode = cs.CustomerStatusCode
LEFT JOIN rolling_3m r
    ON a.CustomerKey = r.CustomerKey
LEFT JOIN exception_counts e
    ON a.CustomerID  = e.CustomerID;
