-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_product_master.sql
-- INPUT:       Raw_ProductMaster, Raw_CommodityMapping
-- OUTPUT:      Stg_ProductMaster
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     2.0.0 — CommodityID resolved from Raw_CommodityMapping (2026-06-24)
-- =============================================================================
-- CHANGE LOG (v2.0.0):
--   - CommodityID now resolved via LEFT JOIN to Raw_CommodityMapping on ItemID.
--     Previously NULL for all rows (source item master has no commodity column).
--   - Raw_CommodityMapping.CommodityID_Mapped value 'UNKNOWN' is treated as
--     NULL — mapped items with no confirmed commodity are flagged identically
--     to unmapped items (Flag_MissingCommodityMapping = 1).
--   - CommodityID_Raw added: preserves original source value (always NULL from
--     Raw_ProductMaster) for audit. Mapping source is now Raw_CommodityMapping.
--   - Flag_MissingCommodityMapping now fires on: NULL source + no mapping,
--     NULL source + mapping exists but value is 'UNKNOWN'.
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per ItemID. Duplicate ItemIDs are a data
--       quality issue — flagged and retained.
--   A2: CommodityID is not present in Raw_ProductMaster (real source).
--       It is resolved entirely from Raw_CommodityMapping. Rows with no
--       mapping entry or UNKNOWN mapping are flagged with
--       Flag_MissingCommodityMapping = 1.
--   A3: OrganicConventionalFlag semantics are UNKNOWN (not in UNK log but
--       unconfirmed as a governed vs. inferred field). The field is staged
--       as-is with a flag when NULL.
--   A4: ProductDescription is free-text; it is trimmed but not parsed.
--   A5: UnitOfMeasure is expected to be a controlled value (e.g., 'CASE',
--       'LB', 'EACH'). Unexpected values are flagged.
--   A6: Raw_CommodityMapping is loaded in Phase 2 before this script runs.
--       Pipeline dependency: phase2_load_raw_data.sql must precede this script.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_ProductMaster AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting and NULL normalization
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Natural key
        CAST(ItemID              AS VARCHAR(50))   AS ItemID,

        -- CommodityID from source is NULL for all real records;
        -- preserved as CommodityID_Raw for audit only
        CAST(CommodityID         AS VARCHAR(50))   AS CommodityID_Raw,

        -- Product descriptors
        TRIM(CAST(ItemDescription    AS VARCHAR(500)))  AS ItemDescription,
        CAST(ItemCategory        AS VARCHAR(100))  AS ItemCategory,
        CAST(PackSize            AS VARCHAR(50))   AS PackSize,

        -- Unit of measure normalized to uppercase
        UPPER(TRIM(CAST(UnitOfMeasure AS VARCHAR(20))))  AS UnitOfMeasure,

        -- Product classification flags
        CAST(OrganicConventionalFlag AS VARCHAR(20))  AS OrganicConventionalFlag,
        CAST(ActiveFlag          AS VARCHAR(10))   AS ActiveFlag,

        -- Weight / volume (for freight calculations)
        TRY_CAST(WeightPerCase   AS DECIMAL(10, 4))  AS WeightPerCase,

        -- Batch metadata
        COALESCE(
            CAST(SourceSystem AS VARCHAR(100)),
            'ERP_PRODUCTMASTER'
        )                                           AS SourceSystem,
        COALESCE(
            CAST(BatchID AS VARCHAR(100)),
            CAST(CURRENT_TIMESTAMP AS VARCHAR(30))
        )                                           AS BatchID,
        CURRENT_TIMESTAMP                           AS StagedAt

    FROM Raw_ProductMaster
),

-- ---------------------------------------------------------------------------
-- STEP 1b: Resolve CommodityID from Raw_CommodityMapping
-- Join on ItemID. UNKNOWN values converted to NULL.
-- ---------------------------------------------------------------------------
with_commodity AS (
    SELECT
        r.*,
        CASE
            WHEN UPPER(TRIM(cm.CommodityID_Mapped)) = 'UNKNOWN' THEN NULL
            WHEN cm.CommodityID_Mapped IS NULL THEN NULL
            ELSE TRIM(cm.CommodityID_Mapped)
        END                                         AS CommodityID
    FROM raw_cast r
    LEFT JOIN Raw_CommodityMapping cm
        ON UPPER(TRIM(r.ItemID)) = UPPER(TRIM(cm.ItemID))
),

-- ---------------------------------------------------------------------------
-- STEP 2: Deduplication detection
-- Duplicate = same ItemID appearing more than once.
-- Prefer rows with CommodityID populated.
-- ---------------------------------------------------------------------------
dedup_flag AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY ItemID
            ORDER BY
                CASE WHEN CommodityID IS NOT NULL THEN 0 ELSE 1 END ASC,
                CASE WHEN ActiveFlag = 'Y'        THEN 0 ELSE 1 END ASC,
                StagedAt ASC
        ) AS DeduplicationRank,
        COUNT(*) OVER (
            PARTITION BY ItemID
        ) AS DuplicateCount
    FROM with_commodity
),

-- ---------------------------------------------------------------------------
-- STEP 3: Row-level data quality flags
-- ---------------------------------------------------------------------------
dq_flags AS (
    SELECT
        d.*,

        -- DQ FLAG: Duplicate ItemID
        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                    AS Flag_DuplicateKey,

        -- DQ FLAG: NULL or UNKNOWN CommodityID after mapping resolution
        CASE WHEN CommodityID IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingCommodityMapping,

        -- DQ FLAG: NULL ItemDescription
        CASE WHEN ItemDescription IS NULL
              OR TRIM(ItemDescription) = ''
             THEN 1 ELSE 0 END                      AS Flag_MissingDescription,

        -- DQ FLAG: NULL or unexpected UnitOfMeasure
        CASE
            WHEN UnitOfMeasure IS NULL THEN 1
            WHEN UnitOfMeasure NOT IN ('CASE', 'LB', 'EACH', 'BOX', 'PALLET') THEN 1
            ELSE 0
        END                                         AS Flag_UnexpectedUOM,

        -- DQ FLAG: NULL OrganicConventionalFlag
        CASE WHEN OrganicConventionalFlag IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingOrganicFlag,

        -- DQ FLAG: NULL WeightPerCase
        CASE WHEN WeightPerCase IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingWeight,

        -- DQ FLAG: Inactive item
        CASE
            WHEN ActiveFlag IS NULL    THEN 1
            WHEN ActiveFlag = 'N'      THEN 1
            ELSE 0
        END                                         AS Flag_InactiveItem,

        -- COMPOSITE: Row is clean
        CASE
            WHEN ItemID IS NULL          THEN 0
            WHEN CommodityID IS NULL     THEN 0
            WHEN DuplicateCount > 1      THEN 0
            WHEN ItemDescription IS NULL THEN 0
            WHEN TRIM(ItemDescription) = '' THEN 0
            WHEN UnitOfMeasure IS NULL   THEN 0
            ELSE 1
        END                                         AS IsCleanRow

    FROM dedup_flag d
)

-- ---------------------------------------------------------------------------
-- STEP 4: Final projection — staging output
-- ---------------------------------------------------------------------------
SELECT
    -- Natural key
    ItemID,

    -- Commodity (resolved from mapping; NULL if unmapped or UNKNOWN)
    CommodityID,
    CommodityID_Raw,    -- always NULL for real source; preserved for audit

    -- Product descriptors
    ItemDescription,
    ItemCategory,
    PackSize,
    UnitOfMeasure,

    -- Product classification
    OrganicConventionalFlag,
    ActiveFlag,

    -- Physical attributes
    WeightPerCase,

    -- Deduplication metadata
    DeduplicationRank,
    DuplicateCount,

    -- Data quality flags
    Flag_DuplicateKey,
    Flag_MissingCommodityMapping,
    Flag_MissingDescription,
    Flag_UnexpectedUOM,
    Flag_MissingOrganicFlag,
    Flag_MissingWeight,
    Flag_InactiveItem,
    IsCleanRow,

    -- Batch metadata
    SourceSystem,
    BatchID,
    StagedAt

FROM dq_flags;

-- =============================================================================
-- POST-LOAD VALIDATION QUERIES
-- =============================================================================

-- Commodity mapping coverage (expect 0 or low UNKNOWN count after mapping)
-- SELECT CommodityID, COUNT(*) AS ItemCount, SUM(Flag_MissingCommodityMapping) AS UnmappedCount
-- FROM Stg_ProductMaster GROUP BY CommodityID ORDER BY ItemCount DESC;

-- Items still missing commodity mapping after join (take to Copilot for resolution)
-- SELECT ItemID, ItemDescription, ItemCategory
-- FROM Stg_ProductMaster WHERE Flag_MissingCommodityMapping = 1 ORDER BY ItemID;

-- UOM distribution
-- SELECT UnitOfMeasure, COUNT(*) AS ItemCount
-- FROM Stg_ProductMaster GROUP BY UnitOfMeasure ORDER BY ItemCount DESC;
