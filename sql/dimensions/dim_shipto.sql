-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_shipto.sql
-- INPUT:       Raw_ShipToReference
-- OUTPUT:      Dim_ShipTo
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     1.0.1 — DuckDB UNION ALL NULL cast fix (2026-06-23)
-- =============================================================================
-- CHANGE LOG (v1.0.1):
--   - Added explicit CAST(NULL AS VARCHAR) on all nullable columns in the
--     default member row. DuckDB requires typed NULLs in UNION ALL when the
--     NULL appears in the first SELECT of the union.
--   - Raw_ShipToReference is empty with real data (no ShipTo source available).
--     Dim_ShipTo will contain only the default member (-1 row).
--     All fact rows will carry ShipToKey = -1. This is expected behavior.
-- =============================================================================

CREATE OR REPLACE TABLE Dim_ShipTo AS

WITH

raw_cast AS (
    SELECT
        CAST(ShipToID           AS VARCHAR)     AS ShipToID,
        CAST(CustomerID         AS VARCHAR)     AS CustomerID,
        TRIM(CAST(ShipToName    AS VARCHAR))    AS ShipToName,
        TRIM(CAST(City          AS VARCHAR))    AS City,
        TRIM(CAST(StateProvince AS VARCHAR))    AS StateProvince,
        CAST(ActiveFlag         AS VARCHAR)     AS ActiveFlag,
        CURRENT_TIMESTAMP                       AS LoadedAt
    FROM Raw_ShipToReference
),

dedup AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY ShipToID
            ORDER BY
                CASE WHEN ActiveFlag = 'Y' THEN 0 ELSE 1 END ASC,
                LoadedAt ASC
        ) AS RowRank,
        COUNT(*) OVER (PARTITION BY ShipToID) AS DuplicateCount
    FROM raw_cast
),

keyed AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY ShipToID ASC)   AS ShipToKey,
        ShipToID,
        CustomerID,
        ShipToName,
        City,
        StateProvince,
        CASE WHEN ActiveFlag = 'Y' THEN 1 ELSE 0 END AS IsActive,
        DuplicateCount,
        LoadedAt
    FROM dedup
    WHERE RowRank = 1
)

-- Default member — explicit CAST(NULL AS VARCHAR) required by DuckDB
SELECT
    -1                          AS ShipToKey,
    'UNKNOWN'                   AS ShipToID,
    CAST(NULL AS VARCHAR)       AS CustomerID,
    'Unknown'                   AS ShipToName,
    CAST(NULL AS VARCHAR)       AS City,
    CAST(NULL AS VARCHAR)       AS StateProvince,
    0                           AS IsActive,
    0                           AS DuplicateCount,
    CURRENT_TIMESTAMP           AS LoadedAt,
    'SYSTEM'                    AS SourceSystem

UNION ALL

SELECT
    ShipToKey,
    ShipToID,
    CustomerID,
    ShipToName,
    City,
    StateProvince,
    IsActive,
    DuplicateCount,
    LoadedAt,
    'Raw_ShipToReference'       AS SourceSystem

FROM keyed;
