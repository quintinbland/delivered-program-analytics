-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_customer_reference.sql
-- INPUT:       Raw_CustomerReference
-- OUTPUT:      Stg_CustomerReference
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per CustomerID. Duplicate CustomerIDs are
--       a data quality issue — flagged and retained.
--   A2: CustomerHQID represents the parent/HQ-level grouping used in
--       contract matching (UNK-001). NULL CustomerHQID is flagged; some
--       customers may legitimately be standalone (no HQ parent), but this
--       cannot be distinguished from missing data at staging without
--       business confirmation. Flagged for review.
--   A3: CustomerStatus drives contract matching eligibility. Expected values
--       are: 'Contract', 'OpenMarket', 'Commit'. Unexpected values are flagged.
--   A4: CustomerStatusKey is a FK to Dim_CustomerStatus. It is passed
--       through unresolved; resolution occurs in the dimension build layer.
--   A5: ShipToID records related to customers are in a separate input source
--       (Raw_ShipToReference). This script does NOT stage ShipTo records.
--   A6: CustomerName is free-text; trimmed but not parsed or validated.
-- OPEN UNKNOWNS AFFECTING THIS SCRIPT:
--   UNK-001: Contract matching hierarchy uses CustomerHQID. NULL handling
--            for HQ-less customers must be confirmed before Fact build.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_CustomerReference AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting and NULL normalization
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Natural key
        CAST(CustomerID          AS VARCHAR(50))   AS CustomerID,

        -- HQ grouping (used in contract matching hierarchy)
        CAST(CustomerHQID        AS VARCHAR(50))   AS CustomerHQID,

        -- Customer descriptors
        TRIM(CAST(CustomerName   AS VARCHAR(500)))  AS CustomerName,
        TRIM(CAST(CustomerHQName AS VARCHAR(500)))  AS CustomerHQName,

        -- Status classification
        CAST(CustomerStatusKey   AS VARCHAR(50))   AS CustomerStatusKey,

        -- Normalized status value for DQ evaluation
        UPPER(TRIM(CAST(CustomerStatus AS VARCHAR(50))))  AS CustomerStatus,

        -- Geographic / operational attributes
        CAST(CustomerRegion      AS VARCHAR(100))  AS CustomerRegion,
        CAST(CustomerSegment     AS VARCHAR(100))  AS CustomerSegment,
        CAST(SalesRepID          AS VARCHAR(50))   AS SalesRepID,

        -- Active status
        CAST(ActiveFlag          AS VARCHAR(10))   AS ActiveFlag,

        -- Batch metadata
        COALESCE(
            CAST(SourceSystem AS VARCHAR(100)),
            'ERP_CUSTOMERREFERENCE'
        )                                           AS SourceSystem,
        COALESCE(
            CAST(BatchID AS VARCHAR(100)),
            CAST(CURRENT_TIMESTAMP AS VARCHAR(30))
        )                                           AS BatchID,
        CURRENT_TIMESTAMP                           AS StagedAt

    FROM Raw_CustomerReference
),

-- ---------------------------------------------------------------------------
-- STEP 2: Deduplication detection
-- Duplicate = same CustomerID appearing more than once.
-- Prefer active customers with CustomerHQID populated.
-- ---------------------------------------------------------------------------
dedup_flag AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY CustomerID
            ORDER BY
                CASE WHEN ActiveFlag = 'Y'        THEN 0 ELSE 1 END ASC,
                CASE WHEN CustomerHQID IS NOT NULL THEN 0 ELSE 1 END ASC,
                StagedAt ASC
        ) AS DeduplicationRank,
        COUNT(*) OVER (
            PARTITION BY CustomerID
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

        -- DQ FLAG: Duplicate CustomerID
        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                    AS Flag_DuplicateKey,

        -- DQ FLAG: NULL CustomerName
        CASE
            WHEN CustomerName IS NULL THEN 1
            WHEN TRIM(CustomerName) = '' THEN 1
            ELSE 0
        END                                         AS Flag_MissingCustomerName,

        -- DQ FLAG: NULL CustomerHQID (may block contract matching at Tier 2/3)
        CASE WHEN CustomerHQID IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingHQID,

        -- DQ FLAG: NULL or unexpected CustomerStatus
        -- Valid values: CONTRACT, OPENMARKET, COMMIT (normalized to uppercase)
        CASE
            WHEN CustomerStatus IS NULL THEN 1
            WHEN CustomerStatus NOT IN ('CONTRACT', 'OPENMARKET', 'COMMIT') THEN 1
            ELSE 0
        END                                         AS Flag_InvalidCustomerStatus,

        -- DQ FLAG: NULL CustomerStatusKey (FK to Dim_CustomerStatus)
        CASE WHEN CustomerStatusKey IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingStatusKey,

        -- DQ FLAG: Inactive customer
        CASE
            WHEN ActiveFlag IS NULL THEN 1
            WHEN ActiveFlag = 'N'   THEN 1
            ELSE 0
        END                                         AS Flag_InactiveCustomer,

        -- DQ FLAG: Contract customer without HQ mapping
        -- Contract customers require HQ for Tier 2/3 contract matching.
        -- NULL HQIDs for contract customers block hierarchy resolution.
        CASE
            WHEN CustomerStatus = 'CONTRACT'
             AND CustomerHQID IS NULL
            THEN 1
            ELSE 0
        END                                         AS Flag_ContractCustomerMissingHQ,

        -- COMPOSITE: Row is clean
        CASE
            WHEN CustomerID IS NULL     THEN 0
            WHEN CustomerName IS NULL   THEN 0
            WHEN TRIM(CustomerName) = '' THEN 0
            WHEN CustomerStatus IS NULL THEN 0
            WHEN CustomerStatus NOT IN ('CONTRACT', 'OPENMARKET', 'COMMIT') THEN 0
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
    CustomerID,

    -- HQ grouping
    CustomerHQID,
    CustomerHQName,

    -- Descriptors
    CustomerName,

    -- Status
    CustomerStatusKey,
    CustomerStatus,

    -- Operational attributes
    CustomerRegion,
    CustomerSegment,
    SalesRepID,
    ActiveFlag,

    -- Deduplication metadata
    DeduplicationRank,
    DuplicateCount,

    -- Data quality flags
    Flag_DuplicateKey,
    Flag_MissingCustomerName,
    Flag_MissingHQID,
    Flag_InvalidCustomerStatus,
    Flag_MissingStatusKey,
    Flag_InactiveCustomer,
    Flag_ContractCustomerMissingHQ,
    IsCleanRow,

    -- Batch metadata
    SourceSystem,
    BatchID,
    StagedAt

FROM dq_flags;

-- =============================================================================
-- POST-LOAD VALIDATION QUERIES
-- =============================================================================

-- Contract customers missing HQ mapping (blocks Tier 2/3 contract resolution)
-- SELECT CustomerID, CustomerName, CustomerStatus, CustomerHQID
-- FROM Stg_CustomerReference
-- WHERE Flag_ContractCustomerMissingHQ = 1;

-- Status distribution
-- SELECT CustomerStatus, COUNT(*) AS CustomerCount
-- FROM Stg_CustomerReference
-- GROUP BY CustomerStatus
-- ORDER BY CustomerCount DESC;

-- Inactive customers present in source
-- SELECT CustomerID, CustomerName, CustomerStatus
-- FROM Stg_CustomerReference
-- WHERE Flag_InactiveCustomer = 1;
