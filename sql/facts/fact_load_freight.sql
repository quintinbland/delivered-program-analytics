-- =============================================================================
-- MODULE:      Fact Tables
-- SCRIPT:      fact_load_freight.sql
-- INPUT:       Stg_LoadFreight, Dim_Carrier, Dim_Date
-- OUTPUT:      Fact_LoadFreight
-- DIALECT:     DuckDB (STRFTIME patch applied)
-- VERSION:     1.1.0 — Mode_of_Delivery, Mode_Clean, FreightStatus added (UNK-008 resolved)
-- =============================================================================
-- CHANGE LOG:
--   v1.1.0 (2026-06-24):
--     - Mode_of_Delivery, Mode_Clean, FreightStatus added from Stg_LoadFreight v2.2.0
--     - Flag_UnknownMode added
--     - source filter updated: IsCleanRow = 1 only (removes Flag_FreightChargedSuspect
--       fallback — FOB zero rows are now IsCleanRow = 1 in staging v2.2.0;
--       DLV zero rows remain IsCleanRow = 0 and are not loaded to fact)
--   v1.0.2 (2026-06-24):
--     - FreightPaid → FreightCost
--     - Flag_CandidateThreshold_UNK002 removed
--     - ShipToID join removed
-- =============================================================================

CREATE OR REPLACE TABLE Fact_LoadFreight AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Source from staging — clean rows only, primary record per LoadID
-- v1.1.0: IsCleanRow = 1 is now sufficient — FOB zero rows are clean in v2.2.0.
--         The Flag_FreightChargedSuspect fallback is removed.
-- ---------------------------------------------------------------------------
source AS (
    SELECT *
    FROM Stg_LoadFreight
    WHERE DeduplicationRank = 1
      AND IsCleanRow = 1
),

-- ---------------------------------------------------------------------------
-- STEP 2: Resolve dimension foreign keys
-- ---------------------------------------------------------------------------
resolved AS (
    SELECT
        s.LoadID,

        -- CarrierKey
        COALESCE(dc.CarrierKey, -1)                     AS CarrierKey,

        -- ShipToKey: not available in source; defaults to -1
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

        -- Mode attributes (new in v1.1.0)
        s.Mode_of_Delivery,
        s.Mode_Clean,
        s.FreightStatus,

        -- Measures
        s.FreightCharged,
        s.FreightCost,
        s.FreightMargin,        -- NULL for FOB loads (not applicable)
        s.FreightMarginPct,     -- NULL for FOB loads (not applicable)
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
        s.Flag_UnknownMode,
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
    Mode_of_Delivery,
    Mode_Clean,
    FreightStatus,
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
    Flag_UnknownMode,
    Flag_CarrierNotInDim,
    Flag_ShipToNotInDim,
    IsCleanRow,
    SourceSystem,
    BatchID,
    FactLoadedAt

FROM resolved;
