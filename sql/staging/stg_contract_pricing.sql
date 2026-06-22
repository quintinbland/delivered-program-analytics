-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_contract_pricing.sql
-- INPUT:       Raw_ContractPricing
-- OUTPUT:      Stg_ContractPricing
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per ContractPriceKey (unique contract rule).
--       Each rule is bound to a customer entity, item or commodity, and an
--       effective date range.
--   A2: Contract matching hierarchy (UNK-001) is NOT resolved at staging.
--       All contract records are staged regardless of match tier.
--       Hierarchy application occurs in the Contract Pricing Fact build.
--   A3: EffectiveDate and ExpirationDate arrive as character strings;
--       format assumed YYYY-MM-DD.
--   A4: ContractFOBPrice is the per-case contract price, expressed as a
--       positive decimal. Negative values are flagged as invalid.
--   A5: A contract record is considered expired if ExpirationDate < CURRENT_DATE.
--       Expired records are retained and flagged — not dropped.
--   A6: CustomerHQID may be NULL when the contract is bound to a specific
--       CustomerID. Both fields are staged; resolution logic is downstream.
--   A7: CommodityID may be NULL when the contract is at item level (ItemID).
--       Both fields are staged; match-tier logic is downstream.
-- OPEN UNKNOWNS AFFECTING THIS SCRIPT:
--   UNK-001: Contract matching hierarchy — not applied at staging.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_ContractPricing AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting and NULL normalization
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Natural key
        CAST(ContractPriceKey    AS VARCHAR(50))   AS ContractPriceKey,

        -- Contract scope (customer)
        CAST(CustomerID          AS VARCHAR(50))   AS CustomerID,
        CAST(CustomerHQID        AS VARCHAR(50))   AS CustomerHQID,

        -- Contract scope (product)
        CAST(ItemID              AS VARCHAR(50))   AS ItemID,
        CAST(CommodityID         AS VARCHAR(50))   AS CommodityID,

        -- Pricing
        TRY_CAST(ContractFOBPrice AS DECIMAL(18, 6)) AS ContractFOBPrice,

        -- Effective range
        TRY_CAST(EffectiveDate   AS DATE)          AS EffectiveDate,
        TRY_CAST(ExpirationDate  AS DATE)          AS ExpirationDate,

        -- Contract metadata
        CAST(ContractType        AS VARCHAR(50))   AS ContractType,
        CAST(ContractStatus      AS VARCHAR(50))   AS ContractStatus,

        -- Batch metadata
        COALESCE(
            CAST(SourceSystem AS VARCHAR(100)),
            'CONTRACT_PRICING_REFERENCE'
        )                                           AS SourceSystem,
        COALESCE(
            CAST(BatchID AS VARCHAR(100)),
            CAST(CURRENT_TIMESTAMP AS VARCHAR(30))
        )                                           AS BatchID,
        CURRENT_TIMESTAMP                           AS StagedAt

    FROM Raw_ContractPricing
),

-- ---------------------------------------------------------------------------
-- STEP 2: Deduplication detection
-- Duplicate = same ContractPriceKey appearing more than once.
-- Also detect functional duplicates: same CustomerID/HQ + ItemID/Commodity
-- with overlapping date ranges (a data integrity issue, not just a key clash).
-- ---------------------------------------------------------------------------
dedup_flag AS (
    SELECT
        *,
        -- Key-level dedup
        ROW_NUMBER() OVER (
            PARTITION BY ContractPriceKey
            ORDER BY
                CASE
                    WHEN ContractFOBPrice IS NOT NULL
                     AND EffectiveDate   IS NOT NULL
                     AND ExpirationDate  IS NOT NULL
                    THEN 0
                    ELSE 1
                END ASC,
                StagedAt ASC
        ) AS DeduplicationRank,
        COUNT(*) OVER (
            PARTITION BY ContractPriceKey
        ) AS DuplicateCount,

        -- Functional overlap detection:
        -- Count records with the same customer + item/commodity scope
        -- whose date ranges could overlap with this record.
        -- Overlap is confirmed in the Fact build; here we flag for awareness.
        COUNT(*) OVER (
            PARTITION BY
                COALESCE(CustomerID, CustomerHQID),
                COALESCE(ItemID,     CommodityID)
        ) AS ScopeCount

    FROM raw_cast
),

-- ---------------------------------------------------------------------------
-- STEP 3: Derived fields and row-level data quality flags
-- ---------------------------------------------------------------------------
dq_flags AS (
    SELECT
        d.*,

        -- -----------
        -- DERIVED FIELDS
        -- -----------

        -- Contract match tier — based on populated scope fields
        -- This is structural classification only; hierarchy precedence is NOT
        -- applied here. Applied in Fact_ContractPrice build (UNK-001).
        CASE
            WHEN CustomerID  IS NOT NULL AND ItemID      IS NOT NULL THEN 'Tier1_CustomerItem'
            WHEN CustomerHQID IS NOT NULL AND ItemID     IS NOT NULL THEN 'Tier2_HQItem'
            WHEN CustomerHQID IS NOT NULL AND CommodityID IS NOT NULL THEN 'Tier3_HQCommodity'
            ELSE 'Unclassified'
        END                                             AS ContractMatchTier,

        -- Is the contract currently active based on date?
        -- [DIALECT NOTE] CURRENT_DATE is ANSI-compatible.
        CASE
            WHEN EffectiveDate  IS NULL THEN 'UNKNOWN'
            WHEN ExpirationDate IS NULL THEN 'UNKNOWN'
            WHEN CURRENT_DATE BETWEEN EffectiveDate AND ExpirationDate THEN 'Active'
            WHEN CURRENT_DATE > ExpirationDate  THEN 'Expired'
            WHEN CURRENT_DATE < EffectiveDate   THEN 'Future'
            ELSE 'UNKNOWN'
        END                                             AS ContractDateStatus,

        -- -----------
        -- DATA QUALITY FLAGS
        -- -----------

        -- DQ FLAG: Duplicate ContractPriceKey
        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                        AS Flag_DuplicateKey,

        -- DQ FLAG: NULL ContractFOBPrice
        CASE WHEN ContractFOBPrice IS NULL THEN 1 ELSE 0 END
                                                        AS Flag_MissingFOBPrice,

        -- DQ FLAG: Negative ContractFOBPrice (invalid — price must be >= 0)
        CASE
            WHEN ContractFOBPrice IS NOT NULL
             AND ContractFOBPrice < 0
            THEN 1
            ELSE 0
        END                                             AS Flag_NegativeFOBPrice,

        -- DQ FLAG: NULL EffectiveDate
        CASE WHEN EffectiveDate IS NULL THEN 1 ELSE 0 END
                                                        AS Flag_MissingEffectiveDate,

        -- DQ FLAG: NULL ExpirationDate
        CASE WHEN ExpirationDate IS NULL THEN 1 ELSE 0 END
                                                        AS Flag_MissingExpirationDate,

        -- DQ FLAG: Date range inversion (effective > expiration)
        CASE
            WHEN EffectiveDate  IS NOT NULL
             AND ExpirationDate IS NOT NULL
             AND EffectiveDate  > ExpirationDate
            THEN 1
            ELSE 0
        END                                             AS Flag_InvertedDateRange,

        -- DQ FLAG: Expired contract
        CASE
            WHEN ExpirationDate IS NOT NULL
             AND CURRENT_DATE > ExpirationDate
            THEN 1
            ELSE 0
        END                                             AS Flag_ExpiredContract,

        -- DQ FLAG: No customer scope (neither CustomerID nor CustomerHQID)
        CASE
            WHEN CustomerID IS NULL AND CustomerHQID IS NULL THEN 1
            ELSE 0
        END                                             AS Flag_MissingCustomerScope,

        -- DQ FLAG: No product scope (neither ItemID nor CommodityID)
        CASE
            WHEN ItemID IS NULL AND CommodityID IS NULL THEN 1
            ELSE 0
        END                                             AS Flag_MissingProductScope,

        -- DQ FLAG: Potential scope overlap (multiple contracts for same entity)
        CASE WHEN ScopeCount > 1 THEN 1 ELSE 0 END
                                                        AS Flag_PotentialScopeOverlap,

        -- COMPOSITE: Row is clean
        CASE
            WHEN ContractPriceKey IS NULL  THEN 0
            WHEN ContractFOBPrice IS NULL  THEN 0
            WHEN ContractFOBPrice < 0      THEN 0
            WHEN EffectiveDate IS NULL     THEN 0
            WHEN ExpirationDate IS NULL    THEN 0
            WHEN EffectiveDate > ExpirationDate THEN 0
            WHEN CustomerID IS NULL AND CustomerHQID IS NULL THEN 0
            WHEN ItemID IS NULL AND CommodityID IS NULL      THEN 0
            WHEN DuplicateCount > 1        THEN 0
            ELSE 1
        END                                             AS IsCleanRow

    FROM dedup_flag d
)

-- ---------------------------------------------------------------------------
-- STEP 4: Final projection — staging output
-- ---------------------------------------------------------------------------
SELECT
    -- Natural key
    ContractPriceKey,

    -- Contract scope
    CustomerID,
    CustomerHQID,
    ItemID,
    CommodityID,

    -- Pricing
    ContractFOBPrice,

    -- Effective range
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
    Flag_MissingEffectiveDate,
    Flag_MissingExpirationDate,
    Flag_InvertedDateRange,
    Flag_ExpiredContract,
    Flag_MissingCustomerScope,
    Flag_MissingProductScope,
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

-- Contract tier distribution
-- SELECT ContractMatchTier, COUNT(*) AS RecordCount
-- FROM Stg_ContractPricing
-- GROUP BY ContractMatchTier;

-- Date status breakdown
-- SELECT ContractDateStatus, COUNT(*) AS RecordCount
-- FROM Stg_ContractPricing
-- GROUP BY ContractDateStatus;

-- Overlap candidates (review before Fact build)
-- SELECT ContractPriceKey, CustomerID, CustomerHQID, ItemID, CommodityID,
--        EffectiveDate, ExpirationDate, ScopeCount
-- FROM Stg_ContractPricing
-- WHERE Flag_PotentialScopeOverlap = 1
-- ORDER BY COALESCE(CustomerID, CustomerHQID), COALESCE(ItemID, CommodityID);
