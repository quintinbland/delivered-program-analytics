-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_carrier.sql
-- INPUT:       Stg_LoadFreight (distinct CarrierID values)
-- OUTPUT:      Dim_Carrier
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES: Stg_LoadFreight (Module 1)
-- BUILD ORDER:  4 of 7 — depends on Stg_LoadFreight only
-- =============================================================================
-- ASSUMPTIONS:
--   A1: No dedicated Raw_CarrierReference table exists in the current data
--       model. Dim_Carrier is derived from distinct CarrierID values observed
--       in Stg_LoadFreight. If a carrier reference table is added in a future
--       iteration, this script must be rebuilt against that source.
--   A2: CarrierName, CarrierType, and CarrierMode are NOT available in
--       Stg_LoadFreight. These attributes default to NULL and must be
--       enriched from an external carrier reference if available.
--   A3: A carrier that appears in Stg_LoadFreight with Flag_MissingCarrierID = 1
--       is excluded from dimension population. Those rows resolve to the
--       default member (CarrierKey = -1).
--   A4: CarrierKey = -1 is the default/unknown member for NULL CarrierID FKs.
--   A5: IsActive defaults to 1 for all carriers derived from load data.
--       A carrier observed in freight data is presumed active unless
--       explicitly flagged otherwise in a future carrier reference table.
-- =============================================================================

CREATE OR REPLACE TABLE Dim_Carrier AS

WITH

-- Distinct carriers from staging (exclude NULL CarrierID rows)
carrier_source AS (
    SELECT DISTINCT
        CarrierID,
        NULL        AS CarrierName,       -- UNKNOWN: no carrier reference table
        NULL        AS CarrierType,       -- UNKNOWN: no carrier reference table
        NULL        AS CarrierMode,       -- UNKNOWN: no carrier reference table (e.g., 'TL', 'LTL', 'INTERMODAL')
        1           AS IsActive,
        MIN(LoadDate) OVER (PARTITION BY CarrierID) AS FirstObservedDate,
        MAX(LoadDate) OVER (PARTITION BY CarrierID) AS LastObservedDate
    FROM Stg_LoadFreight
    WHERE CarrierID IS NOT NULL
      AND Flag_MissingCarrierID = 0
      AND IsCleanRow = 1
),

-- Surrogate key assignment
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
    -1              AS CarrierKey,
    'UNKNOWN'       AS CarrierID,
    'Unknown'       AS CarrierName,
    NULL            AS CarrierType,
    NULL            AS CarrierMode,
    0               AS IsActive,
    NULL            AS FirstObservedDate,
    NULL            AS LastObservedDate,
    'SYSTEM'        AS SourceSystem,
    CURRENT_TIMESTAMP AS LoadedAt

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

-- ---------------------------------------------------------------------------
-- POST-LOAD VALIDATION
-- ---------------------------------------------------------------------------

-- Carriers in freight staging that did not resolve to dimension
-- SELECT DISTINCT s.CarrierID
-- FROM Stg_LoadFreight s
-- LEFT JOIN Dim_Carrier c ON s.CarrierID = c.CarrierID
-- WHERE c.CarrierKey IS NULL
--   AND s.CarrierID IS NOT NULL;

-- Carriers with NULL enrichment fields (expected until reference table added)
-- SELECT CarrierKey, CarrierID, CarrierName, CarrierType, CarrierMode
-- FROM Dim_Carrier
-- WHERE CarrierName IS NULL AND CarrierKey <> -1;
