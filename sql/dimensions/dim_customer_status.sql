-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_customer_status.sql
-- INPUT:       Stg_CustomerReference
-- OUTPUT:      Dim_CustomerStatus
-- DIALECT:     ANSI SQL (DuckDB / T-SQL / Snowflake compatible)
-- VERSION:     1.0.1 — replaced TRUNCATE+INSERT with CREATE OR REPLACE TABLE AS
--              DuckDB requires table to exist before TRUNCATE; pattern aligned
--              with all other dimension scripts for consistency.
-- DEPENDENCIES: Stg_CustomerReference (Module 1)
-- BUILD ORDER:  1 of 7 — no upstream dimension dependencies
-- =============================================================================
-- ASSUMPTIONS:
--   A1: CustomerStatus controlled values: CONTRACT, OPENMARKET, COMMIT.
--   A2: Full reload on every run via CREATE OR REPLACE TABLE.
--   A3: CustomerStatusKey is a system-assigned integer surrogate key.
--   A4: SortOrder: CONTRACT=1, COMMIT=2, OPENMARKET=3, UNKNOWN=99.
--   A5: Default/unknown member: CustomerStatusKey = -1.
-- =============================================================================

CREATE OR REPLACE TABLE Dim_CustomerStatus AS

SELECT
    CustomerStatusKey,
    CustomerStatusCode,
    CustomerStatusLabel,
    CustomerStatusDescription,
    SortOrder,
    IsActive,
    SourceSystem,
    CURRENT_TIMESTAMP AS LoadedAt

FROM (

    -- Default/unknown member
    SELECT
        -1                                                      AS CustomerStatusKey,
        'UNKNOWN'                                               AS CustomerStatusCode,
        'Unknown'                                               AS CustomerStatusLabel,
        'Default member for unresolvable or missing status.'    AS CustomerStatusDescription,
        99                                                      AS SortOrder,
        0                                                       AS IsActive,
        'SYSTEM'                                                AS SourceSystem

    UNION ALL

    -- Controlled values with surrogate key assigned via ROW_NUMBER
    SELECT
        ROW_NUMBER() OVER (ORDER BY SortOrder ASC)              AS CustomerStatusKey,
        CustomerStatusCode,
        CustomerStatusLabel,
        CustomerStatusDescription,
        SortOrder,
        1                                                       AS IsActive,
        'Stg_CustomerReference'                                 AS SourceSystem

    FROM (
        SELECT 'CONTRACT'   AS CustomerStatusCode,
               'Contract'   AS CustomerStatusLabel,
               'Customer is on a negotiated contract pricing agreement.' AS CustomerStatusDescription,
               1            AS SortOrder
        UNION ALL
        SELECT 'COMMIT',
               'Commit',
               'Customer operates under a volume commitment arrangement.',
               2
        UNION ALL
        SELECT 'OPENMARKET',
               'Open Market',
               'Customer purchases at open market (non-contract) pricing.',
               3
    ) controlled_values

) all_rows;

-- =============================================================================
-- POST-LOAD VALIDATION
-- Expected: 4 rows (CustomerStatusKey: -1, 1, 2, 3)
-- =============================================================================
-- SELECT CustomerStatusKey, CustomerStatusCode, CustomerStatusLabel
-- FROM Dim_CustomerStatus
-- ORDER BY CustomerStatusKey;
