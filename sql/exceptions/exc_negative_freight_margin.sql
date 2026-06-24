-- =============================================================================
-- MODULE:      Exception System
-- SCRIPT:      exc_negative_freight_margin.sql
-- INPUT:       Fact_LoadFreight, Dim_Carrier, Dim_Date
-- OUTPUT:      Exc_NegativeFreightMargin
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     1.0.1 — FreightPaid → FreightCost; UNK-007 resolved (2026-06-24)
-- =============================================================================
-- CHANGE LOG (v1.0.1):
--   - FreightPaid renamed to FreightCost throughout (stg_load_freight v2.0)
--   - UNK-007 resolved: FreightCharged is confirmed load-level total billed
--     to customer. OpenUnknownNote updated accordingly.
-- =============================================================================

CREATE OR REPLACE TABLE Exc_NegativeFreightMargin AS

SELECT
    'NEGATIVE_FREIGHT_MARGIN'                           AS ExceptionType,
    'HIGH'                                              AS Severity,
    'FreightCost exceeds FreightCharged on this load — negative freight margin.' AS ExceptionDescription,

    f.LoadID,
    f.CarrierKey,
    dc.CarrierID,
    f.LoadDateKey,
    d.CalendarYear,
    d.CalendarMonth,

    f.FreightCharged,
    f.FreightCost,
    f.FreightMargin,
    f.FreightMarginPct,

    f.LoadPallets,
    f.LoadUtilizationBand,
    f.OriginWarehouse,

    CASE
        WHEN f.FreightMargin >= -100    THEN 'Low'
        WHEN f.FreightMargin >= -500    THEN 'Medium'
        WHEN f.FreightMargin >= -2000   THEN 'High'
        ELSE                                 'Critical'
    END                                                 AS ImpactBand,

    f.Flag_FreightChargedSuspect,
    'UNK-007 resolved: FreightCharged is load-level total billed to customer.' AS OpenUnknownNote,

    f.SourceSystem,
    f.BatchID,
    CURRENT_TIMESTAMP                                   AS ExceptionLoadedAt

FROM Fact_LoadFreight f
JOIN Dim_Carrier dc ON f.CarrierKey  = dc.CarrierKey
JOIN Dim_Date    d  ON f.LoadDateKey = d.DateKey
WHERE f.Flag_NegativeFreightMargin = 1
  AND f.CarrierKey  <> -1
  AND f.LoadDateKey <> -1;
