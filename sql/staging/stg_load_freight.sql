-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_load_freight.sql
-- INPUT:       Raw_LoadFreight, Raw_SalesOrderLine
-- OUTPUT:      Stg_LoadFreight
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     2.2.0 — Mode_of_Delivery derived from Raw_SalesOrderLine (UNK-008 RESOLVED)
-- =============================================================================
-- CHANGE LOG:
--   v2.2.0 (2026-06-24):
--     - Mode derived from Raw_SalesOrderLine via load-level aggregation.
--       Source column: Mode_of_Delivery (VARCHAR). Raw values: 'DLV', 'PUP'.
--     - Priority rule: if ANY line on load = 'DLV' → Mode = 'DLV'.
--                      else if ANY line = 'PUP' → Mode = 'PUP'.
--                      else → NULL (unknown).
--     - Mode_Clean added: 'DLV'→'Delivered', 'PUP'→'FOB', NULL→'Unknown'.
--     - FreightStatus added: classifies each load per freight/mode combination.
--     - Flag_FreightChargedSuspect: mode-conditional. FOB zero = valid; DLV zero = suspect.
--     - IsCleanRow: DLV loads with zero/null FreightCharged excluded.
--                   FOB loads with zero FreightCharged included.
--     - FreightMargin/FreightMarginPct: NULL for FOB loads (not applicable).
--     - Raw_SalesOrderLine added as second input — no re-export of CSV required.
--     - UNK-008 RESOLVED.
--   v2.1.0 (2026-06-24):
--     - Interim: zero still flagged; IsCleanRow relaxed (never deployed).
--   v2.0.0 (2026-06-23):
--     - Real data column mapping applied.
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain of Raw_LoadFreight is one row per LoadID.
--   A2: Mode_of_Delivery exists in Raw_SalesOrderLine with values 'DLV' and 'PUP'.
--       If the column is absent from the source extract, the pipeline will fail
--       at raw_cast and must be resolved by re-exporting fact_base.csv with
--       Mode_of_Delivery included.
--   A3: DLV = Delivered (Bonipak arranges freight; freight charge is expected).
--       PUP = FOB / Pickup (customer arranges freight; zero charge is valid).
--   A4: Conflict resolution: DLV takes priority over PUP at the load level.
--       A load with any DLV line is treated as Delivered for freight purposes.
--   A5: FreightCharged = loadShippingCharged (load-level total billed to customer).
--   A6: FreightCost = loadShippingCost (internal cost paid to carrier).
--   A7: MaxPalletCapacity = 24 (confirmed standard truck default, UNK-002 resolved).
--   A8: FreightMargin is NULL for FOB loads — customer-arranged freight; margin
--       is not measurable from this dataset.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_LoadFreight AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Derive Mode at load level from Raw_SalesOrderLine
-- Replicates Power Query Mode_Map logic exactly.
-- Priority: DLV > PUP > NULL
-- ---------------------------------------------------------------------------
mode_map AS (
    SELECT
        CAST(loadId AS VARCHAR(50)) AS LoadID,

        -- DLV takes priority over PUP (any DLV line → whole load is Delivered)
        CASE
            WHEN MAX(CASE WHEN UPPER(TRIM(Mode_of_Delivery)) = 'DLV' THEN 1 ELSE 0 END) = 1
                THEN 'DLV'
            WHEN MAX(CASE WHEN UPPER(TRIM(Mode_of_Delivery)) = 'PUP' THEN 1 ELSE 0 END) = 1
                THEN 'PUP'
            ELSE NULL
        END AS Mode_of_Delivery

    FROM Raw_SalesOrderLine
    WHERE loadId IS NOT NULL
    GROUP BY loadId
),

-- ---------------------------------------------------------------------------
-- STEP 2: Raw ingest of Raw_LoadFreight with type casting
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        CAST(lf.loadId          AS VARCHAR(50))     AS LoadID,
        CAST(lf.carrierName     AS VARCHAR(200))    AS CarrierID,
        CAST(lf.warehouse       AS VARCHAR(50))     AS OriginWarehouse,
        TRY_CAST(lf.shipDate    AS DATE)            AS LoadDate,
        CAST(NULL AS DATE)                          AS DeliveryDate,
        TRY_CAST(lf.loadShippingCharged AS DECIMAL(18, 4)) AS FreightCharged,
        TRY_CAST(lf.loadShippingCost    AS DECIMAL(18, 4)) AS FreightCost,
        TRY_CAST(lf.loadPallets AS DECIMAL(10, 2)) AS LoadPallets,
        CAST(NULL AS DECIMAL(18, 4))                AS LoadWeight,
        CAST(24 AS DECIMAL(10, 2))                  AS MaxPalletCapacity,
        CAST(NULL AS VARCHAR(50))                   AS ShipToID,

        -- Mode joined from mode_map
        mm.Mode_of_Delivery,

        COALESCE(
            CAST(lf.SourceSystem AS VARCHAR(100)),
            'ORDER_LEVEL_QUERY'
        )                                           AS SourceSystem,
        COALESCE(
            CAST(lf.BatchID AS VARCHAR(100)),
            CAST(CURRENT_TIMESTAMP AS VARCHAR(30))
        )                                           AS BatchID,
        CURRENT_TIMESTAMP                           AS StagedAt

    FROM Raw_LoadFreight lf
    LEFT JOIN mode_map mm
        ON CAST(lf.loadId AS VARCHAR(50)) = mm.LoadID
),

-- ---------------------------------------------------------------------------
-- STEP 3: Deduplication detection
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
-- STEP 4: Derived measures and data quality flags
-- ---------------------------------------------------------------------------
dq_flags AS (
    SELECT
        d.*,

        -- Mode_Clean: display label (mirrors Power Query AddModeClean step)
        CASE
            WHEN Mode_of_Delivery = 'DLV' THEN 'Delivered'
            WHEN Mode_of_Delivery = 'PUP' THEN 'FOB'
            WHEN Mode_of_Delivery IS NULL  THEN 'Unknown'
            ELSE 'Other'
        END                                         AS Mode_Clean,

        -- FreightStatus: full classification (mirrors Power Query AddFreightStatus step)
        CASE
            WHEN FreightCharged IS NULL
                                         THEN 'Missing (Null)'
            WHEN Mode_of_Delivery = 'PUP'
             AND FreightCharged = 0      THEN 'Valid Zero (FOB)'
            WHEN Mode_of_Delivery = 'PUP'
             AND FreightCharged > 0      THEN 'FOB with Freight (Review)'
            WHEN Mode_of_Delivery = 'DLV'
             AND FreightCharged = 0      THEN 'Missing Freight (DLV)'
            WHEN Mode_of_Delivery = 'DLV'
             AND FreightCharged > 0      THEN 'Freight Charged (DLV)'
            ELSE 'Review'
        END                                         AS FreightStatus,

        -- FreightMargin: only applicable for Delivered loads with actual freight
        -- FOB: NULL — customer-arranged freight; margin not measurable here
        CASE
            WHEN Mode_of_Delivery = 'PUP'           THEN NULL
            WHEN FreightCharged IS NOT NULL
             AND FreightCost    IS NOT NULL
             AND FreightCharged > 0
            THEN FreightCharged - FreightCost
            ELSE NULL
        END                                         AS FreightMargin,

        -- FreightMarginPct
        CASE
            WHEN Mode_of_Delivery = 'PUP'           THEN NULL
            WHEN FreightCharged IS NOT NULL
             AND FreightCost    IS NOT NULL
             AND FreightCharged > 0
            THEN (FreightCharged - FreightCost) / FreightCharged
            ELSE NULL
        END                                         AS FreightMarginPct,

        -- LoadUtilizationPct
        CASE
            WHEN LoadPallets IS NOT NULL
             AND MaxPalletCapacity > 0
            THEN LoadPallets / MaxPalletCapacity
            ELSE NULL
        END                                         AS LoadUtilizationPct,

        -- LoadUtilizationBand
        CASE
            WHEN LoadPallets IS NULL THEN 'UNKNOWN'
            WHEN LoadPallets >= 22   THEN 'Full'
            WHEN LoadPallets >= 18   THEN 'Partial'
            ELSE                          'Underutilized'
        END                                         AS LoadUtilizationBand,

        -- -------
        -- DQ FLAGS
        -- -------

        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                    AS Flag_DuplicateLoadID,

        CASE WHEN CarrierID IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingCarrierID,

        CASE WHEN LoadDate IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingLoadDate,

        -- Mode-conditional freight flag (UNK-008 resolved)
        -- FOB (PUP): zero is valid — no flag
        -- Delivered (DLV): zero or null is a data gap — flag
        -- Unknown mode: zero flagged (cannot confirm validity)
        CASE
            WHEN FreightCharged IS NULL
             AND Mode_of_Delivery = 'PUP'           THEN 0  -- unusual but not blocking
            WHEN FreightCharged IS NULL              THEN 1
            WHEN Mode_of_Delivery = 'PUP'           THEN 0  -- zero is valid for FOB
            WHEN Mode_of_Delivery = 'DLV'
             AND FreightCharged = 0                  THEN 1
            WHEN FreightCharged = 0                  THEN 1  -- unknown mode: flag
            ELSE 0
        END                                         AS Flag_FreightChargedSuspect,

        CASE WHEN FreightCost IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingFreightCost,

        CASE WHEN Mode_of_Delivery IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_UnknownMode,

        CASE
            WHEN LoadPallets IS NULL THEN 1
            WHEN LoadPallets = 0     THEN 1
            ELSE 0
        END                                         AS Flag_MissingLoadPallets,

        CASE
            WHEN LoadPallets IS NOT NULL
             AND LoadPallets > 24                    THEN 1
            ELSE 0
        END                                         AS Flag_OverfilledLoad,

        -- Negative margin: only evaluated for Delivered loads
        CASE
            WHEN Mode_of_Delivery = 'PUP'           THEN 0  -- not applicable
            WHEN FreightCharged IS NOT NULL
             AND FreightCost    IS NOT NULL
             AND FreightCharged > 0
             AND (FreightCharged - FreightCost) < 0  THEN 1
            ELSE 0
        END                                         AS Flag_NegativeFreightMargin,

        CASE
            WHEN LoadPallets IS NOT NULL
             AND LoadPallets < 18                    THEN 1
            ELSE 0
        END                                         AS Flag_UnderutilizedLoad,

        -- IsCleanRow: mirrors Power Query Freight_IsCleanRow logic
        -- DLV + zero/null FreightCharged = 0 (not clean)
        -- PUP + zero FreightCharged = 1 (clean — valid operational condition)
        -- Unknown mode + zero FreightCharged = 0 (cannot confirm)
        CASE
            WHEN LoadID         IS NULL              THEN 0
            WHEN CarrierID      IS NULL              THEN 0
            WHEN LoadDate       IS NULL              THEN 0
            WHEN FreightCost    IS NULL              THEN 0
            WHEN LoadPallets    IS NULL              THEN 0
            WHEN DuplicateCount > 1                  THEN 0
            WHEN Mode_of_Delivery = 'DLV'
             AND (FreightCharged IS NULL
               OR FreightCharged = 0)                THEN 0
            WHEN Mode_of_Delivery IS NULL
             AND (FreightCharged IS NULL
               OR FreightCharged = 0)                THEN 0
            ELSE 1
        END                                         AS IsCleanRow

    FROM dedup_flag d
)

-- ---------------------------------------------------------------------------
-- STEP 5: Final projection
-- ---------------------------------------------------------------------------
SELECT
    -- Natural key
    LoadID,

    -- Dimension FKs
    CarrierID,
    ShipToID,
    OriginWarehouse,

    -- Mode
    Mode_of_Delivery,
    Mode_Clean,

    -- Dates
    LoadDate,
    DeliveryDate,

    -- Freight financials (raw)
    FreightCharged,
    FreightCost,

    -- Freight classification
    FreightStatus,

    -- Freight financials (derived)
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
    Flag_UnknownMode,
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

-- Mode distribution and freight status (run after load)
-- SELECT Mode_Clean, FreightStatus, COUNT(*) AS Loads
-- FROM Stg_LoadFreight
-- GROUP BY Mode_Clean, FreightStatus
-- ORDER BY Mode_Clean, Loads DESC;

-- Clean row count by mode
-- SELECT Mode_Clean, SUM(IsCleanRow) AS CleanLoads, COUNT(*) AS TotalLoads
-- FROM Stg_LoadFreight GROUP BY Mode_Clean;

-- Loads with unknown mode
-- SELECT COUNT(*) AS UnknownModeLoads FROM Stg_LoadFreight WHERE Flag_UnknownMode = 1;
