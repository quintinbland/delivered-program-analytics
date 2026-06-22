-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_product.sql
-- INPUT:       Stg_ProductMaster
-- OUTPUT:      Dim_Product
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES: Stg_ProductMaster (Module 1), Dim_Commodity (this module)
-- BUILD ORDER:  5 of 7 — Dim_Commodity must exist before this script runs
-- =============================================================================
-- ASSUMPTIONS:
--   A1: ItemID is the natural key. One row per ItemID in output.
--       Duplicate ItemIDs in staging use the row with DeduplicationRank = 1.
--   A2: Products with Flag_MissingCommodityMapping = 1 in staging are
--       included in Dim_Product but resolve to CommodityKey = -1 (unknown).
--       They are NOT excluded. Exclusion would break FK integrity for any
--       transaction referencing these items.
--   A3: ProductKey is a system-assigned integer surrogate. ItemID is
--       preserved as the natural key for join and audit purposes.
--   A4: ProductKey = -1 is the default/unknown member.
--   A5: OrganicConventionalFlag is passed through as-is from staging.
--       Its governance status is unconfirmed; no normalization applied.
--   A6: WeightPerCase is included for potential use in freight weight
--       calculations in Fact_LoadFreight. NULL values are retained.
-- =============================================================================

CREATE OR REPLACE TABLE Dim_Product AS

WITH

-- Staging input: deduplicated, clean rows preferred; dirty rows included
-- with CommodityKey defaulting to -1
staged AS (
    SELECT
        s.ItemID,
        s.CommodityID,
        s.ItemDescription,
        s.ItemCategory,
        s.PackSize,
        s.UnitOfMeasure,
        s.OrganicConventionalFlag,
        s.ActiveFlag,
        s.WeightPerCase,
        s.Flag_MissingCommodityMapping,
        s.IsCleanRow
    FROM Stg_ProductMaster s
    WHERE s.DeduplicationRank = 1
),

-- Resolve CommodityID to CommodityKey
-- Products with missing commodity mapping join to default member (-1)
resolved AS (
    SELECT
        s.ItemID,
        COALESCE(c.CommodityKey, -1)    AS CommodityKey,
        s.CommodityID                   AS CommodityID_Source,
        s.ItemDescription,
        s.ItemCategory,
        s.PackSize,
        s.UnitOfMeasure,
        s.OrganicConventionalFlag,
        s.ActiveFlag,
        s.WeightPerCase,
        s.Flag_MissingCommodityMapping,
        s.IsCleanRow,

        -- Flag: commodity resolved to default member
        CASE WHEN COALESCE(c.CommodityKey, -1) = -1 THEN 1 ELSE 0 END
                                        AS Flag_CommodityDefaulted

    FROM staged s
    LEFT JOIN Dim_Commodity c
        ON s.CommodityID = c.CommodityID
       AND c.CommodityKey <> -1         -- Exclude join to default member row
),

keyed AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY ItemID ASC) AS ProductKey,
        *
    FROM resolved
)

-- Default member
SELECT
    -1              AS ProductKey,
    'UNKNOWN'       AS ItemID,
    -1              AS CommodityKey,
    NULL            AS CommodityID_Source,
    'Unknown'       AS ItemDescription,
    NULL            AS ItemCategory,
    NULL            AS PackSize,
    NULL            AS UnitOfMeasure,
    NULL            AS OrganicConventionalFlag,
    'N'             AS ActiveFlag,
    NULL            AS WeightPerCase,
    0               AS Flag_MissingCommodityMapping,
    0               AS Flag_CommodityDefaulted,
    0               AS IsCleanRow,
    'SYSTEM'        AS SourceSystem,
    CURRENT_TIMESTAMP AS LoadedAt

UNION ALL

SELECT
    ProductKey,
    ItemID,
    CommodityKey,
    CommodityID_Source,
    ItemDescription,
    ItemCategory,
    PackSize,
    UnitOfMeasure,
    OrganicConventionalFlag,
    ActiveFlag,
    WeightPerCase,
    Flag_MissingCommodityMapping,
    Flag_CommodityDefaulted,
    IsCleanRow,
    'Stg_ProductMaster' AS SourceSystem,
    CURRENT_TIMESTAMP   AS LoadedAt

FROM keyed;

-- ---------------------------------------------------------------------------
-- POST-LOAD VALIDATION
-- ---------------------------------------------------------------------------

-- Products that defaulted to unknown commodity (exception type: Missing Commodity Mapping)
-- SELECT ProductKey, ItemID, CommodityID_Source
-- FROM Dim_Product
-- WHERE Flag_CommodityDefaulted = 1 AND ProductKey <> -1;

-- Transaction items not in dimension (run after fact tables loaded)
-- SELECT DISTINCT f.ItemID
-- FROM Stg_SalesOrderLine f
-- LEFT JOIN Dim_Product p ON f.ItemID = p.ItemID
-- WHERE p.ProductKey IS NULL AND f.ItemID IS NOT NULL;
