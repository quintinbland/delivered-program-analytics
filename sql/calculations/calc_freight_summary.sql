-- =============================================================================
-- MODULE:      Calculation Engine
-- SCRIPT:      calc_freight_summary.sql
-- INPUT:       Fact_LoadFreight, Dim_Carrier, Dim_Date
-- OUTPUT:      Calc_FreightSummary
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     1.0.1 — FreightPaid → FreightCost; removed Flag_CandidateThreshold_UNK002 (2026-06-24)
-- =============================================================================

CREATE OR REPLACE TABLE Calc_FreightSummary AS

SELECT
    f.CarrierKey,
    dc.CarrierID,
    d.CalendarYear,
    d.CalendarMonth,
    d.MonthName,
    d.FiscalYear,
    d.FiscalQuarter,
    d.FiscalPeriod,

    COUNT(DISTINCT f.LoadID)                            AS LoadCount,
    SUM(f.LoadPallets)                                  AS TotalPallets,
    AVG(f.LoadPallets)                                  AS AvgPalletsPerLoad,
    SUM(f.LoadWeight)                                   AS TotalWeight,

    SUM(CASE WHEN f.LoadUtilizationBand = 'Full'          THEN 1 ELSE 0 END) AS LoadCount_Full,
    SUM(CASE WHEN f.LoadUtilizationBand = 'Partial'       THEN 1 ELSE 0 END) AS LoadCount_Partial,
    SUM(CASE WHEN f.LoadUtilizationBand = 'Underutilized' THEN 1 ELSE 0 END) AS LoadCount_Underutilized,
    SUM(CASE WHEN f.LoadUtilizationBand = 'UNKNOWN'       THEN 1 ELSE 0 END) AS LoadCount_Unknown,

    CASE
        WHEN COUNT(DISTINCT f.LoadID) = 0 THEN NULL
        ELSE CAST(
            SUM(CASE WHEN f.LoadUtilizationBand IN ('Full','Partial') THEN 1 ELSE 0 END)
            AS DECIMAL(10,4))
            / COUNT(DISTINCT f.LoadID)
    END                                                 AS LoadUtilizationRate,

    SUM(f.FreightCharged)                               AS TotalFreightCharged,
    SUM(f.FreightCost)                                  AS TotalFreightCost,
    SUM(f.FreightMargin)                                AS TotalFreightMargin,

    CASE
        WHEN SUM(f.FreightCharged) IS NULL
          OR SUM(f.FreightCharged) = 0 THEN NULL
        ELSE SUM(f.FreightMargin) / SUM(f.FreightCharged)
    END                                                 AS FreightMarginPct,

    SUM(f.Flag_NegativeFreightMargin)                   AS Count_NegativeMarginLoads,
    SUM(f.Flag_UnderutilizedLoad)                       AS Count_UnderutilizedLoads,
    SUM(f.Flag_FreightChargedSuspect)                   AS Count_FreightChargedSuspect,

    -- Confirmed target pallets (UNK-002 resolved)
    24                                                  AS TargetPallets,

    CURRENT_TIMESTAMP                                   AS CalcLoadedAt

FROM Fact_LoadFreight f
JOIN Dim_Carrier dc ON f.CarrierKey  = dc.CarrierKey
JOIN Dim_Date    d  ON f.LoadDateKey = d.DateKey
WHERE f.LoadDateKey <> -1
  AND f.CarrierKey  <> -1
GROUP BY
    f.CarrierKey,
    dc.CarrierID,
    d.CalendarYear,
    d.CalendarMonth,
    d.MonthName,
    d.FiscalYear,
    d.FiscalQuarter,
    d.FiscalPeriod;
