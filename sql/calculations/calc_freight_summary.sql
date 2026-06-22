-- =============================================================================
-- MODULE:      Calculation Engine
-- SCRIPT:      calc_freight_summary.sql
-- INPUT:       Fact_LoadFreight, Dim_Carrier, Dim_Date
-- OUTPUT:      Calc_FreightSummary
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Fact_LoadFreight  (Module 3)
--   Dim_Carrier       (Module 2)
--   Dim_Date          (Module 2)
-- =============================================================================
-- BUSINESS RULES IMPLEMENTED:
--
--   RULE: FREIGHT_MARGIN
--     Inputs:       FreightCharged, FreightPaid
--     Condition:    FreightCharged IS NOT NULL AND FreightPaid IS NOT NULL
--     Output:       FreightMargin = FreightCharged - FreightPaid
--     Edge Cases:   NULL if either input is NULL
--
--   RULE: FREIGHT_MARGIN_PCT
--     Inputs:       FreightMargin, FreightCharged
--     Condition:    FreightCharged IS NOT NULL AND FreightCharged <> 0
--     Output:       FreightMarginPct = FreightMargin / FreightCharged
--     Edge Cases:   NULL if FreightCharged = 0 or NULL
--
--   RULE: LOAD_UTILIZATION_BAND (CANDIDATE — UNK-002)
--     Inputs:       LoadPallets
--     Condition:    LoadPallets >= 24 → Full
--                   LoadPallets >= 18 AND < 24 → Partial
--                   LoadPallets < 18 → Underutilized
--                   LoadPallets IS NULL → UNKNOWN
--     Output:       LoadUtilizationBand
--     Edge Cases:   Threshold of 24 is candidate; all rows carry
--                   Flag_CandidateThreshold_UNK002 = 1
--
-- AGGREGATION GRAIN: CarrierKey + CalendarYear + CalendarMonth
-- =============================================================================

CREATE OR REPLACE TABLE Calc_FreightSummary AS

SELECT
    -- Dimension keys
    f.CarrierKey,
    dc.CarrierID,
    d.CalendarYear,
    d.CalendarMonth,
    d.MonthName,
    d.FiscalYear,
    d.FiscalQuarter,
    d.FiscalPeriod,

    -- Load volume
    COUNT(DISTINCT f.LoadID)                            AS LoadCount,
    SUM(f.LoadPallets)                                  AS TotalPallets,
    AVG(f.LoadPallets)                                  AS AvgPalletsPerLoad,
    SUM(f.LoadWeight)                                   AS TotalWeight,

    -- Load utilization band counts (candidate thresholds — UNK-002)
    SUM(CASE WHEN f.LoadUtilizationBand = 'Full'          THEN 1 ELSE 0 END) AS LoadCount_Full,
    SUM(CASE WHEN f.LoadUtilizationBand = 'Partial'       THEN 1 ELSE 0 END) AS LoadCount_Partial,
    SUM(CASE WHEN f.LoadUtilizationBand = 'Underutilized' THEN 1 ELSE 0 END) AS LoadCount_Underutilized,
    SUM(CASE WHEN f.LoadUtilizationBand = 'UNKNOWN'       THEN 1 ELSE 0 END) AS LoadCount_Unknown,

    -- Utilization rate (Full + Partial as pct of total)
    CASE
        WHEN COUNT(DISTINCT f.LoadID) = 0 THEN NULL
        ELSE CAST(
            SUM(CASE WHEN f.LoadUtilizationBand IN ('Full','Partial') THEN 1 ELSE 0 END)
            AS DECIMAL(10,4))
            / COUNT(DISTINCT f.LoadID)
    END                                                 AS LoadUtilizationRate,

    -- Freight financials
    SUM(f.FreightCharged)                               AS TotalFreightCharged,
    SUM(f.FreightPaid)                                  AS TotalFreightPaid,
    SUM(f.FreightMargin)                                AS TotalFreightMargin,

    -- Margin pct at summary level (recalculated from aggregates, not avg of row pcts)
    CASE
        WHEN SUM(f.FreightCharged) IS NULL
          OR SUM(f.FreightCharged) = 0 THEN NULL
        ELSE SUM(f.FreightMargin) / SUM(f.FreightCharged)
    END                                                 AS FreightMarginPct,

    -- Exception counts
    SUM(f.Flag_NegativeFreightMargin)                   AS Count_NegativeMarginLoads,
    SUM(f.Flag_UnderutilizedLoad)                       AS Count_UnderutilizedLoads,
    SUM(f.Flag_FreightChargedSuspect)                   AS Count_FreightChargedSuspect,

    -- Candidate threshold flag (propagated from fact)
    MAX(f.Flag_CandidateThreshold_UNK002)               AS Flag_CandidateThreshold_UNK002,

    CURRENT_TIMESTAMP                                   AS CalcLoadedAt

FROM Fact_LoadFreight f
JOIN Dim_Carrier dc
    ON f.CarrierKey = dc.CarrierKey
JOIN Dim_Date d
    ON f.LoadDateKey = d.DateKey
WHERE f.LoadDateKey <> -1      -- Exclude unknown date rows from period aggregates
  AND f.CarrierKey  <> -1      -- Exclude unknown carrier rows
GROUP BY
    f.CarrierKey,
    dc.CarrierID,
    d.CalendarYear,
    d.CalendarMonth,
    d.MonthName,
    d.FiscalYear,
    d.FiscalQuarter,
    d.FiscalPeriod;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Total freight margin must equal sum of row-level margins in fact
-- SELECT SUM(TotalFreightMargin) FROM Calc_FreightSummary;
-- SELECT SUM(FreightMargin) FROM Fact_LoadFreight WHERE LoadDateKey <> -1 AND CarrierKey <> -1;

-- Period coverage check
-- SELECT CalendarYear, CalendarMonth, COUNT(*) AS CarrierCount
-- FROM Calc_FreightSummary GROUP BY CalendarYear, CalendarMonth ORDER BY 1, 2;
