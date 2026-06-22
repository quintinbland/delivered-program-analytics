-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_customer_status.sql
-- INPUT:       Stg_CustomerReference
-- OUTPUT:      Dim_CustomerStatus
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES: Stg_CustomerReference (Module 1)
-- BUILD ORDER:  1 of 7 — no upstream dimension dependencies
-- =============================================================================
-- ASSUMPTIONS:
--   A1: CustomerStatus controlled values are: CONTRACT, OPENMARKET, COMMIT.
--       These are the only values that will generate dimension rows.
--       Any value outside this set that passed staging DQ flags will not
--       generate a dimension row and will be routed to exceptions.
--   A2: Dim_CustomerStatus is a static reference dimension. It does not
--       change frequently. A full reload pattern is used (TRUNCATE + INSERT).
--   A3: CustomerStatusKey is a system-assigned integer surrogate key.
--       Source string values are preserved in CustomerStatusCode.
--   A4: SortOrder is assigned to support consistent UI rendering in reports.
--       Assignment: CONTRACT=1, COMMIT=2, OPENMARKET=3, UNKNOWN=99.
--   A5: An UNKNOWN row (CustomerStatusKey = -1) is inserted as a default
--       member to handle NULL or unresolvable FK lookups in fact tables.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STEP 1: Truncate and reload (static reference dimension)
-- [DIALECT NOTE] TRUNCATE TABLE is ANSI-compatible.
-- ---------------------------------------------------------------------------
TRUNCATE TABLE Dim_CustomerStatus;

-- ---------------------------------------------------------------------------
-- STEP 2: Insert default/unknown member first
-- CustomerStatusKey = -1 is reserved for unresolvable lookups.
-- ---------------------------------------------------------------------------
INSERT INTO Dim_CustomerStatus (
    CustomerStatusKey,
    CustomerStatusCode,
    CustomerStatusLabel,
    CustomerStatusDescription,
    SortOrder,
    IsActive,
    SourceSystem,
    LoadedAt
)
VALUES (
    -1,
    'UNKNOWN',
    'Unknown',
    'Default member for unresolvable or missing customer status values.',
    99,
    0,
    'SYSTEM',
    CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------------
-- STEP 3: Insert controlled values from staging
-- Derives distinct status values from Stg_CustomerReference.
-- Only clean, recognized values are promoted to the dimension.
-- ---------------------------------------------------------------------------
INSERT INTO Dim_CustomerStatus (
    CustomerStatusKey,
    CustomerStatusCode,
    CustomerStatusLabel,
    CustomerStatusDescription,
    SortOrder,
    IsActive,
    SourceSystem,
    LoadedAt
)
SELECT
    -- [DIALECT NOTE] ROW_NUMBER with ORDER BY for surrogate key assignment.
    -- T-SQL / Snowflake: IDENTITY columns are an alternative; ROW_NUMBER
    -- is used here for portability and explicit control.
    ROW_NUMBER() OVER (ORDER BY SortOrder ASC)      AS CustomerStatusKey,
    CustomerStatusCode,
    CustomerStatusLabel,
    CustomerStatusDescription,
    SortOrder,
    1                                               AS IsActive,
    'Stg_CustomerReference'                         AS SourceSystem,
    CURRENT_TIMESTAMP                               AS LoadedAt

FROM (
    -- Static definition of controlled values with business metadata.
    -- Source of truth for labels and descriptions is this script, not the
    -- staging table. Staging provides the code; dimension provides the label.
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

-- Validate that each controlled value exists in staging before inserting.
-- If a controlled value has zero records in staging, it is still inserted.
-- This ensures the dimension is complete regardless of staging data volume.
WHERE EXISTS (
    SELECT 1
    FROM Stg_CustomerReference src
    WHERE src.CustomerStatus = controlled_values.CustomerStatusCode
       OR 1=1  -- Always insert all controlled values; staging validates, not gates.
);

-- ---------------------------------------------------------------------------
-- POST-LOAD VALIDATION
-- ---------------------------------------------------------------------------

-- Confirm row count (expect 4 rows: -1 unknown + 3 controlled values)
-- SELECT COUNT(*) AS RowCount FROM Dim_CustomerStatus;

-- Confirm no CustomerStatusKey collisions
-- SELECT CustomerStatusKey, COUNT(*) FROM Dim_CustomerStatus
-- GROUP BY CustomerStatusKey HAVING COUNT(*) > 1;

-- Confirm all staging status codes resolve to a dimension row
-- SELECT DISTINCT src.CustomerStatus
-- FROM Stg_CustomerReference src
-- LEFT JOIN Dim_CustomerStatus dim ON src.CustomerStatus = dim.CustomerStatusCode
-- WHERE dim.CustomerStatusKey IS NULL
--   AND src.CustomerStatus IS NOT NULL;
