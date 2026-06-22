-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_commodity.sql
-- INPUT:       Raw_CommodityReference
-- OUTPUT:      Dim_Commodity
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES: None
-- BUILD ORDER:  2 of 7 — no upstream dimension dependencies
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Raw_CommodityReference is a managed reference table maintained by
--       the operations team. It is not derived from transaction data.
--   A2: CommodityID is the natural key. It is assumed to be unique in source.
--       Duplicate CommodityIDs are flagged and the first occurrence is used.
--   A3: CommodityGroup is a higher-level grouping above CommodityID
--       (e.g., CommodityID = 'LETTUCE_ROMAINE', CommodityGroup = 'LEAFY_GREENS').
--       If CommodityGroup is absent in source, it defaults to CommodityID.
--   A4: Seasonality data (peak months) is stored as a comma-delimited string
--       in SeasonalityWindow if present. Parsing is deferred to the reporting
--       layer. Staged as-is.
--   A5: An UNKNOWN row (CommodityKey = -1) is inserted as a default member.
-- =============================================================================

CREATE OR REPLACE TABLE Dim_Commodity AS

WITH

raw_cast AS (
    SELECT
        CAST(CommodityID          AS VARCHAR(50))   AS CommodityID,
        TRIM(CAST(CommodityName   AS VARCHAR(200)))  AS CommodityName,
        COALESCE(
            NULLIF(TRIM(CAST(CommodityGroup AS VARCHAR(100))), ''),
            CAST(CommodityID AS VARCHAR(100))
        )                                            AS CommodityGroup,
        TRIM(CAST(CommodityCategory AS VARCHAR(100))) AS CommodityCategory,
        CAST(SeasonalityWindow    AS VARCHAR(200))   AS SeasonalityWindow,
        CAST(ActiveFlag           AS VARCHAR(10))    AS ActiveFlag,
        CURRENT_TIMESTAMP                            AS LoadedAt
    FROM Raw_CommodityReference
),

dedup AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY CommodityID
            ORDER BY
                CASE WHEN ActiveFlag = 'Y' THEN 0 ELSE 1 END ASC,
                LoadedAt ASC
        ) AS RowRank
    FROM raw_cast
),

-- Default member unioned in before surrogate key assignment
with_default AS (
    SELECT
        'UNKNOWN'   AS CommodityID,
        'Unknown'   AS CommodityName,
        'UNKNOWN'   AS CommodityGroup,
        'UNKNOWN'   AS CommodityCategory,
        NULL        AS SeasonalityWindow,
        '0'         AS ActiveFlag,
        CURRENT_TIMESTAMP AS LoadedAt,
        -1          AS ForcedKey
    UNION ALL
    SELECT
        CommodityID,
        CommodityName,
        CommodityGroup,
        CommodityCategory,
        SeasonalityWindow,
        ActiveFlag,
        LoadedAt,
        NULL        AS ForcedKey
    FROM dedup
    WHERE RowRank = 1
)

SELECT
    -- Surrogate key: -1 for default, sequential for all others
    CASE
        WHEN ForcedKey = -1 THEN -1
        ELSE ROW_NUMBER() OVER (
            PARTITION BY CASE WHEN ForcedKey = -1 THEN 1 ELSE 0 END
            ORDER BY CommodityID ASC
        )
    END                                             AS CommodityKey,

    CommodityID,
    CommodityName,
    CommodityGroup,
    CommodityCategory,
    SeasonalityWindow,

    CASE
        WHEN ActiveFlag = 'Y' THEN 1
        WHEN ForcedKey = -1   THEN 0
        ELSE 0
    END                                             AS IsActive,

    'Raw_CommodityReference'                        AS SourceSystem,
    LoadedAt

FROM with_default;

-- ---------------------------------------------------------------------------
-- POST-LOAD VALIDATION
-- ---------------------------------------------------------------------------

-- All products with a CommodityID should resolve to a dimension row
-- SELECT p.ItemID, p.CommodityID
-- FROM Stg_ProductMaster p
-- LEFT JOIN Dim_Commodity c ON p.CommodityID = c.CommodityID
-- WHERE c.CommodityKey IS NULL
--   AND p.CommodityID IS NOT NULL;

-- Row count by group
-- SELECT CommodityGroup, COUNT(*) AS CommodityCount
-- FROM Dim_Commodity
-- WHERE CommodityKey <> -1
-- GROUP BY CommodityGroup
-- ORDER BY CommodityCount DESC;
