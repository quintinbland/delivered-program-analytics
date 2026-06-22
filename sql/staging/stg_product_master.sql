-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_product_master.sql
-- INPUT:       Raw_ProductMaster
-- OUTPUT:      Stg_ProductMaster
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per ItemID. Duplicate ItemIDs are a data
--       quality issue — flagged and retained.
--   A2: CommodityID may be NULL. This is a known data quality issue baked
--       into the synthetic dataset. Rows with NULL CommodityID are flagged
--       with Flag_MissingCommodityMapping = 1 for exception routing.
--   A3: OrganicConventionalFlag semantics are UNKNOWN (not in UNK log but
--       unconfirmed as a governed vs. inferred field). The field is staged
--       as-is with a flag when NULL.
--   A4: ProductDescription is free-text; it is trimmed but not parsed.
--   A5: UnitOfMeasure is expected to be a controlled value (e.g., 'CASE',
--       'LB', 'EACH'). Unexpected values are flagged.
-- OPEN UNKNOWNS AFFECTING THIS SCRIPT:
--   None registered in unknowns_log.md, but:
--   IMPLICIT UNKNOWN: Whether OrganicConventionalFlag is a governed field
--   or inferred from product attributes. Staged as-is until confirmed.
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

        -- Dimension FKs (unresolved)
        CAST(CommodityID         AS VARCHAR(50))   AS CommodityID,

        -- Product descriptors
        -- [DIALECT NOTE] TRIM is ANSI-compatible.
        TRIM(CAST(ItemDescription    AS VARCHAR(500)))  AS ItemDescription,
        CAST(ItemCategory        AS VARCHAR(100))  AS ItemCategory,
        CAST(PackSize            AS VARCHAR(50))   AS PackSize,

        -- Unit of measure
        -- Normalized to uppercase for consistent comparison.
        -- [DIALECT NOTE] UPPER is ANSI-compatible.
        UPPER(TRIM(CAST(UnitOfMeasure AS VARCHAR(20))))  AS UnitOfMeasure,

        -- Product classification flags
        -- Stored as raw value; interpreted downstream.
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
    FROM raw_cast
),

-- ---------------------------------------------------------------------------
-- STEP 3: Row-level data quality flags
-- ---------------------------------------------------------------------------
dq_flags AS (
    SELECT
        d.*,

        -- -----------
        -- DATA QUALITY FLAGS
        -- -----------

        -- DQ FLAG: Duplicate ItemID
        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                    AS Flag_DuplicateKey,

        -- DQ FLAG: NULL CommodityID (known exception type: Missing Commodity Mapping)
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

        -- DQ FLAG: NULL OrganicConventionalFlag (unconfirmed field governance)
        CASE WHEN OrganicConventionalFlag IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingOrganicFlag,

        -- DQ FLAG: NULL WeightPerCase
        CASE WHEN WeightPerCase IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingWeight,

        -- DQ FLAG: Inactive item appearing in transactions
        -- This flag is set at staging; cross-reference with transaction tables
        -- is done at the dimension build layer.
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

    -- Dimension FK (unresolved)
    CommodityID,

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

-- Items missing commodity mapping (exception type: Missing Commodity Mapping)
-- SELECT ItemID, ItemDescription, ItemCategory
-- FROM Stg_ProductMaster
-- WHERE Flag_MissingCommodityMapping = 1;

-- UOM distribution
-- SELECT UnitOfMeasure, COUNT(*) AS ItemCount
-- FROM Stg_ProductMaster
-- GROUP BY UnitOfMeasure
-- ORDER BY ItemCount DESC;
