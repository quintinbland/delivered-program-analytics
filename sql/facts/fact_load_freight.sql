-- =============================================================================
-- MODULE:      Fact Tables
-- SCRIPT:      fact_load_freight.sql
-- INPUT:       Stg_LoadFreight, Dim_Carrier, Dim_ShipTo, Dim_Date
-- OUTPUT:      Fact_LoadFreight
-- DIALECT:     DuckDB (patched from Snowflake original — STRFTIME applied)
-- PATCHED:      TO_CHAR date key expressions replaced with STRFTIME
-- VERSION:      1.0.1
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Stg_LoadFreight     (Module 1)
--   Dim_Carrier         (Module 2)
--   Dim_ShipTo          (Module 2)
--   Dim_Date            (Module 2)
-- BUILD ORDER:  1 of 3 — no dependency on other fact tables
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Grain is one row per LoadID. Duplicate LoadIDs in staging use
--       DeduplicationRank = 1 (set in staging layer).
--   A2: Only rows with IsCleanRow = 1 in staging are promoted to the fact
--       table. Dirty rows are routed to the exception layer (Module 5).
--       Exception: rows with Flag_FreightChargedSuspect = 1 are included
--       but carry a fact-level flag. They are not clean but are operationally
--       necessary for load coverage reporting.
--   A3: FreightMargin and FreightMarginPct are inherited from staging.
--       They are not recalculated here. If staging values are NULL, the
--       fact columns are NULL.
--   A4: LoadUtilizationBand is inherited from staging (candidate thresholds
--       per UNK-002). Flag_CandidateThreshold is carried forward.
--   A5: DateKey is derived from LoadDate using the YYYYMMDD integer format
--       matching Dim_Date.DateKey. NULL LoadDate resolves to DateKey = -1.
--   A6: Unresolvable FK values (CarrierID, ShipToID not in dimension) resolve
--       to surrogate key = -1. No row is dropped for a missing dimension member.
-- OPEN UNKNOWNS:
--   UNK-002: LoadUtilizationBand candidate thresholds carried from staging.
--   UNK-007: FreightCharged semantics unconfirmed; field included as-is.
-- =============================================================================

CREATE OR REPLACE TABLE Fact_LoadFreight AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Source from staging — primary record per LoadID
-- Include clean rows + FreightChargedSuspect rows (operationally required)
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
-- All unresolvable values default to -1 (unknown member)
-- ---------------------------------------------------------------------------
resolved AS (
    SELECT
        s.LoadID,

        -- CarrierKey
        COALESCE(dc.CarrierKey, -1)                     AS CarrierKey,

        -- ShipToKey
        COALESCE(dst.ShipToKey, -1)                     AS ShipToKey,

        -- LoadDateKey (YYYYMMDD integer)
        -- [DIALECT: DUCKDB] STRFTIME(date, '%Y%m%d') used in place of TO_CHAR
        
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

        -- Measures (pass-through from staging)
        s.FreightCharged,
        s.FreightPaid,
        s.FreightMargin,
        s.FreightMarginPct,
        s.LoadPallets,
        s.LoadWeight,
        s.LoadUtilizationBand,

        -- Operational attributes
        s.OriginWarehouse,

        -- DQ / candidate flags carried forward from staging
        s.Flag_FreightChargedSuspect,
        s.Flag_NegativeFreightMargin,
        s.Flag_UnderutilizedLoad,
        s.Flag_CandidateThreshold_UNK002,
        s.IsCleanRow,

        -- FK resolution flags
        CASE WHEN dc.CarrierKey IS NULL THEN 1 ELSE 0 END   AS Flag_CarrierNotInDim,
        CASE WHEN dst.ShipToKey IS NULL THEN 1 ELSE 0 END   AS Flag_ShipToNotInDim,

        -- Batch metadata
        s.SourceSystem,
        s.BatchID,
        CURRENT_TIMESTAMP                               AS FactLoadedAt

    FROM source s

    LEFT JOIN Dim_Carrier dc
        ON s.CarrierID = dc.CarrierID
       AND dc.CarrierKey <> -1

    LEFT JOIN Dim_ShipTo dst
        ON s.ShipToID = dst.ShipToID
       AND dst.ShipToKey <> -1
)

-- ---------------------------------------------------------------------------
-- STEP 3: Final projection
-- ---------------------------------------------------------------------------
SELECT
    -- Natural key (retained for auditability)
    LoadID,

    -- Dimension keys
    CarrierKey,
    ShipToKey,
    LoadDateKey,
    DeliveryDateKey,

    -- Measures
    FreightCharged,
    FreightPaid,
    FreightMargin,
    FreightMarginPct,
    LoadPallets,
    LoadWeight,

    -- Derived classification
    LoadUtilizationBand,

    -- Operational
    OriginWarehouse,

    -- Fact-level flags
    Flag_FreightChargedSuspect,
    Flag_NegativeFreightMargin,
    Flag_UnderutilizedLoad,
    Flag_CandidateThreshold_UNK002,
    Flag_CarrierNotInDim,
    Flag_ShipToNotInDim,
    IsCleanRow,

    -- Lineage
    SourceSystem,
    BatchID,
    FactLoadedAt

FROM resolved;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Row count vs staging (clean rows)
-- SELECT COUNT(*) FROM Fact_LoadFreight;
-- SELECT COUNT(*) FROM Stg_LoadFreight WHERE DeduplicationRank = 1 AND IsCleanRow = 1;

-- Unresolved dimension keys
-- SELECT
--     SUM(Flag_CarrierNotInDim)   AS Unresolved_Carrier,
--     SUM(Flag_ShipToNotInDim)    AS Unresolved_ShipTo
-- FROM Fact_LoadFreight;

-- Negative margin loads
-- SELECT LoadID, FreightCharged, FreightPaid, FreightMargin
-- FROM Fact_LoadFreight
-- WHERE Flag_NegativeFreightMargin = 1;
