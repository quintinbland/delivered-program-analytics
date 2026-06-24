-- =============================================================================
-- MODULE:      Reporting Layer
-- SCRIPT:      rpt_executive_summary.sql
-- INPUT:       Calc_CustomerPerformance, Calc_FreightSummary,
--              Calc_LoadUtilization, Dim_Date
-- OUTPUT:      Rpt_ExecutiveSummary
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Calc_CustomerPerformance  (Module 4)
--   Calc_FreightSummary       (Module 4)
--   Calc_LoadUtilization      (Module 4)
--   Dim_Date                  (Module 2)
-- =============================================================================
-- PURPOSE:
--   Period-level executive summary aggregating revenue, FOB variance,
--   freight margin, and load utilization into a single reporting surface.
--   Grain: CalendarYear + CalendarMonth (one row per period).
--
-- ASSUMPTIONS:
--   A1: Reporting currency is USD throughout.
--   A2: All candidate threshold flags (UNK-002) are surfaced in output.
--   A3: Prior period comparison uses LAG() over CalendarYear + CalendarMonth.
--       [DIALECT NOTE] LAG() is ANSI SQL:2003 — supported in both T-SQL
--       and Snowflake.
--   A4: MoM = Month-over-Month. Calculated as (Current - Prior) / ABS(Prior).
--       NULL if prior period has no data.
-- =============================================================================

CREATE OR REPLACE TABLE Rpt_ExecutiveSummary AS

WITH

-- Period-level sales and FOB rollup
sales_period AS (
    SELECT
        CalendarYear,
        CalendarMonth,
        FiscalYear,
        FiscalQuarter,
        FiscalPeriod,
        SUM(TotalRevenue)                               AS TotalRevenue,
        SUM(TotalQuantityCases)                         AS TotalQuantityCases,
        SUM(TotalFOBVariance)                           AS TotalFOBVariance,
        SUM(TotalExcessSalesProfit)                     AS TotalExcessSalesProfit,
        SUM(LoadCount)                                  AS SalesLoadCount,
        COUNT(DISTINCT CustomerKey)                     AS ActiveCustomerCount,
        SUM(Count_NegativeFOBVarianceLines)             AS Count_NegativeFOBVarianceLines,
        SUM(Count_NoContractMatchLines)                 AS Count_NoContractMatchLines,
        MAX(Flag_CandidateHierarchy_UNK001)             AS Flag_CandidateHierarchy_UNK001
    FROM Calc_CustomerPerformance
    GROUP BY CalendarYear, CalendarMonth, FiscalYear, FiscalQuarter, FiscalPeriod
),

-- Period-level freight rollup
freight_period AS (
    SELECT
        CalendarYear,
        CalendarMonth,
        SUM(TotalFreightCharged)                        AS TotalFreightCharged,
        SUM(TotalFreightCost)                           AS TotalFreightCost,
        SUM(TotalFreightMargin)                         AS TotalFreightMargin,
        SUM(Count_NegativeMarginLoads)                  AS Count_NegativeMarginLoads,
        24                                                  AS TargetPallets
    FROM Calc_FreightSummary
    GROUP BY CalendarYear, CalendarMonth
),

-- Period-level load utilization rollup
util_period AS (
    SELECT
        CalendarYear,
        CalendarMonth,
        SUM(TotalLoadCount)                             AS TotalLoadCount,
        SUM(LoadCount_Full)                             AS LoadCount_Full,
        SUM(LoadCount_Partial)                          AS LoadCount_Partial,
        SUM(LoadCount_Underutilized)                    AS LoadCount_Underutilized,
        AVG(AvgFillRate)                                AS AvgFillRate,
        SUM(TotalPalletShortfall)                       AS TotalPalletShortfall
    FROM Calc_LoadUtilization
    GROUP BY CalendarYear, CalendarMonth
),

-- Join all period sources
combined AS (
    SELECT
        s.CalendarYear,
        s.CalendarMonth,
        s.FiscalYear,
        s.FiscalQuarter,
        s.FiscalPeriod,

        -- Sales
        s.TotalRevenue,
        s.TotalQuantityCases,
        s.TotalFOBVariance,
        s.TotalExcessSalesProfit,
        s.ActiveCustomerCount,
        s.Count_NegativeFOBVarianceLines,
        s.Count_NoContractMatchLines,

        -- Freight
        f.TotalFreightCharged,
        f.TotalFreightCost,
        f.TotalFreightMargin,
        CASE
            WHEN f.TotalFreightCharged > 0
            THEN f.TotalFreightMargin / f.TotalFreightCharged
            ELSE NULL
        END                                             AS FreightMarginPct,
        f.Count_NegativeMarginLoads,

        -- Load utilization
        u.TotalLoadCount,
        u.LoadCount_Full,
        u.LoadCount_Partial,
        u.LoadCount_Underutilized,
        u.AvgFillRate,
        u.TotalPalletShortfall,
        CASE
            WHEN u.TotalLoadCount > 0
            THEN CAST(u.LoadCount_Underutilized AS DECIMAL(10,4)) / u.TotalLoadCount
            ELSE NULL
        END                                             AS UnderutilizationRate,

        -- Combined margin
        COALESCE(s.TotalFOBVariance, 0)
        + COALESCE(f.TotalFreightMargin, 0)             AS TotalCombinedMargin,

        -- Candidate flags
        s.Flag_CandidateHierarchy_UNK001,
        f.TargetPallets

    FROM sales_period s
    LEFT JOIN freight_period f
        ON s.CalendarYear  = f.CalendarYear
       AND s.CalendarMonth = f.CalendarMonth
    LEFT JOIN util_period u
        ON s.CalendarYear  = u.CalendarYear
       AND s.CalendarMonth = u.CalendarMonth
),

-- MoM comparison using LAG
with_lag AS (
    SELECT
        c.*,
        LAG(c.TotalRevenue)       OVER (ORDER BY c.CalendarYear, c.CalendarMonth) AS Prior_TotalRevenue,
        LAG(c.TotalFOBVariance)   OVER (ORDER BY c.CalendarYear, c.CalendarMonth) AS Prior_TotalFOBVariance,
        LAG(c.TotalFreightMargin) OVER (ORDER BY c.CalendarYear, c.CalendarMonth) AS Prior_TotalFreightMargin,
        LAG(c.AvgFillRate)        OVER (ORDER BY c.CalendarYear, c.CalendarMonth) AS Prior_AvgFillRate
    FROM combined c
)

SELECT
    CalendarYear,
    CalendarMonth,
    FiscalYear,
    FiscalQuarter,
    FiscalPeriod,

    -- Revenue
    TotalRevenue,
    TotalQuantityCases,
    Prior_TotalRevenue,
    CASE
        WHEN Prior_TotalRevenue IS NOT NULL AND Prior_TotalRevenue <> 0
        THEN (TotalRevenue - Prior_TotalRevenue) / ABS(Prior_TotalRevenue)
        ELSE NULL
    END                                                 AS Revenue_MoM_Pct,

    -- FOB variance
    TotalFOBVariance,
    TotalExcessSalesProfit,
    Prior_TotalFOBVariance,
    CASE
        WHEN Prior_TotalFOBVariance IS NOT NULL AND Prior_TotalFOBVariance <> 0
        THEN (TotalFOBVariance - Prior_TotalFOBVariance) / ABS(Prior_TotalFOBVariance)
        ELSE NULL
    END                                                 AS FOBVariance_MoM_Pct,

    -- Freight
    TotalFreightCharged,
    TotalFreightCost,
    TotalFreightMargin,
    FreightMarginPct,
    Prior_TotalFreightMargin,

    -- Load utilization
    TotalLoadCount,
    LoadCount_Full,
    LoadCount_Partial,
    LoadCount_Underutilized,
    AvgFillRate,
    TotalPalletShortfall,
    UnderutilizationRate,

    -- Combined
    TotalCombinedMargin,
    ActiveCustomerCount,

    -- Exception counts
    Count_NegativeFOBVarianceLines,
    Count_NoContractMatchLines,
    Count_NegativeMarginLoads,

    -- Candidate flags
    Flag_CandidateHierarchy_UNK001,
    TargetPallets,

    CURRENT_TIMESTAMP                                   AS ReportLoadedAt

FROM with_lag
ORDER BY CalendarYear, CalendarMonth;
