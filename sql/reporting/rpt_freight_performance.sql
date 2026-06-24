-- =============================================================================
-- MODULE:      Reporting Layer
-- SCRIPT:      rpt_freight_performance.sql
-- INPUT:       Calc_FreightSummary, Calc_LoadUtilization, Dim_Carrier
-- OUTPUT:      Rpt_FreightPerformance
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Calc_FreightSummary    (Module 4)
--   Calc_LoadUtilization   (Module 4)
--   Dim_Carrier            (Module 2)
-- =============================================================================
-- PURPOSE:
--   Carrier + period level freight performance report combining margin,
--   utilization, and load volume metrics into a single BI-ready surface.
--   Grain: CarrierKey + CalendarYear + CalendarMonth.
--
-- ASSUMPTIONS:
--   A1: CarrierName, CarrierType, CarrierMode are NULL in Dim_Carrier
--       until a carrier reference table is added (noted in Module 2).
--       These columns are included in output for future enrichment.
--   A2: UtilizationRate and UnderutilizationRate are derived from
--       Calc_LoadUtilization using candidate thresholds (UNK-002).
--   A3: Performance tier classification is applied at reporting layer:
--       STRONG:   FreightMarginPct >= 0.15 AND UtilizationRate >= 0.80
--       ADEQUATE: FreightMarginPct >= 0.05 AND UtilizationRate >= 0.65
--       AT_RISK:  FreightMarginPct < 0.05  OR  UtilizationRate < 0.65
--       NEGATIVE: FreightMarginPct < 0
--       THRESHOLD VALUES ARE CANDIDATE — no confirmed targets in unknowns log.
--       All rows carry Flag_CandidatePerformanceTier = 1.
-- =============================================================================

CREATE OR REPLACE TABLE Rpt_FreightPerformance AS

WITH

joined AS (
    SELECT
        f.CarrierKey,
        f.CarrierID,
        dc.CarrierName,
        dc.CarrierType,
        dc.CarrierMode,
        f.CalendarYear,
        f.CalendarMonth,
        f.MonthName,
        f.FiscalYear,
        f.FiscalQuarter,
        f.FiscalPeriod,

        -- Load volume
        f.LoadCount                                     AS TotalLoadCount,
        f.TotalPallets,
        f.AvgPalletsPerLoad,
        f.TotalWeight,

        -- Utilization band counts
        f.LoadCount_Full,
        f.LoadCount_Partial,
        f.LoadCount_Underutilized,
        f.LoadUtilizationRate,

        -- Fill rate detail
        u.AvgFillRate,
        u.MinFillRate,
        u.MaxFillRate,
        u.TotalPalletShortfall,
        u.UnderutilizationRate,

        -- Freight financials
        f.TotalFreightCharged,
        f.TotalFreightCost,
        f.TotalFreightMargin,
        f.FreightMarginPct,

        -- Exception counts
        f.Count_NegativeMarginLoads,
        f.Count_UnderutilizedLoads,
        f.Count_FreightChargedSuspect,

        -- Candidate flags
        f.TargetPallets

    FROM Calc_FreightSummary f
    JOIN Dim_Carrier dc ON f.CarrierKey = dc.CarrierKey
    LEFT JOIN Calc_LoadUtilization u
        ON  f.CarrierKey    = u.CarrierKey
        AND f.CalendarYear  = u.CalendarYear
        AND f.CalendarMonth = u.CalendarMonth
    WHERE f.CarrierKey <> -1
)

SELECT
    j.*,

    -- Performance tier classification (CANDIDATE thresholds)
    CASE
        WHEN j.FreightMarginPct < 0                                     THEN 'Negative'
        WHEN j.FreightMarginPct >= 0.15 AND j.LoadUtilizationRate >= 0.80 THEN 'Strong'
        WHEN j.FreightMarginPct >= 0.05 AND j.LoadUtilizationRate >= 0.65 THEN 'Adequate'
        ELSE                                                                  'At_Risk'
    END                                                 AS PerformanceTier,

    -- Candidate flag for performance tier thresholds
    1                                                   AS Flag_CandidatePerformanceTier,

    CURRENT_TIMESTAMP                                   AS ReportLoadedAt

FROM joined j;
