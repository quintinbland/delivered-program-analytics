-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_shipto.sql
-- INPUT:       Raw_ShipToReference
-- OUTPUT:      Dim_ShipTo
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES: None
-- BUILD ORDER:  6 of 7 — no upstream dimension dependencies
-- =============================================================================
-- ASSUMPTIONS:
--   A1: ShipToID is the natural key. One row per ShipToID in output.
--   A2: A ShipTo location may be associated with multiple CustomerIDs
--       (e.g., a shared distribution center). The CustomerID field on
--       this dimension represents the PRIMARY customer owner of the
--       ShipTo location, not an exclusive relationship.
--   A3: Geographic fields (City, State, ZipCode, Region) are passed
--       through as-is. No geocoding or address validation is performed
--       at this layer.
--   A4: ShipToKey = -1 is the default/unknown member.
--   A5: DeliveryDayOfWeek is expected as a comma-delimited string
--       (e.g., 'MON,WED,FRI') if present. Not parsed at this layer.
-- =============================================================================

CREATE OR REPLACE TABLE Dim_ShipTo AS

WITH

raw_cast AS (
    SELECT
        CAST(ShipToID            AS VARCHAR(50))    AS ShipToID,
        CAST(CustomerID          AS VARCHAR(50))    AS CustomerID,
        TRIM(CAST(ShipToName     AS VARCHAR(500)))  AS ShipToName,
        TRIM(CAST(AddressLine1   AS VARCHAR(200)))  AS AddressLine1,
        TRIM(CAST(AddressLine2   AS VARCHAR(200)))  AS AddressLine2,
        TRIM(CAST(City           AS VARCHAR(100)))  AS City,
        TRIM(CAST(StateProvince  AS VARCHAR(50)))   AS StateProvince,
        TRIM(CAST(ZipPostalCode  AS VARCHAR(20)))   AS ZipPostalCode,
        TRIM(CAST(Country        AS VARCHAR(50)))   AS Country,
        TRIM(CAST(Region         AS VARCHAR(100)))  AS Region,
        CAST(DeliveryDayOfWeek   AS VARCHAR(50))    AS DeliveryDayOfWeek,
        CAST(ActiveFlag          AS VARCHAR(10))    AS ActiveFlag,
        CURRENT_TIMESTAMP                           AS LoadedAt
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
        ROW_NUMBER() OVER (ORDER BY ShipToID ASC)  AS ShipToKey,
        ShipToID,
        CustomerID,
        ShipToName,
        AddressLine1,
        AddressLine2,
        City,
        StateProvince,
        ZipPostalCode,
        COALESCE(NULLIF(TRIM(Country), ''), 'UNKNOWN') AS Country,
        Region,
        DeliveryDayOfWeek,
        CASE WHEN ActiveFlag = 'Y' THEN 1 ELSE 0 END  AS IsActive,
        DuplicateCount,
        LoadedAt
    FROM dedup
    WHERE RowRank = 1
)

-- Default member
SELECT
    -1              AS ShipToKey,
    'UNKNOWN'       AS ShipToID,
    NULL            AS CustomerID,
    'Unknown'       AS ShipToName,
    NULL            AS AddressLine1,
    NULL            AS AddressLine2,
    NULL            AS City,
    NULL            AS StateProvince,
    NULL            AS ZipPostalCode,
    'UNKNOWN'       AS Country,
    NULL            AS Region,
    NULL            AS DeliveryDayOfWeek,
    0               AS IsActive,
    0               AS DuplicateCount,
    CURRENT_TIMESTAMP AS LoadedAt,
    'SYSTEM'        AS SourceSystem

UNION ALL

SELECT
    ShipToKey,
    ShipToID,
    CustomerID,
    ShipToName,
    AddressLine1,
    AddressLine2,
    City,
    StateProvince,
    ZipPostalCode,
    Country,
    Region,
    DeliveryDayOfWeek,
    IsActive,
    DuplicateCount,
    LoadedAt,
    'Raw_ShipToReference' AS SourceSystem

FROM keyed;

-- ---------------------------------------------------------------------------
-- POST-LOAD VALIDATION
-- ---------------------------------------------------------------------------

-- ShipTo IDs in transactions that do not resolve to dimension
-- SELECT DISTINCT s.ShipToID
-- FROM Stg_SalesOrderLine s
-- LEFT JOIN Dim_ShipTo st ON s.ShipToID = st.ShipToID
-- WHERE st.ShipToKey IS NULL AND s.ShipToID IS NOT NULL;

-- Duplicate ShipToID source records (informational)
-- SELECT ShipToID, DuplicateCount
-- FROM Dim_ShipTo
-- WHERE DuplicateCount > 1 AND ShipToKey <> -1;
