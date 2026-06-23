-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_carrier.sql
-- INPUT:       Stg_LoadFreight (distinct CarrierID values)
-- OUTPUT:      Dim_Carrier
-- DIALECT:     ANSI SQL (DuckDB / T-SQL / Snowflake compatible)
-- VERSION:     1.0.1 — fixed window function + DISTINCT incompatibility in DuckDB
--              MIN/MAX OVER (PARTITION BY) moved to subquery before DISTINCT
-- DEPENDENCIES: Stg_LoadFreight (Module 1)
-- BUILD ORDER:  4 of 7 — depends on Stg_LoadFreight only
-- =============================================================================

CREATE OR REPLACE TABLE Dim_Carrier AS

WITH

-- Step 1: Compute per-carrier date range before deduplication
carrier_with_dates AS (
    SELECT
        CarrierID,
        MIN(LoadDate) AS FirstObservedDate,
        MAX(LoadDate) AS LastObservedDate
    FROM Stg_LoadFreight
    WHERE CarrierID IS NOT NULL
      AND Flag_MissingCarrierID = 0
      AND IsCleanRow = 1
    GROUP BY CarrierID
),

-- Step 2: Distinct carriers joined to date range
carrier_source AS (
    SELECT
        d.CarrierID,
        NULL        AS CarrierName,
        NULL        AS CarrierType,
        NULL        AS CarrierMode,
        1           AS IsActive,
        d.FirstObservedDate,
        d.LastObservedDate
    FROM carrier_with_dates d
),

-- Step 3: Surrogate key assignment
keyed AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY CarrierID ASC) AS CarrierKey,
        CarrierID,
        CarrierName,
        CarrierType,
        CarrierMode,
        IsActive,
        FirstObservedDate,
        LastObservedDate
    FROM carrier_source
)

-- Default member
SELECT
    -1                  AS CarrierKey,
    'UNKNOWN'           AS CarrierID,
    'Unknown'           AS CarrierName,
    NULL                AS CarrierType,
    NULL                AS CarrierMode,
    0                   AS IsActive,
    NULL                AS FirstObservedDate,
    NULL                AS LastObservedDate,
    'SYSTEM'            AS SourceSystem,
    CURRENT_TIMESTAMP   AS LoadedAt

UNION ALL

SELECT
    CarrierKey,
    CarrierID,
    CarrierName,
    CarrierType,
    CarrierMode,
    IsActive,
    FirstObservedDate,
    LastObservedDate,
    'Stg_LoadFreight'   AS SourceSystem,
    CURRENT_TIMESTAMP   AS LoadedAt

FROM keyed;

-- =============================================================================
-- POST-LOAD VALIDATION
-- Expected: 1 default row (CarrierKey = -1) + one row per distinct CarrierID
-- =============================================================================
-- SELECT CarrierKey, CarrierID, FirstObservedDate, LastObservedDate
-- FROM Dim_Carrier ORDER BY CarrierKey;
