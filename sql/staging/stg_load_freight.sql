-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_load_freight.sql
-- INPUT:       Raw_LoadFreight
-- OUTPUT:      Stg_LoadFreight
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     2.0.0 — Real data mapping applied (2026-06-23)
-- =============================================================================
-- CHANGE LOG (v2.0.0):
--   - Mapped all columns to confirmed real source columns from Copilot mapping
--   - LoadID             ← Order_Level_Query.loadId
--   - CarrierID          ← Order_Level_Query.carrierName
--   - LoadDate           ← Order_Level_Query.shipDate
--   - LoadPallets        ← Order_Level_Query.loadPallets
--   - FreightCost        ← Order_Level_Query.loadShippingCost (internal cost)
--   - FreightCharged     ← Order_Level_Query.loadShippingCharged (billed to customer)
--                          MOVED HERE from stg_sales_order_line (load-level total)
--   - MaxPalletCapacity  ← hardcoded 24 (confirmed default; no source column)
--   - ShipToID           ← removed (not available at load level in real source)
-- RESOLVED UNKNOWNS:
--   - UNK-007: FreightCharged confirmed as load-level total dollar amount billed
--              to customer. Per-case rate is NOT the correct interpretation.
--              FreightCharged now lives exclusively at load grain.
--   - UNK-002: MaxPalletCapacity = 24 confirmed as standard truck default.
--              Flag_CandidateThreshold_UNK002 REMOVED — threshold now confirmed.
-- REMAINING OPEN:
--   - DeliveryDate: not available in Order_Level_Query; defaulted NULL
--   - LoadWeight: not available in real source; defaulted NULL
--   - OriginWarehouse: Order_Level_Query.warehouse confirmed as source;
--                      included pending DivisionID confirmation
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per LoadID. Duplicate LoadIDs in source
--       are a data quality issue — flagged, not silently deduplicated.
--   A2: FreightCharged = Order_Level_Query.loadShippingCharged.
--       This is the total dollar amount billed to the customer for the load.
--       It is NOT a per-case rate. FreightMargin = FreightCharged - FreightCost.
--   A3: FreightCost = Order_Level_Query.loadShippingCost.
--       This is the internal cost paid to the carrier.
--   A4: MaxPalletCapacity = 24 (confirmed standard truck default).
--       LoadUtilizationPct = LoadPallets / 24.
--       LoadUtilizationBand derived from this ratio.
--   A5: CarrierID populated from carrierName (string identifier, not integer key).
--       Dim_Carrier resolution uses carrierName as the natural key.
--   A6: LoadDate = Order_Level_Query.shipDate (same as DeliveryDate on line level).
-- =============================================================================

CREATE OR REPLACE TABLE Stg_LoadFreight AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting and NULL normalization
-- Source: Raw_LoadFreight (Order Level Query)
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Natural key
        CAST(loadId         AS VARCHAR(50))     AS LoadID,

        -- Carrier (carrierName is the natural key for Dim_Carrier)
        CAST(carrierName    AS VARCHAR(200))    AS CarrierID,

        -- Origin warehouse (used for DivisionID derivation if confirmed)
        CAST(warehouse      AS VARCHAR(50))     AS OriginWarehouse,

        -- Dates
        TRY_CAST(shipDate   AS DATE)            AS LoadDate,
        -- DeliveryDate not available in Order Level Query source
        CAST(NULL AS DATE)                      AS DeliveryDate,

        -- Freight financials
        -- FreightCharged: total amount billed to customer for this load (UNK-007 RESOLVED)
        TRY_CAST(loadShippingCharged AS DECIMAL(18, 4)) AS FreightCharged,
        -- FreightCost: internal cost paid to carrier
        TRY_CAST(loadShippingCost    AS DECIMAL(18, 4)) AS FreightCost,

        -- Load physical metrics
        TRY_CAST(loadPallets AS DECIMAL(10, 2)) AS LoadPallets,
        -- LoadWeight not available in real source
        CAST(NULL AS DECIMAL(18, 4))            AS LoadWeight,

        -- MaxPalletCapacity: confirmed default 24 (no source column)
        CAST(24 AS DECIMAL(10, 2))              AS MaxPalletCapacity,

        -- ShipToID not available at load level; will resolve via line-level join
        CAST(NULL AS VARCHAR(50))               AS ShipToID,

        -- Batch metadata
        COALESCE(
            CAST(SourceSystem AS VARCHAR(100)),
            'ORDER_LEVEL_QUERY'
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
-- ---------------------------------------------------------------------------
dedup_flag AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY LoadID
            ORDER BY
                CASE
                    WHEN FreightCharged IS NOT NULL
                     AND FreightCost    IS NOT NULL
                     AND LoadPallets    IS NOT NULL
                    THEN 0
                    ELSE 1
                END ASC,
                FreightCharged DESC NULLS LAST,
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
        -- DERIVED MEASURES
        -- -----------

        -- FreightMargin = FreightCharged - FreightCost
        -- FreightCharged: billed to customer | FreightCost: paid to carrier
        CASE
            WHEN FreightCharged IS NOT NULL
             AND FreightCost    IS NOT NULL
            THEN FreightCharged - FreightCost
            ELSE NULL
        END                                     AS FreightMargin,

        -- FreightMarginPct = FreightMargin / FreightCharged
        CASE
            WHEN FreightCharged IS NOT NULL
             AND FreightCost    IS NOT NULL
             AND FreightCharged <> 0
            THEN (FreightCharged - FreightCost) / FreightCharged
            ELSE NULL
        END                                     AS FreightMarginPct,

        -- LoadUtilizationPct = LoadPallets / MaxPalletCapacity (confirmed: 24)
        CASE
            WHEN LoadPallets IS NOT NULL
             AND MaxPalletCapacity > 0
            THEN LoadPallets / MaxPalletCapacity
            ELSE NULL
        END                                     AS LoadUtilizationPct,

        -- LoadUtilizationBand — thresholds confirmed (MaxPalletCapacity = 24)
        -- Full    >= 22 pallets (>= 92% utilization)
        -- Partial >= 18 pallets (>= 75% utilization)
        -- Underutilized < 18 pallets
        CASE
            WHEN LoadPallets IS NULL THEN 'UNKNOWN'
            WHEN LoadPallets >= 22   THEN 'Full'
            WHEN LoadPallets >= 18   THEN 'Partial'
            ELSE                          'Underutilized'
        END                                     AS LoadUtilizationBand,

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

        -- DQ FLAG: NULL or zero FreightCharged
        -- UNK-007 RESOLVED: zero FreightCharged is now a confirmed data issue
        CASE
            WHEN FreightCharged IS NULL THEN 1
            WHEN FreightCharged = 0     THEN 1
            ELSE 0
        END                                     AS Flag_FreightChargedSuspect,

        -- DQ FLAG: NULL FreightCost (was FreightPaid in v1.0)
        CASE WHEN FreightCost IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingFreightCost,

        -- DQ FLAG: NULL or zero LoadPallets
        CASE
            WHEN LoadPallets IS NULL THEN 1
            WHEN LoadPallets = 0     THEN 1
            ELSE 0
        END                                     AS Flag_MissingLoadPallets,

        -- DQ FLAG: LoadPallets exceeds MaxPalletCapacity (overfilled load)
        CASE
            WHEN LoadPallets IS NOT NULL
             AND LoadPallets > 24
            THEN 1
            ELSE 0
        END                                     AS Flag_OverfilledLoad,

        -- DQ FLAG: Negative FreightMargin
        CASE
            WHEN FreightCharged IS NOT NULL
             AND FreightCost    IS NOT NULL
             AND (FreightCharged - FreightCost) < 0
            THEN 1
            ELSE 0
        END                                     AS Flag_NegativeFreightMargin,

        -- DQ FLAG: Underutilized load (< 18 pallets)
        CASE
            WHEN LoadPallets IS NOT NULL
             AND LoadPallets < 18
            THEN 1
            ELSE 0
        END                                     AS Flag_UnderutilizedLoad,

        -- COMPOSITE: Row is clean
        CASE
            WHEN LoadID         IS NULL THEN 0
            WHEN CarrierID      IS NULL THEN 0
            WHEN LoadDate       IS NULL THEN 0
            WHEN FreightCharged IS NULL THEN 0
            WHEN FreightCost    IS NULL THEN 0
            WHEN LoadPallets    IS NULL THEN 0
            WHEN DuplicateCount > 1     THEN 0
            ELSE 1
        END                                     AS IsCleanRow

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
    FreightCost,

    -- Freight financials (derived at staging)
    FreightMargin,
    FreightMarginPct,

    -- Load metrics (raw)
    LoadPallets,
    LoadWeight,
    MaxPalletCapacity,

    -- Load metrics (derived)
    LoadUtilizationPct,
    LoadUtilizationBand,

    -- Deduplication metadata
    DeduplicationRank,
    DuplicateCount,

    -- Data quality flags
    Flag_DuplicateLoadID,
    Flag_MissingCarrierID,
    Flag_MissingLoadDate,
    Flag_FreightChargedSuspect,
    Flag_MissingFreightCost,
    Flag_MissingLoadPallets,
    Flag_OverfilledLoad,
    Flag_NegativeFreightMargin,
    Flag_UnderutilizedLoad,
    IsCleanRow,

    -- Batch metadata
    SourceSystem,
    BatchID,
    StagedAt

FROM dq_flags;

-- =============================================================================
-- POST-LOAD VALIDATION QUERIES
-- =============================================================================

-- Load utilization band distribution
-- SELECT LoadUtilizationBand, COUNT(*) AS LoadCount, AVG(LoadUtilizationPct) AS AvgUtil
-- FROM Stg_LoadFreight GROUP BY LoadUtilizationBand;

-- Freight margin summary
-- SELECT
--     SUM(Flag_NegativeFreightMargin) AS Cnt_NegativeMargin,
--     SUM(Flag_OverfilledLoad)        AS Cnt_OverfilledLoads,
--     AVG(FreightMarginPct)           AS Avg_MarginPct,
--     SUM(FreightCharged)             AS Total_FreightCharged,
--     SUM(FreightCost)                AS Total_FreightCost,
--     SUM(FreightMargin)              AS Total_FreightMargin
-- FROM Stg_LoadFreight WHERE IsCleanRow = 1;

-- Overfilled loads (exception candidates)
-- SELECT LoadID, CarrierID, LoadPallets, MaxPalletCapacity
-- FROM Stg_LoadFreight WHERE Flag_OverfilledLoad = 1;
