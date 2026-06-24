-- =============================================================================
-- MODULE:      Calculation Engine
-- SCRIPT:      calc_load_utilization.sql
-- INPUT:       Fact_LoadFreight, Dim_Carrier, Dim_Date
-- OUTPUT:      Calc_LoadUtilization
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     1.0.1 — Removed Flag_CandidateThreshold_UNK002 (2026-06-24)
-- =============================================================================
-- CHANGE LOG (v1.0.1):
--   - Removed f.Flag_CandidateThreshold_UNK002 (column removed from
--     Fact_LoadFreight v1.0.2; UNK-002 resolved: MaxPalletCapacity = 24)
--   - Renamed CandidateTargetPallets_UNK002 → TargetPallets (confirmed value)
-- =============================================================================

CREATE OR REPLACE TABLE Calc_LoadUtilization AS

WITH

load_fill AS (
    SELECT
        f.LoadID,
        f.CarrierKey,
        f.LoadDateKey,
        f.LoadPallets,
        f.LoadUtilizationBand,
        f.Flag_UnderutilizedLoad,

        -- Fill rate per load (confirmed threshold = 24)
        CASE
            WHEN f.LoadPallets IS NULL THEN NULL
            ELSE f.LoadPallets / 24.0
        END                                             AS FillRate,

        -- Pallet shortfall from full truckload
        CASE
            WHEN f.LoadPallets IS NULL THEN NULL
            WHEN f.LoadPallets >= 24   THEN 0
            ELSE 24.0 - f.LoadPallets
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

    -- Confirmed target (UNK-002 resolved)
    24                                                  AS TargetPallets,

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
