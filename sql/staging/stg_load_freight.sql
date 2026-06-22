-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_load_freight.sql
-- INPUT:       Raw_LoadFreight
-- OUTPUT:      Stg_LoadFreight
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per LoadID. Duplicate LoadIDs in source
--       are a data quality issue — flagged, not silently deduplicated.
--   A2: FreightCharged semantics are UNKNOWN (UNK-007). The field is
--       staged as-is. A flag is applied when FreightCharged = 0 or NULL.
--       Downstream logic must apply confirmed semantics before use.
--   A3: LoadDate arrives as a character string; format assumed YYYY-MM-DD.
--   A4: CarrierID is passed through unresolved. Resolution to Dim_Carrier
--       occurs in the dimension build layer.
--   A5: LoadPallets = 0 is flagged as suspect but retained.
--   A6: TargetFullTruckloadPallets threshold = 24 (CANDIDATE — UNK-002).
--       LoadUtilizationBand is derived at staging using this candidate value.
--       Flag_CandidateThreshold = 1 is applied to every row to signal that
--       the band assignment must be re-evaluated once UNK-002 is confirmed.
-- OPEN UNKNOWNS AFFECTING THIS SCRIPT:
--   UNK-002: TargetFullTruckloadPallets — candidate value 24 used.
--   UNK-007: FreightCharged semantics — field passed through uninterpreted.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_LoadFreight AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting and NULL normalization
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Natural key
        CAST(LoadID          AS VARCHAR(50))   AS LoadID,

        -- Carrier dimension FK (unresolved)
        CAST(CarrierID       AS VARCHAR(50))   AS CarrierID,

        -- Dates
        TRY_CAST(LoadDate    AS DATE)          AS LoadDate,
        TRY_CAST(DeliveryDate AS DATE)         AS DeliveryDate,

        -- Freight financials
        TRY_CAST(FreightCharged  AS DECIMAL(18, 4))  AS FreightCharged,
        TRY_CAST(FreightPaid     AS DECIMAL(18, 4))  AS FreightPaid,

        -- Load physical metrics
        TRY_CAST(LoadPallets     AS DECIMAL(10, 2))  AS LoadPallets,
        TRY_CAST(LoadWeight      AS DECIMAL(18, 4))  AS LoadWeight,

        -- Origin/destination
        CAST(OriginWarehouse AS VARCHAR(50))   AS OriginWarehouse,
        CAST(ShipToID        AS VARCHAR(50))   AS ShipToID,

        -- Batch metadata
        COALESCE(
            CAST(SourceSystem AS VARCHAR(100)),
            'ERP_LOADFREIGHT'
        )                                       AS SourceSystem,
        COALESCE(
            CAST(BatchID AS VARCHAR(100)),
            CAST(CURRENT_TIMESTAMP AS VARCHAR(30))
        )                                       AS BatchID,
        CURRENT_TIMESTAMP                       AS StagedAt

    FROM Raw_LoadFreight
),

-- ---------------------------------------------------------------------------
-- STEP 2: Deduplication detection
-- Duplicate = same LoadID appearing more than once.
-- Prefer row with higher FreightCharged (more complete financial data).
-- All duplicates retained and flagged.
-- ---------------------------------------------------------------------------
dedup_flag AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY LoadID
            ORDER BY
                CASE
                    WHEN FreightCharged IS NOT NULL
                     AND FreightPaid IS NOT NULL
                     AND LoadPallets IS NOT NULL
                    THEN 0
                    ELSE 1
                END ASC,
                FreightCharged DESC,
                StagedAt ASC
        ) AS DeduplicationRank,
        COUNT(*) OVER (
            PARTITION BY LoadID
        ) AS DuplicateCount
    FROM raw_cast
),

-- ---------------------------------------------------------------------------
-- STEP 3: Derived measures and row-level data quality flags
-- ---------------------------------------------------------------------------
dq_flags AS (
    SELECT
        d.*,

        -- -----------
        -- DERIVED MEASURES (calculated at staging for downstream use)
        -- -----------

        -- FreightMargin = FreightCharged - FreightPaid
        -- NULL-safe: result is NULL if either input is NULL.
        CASE
            WHEN FreightCharged IS NOT NULL
             AND FreightPaid    IS NOT NULL
            THEN FreightCharged - FreightPaid
            ELSE NULL
        END                                         AS FreightMargin,

        -- FreightMarginPct = FreightMargin / FreightCharged
        -- NULL and divide-by-zero safe.
        CASE
            WHEN FreightCharged IS NOT NULL
             AND FreightPaid    IS NOT NULL
             AND FreightCharged <> 0
            THEN (FreightCharged - FreightPaid) / FreightCharged
            ELSE NULL
        END                                         AS FreightMarginPct,

        -- LoadUtilizationBand — CANDIDATE thresholds (UNK-002)
        -- Full >= 24, Partial >= 18, Underutilized < 18
        CASE
            WHEN LoadPallets IS NULL THEN 'UNKNOWN'
            WHEN LoadPallets >= 24   THEN 'Full'
            WHEN LoadPallets >= 18   THEN 'Partial'
            ELSE                          'Underutilized'
        END                                         AS LoadUtilizationBand,

        -- -----------
        -- DATA QUALITY FLAGS
        -- -----------

        -- DQ FLAG: Duplicate LoadID
        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                    AS Flag_DuplicateLoadID,

        -- DQ FLAG: NULL CarrierID
        CASE WHEN CarrierID IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingCarrierID,

        -- DQ FLAG: NULL LoadDate
        CASE WHEN LoadDate IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingLoadDate,

        -- DQ FLAG: NULL or zero FreightCharged (UNK-007 — semantics unknown)
        CASE
            WHEN FreightCharged IS NULL THEN 1
            WHEN FreightCharged = 0     THEN 1
            ELSE 0
        END                                         AS Flag_FreightChargedSuspect,

        -- DQ FLAG: NULL FreightPaid
        CASE WHEN FreightPaid IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingFreightPaid,

        -- DQ FLAG: NULL or zero LoadPallets
        CASE
            WHEN LoadPallets IS NULL THEN 1
            WHEN LoadPallets = 0     THEN 1
            ELSE 0
        END                                         AS Flag_MissingLoadPallets,

        -- DQ FLAG: Negative FreightMargin
        CASE
            WHEN FreightCharged IS NOT NULL
             AND FreightPaid    IS NOT NULL
             AND (FreightCharged - FreightPaid) < 0
            THEN 1
            ELSE 0
        END                                         AS Flag_NegativeFreightMargin,

        -- DQ FLAG: Underutilized load (candidate threshold — UNK-002)
        CASE
            WHEN LoadPallets IS NOT NULL
             AND LoadPallets < 18
            THEN 1
            ELSE 0
        END                                         AS Flag_UnderutilizedLoad,

        -- DQ FLAG: Candidate threshold applied — re-validate when UNK-002 confirmed
        1                                           AS Flag_CandidateThreshold_UNK002,

        -- COMPOSITE: Row is clean
        CASE
            WHEN LoadID IS NULL         THEN 0
            WHEN CarrierID IS NULL      THEN 0
            WHEN LoadDate IS NULL       THEN 0
            WHEN FreightCharged IS NULL THEN 0
            WHEN FreightPaid IS NULL    THEN 0
            WHEN LoadPallets IS NULL    THEN 0
            WHEN DuplicateCount > 1     THEN 0
            ELSE 1
        END                                         AS IsCleanRow

    FROM dedup_flag d
)

-- ---------------------------------------------------------------------------
-- STEP 4: Final projection — staging output
-- ---------------------------------------------------------------------------
SELECT
    -- Natural key
    LoadID,

    -- Dimension FKs (unresolved)
    CarrierID,
    ShipToID,
    OriginWarehouse,

    -- Dates
    LoadDate,
    DeliveryDate,

    -- Freight financials (raw)
    FreightCharged,
    FreightPaid,

    -- Freight financials (derived at staging)
    FreightMargin,
    FreightMarginPct,

    -- Load metrics
    LoadPallets,
    LoadWeight,
    LoadUtilizationBand,

    -- Deduplication metadata
    DeduplicationRank,
    DuplicateCount,

    -- Data quality flags
    Flag_DuplicateLoadID,
    Flag_MissingCarrierID,
    Flag_MissingLoadDate,
    Flag_FreightChargedSuspect,
    Flag_MissingFreightPaid,
    Flag_MissingLoadPallets,
    Flag_NegativeFreightMargin,
    Flag_UnderutilizedLoad,
    Flag_CandidateThreshold_UNK002,
    IsCleanRow,

    -- Batch metadata
    SourceSystem,
    BatchID,
    StagedAt

FROM dq_flags;

-- =============================================================================
-- POST-LOAD VALIDATION QUERIES
-- =============================================================================

-- Load utilization band distribution (candidate thresholds)
-- SELECT LoadUtilizationBand, COUNT(*) AS LoadCount
-- FROM Stg_LoadFreight
-- GROUP BY LoadUtilizationBand;

-- Freight margin summary
-- SELECT
--     SUM(Flag_NegativeFreightMargin) AS Cnt_NegativeMargin,
--     AVG(FreightMarginPct)           AS Avg_MarginPct,
--     MIN(FreightMargin)              AS Min_FreightMargin,
--     MAX(FreightMargin)              AS Max_FreightMargin
-- FROM Stg_LoadFreight
-- WHERE IsCleanRow = 1;
