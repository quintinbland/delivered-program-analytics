-- =============================================================================
-- MODULE:      Reporting Layer
-- SCRIPT:      rpt_exception_dashboard.sql
-- INPUT:       Exc_Master, Dim_Date
-- OUTPUT:      Rpt_ExceptionDashboard
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Exc_Master  (Module 5)
-- =============================================================================
-- PURPOSE:
--   Operational exception dashboard providing triage-ready summary metrics
--   and trend data across all exception types, severities, and owner domains.
--
--   TWO OUTPUT SECTIONS:
--   Section 1 — Rpt_ExceptionDashboard_Summary: aggregated by type + period
--   Section 2 — Rpt_ExceptionDashboard_Open: open HIGH severity detail list
--
-- ASSUMPTIONS:
--   A1: ExceptionLoadedAt is used as the period date proxy.
--       No ShipDate or LoadDate join is applied — exceptions may span
--       multiple transaction periods.
--   A2: Financial impact is NULL for mapping and DQ exception types.
--       TotalFinancialImpact for these types reports 0 (COALESCE applied).
--   A3: ResolutionStatus = 'OPEN' is the default state for all exceptions.
--       Dashboard reflects current open state only.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Section 1: Exception summary by type, severity, and owner domain
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE Rpt_ExceptionDashboard_Summary AS

SELECT
    ExceptionType,
    Severity,
    OwnerDomain,
    ResolutionStatus,
    COUNT(*)                                            AS ExceptionCount,
    SUM(COALESCE(FinancialImpact, 0))                   AS TotalFinancialImpact,
    MIN(COALESCE(FinancialImpact, 0))                   AS MinFinancialImpact,
    MAX(COALESCE(FinancialImpact, 0))                   AS MaxFinancialImpact,
    COUNT(CASE WHEN FinancialImpact IS NOT NULL THEN 1 END) AS ExceptionCount_WithImpact,
    COUNT(CASE WHEN FinancialImpact IS NULL     THEN 1 END) AS ExceptionCount_NoImpact,
    CURRENT_TIMESTAMP                                   AS ReportLoadedAt

FROM Exc_Master
GROUP BY ExceptionType, Severity, OwnerDomain, ResolutionStatus
ORDER BY
    CASE Severity WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
    ExceptionCount DESC;


-- ---------------------------------------------------------------------------
-- Section 2: Open HIGH severity exception detail list (triage queue)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE Rpt_ExceptionDashboard_Open AS

SELECT
    ExceptionID,
    ExceptionType,
    Severity,
    OwnerDomain,
    PrimaryEntityID,
    PrimaryEntityType,
    SecondaryEntityID,
    SecondaryEntityType,
    FinancialImpact,
    ImpactCurrency,
    ImpactNote,
    ResolutionGuidance,
    OpenUnknownNote,
    ResolutionStatus,
    SourceSystem,
    BatchID,
    ExceptionLoadedAt,
    CURRENT_TIMESTAMP                                   AS ReportLoadedAt

FROM Exc_Master
WHERE ResolutionStatus = 'OPEN'
  AND Severity = 'HIGH'
ORDER BY
    COALESCE(FinancialImpact, 0) ASC,   -- Largest negative impact first
    ExceptionType,
    PrimaryEntityID;
