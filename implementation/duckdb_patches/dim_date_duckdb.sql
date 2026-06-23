-- =============================================================================
-- DIALECT PATCH:  DuckDB
-- ORIGINAL:       sql/dimensions/dim_date.sql
-- CHANGE:         Snowflake GENERATOR block replaced with DuckDB generate_series
-- ALL OTHER LOGIC IDENTICAL TO ORIGINAL
-- =============================================================================

CREATE OR REPLACE TABLE Dim_Date AS

WITH

date_spine AS (
    -- [DIALECT: DUCKDB] generate_series produces one row per date in range
    SELECT UNNEST(
        generate_series(DATE '2020-01-01', DATE '2030-12-31', INTERVAL '1 day')
    ) AS CalendarDate
),

date_attributes AS (
    SELECT
        CalendarDate,

        -- Integer key: YYYYMMDD
        -- [DIALECT: DUCKDB] STRFTIME returns VARCHAR; cast to INTEGER
        CAST(STRFTIME(CalendarDate, '%Y%m%d') AS INTEGER)       AS DateKey,

        -- Calendar attributes
        YEAR(CalendarDate)                                       AS CalendarYear,
        QUARTER(CalendarDate)                                    AS CalendarQuarter,
        MONTH(CalendarDate)                                      AS CalendarMonth,
        STRFTIME(CalendarDate, '%B')                             AS MonthName,
        -- [DIALECT: DUCKDB] DAYOFWEEK: 0=Sunday
        DAYOFWEEK(CalendarDate)                                  AS DayOfWeek,
        STRFTIME(CalendarDate, '%A')                             AS DayName,
        DAY(CalendarDate)                                        AS DayOfMonth,
        DAYOFYEAR(CalendarDate)                                  AS DayOfYear,
        -- [DIALECT: DUCKDB] WEEKOFYEAR returns ISO week number
        WEEKOFYEAR(CalendarDate)                                 AS WeekOfYear,

        -- Derived flags
        CASE WHEN DAYOFWEEK(CalendarDate) IN (0, 6) THEN 1 ELSE 0 END  AS IsWeekend,
        0                                                        AS IsHoliday,

        -- Period labels
        STRFTIME(CalendarDate, '%Y-%m')                          AS YearMonthLabel,
        'Q' || CAST(QUARTER(CalendarDate) AS VARCHAR)
            || ' ' || CAST(YEAR(CalendarDate) AS VARCHAR)        AS QuarterLabel,

        -- Fiscal calendar (CANDIDATE: fiscal year start = October 1 — UNK-004)
        CASE
            WHEN MONTH(CalendarDate) >= 10
            THEN YEAR(CalendarDate) + 1
            ELSE YEAR(CalendarDate)
        END                                                      AS FiscalYear,

        CASE
            WHEN MONTH(CalendarDate) IN (10, 11, 12) THEN 1
            WHEN MONTH(CalendarDate) IN (1,  2,  3)  THEN 2
            WHEN MONTH(CalendarDate) IN (4,  5,  6)  THEN 3
            WHEN MONTH(CalendarDate) IN (7,  8,  9)  THEN 4
        END                                                      AS FiscalQuarter,

        -- [DIALECT: DUCKDB] MOD() function is supported
        MOD(MONTH(CalendarDate) - 10 + 12, 12) + 1              AS FiscalPeriod,

        1                                                        AS Flag_CandidateFiscalCalendar

    FROM date_spine
)

-- Default/unknown member
SELECT
    -1          AS DateKey,
    NULL        AS CalendarDate,
    -1          AS CalendarYear,
    -1          AS CalendarQuarter,
    -1          AS CalendarMonth,
    'Unknown'   AS MonthName,
    -1          AS DayOfWeek,
    'Unknown'   AS DayName,
    -1          AS DayOfMonth,
    -1          AS DayOfYear,
    -1          AS WeekOfYear,
    0           AS IsWeekend,
    0           AS IsHoliday,
    'Unknown'   AS YearMonthLabel,
    'Unknown'   AS QuarterLabel,
    -1          AS FiscalYear,
    -1          AS FiscalQuarter,
    -1          AS FiscalPeriod,
    1           AS Flag_CandidateFiscalCalendar

UNION ALL

SELECT
    DateKey, CalendarDate, CalendarYear, CalendarQuarter, CalendarMonth,
    MonthName, DayOfWeek, DayName, DayOfMonth, DayOfYear, WeekOfYear,
    IsWeekend, IsHoliday, YearMonthLabel, QuarterLabel,
    FiscalYear, FiscalQuarter, FiscalPeriod, Flag_CandidateFiscalCalendar
FROM date_attributes;

-- =============================================================================
-- VALIDATION
-- =============================================================================
-- SELECT COUNT(*) FROM Dim_Date;
-- EXPECTED: 4019 (4018 calendar days 2020-2030 + 1 default row)

-- SELECT MIN(DateKey), MAX(DateKey) FROM Dim_Date WHERE DateKey <> -1;
-- EXPECTED: 20200101, 20301231
