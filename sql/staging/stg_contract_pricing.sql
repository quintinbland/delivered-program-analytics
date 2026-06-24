-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_contract_pricing.sql
-- INPUT:       Raw_ContractPricing
-- OUTPUT:      Stg_ContractPricing
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     2.0.0 — Real data mapping applied (2026-06-23)
-- =============================================================================
-- CHANGE LOG (v2.0.0):
--   - Mapped all columns to confirmed real source columns from Copilot mapping
--   - ContractPriceKey   ← generated surrogate (no natural key in source)
--   - CustomerHQID       ← Contract_Unified.Customer_HQ
--   - CommodityID        ← Contract_Unified.Commodity
--   - ContractFOBPrice   ← Contract_Unified.Contract_FOB
--   - EffectiveDate      ← NULL (no contract date range in real source)
--   - ExpirationDate     ← NULL (no contract date range in real source)
--   - ContractType       ← derived from CustomerProgramStatus (Contract/Commit/Open Market)
-- RESOLVED UNKNOWNS:
--   - UNK-001: Contract hierarchy confirmed: Contract > Commit > Open Market
--              Maps to pipeline tiers: Contract=Tier1, Commit=Tier2, Open Market=Tier3
--              Flag_CandidateHierarchy_UNK001 REMOVED — hierarchy now confirmed.
-- REMAINING OPEN:
--   - EffectiveDate / ExpirationDate: not in real source. Contract matching in
--     fact_sales_order_line.sql must be updated to remove date range filter.
--     See ASSUMPTION A3 below.
--   - CustomerID (account-level): real contracts are at HQ level only.
--     Tier1 (CustomerID + ItemID) matching will produce zero results.
--     Effective hierarchy becomes: Tier2 (HQ+Item) > Tier3 (HQ+Commodity).
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per CustomerHQ + Commodity combination.
--       Surrogate ContractPriceKey is generated at staging via ROW_NUMBER.
--   A2: Real source has no EffectiveDate or ExpirationDate columns.
--       EffectiveDate defaults to '1900-01-01'; ExpirationDate defaults to
--       '9999-12-31' (open-ended). This ensures all contracts match any
--       transaction date. Date-range filtering in fact_sales_order_line.sql
--       must be updated to remove the BETWEEN clause or use these defaults.
--   A3: Contract matching hierarchy (UNK-001 RESOLVED):
--       Contract  = highest priority (maps to Tier2: HQ+Item in practice)
--       Commit    = second priority  (maps to Tier3: HQ+Commodity)
--       Open Market = no contract pricing; matches to NoMatch tier
--       NOTE: Since real contracts are at HQ level, Tier1 (CustomerID+ItemID)
--       will never match. The active tiers are Tier2 and Tier3 only.
--   A4: ContractFOBPrice is the per-case contract price (positive decimal).
--   A5: Commodity in source maps to CommodityID in the pipeline.
--       ItemID (product-level) is NULL for all real contract records.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_ContractPricing AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting and NULL normalization
-- Source: Raw_ContractPricing (Contract_Unified)
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Customer scope (HQ level only in real source)
        CAST(Customer_HQ    AS VARCHAR(200))    AS CustomerHQID,
        -- CustomerID not available at contract level in real source
        CAST(NULL AS VARCHAR(50))               AS CustomerID,

        -- Product scope (Commodity level in real source)
        CAST(Commodity      AS VARCHAR(200))    AS CommodityID,
        -- ItemID not available at contract level in real source
        CAST(NULL AS VARCHAR(50))               AS ItemID,

        -- Pricing
        TRY_CAST(Contract_FOB AS DECIMAL(18, 6)) AS ContractFOBPrice,

        -- Contract type from program status
        -- Values: 'Contract', 'Commit', 'Open Market'
        CAST(CustomerProgramStatus AS VARCHAR(50)) AS ContractType,

        -- Effective range: not in real source; open-ended defaults applied
        -- '1900-01-01' to '9999-12-31' ensures match against any transaction date
        CAST('1900-01-01' AS DATE)              AS EffectiveDate,
        CAST('9999-12-31' AS DATE)              AS ExpirationDate,

        -- ContractStatus: active by default (no status column in real source)
        'Active'                                AS ContractStatus,

        -- Batch metadata
        COALESCE(
            CAST(SourceSystem AS VARCHAR(100)),
            'CONTRACT_UNIFIED'
        )                                       AS SourceSystem,
        COALESCE(
            CAST(BatchID AS VARCHAR(100)),
            CAST(CURRENT_TIMESTAMP AS VARCHAR(30))
        )                                       AS BatchID,
        CURRENT_TIMESTAMP                       AS StagedAt

    FROM Raw_ContractPricing
),

-- ---------------------------------------------------------------------------
-- STEP 1b: Generate surrogate ContractPriceKey
-- Source has no natural primary key; generate deterministic surrogate.
-- ---------------------------------------------------------------------------
with_key AS (
    SELECT
        -- Surrogate key: hash of HQ + Commodity (functional natural key)
        CONCAT(
            COALESCE(CustomerHQID, 'NULL'), '|',
            COALESCE(CommodityID,  'NULL')
        )                                       AS ContractPriceKey,
        *
    FROM raw_cast
),

-- ---------------------------------------------------------------------------
-- STEP 2: Deduplication detection
-- Duplicate = same CustomerHQID + CommodityID appearing more than once.
-- ---------------------------------------------------------------------------
dedup_flag AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY CustomerHQID, CommodityID
            ORDER BY
                CASE
                    WHEN ContractFOBPrice IS NOT NULL THEN 0
                    ELSE 1
                END ASC,
                StagedAt ASC
        ) AS DeduplicationRank,
        COUNT(*) OVER (
            PARTITION BY CustomerHQID, CommodityID
        ) AS DuplicateCount,

        -- Scope count for overlap detection
        COUNT(*) OVER (
            PARTITION BY CustomerHQID
        ) AS ScopeCount

    FROM with_key
),

-- ---------------------------------------------------------------------------
-- STEP 3: Derived fields and row-level data quality flags
-- ---------------------------------------------------------------------------
dq_flags AS (
    SELECT
        d.*,

        -- Contract match tier classification (UNK-001 RESOLVED)
        -- Real source is HQ-level only; Tier1 (CustomerID+ItemID) will not fire.
        CASE
            WHEN CustomerHQID IS NOT NULL AND CommodityID IS NOT NULL THEN 'Tier3_HQCommodity'
            ELSE 'Unclassified'
        END                                     AS ContractMatchTier,

        -- Contract date status: always 'Active' since dates are open-ended defaults
        'Active'                                AS ContractDateStatus,

        -- -----------
        -- DATA QUALITY FLAGS
        -- -----------

        -- DQ FLAG: Duplicate CustomerHQID + CommodityID
        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                AS Flag_DuplicateKey,

        -- DQ FLAG: NULL ContractFOBPrice
        CASE WHEN ContractFOBPrice IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingFOBPrice,

        -- DQ FLAG: Negative ContractFOBPrice
        CASE
            WHEN ContractFOBPrice IS NOT NULL
             AND ContractFOBPrice < 0
            THEN 1
            ELSE 0
        END                                     AS Flag_NegativeFOBPrice,

        -- DQ FLAG: NULL CustomerHQID
        CASE WHEN CustomerHQID IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingCustomerScope,

        -- DQ FLAG: NULL CommodityID
        CASE WHEN CommodityID IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingProductScope,

        -- DQ FLAG: ContractType outside controlled values
        CASE
            WHEN ContractType IS NULL THEN 1
            WHEN UPPER(TRIM(ContractType)) NOT IN ('CONTRACT','COMMIT','OPEN MARKET') THEN 1
            ELSE 0
        END                                     AS Flag_InvalidContractType,

        -- DQ FLAG: Open Market contracts (no FOB price expected; flag for awareness)
        CASE
            WHEN UPPER(TRIM(ContractType)) = 'OPEN MARKET' THEN 1
            ELSE 0
        END                                     AS Flag_OpenMarketContract,

        -- DQ FLAG: Potential scope overlap (multiple contracts per HQ)
        CASE WHEN ScopeCount > 1 THEN 1 ELSE 0 END
                                                AS Flag_PotentialScopeOverlap,

        -- COMPOSITE: Row is clean
        CASE
            WHEN ContractPriceKey IS NULL   THEN 0
            WHEN ContractFOBPrice IS NULL   THEN 0
            WHEN ContractFOBPrice < 0       THEN 0
            WHEN CustomerHQID IS NULL       THEN 0
            WHEN CommodityID IS NULL        THEN 0
            WHEN DuplicateCount > 1         THEN 0
            -- Open Market contracts are staged but marked not clean
            -- (they have no ContractFOBPrice by definition)
            WHEN UPPER(TRIM(ContractType)) = 'OPEN MARKET' THEN 0
            ELSE 1
        END                                     AS IsCleanRow

    FROM dedup_flag d
)

-- ---------------------------------------------------------------------------
-- STEP 4: Final projection — staging output
-- ---------------------------------------------------------------------------
SELECT
    -- Natural key (generated surrogate)
    ContractPriceKey,

    -- Contract scope
    CustomerID,
    CustomerHQID,
    ItemID,
    CommodityID,

    -- Pricing
    ContractFOBPrice,

    -- Effective range (open-ended defaults; no date filter in matching)
    EffectiveDate,
    ExpirationDate,

    -- Derived classifications
    ContractMatchTier,
    ContractDateStatus,

    -- Contract metadata
    ContractType,
    ContractStatus,

    -- Deduplication metadata
    DeduplicationRank,
    DuplicateCount,
    ScopeCount,

    -- Data quality flags
    Flag_DuplicateKey,
    Flag_MissingFOBPrice,
    Flag_NegativeFOBPrice,
    -- EffectiveDate / ExpirationDate flags suppressed (open-ended defaults; always valid)
    Flag_MissingCustomerScope,
    Flag_MissingProductScope,
    Flag_InvalidContractType,
    Flag_OpenMarketContract,
    Flag_PotentialScopeOverlap,
    IsCleanRow,

    -- Batch metadata
    SourceSystem,
    BatchID,
    StagedAt

FROM dq_flags;

-- =============================================================================
-- POST-LOAD VALIDATION QUERIES
-- =============================================================================

-- Contract tier distribution (expect mostly Tier3_HQCommodity with real data)
-- SELECT ContractMatchTier, COUNT(*) AS RecordCount
-- FROM Stg_ContractPricing GROUP BY ContractMatchTier;

-- ContractType distribution
-- SELECT ContractType, COUNT(*) AS RecordCount, SUM(IsCleanRow) AS CleanCount
-- FROM Stg_ContractPricing GROUP BY ContractType;

-- Open Market contracts (no FOB price; these will be NoMatch in fact layer)
-- SELECT CustomerHQID, CommodityID, ContractType
-- FROM Stg_ContractPricing WHERE Flag_OpenMarketContract = 1;

-- Duplicate scope check
-- SELECT CustomerHQID, CommodityID, COUNT(*) AS RecordCount
-- FROM Stg_ContractPricing
-- GROUP BY CustomerHQID, CommodityID HAVING COUNT(*) > 1;
