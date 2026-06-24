-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_contract_pricing.sql
-- INPUT:       Raw_ContractPricing
-- OUTPUT:      Stg_ContractPricing
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     2.2.0 — CommodityID canonical normalization applied (2026-06-24)
-- =============================================================================
-- CHANGE LOG (v2.2.0):
--   - CommodityID normalized to canonical names in raw_cast CTE.
--     Source column Commodity contains 53 distinct values with inconsistent
--     casing, abbreviations, and typos. All mapped to canonical list via
--     CASE on UPPER(TRIM(Commodity)).
--   - CommodityID_Raw added: preserves original source value for audit.
--   - Flag_UnmappedCommodity added: fires when source value has no mapping.
--   - Canonical commodity list (29 values, confirmed 2026-06-24):
--     Cauliflower, Broccoli, Broccoli Bunch, Celery, Lettuce,
--     Romaine Hearts, Romaine, Green Leaf, Red Leaf, Green Cabbage,
--     Red Cabbage, Cilantro, Spinach, Parsley, Bok Choy, Napa,
--     Brussels Sprouts, Organic Cauliflower, Organic Broccoli,
--     Organic Celery, Organic Romaine Hearts, Process Cauliflower,
--     Process Broccoli, Process Celery, Process Organic Cauliflower,
--     Process Organic Broccoli, Process Organic Celery,
--     Process Brussels Sprouts, Process Medley, Process Organic Medley
--   - Key mapping decisions (confirmed with business owner 2026-06-24):
--     BROCCOLI CROWNS / Broccoli Crown / Broccoli Crowns → Broccoli
--       (industry standard: "Broccoli" = Broccoli Crowns)
--     BROCCOLI BUNCH / Broccoli Bunch → Broccoli Bunch (distinct COGS)
--     CELERY HEARTS / CELERY STALK / CELERY STICKS / Celery → Celery
--       (pack types consolidated; COGS tracked at SKU level)
--     PARSLEY, CURLEY / PARSLEY, ITALIAN / Parsley → Parsley
--     Organic Romaine Hearts / ROMAINE HEARTS (organic context) → Organic Romaine Hearts
--     BRUSSEL SPROUTS → Brussels Sprouts (typo correction)
--     Processed Broccoil → Process Broccoli (typo correction)
-- CHANGE LOG (v2.1.0):
--   - CustomerHQID translation applied (COSTCO→Costco US, KROGER→Kroger, WALMART→WMT)
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per CustomerHQ + Commodity combination.
--   A2: EffectiveDate defaults to '1900-01-01'; ExpirationDate defaults to
--       '9999-12-31' (open-ended). No date range in real source.
--   A3: Contract hierarchy: Contract > Commit > Open Market (UNK-001 RESOLVED).
--       Active tiers with real data: Tier3 (HQ+Commodity) only.
--   A4: ContractFOBPrice is the per-case contract price (positive decimal).
--   A5: ItemID is NULL for all real contract records (HQ+Commodity level only).
--   A6: CustomerHQID mapping: COSTCO→Costco US, KROGER→Kroger, WALMART→WMT.
--   A7: CommodityID mapping: all 53 source variants mapped to 29 canonical names.
--       Source values outside the known set produce NULL + Flag_UnmappedCommodity=1.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_ContractPricing AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting, CustomerHQID translation,
--         and CommodityID canonical normalization
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Customer scope
        CAST(Customer_HQ AS VARCHAR(200))           AS CustomerHQID_Raw,

        -- CustomerHQID: source UPPER codes → FACT_Base HQ Names
        CASE UPPER(TRIM(CAST(Customer_HQ AS VARCHAR(200))))
            WHEN 'COSTCO'  THEN 'Costco US'
            WHEN 'KROGER'  THEN 'Kroger'
            WHEN 'WALMART' THEN 'WMT'
            ELSE NULL
        END                                         AS CustomerHQID,

        CAST(NULL AS VARCHAR(50))                   AS CustomerID,

        -- Product scope — raw value preserved, canonical applied below
        CAST(Commodity AS VARCHAR(200))             AS CommodityID_Raw,

        -- CommodityID: normalize all source variants to canonical names
        -- Mapping confirmed with business owner 2026-06-24
        CASE UPPER(TRIM(CAST(Commodity AS VARCHAR(200))))

            -- Cauliflower family
            WHEN 'CAULIFLOWER'              THEN 'Cauliflower'
            WHEN 'ORGANIC CAULIFLOWER'      THEN 'Organic Cauliflower'
            WHEN 'PROCESSED CAULIFLOWER'    THEN 'Process Cauliflower'
            WHEN 'PROCESS CAULIFLOWER'      THEN 'Process Cauliflower'
            WHEN 'PROCESSED ORGANIC CAULIFLOWER' THEN 'Process Organic Cauliflower'
            WHEN 'PROCESS ORGANIC CAULIFLOWER'   THEN 'Process Organic Cauliflower'

            -- Broccoli family (Broccoli = Broccoli Crowns per industry standard)
            WHEN 'BROCCOLI'                 THEN 'Broccoli'
            WHEN 'BROCCOLI CROWNS'          THEN 'Broccoli'
            WHEN 'BROCCOLI CROWN'           THEN 'Broccoli'
            WHEN 'BROCCOLI BUNCH'           THEN 'Broccoli Bunch'
            WHEN 'ORGANIC BROCCOLI'         THEN 'Organic Broccoli'
            WHEN 'PROCESSED BROCCOIL'       THEN 'Process Broccoli'  -- typo in source
            WHEN 'PROCESSED BROCCOLI'       THEN 'Process Broccoli'
            WHEN 'PROCESS BROCCOLI'         THEN 'Process Broccoli'
            WHEN 'PROCESSED ORGANIC BROCCOLI'    THEN 'Process Organic Broccoli'
            WHEN 'PROCESS ORGANIC BROCCOLI'      THEN 'Process Organic Broccoli'

            -- Celery family (pack types consolidated to Celery; COGS at SKU level)
            WHEN 'CELERY'                   THEN 'Celery'
            WHEN 'CELERY HEARTS'            THEN 'Celery'
            WHEN 'CELERY STALK'             THEN 'Celery'
            WHEN 'CELERY STICKS'            THEN 'Celery'
            WHEN 'ORGANIC CELERY'           THEN 'Organic Celery'
            WHEN 'ORGANIC CELERY STICKS'    THEN 'Organic Celery'
            WHEN 'PROCESSED CELERY'         THEN 'Process Celery'
            WHEN 'PROCESS CELERY'           THEN 'Process Celery'
            WHEN 'PROCESSED ORGANIC CELERY' THEN 'Process Organic Celery'
            WHEN 'PROCESS ORGANIC CELERY'   THEN 'Process Organic Celery'

            -- Romaine family
            WHEN 'ROMAINE'                  THEN 'Romaine'
            WHEN 'ROMAINE HEARTS'           THEN 'Romaine Hearts'
            WHEN 'ORGANIC ROMAINE'          THEN 'Organic Romaine Hearts'
            WHEN 'ORGANIC ROMAINE HEARTS'   THEN 'Organic Romaine Hearts'

            -- Lettuce / leaf
            WHEN 'LETTUCE'                  THEN 'Lettuce'
            WHEN 'GREEN LEAF'               THEN 'Green Leaf'
            WHEN 'RED LEAF'                 THEN 'Red Leaf'

            -- Cabbage family
            WHEN 'GREEN CABBAGE'            THEN 'Green Cabbage'
            WHEN 'RED CABBAGE'              THEN 'Red Cabbage'
            WHEN 'NAPA'                     THEN 'Napa'
            WHEN 'NAPA CABBAGE'             THEN 'Napa'

            -- Brussels Sprouts (typo correction: BRUSSEL → Brussels)
            WHEN 'BRUSSELS SPROUTS'         THEN 'Brussels Sprouts'
            WHEN 'BRUSSEL SPROUTS'          THEN 'Brussels Sprouts'
            WHEN 'PROCESSED BRUSSELS SPROUTS'    THEN 'Process Brussels Sprouts'
            WHEN 'PROCESS BRUSSELS SPROUTS'      THEN 'Process Brussels Sprouts'

            -- Herbs
            WHEN 'CILANTRO'                 THEN 'Cilantro'
            WHEN 'PARSLEY'                  THEN 'Parsley'
            WHEN 'PARSLEY, CURLEY'          THEN 'Parsley'
            WHEN 'PARSLEY, ITALIAN'         THEN 'Parsley'
            WHEN 'PARSLEY, CURLY'           THEN 'Parsley'

            -- Other
            WHEN 'SPINACH'                  THEN 'Spinach'
            WHEN 'BOK CHOY'                 THEN 'Bok Choy'

            -- Medley processed
            WHEN 'PROCESSED MEDLEY'         THEN 'Process Medley'
            WHEN 'PROCESS MEDLEY'           THEN 'Process Medley'
            WHEN 'PROCESSED ORGANIC MEDLEY' THEN 'Process Organic Medley'
            WHEN 'PROCESS ORGANIC MEDLEY'   THEN 'Process Organic Medley'

            ELSE NULL   -- unmapped → NULL; triggers Flag_UnmappedCommodity
        END                                         AS CommodityID,

        CAST(NULL AS VARCHAR(50))                   AS ItemID,

        TRY_CAST(Contract_FOB AS DECIMAL(18, 6))    AS ContractFOBPrice,
        CAST(CustomerProgramStatus AS VARCHAR(50))  AS ContractType,
        CAST('1900-01-01' AS DATE)                  AS EffectiveDate,
        CAST('9999-12-31' AS DATE)                  AS ExpirationDate,
        'Active'                                    AS ContractStatus,

        COALESCE(
            CAST(SourceSystem AS VARCHAR(100)),
            'CONTRACT_UNIFIED'
        )                                           AS SourceSystem,
        COALESCE(
            CAST(BatchID AS VARCHAR(100)),
            CAST(CURRENT_TIMESTAMP AS VARCHAR(30))
        )                                           AS BatchID,
        CURRENT_TIMESTAMP                           AS StagedAt

    FROM Raw_ContractPricing
),

-- ---------------------------------------------------------------------------
-- STEP 1b: Generate surrogate ContractPriceKey
-- Keyed on translated CustomerHQID + canonical CommodityID
-- ---------------------------------------------------------------------------
with_key AS (
    SELECT
        CONCAT(
            COALESCE(CustomerHQID, 'NULL'), '|',
            COALESCE(CommodityID,  'NULL')
        )                                           AS ContractPriceKey,
        *
    FROM raw_cast
),

-- ---------------------------------------------------------------------------
-- STEP 2: Deduplication detection
-- ---------------------------------------------------------------------------
dedup_flag AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY CustomerHQID, CommodityID
            ORDER BY
                CASE WHEN ContractFOBPrice IS NOT NULL THEN 0 ELSE 1 END ASC,
                StagedAt ASC
        ) AS DeduplicationRank,
        COUNT(*) OVER (
            PARTITION BY CustomerHQID, CommodityID
        ) AS DuplicateCount,
        COUNT(*) OVER (
            PARTITION BY CustomerHQID
        ) AS ScopeCount
    FROM with_key
),

-- ---------------------------------------------------------------------------
-- STEP 3: Derived fields and data quality flags
-- ---------------------------------------------------------------------------
dq_flags AS (
    SELECT
        d.*,

        CASE
            WHEN CustomerHQID IS NOT NULL AND CommodityID IS NOT NULL THEN 'Tier3_HQCommodity'
            ELSE 'Unclassified'
        END                                         AS ContractMatchTier,

        'Active'                                    AS ContractDateStatus,

        -- DQ FLAG: Unmapped CustomerHQ source code
        CASE WHEN CustomerHQID IS NULL AND CustomerHQID_Raw IS NOT NULL THEN 1 ELSE 0 END
                                                    AS Flag_UnmappedCustomerHQ,

        -- DQ FLAG: Unmapped Commodity source value
        CASE WHEN CommodityID IS NULL AND CommodityID_Raw IS NOT NULL THEN 1 ELSE 0 END
                                                    AS Flag_UnmappedCommodity,

        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                    AS Flag_DuplicateKey,
        CASE WHEN ContractFOBPrice IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingFOBPrice,
        CASE
            WHEN ContractFOBPrice IS NOT NULL AND ContractFOBPrice < 0 THEN 1
            ELSE 0
        END                                         AS Flag_NegativeFOBPrice,
        CASE WHEN CustomerHQID IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingCustomerScope,
        CASE WHEN CommodityID IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingProductScope,
        CASE
            WHEN ContractType IS NULL THEN 1
            WHEN UPPER(TRIM(ContractType)) NOT IN ('CONTRACT','COMMIT','OPEN MARKET') THEN 1
            ELSE 0
        END                                         AS Flag_InvalidContractType,
        CASE
            WHEN UPPER(TRIM(ContractType)) = 'OPEN MARKET' THEN 1
            ELSE 0
        END                                         AS Flag_OpenMarketContract,
        CASE WHEN ScopeCount > 1 THEN 1 ELSE 0 END
                                                    AS Flag_PotentialScopeOverlap,

        CASE
            WHEN CustomerHQID IS NULL           THEN 0
            WHEN CommodityID IS NULL            THEN 0
            WHEN ContractPriceKey IS NULL       THEN 0
            WHEN ContractFOBPrice IS NULL       THEN 0
            WHEN ContractFOBPrice < 0           THEN 0
            WHEN DuplicateCount > 1 AND DeduplicationRank > 1 THEN 0
            WHEN UPPER(TRIM(ContractType)) = 'OPEN MARKET' THEN 0
            ELSE 1
        END                                         AS IsCleanRow

    FROM dedup_flag d
)

-- ---------------------------------------------------------------------------
-- STEP 4: Final projection
-- ---------------------------------------------------------------------------
SELECT
    ContractPriceKey,
    CustomerID,
    CustomerHQID,
    CustomerHQID_Raw,
    ItemID,
    CommodityID,
    CommodityID_Raw,
    ContractFOBPrice,
    EffectiveDate,
    ExpirationDate,
    ContractMatchTier,
    ContractDateStatus,
    ContractType,
    ContractStatus,
    DeduplicationRank,
    DuplicateCount,
    ScopeCount,
    Flag_UnmappedCustomerHQ,
    Flag_UnmappedCommodity,
    Flag_DuplicateKey,
    Flag_MissingFOBPrice,
    Flag_NegativeFOBPrice,
    Flag_MissingCustomerScope,
    Flag_MissingProductScope,
    Flag_InvalidContractType,
    Flag_OpenMarketContract,
    Flag_PotentialScopeOverlap,
    IsCleanRow,
    SourceSystem,
    BatchID,
    StagedAt

FROM dq_flags;

-- =============================================================================
-- POST-LOAD VALIDATION QUERIES
-- =============================================================================

-- Commodity normalization audit (expect 0 unmapped after canonical mapping)
-- SELECT CommodityID_Raw, CommodityID, COUNT(*) AS RecordCount,
--        SUM(Flag_UnmappedCommodity) AS UnmappedCount
-- FROM Stg_ContractPricing GROUP BY CommodityID_Raw, CommodityID ORDER BY 1;

-- CustomerHQ translation audit (expect 0 unmapped)
-- SELECT CustomerHQID_Raw, CustomerHQID, COUNT(*) AS RecordCount,
--        SUM(Flag_UnmappedCustomerHQ) AS UnmappedCount
-- FROM Stg_ContractPricing GROUP BY CustomerHQID_Raw, CustomerHQID ORDER BY 1;

-- Clean contract records by HQ + Commodity
-- SELECT CustomerHQID, CommodityID, ContractType, ContractFOBPrice
-- FROM Stg_ContractPricing WHERE IsCleanRow = 1 ORDER BY CustomerHQID, CommodityID;

-- Duplicate scope check
-- SELECT CustomerHQID, CommodityID, COUNT(*) AS RecordCount
-- FROM Stg_ContractPricing
-- GROUP BY CustomerHQID, CommodityID HAVING COUNT(*) > 1;


