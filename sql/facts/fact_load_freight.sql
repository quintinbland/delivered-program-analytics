-- =============================================================================
-- MODULE:      Fact Tables
-- SCRIPT:      fact_load_freight.sql
-- INPUT:       Stg_LoadFreight, Dim_Carrier, Dim_Date
-- OUTPUT:      Fact_LoadFreight
-- DIALECT:     DuckDB (STRFTIME patch applied)
-- VERSION:     1.0.2 — Real data column fixes (2026-06-24)
-- =============================================================================
-- CHANGE LOG (v1.0.2):
--   - FreightPaid → FreightCost (renamed in stg_load_freight v2.0)
--   - Flag_CandidateThreshold_UNK002 removed (UNK-002 resolved: 24 pallets)
--   - ShipToID join removed from Dim_ShipTo lookup (no ShipToID in staging v2.0)
--     ShipToKey defaults to -1 for all rows — expected behavior with real data
-- =============================================================================

CREATE OR REPLACE TABLE Fact_LoadFreight AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Source from staging — primary record per LoadID
-- ---------------------------------------------------------------------------
source AS (
    SELECT *
    FROM Stg_LoadFreight
    WHERE DeduplicationRank = 1
      AND (
          IsCleanRow = 1
          OR Flag_FreightChargedSuspect = 1
      )
),

-- ---------------------------------------------------------------------------
-- STEP 2: Resolve dimension foreign keys
-- ---------------------------------------------------------------------------
resolved AS (
    SELECT
        s.LoadID,

        -- CarrierKey
        COALESCE(dc.CarrierKey, -1)                     AS CarrierKey,

        -- ShipToKey: no ShipToID in staging v2.0; defaults to -1
        -1                                              AS ShipToKey,

        -- LoadDateKey (YYYYMMDD integer)
        CASE
            WHEN s.LoadDate IS NOT NULL
            THEN CAST(STRFTIME(s.LoadDate, '%Y%m%d') AS INTEGER)
            ELSE -1
        END                                             AS LoadDateKey,

        -- DeliveryDateKey
        CASE
            WHEN s.DeliveryDate IS NOT NULL
            THEN CAST(STRFTIME(s.DeliveryDate, '%Y%m%d') AS INTEGER)
            ELSE -1
        END                                             AS DeliveryDateKey,

        -- Measures
        s.FreightCharged,
        s.FreightCost,          -- renamed from FreightPaid in v2.0
        s.FreightMargin,
        s.FreightMarginPct,
        s.LoadPallets,
        s.LoadWeight,
        s.LoadUtilizationBand,

        -- Operational attributes
        s.OriginWarehouse,

        -- DQ flags
        s.Flag_FreightChargedSuspect,
        s.Flag_NegativeFreightMargin,
        s.Flag_UnderutilizedLoad,
        s.Flag_OverfilledLoad,
        s.IsCleanRow,

        -- FK resolution flags
        CASE WHEN dc.CarrierKey IS NULL THEN 1 ELSE 0 END   AS Flag_CarrierNotInDim,
        0                                                   AS Flag_ShipToNotInDim,

        -- Batch metadata
        s.SourceSystem,
        s.BatchID,
        CURRENT_TIMESTAMP                               AS FactLoadedAt

    FROM source s

    LEFT JOIN Dim_Carrier dc
        ON s.CarrierID = dc.CarrierID
       AND dc.CarrierKey <> -1
)

-- ---------------------------------------------------------------------------
-- STEP 3: Final projection
-- ---------------------------------------------------------------------------
SELECT
    LoadID,
    CarrierKey,
    ShipToKey,
    LoadDateKey,
    DeliveryDateKey,
    FreightCharged,
    FreightCost,
    FreightMargin,
    FreightMarginPct,
    LoadPallets,
    LoadWeight,
    LoadUtilizationBand,
    OriginWarehouse,
    Flag_FreightChargedSuspect,
    Flag_NegativeFreightMargin,
    Flag_UnderutilizedLoad,
    Flag_OverfilledLoad,
    Flag_CarrierNotInDim,
    Flag_ShipToNotInDim,
    IsCleanRow,
    SourceSystem,
    BatchID,
    FactLoadedAt

FROM resolved;
