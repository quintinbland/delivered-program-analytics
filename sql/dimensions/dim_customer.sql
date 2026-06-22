-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_customer.sql
-- INPUT:       Stg_CustomerReference
-- OUTPUT:      Dim_Customer
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES: Stg_CustomerReference (Module 1), Dim_CustomerStatus (this module)
-- BUILD ORDER:  7 of 7 — Dim_CustomerStatus must exist before this script runs
-- =============================================================================
-- ASSUMPTIONS:
--   A1: CustomerID is the natural key. One row per CustomerID in output.
--       Duplicate CustomerIDs use the row with DeduplicationRank = 1
--       from Stg_CustomerReference.
--   A2: CustomerHQID represents the HQ-level parent used in contract matching
--       (UNK-001). NULL CustomerHQID is valid (standalone customer — confirmed
--       in Session 5 review). These rows resolve without error.
--   A3: CustomerKey = -1 is the default/unknown member for unresolvable
--       CustomerID FK lookups in fact tables.
--   A4: CustomerStatusKey is resolved via join to Dim_CustomerStatus using
--       CustomerStatus (string code). Unresolvable status codes default to
--       CustomerStatusKey = -1.
--   A5: Inactive customers (Flag_InactiveCustomer = 1 in staging) are included
--       in the dimension. They may appear in historical transaction data.
--       IsActive = 0 flags them for filtering in active-customer reports.
--   A6: HQ-level grouping (CustomerHQID, CustomerHQName) is denormalized onto
--       this dimension to support contract matching without a separate HQ join.
-- =============================================================================

CREATE OR REPLACE TABLE Dim_Customer AS

WITH

-- Staging input: one row per CustomerID, best available record
staged AS (
    SELECT
        CustomerID,
        CustomerHQID,
        CustomerHQName,
        CustomerName,
        CustomerStatusKey       AS CustomerStatusKey_Source,
        CustomerStatus          AS CustomerStatusCode,
        CustomerRegion,
        CustomerSegment,
        SalesRepID,
        ActiveFlag,
        Flag_DuplicateKey,
        Flag_MissingHQID,
        Flag_InvalidCustomerStatus,
        Flag_ContractCustomerMissingHQ,
        Flag_InactiveCustomer,
        IsCleanRow
    FROM Stg_CustomerReference
    WHERE DeduplicationRank = 1
),

-- Resolve CustomerStatus string code to Dim_CustomerStatus surrogate key
resolved AS (
    SELECT
        s.*,
        COALESCE(cs.CustomerStatusKey, -1)          AS CustomerStatusKey,

        -- Flag: status resolved to default member
        CASE
            WHEN COALESCE(cs.CustomerStatusKey, -1) = -1 THEN 1
            ELSE 0
        END                                         AS Flag_StatusDefaulted

    FROM staged s
    LEFT JOIN Dim_CustomerStatus cs
        ON s.CustomerStatusCode = cs.CustomerStatusCode
       AND cs.CustomerStatusKey <> -1
),

keyed AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY CustomerID ASC)  AS CustomerKey,
        *
    FROM resolved
)

-- Default member
SELECT
    -1              AS CustomerKey,
    'UNKNOWN'       AS CustomerID,
    NULL            AS CustomerHQID,
    'Unknown'       AS CustomerHQName,
    'Unknown'       AS CustomerName,
    NULL            AS CustomerStatusKey_Source,
    'UNKNOWN'       AS CustomerStatusCode,
    -1              AS CustomerStatusKey,
    NULL            AS CustomerRegion,
    NULL            AS CustomerSegment,
    NULL            AS SalesRepID,
    'N'             AS ActiveFlag,
    0               AS IsActive,
    0               AS Flag_DuplicateKey,
    0               AS Flag_MissingHQID,
    0               AS Flag_InvalidCustomerStatus,
    0               AS Flag_ContractCustomerMissingHQ,
    0               AS Flag_InactiveCustomer,
    0               AS Flag_StatusDefaulted,
    0               AS IsCleanRow,
    'SYSTEM'        AS SourceSystem,
    CURRENT_TIMESTAMP AS LoadedAt

UNION ALL

SELECT
    CustomerKey,
    CustomerID,
    CustomerHQID,
    CustomerHQName,
    CustomerName,
    CustomerStatusKey_Source,
    CustomerStatusCode,
    CustomerStatusKey,
    CustomerRegion,
    CustomerSegment,
    SalesRepID,
    ActiveFlag,
    CASE WHEN ActiveFlag = 'Y' THEN 1 ELSE 0 END    AS IsActive,
    Flag_DuplicateKey,
    Flag_MissingHQID,
    Flag_InvalidCustomerStatus,
    Flag_ContractCustomerMissingHQ,
    Flag_InactiveCustomer,
    Flag_StatusDefaulted,
    IsCleanRow,
    'Stg_CustomerReference'                         AS SourceSystem,
    CURRENT_TIMESTAMP                               AS LoadedAt

FROM keyed;

-- ---------------------------------------------------------------------------
-- POST-LOAD VALIDATION
-- ---------------------------------------------------------------------------

-- Customers whose status defaulted to unknown
-- SELECT CustomerKey, CustomerID, CustomerStatusCode, CustomerStatusKey
-- FROM Dim_Customer
-- WHERE Flag_StatusDefaulted = 1 AND CustomerKey <> -1;

-- Contract customers without HQ mapping (informational — standalone confirmed valid)
-- SELECT CustomerKey, CustomerID, CustomerName, CustomerHQID
-- FROM Dim_Customer
-- WHERE Flag_ContractCustomerMissingHQ = 1 AND CustomerKey <> -1;

-- Transaction CustomerIDs not in dimension (run after fact tables loaded)
-- SELECT DISTINCT f.CustomerID
-- FROM Stg_SalesOrderLine f
-- LEFT JOIN Dim_Customer c ON f.CustomerID = c.CustomerID
-- WHERE c.CustomerKey IS NULL AND f.CustomerID IS NOT NULL;

-- Status distribution across active customers
-- SELECT cs.CustomerStatusLabel, COUNT(*) AS CustomerCount
-- FROM Dim_Customer c
-- JOIN Dim_CustomerStatus cs ON c.CustomerStatusKey = cs.CustomerStatusKey
-- WHERE c.IsActive = 1 AND c.CustomerKey <> -1
-- GROUP BY cs.CustomerStatusLabel;
