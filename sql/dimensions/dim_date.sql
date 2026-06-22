-- =============================================================================
-- MODULE:      Dimension Build
-- SCRIPT:      dim_date.sql
-- INPUT:       Generated (no source table dependency)
-- OUTPUT:      Dim_Date
-- DIALECT:     T-SQL / Snowflake variants provided separately below
-- VERSION:     1.0.0
-- DEPENDENCIES: None
-- BUILD ORDER:  3 of 7 — no upstream dimension dependencies
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Date range covers 2020-01-01 through 2030-12-31. Extend as needed.
--   A2: DateKey format is INTEGER YYYYMMDD (e.g., 20240115).
--       This format is used as the FK in all fact tables.
--   A3: Fiscal calendar fields (FiscalYear, FiscalQuarter, FiscalPeriod)
--       are populated using a fiscal year start of October 1.
--       ASSUMPTION — fiscal year start month is UNKNOWN. October 1 is a
--       candidate value. Flag: CANDIDATE_FISCAL_START.
--   A4: A default/unknown row (DateKey = -1) is inserted for NULL date FKs.
--   A5: IsHoliday is set to 0 for all rows. Holiday population requires a
--       separate holiday reference table not currently in scope.
--   A6: Week numbering follows ISO 8601 (week starts Monday).
--       [DIALECT NOTE] ISO week functions vary: see dialect-specific blocks.
-- =============================================================================

-- =============================================================================
-- SNOWFLAKE VERSION
-- Uses a generator sequence to produce one row per date.
-- =============================================================================

CREATE OR REPLACE TABLE Dim_Date AS

WITH

date_spine AS (
    -- [DIALECT: SNOWFLAKE] GENERATOR produces N rows; DATEADD shifts from anchor.
    SELECT
        DATEADD(DAY, SEQ4(), '2020-01-01'::DATE) AS CalendarDate
    FROM TABLE(GENERATOR(ROWCOUNT => 4018))  -- 2020-01-01 to 2030-12-31 = 4018 days
    WHERE DATEADD(DAY, SEQ4(), '2020-01-01'::DATE) <= '2030-12-31'::DATE
),

date_attributes AS (
    SELECT
        CalendarDate,

        -- Integer key
        CAST(TO_CHAR(CalendarDate, 'YYYYMMDD') AS INTEGER)  AS DateKey,

        -- Calendar year/quarter/month/week
        YEAR(CalendarDate)                                   AS CalendarYear,
        QUARTER(CalendarDate)                                AS CalendarQuarter,
        MONTH(CalendarDate)                                  AS CalendarMonth,
        TO_CHAR(CalendarDate, 'Month')                       AS MonthName,
        DAYOFWEEK(CalendarDate)                              AS DayOfWeek,        -- 0=Sunday in Snowflake
        TO_CHAR(CalendarDate, 'Day')                         AS DayName,
        DAY(CalendarDate)                                    AS DayOfMonth,
        DAYOFYEAR(CalendarDate)                              AS DayOfYear,
        WEEKOFYEAR(CalendarDate)                             AS WeekOfYear,       -- ISO week in Snowflake

        -- Derived calendar flags
        CASE WHEN DAYOFWEEK(CalendarDate) IN (0, 6) THEN 1 ELSE 0 END  AS IsWeekend,
        0                                                    AS IsHoliday,        -- ASSUMPTION A5

        -- Period labels for reporting
        TO_CHAR(CalendarDate, 'YYYY-MM')                     AS YearMonthLabel,
        'Q' || QUARTER(CalendarDate) || ' ' || YEAR(CalendarDate) AS QuarterLabel,

        -- Fiscal calendar (CANDIDATE: fiscal year starts October 1 — UNK-004 adjacent)
        -- Fiscal year: if month >= 10, fiscal year = calendar year + 1, else calendar year
        CASE
            WHEN MONTH(CalendarDate) >= 10
            THEN YEAR(CalendarDate) + 1
            ELSE YEAR(CalendarDate)
        END                                                  AS FiscalYear,

        CASE
            WHEN MONTH(CalendarDate) IN (10, 11, 12) THEN 1
            WHEN MONTH(CalendarDate) IN (1,  2,  3)  THEN 2
            WHEN MONTH(CalendarDate) IN (4,  5,  6)  THEN 3
            WHEN MONTH(CalendarDate) IN (7,  8,  9)  THEN 4
        END                                                  AS FiscalQuarter,

        -- Fiscal period = fiscal month number (Oct=1 through Sep=12)
        MOD(MONTH(CalendarDate) - 10 + 12, 12) + 1          AS FiscalPeriod,

        -- Candidate flag: all fiscal fields are provisional until UNK-004 confirmed
        1                                                    AS Flag_CandidateFiscalCalendar

    FROM date_spine
)

-- Default/unknown member
SELECT
    -1                  AS DateKey,
    NULL                AS CalendarDate,
    -1                  AS CalendarYear,
    -1                  AS CalendarQuarter,
    -1                  AS CalendarMonth,
    'Unknown'           AS MonthName,
    -1                  AS DayOfWeek,
    'Unknown'           AS DayName,
    -1                  AS DayOfMonth,
    -1                  AS DayOfYear,
    -1                  AS WeekOfYear,
    0                   AS IsWeekend,
    0                   AS IsHoliday,
    'Unknown'           AS YearMonthLabel,
    'Unknown'           AS QuarterLabel,
    -1                  AS FiscalYear,
    -1                  AS FiscalQuarter,
    -1                  AS FiscalPeriod,
    1                   AS Flag_CandidateFiscalCalendar

UNION ALL

SELECT
    DateKey,
    CalendarDate,
    CalendarYear,
    CalendarQuarter,
    CalendarMonth,
    MonthName,
    DayOfWeek,
    DayName,
    DayOfMonth,
    DayOfYear,
    WeekOfYear,
    IsWeekend,
    IsHoliday,
    YearMonthLabel,
    QuarterLabel,
    FiscalYear,
    FiscalQuarter,
    FiscalPeriod,
    Flag_CandidateFiscalCalendar

FROM date_attributes;


-- =============================================================================
-- T-SQL EQUIVALENT (SQL SERVER)
-- Replace the Snowflake block above with this block for T-SQL environments.
-- =============================================================================
/*
WITH date_spine AS (
    SELECT CAST('2020-01-01' AS DATE) AS CalendarDate
    UNION ALL
    SELECT DATEADD(DAY, 1, CalendarDate)
    FROM date_spine
    WHERE CalendarDate < '2030-12-31'
),
date_attributes AS (
    SELECT
        CalendarDate,
        CAST(CONVERT(VARCHAR, CalendarDate, 112) AS INT)    AS DateKey,
        YEAR(CalendarDate)                                  AS CalendarYear,
        DATEPART(QUARTER, CalendarDate)                     AS CalendarQuarter,
        MONTH(CalendarDate)                                 AS CalendarMonth,
        DATENAME(MONTH, CalendarDate)                       AS MonthName,
        DATEPART(WEEKDAY, CalendarDate)                     AS DayOfWeek,
        DATENAME(WEEKDAY, CalendarDate)                     AS DayName,
        DAY(CalendarDate)                                   AS DayOfMonth,
        DATEPART(DAYOFYEAR, CalendarDate)                   AS DayOfYear,
        DATEPART(ISO_WEEK, CalendarDate)                    AS WeekOfYear,
        CASE WHEN DATEPART(WEEKDAY, CalendarDate) IN (1,7) THEN 1 ELSE 0 END AS IsWeekend,
        0                                                   AS IsHoliday,
        FORMAT(CalendarDate, 'yyyy-MM')                     AS YearMonthLabel,
        'Q' + CAST(DATEPART(QUARTER,CalendarDate) AS VARCHAR) + ' ' + CAST(YEAR(CalendarDate) AS VARCHAR) AS QuarterLabel,
        CASE WHEN MONTH(CalendarDate) >= 10 THEN YEAR(CalendarDate)+1 ELSE YEAR(CalendarDate) END AS FiscalYear,
        CASE
            WHEN MONTH(CalendarDate) IN (10,11,12) THEN 1
            WHEN MONTH(CalendarDate) IN (1,2,3)    THEN 2
            WHEN MONTH(CalendarDate) IN (4,5,6)    THEN 3
            WHEN MONTH(CalendarDate) IN (7,8,9)    THEN 4
        END                                                 AS FiscalQuarter,
        ((MONTH(CalendarDate) - 10 + 12) % 12) + 1         AS FiscalPeriod,
        1                                                   AS Flag_CandidateFiscalCalendar
    FROM date_spine
)
SELECT * FROM date_attributes
OPTION (MAXRECURSION 5000);
*/

-- ---------------------------------------------------------------------------
-- POST-LOAD VALIDATION
-- ---------------------------------------------------------------------------

-- Row count (expect 4019: 4018 calendar days + 1 default row)
-- SELECT COUNT(*) FROM Dim_Date;

-- Confirm no duplicate DateKeys
-- SELECT DateKey, COUNT(*) FROM Dim_Date
-- GROUP BY DateKey HAVING COUNT(*) > 1;

-- Confirm fiscal period coverage
-- SELECT FiscalYear, FiscalQuarter, COUNT(*) AS Days
-- FROM Dim_Date WHERE DateKey <> -1
-- GROUP BY FiscalYear, FiscalQuarter
-- ORDER BY FiscalYear, FiscalQuarter;

-- Fact table orphan check (run after fact tables are loaded)
-- SELECT DISTINCT f.ShipDateKey
-- FROM Fact_SalesOrderLine f
-- LEFT JOIN Dim_Date d ON f.ShipDateKey = d.DateKey
-- WHERE d.DateKey IS NULL;
