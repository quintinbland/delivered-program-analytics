-- =============================================================================
-- MODULE:      Calculation Engine
-- SCRIPT:      calc_load_utilization.sql
-- INPUT:       Fact_LoadFreight, Dim_Carrier, Dim_Date
-- OUTPUT:      Calc_LoadUtilization
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Fact_LoadFreight  (Module 3)
--   Dim_Carrier       (Module 2)
--   Dim_Date          (Module 2)
-- =============================================================================
-- BUSINESS RULES IMPLEMENTED:
--
--   RULE: LOAD_UTILIZATION_BAND (CANDIDATE — UNK-002)
--     Inputs:       LoadPallets
--     Conditions:   LoadPallets >= 24                       → Full
--                   LoadPallets >= 18 AND LoadPallets < 24  → Partial
--                   LoadPallets < 18                        → Underutilized
--                   LoadPallets IS NULL                     → UNKNOWN
--     Output:       LoadUtilizationBand
--     Edge Cases:   Threshold 24 is CANDIDATE. All rows carry
--                   Flag_CandidateThreshold_UNK002 = 1.
--
--   RULE: FILL_RATE
--     Inputs:       LoadPallets, TargetPallets (candidate = 24)
--     Condition:    TargetPallets > 0
--     Output:       FillRate = LoadPallets / TargetPallets
--     Edge Cases:   NULL if LoadPallets IS NULL; capped display at 1.0
--                   (overfilled loads report FillRate > 1.0 — retained as-is)
--
--   RULE: UNDERUTILIZATION_RATE
--     Inputs:       LoadCount_Underutilized, TotalLoadCount
--     Condition:    TotalLoadCount > 0
--     Output:       UnderutilizationRate = LoadCount_Underutilized / TotalLoadCount
--     Edge Cases:   NULL if TotalLoadCount = 0
--
-- AGGREGATION GRAIN: CarrierKey + CalendarYear + CalendarMonth
-- CANDIDATE VALUE: TargetFullTruckloadPallets = 24 (UNK-002)
-- =============================================================================

CREATE OR REPLACE TABLE Calc_LoadUtilization AS

WITH

-- Row-level fill rate calculation
load_fill AS (
    SELECT
        f.LoadID,
        f.CarrierKey,
        f.LoadDateKey,
        f.LoadPallets,
        f.LoadUtilizationBand,
        f.Flag_UnderutilizedLoad,
        f.Flag_CandidateThreshold_UNK002,

        -- Fill rate per load (candidate threshold = 24)
        CASE
            WHEN f.LoadPallets IS NULL THEN NULL
            ELSE f.LoadPallets / 24.0       -- CANDIDATE: 24 = UNK-002
        END                                             AS FillRate,

        -- Pallet shortfall from full truckload
        CASE
            WHEN f.LoadPallets IS NULL THEN NULL
            WHEN f.LoadPallets >= 24   THEN 0
            ELSE 24.0 - f.LoadPallets   -- CANDIDATE: 24 = UNK-002
        END                                             AS PalletShortfall

    FROM Fact_LoadFreight f
    WHERE f.LoadDateKey <> -1
      AND f.CarrierKey  <> -1
)

SELECT
    lf.CarrierKey,
    dc.CarrierID,
    d.CalendarYear,
    d.CalendarMonth,
    d.MonthName,
    d.FiscalYear,
    d.FiscalQuarter,
    d.FiscalPeriod,

    -- Load counts by band
    COUNT(lf.LoadID)                                    AS TotalLoadCount,
    SUM(CASE WHEN lf.LoadUtilizationBand = 'Full'          THEN 1 ELSE 0 END) AS LoadCount_Full,
    SUM(CASE WHEN lf.LoadUtilizationBand = 'Partial'       THEN 1 ELSE 0 END) AS LoadCount_Partial,
    SUM(CASE WHEN lf.LoadUtilizationBand = 'Underutilized' THEN 1 ELSE 0 END) AS LoadCount_Underutilized,
    SUM(CASE WHEN lf.LoadUtilizationBand = 'UNKNOWN'       THEN 1 ELSE 0 END) AS LoadCount_UnknownBand,

    -- Pallet totals
    SUM(lf.LoadPallets)                                 AS TotalPallets,
    AVG(lf.LoadPallets)                                 AS AvgPalletsPerLoad,
    SUM(lf.PalletShortfall)                             AS TotalPalletShortfall,

    -- Fill rate summary
    AVG(lf.FillRate)                                    AS AvgFillRate,
    MIN(lf.FillRate)                                    AS MinFillRate,
    MAX(lf.FillRate)                                    AS MaxFillRate,

    -- Underutilization rate
    CASE
        WHEN COUNT(lf.LoadID) = 0 THEN NULL
        ELSE CAST(SUM(CASE WHEN lf.LoadUtilizationBand = 'Underutilized' THEN 1 ELSE 0 END)
                  AS DECIMAL(10,4))
             / COUNT(lf.LoadID)
    END                                                 AS UnderutilizationRate,

    -- Full + Partial combined utilization rate
    CASE
        WHEN COUNT(lf.LoadID) = 0 THEN NULL
        ELSE CAST(SUM(CASE WHEN lf.LoadUtilizationBand IN ('Full','Partial') THEN 1 ELSE 0 END)
                  AS DECIMAL(10,4))
             / COUNT(lf.LoadID)
    END                                                 AS UtilizationRate,

    -- Candidate threshold flag
    MAX(lf.Flag_CandidateThreshold_UNK002)              AS Flag_CandidateThreshold_UNK002,

    -- Candidate threshold value documented inline
    24                                                  AS CandidateTargetPallets_UNK002,

    CURRENT_TIMESTAMP                                   AS CalcLoadedAt

FROM load_fill lf
JOIN Dim_Carrier dc ON lf.CarrierKey = dc.CarrierKey
JOIN Dim_Date    d  ON lf.LoadDateKey = d.DateKey
GROUP BY
    lf.CarrierKey,
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

-- Total load count must match fact table (excluding unknown date/carrier)
-- SELECT SUM(TotalLoadCount) FROM Calc_LoadUtilization;
-- SELECT COUNT(*) FROM Fact_LoadFreight WHERE LoadDateKey <> -1 AND CarrierKey <> -1;

-- Period with highest underutilization
-- SELECT CalendarYear, CalendarMonth, SUM(LoadCount_Underutilized) AS UnderutilizedLoads
-- FROM Calc_LoadUtilization
-- GROUP BY CalendarYear, CalendarMonth
-- ORDER BY UnderutilizedLoads DESC
-- LIMIT 10;
