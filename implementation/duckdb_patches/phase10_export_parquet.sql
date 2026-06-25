-- =============================================================================
-- IMPLEMENTATION: Phase 10 -- Parquet Export for Power BI
-- TARGET:         DuckDB
-- PURPOSE:        Export reporting views to Parquet for Power BI Desktop import
-- VERSION:        1.0.1 -- Corrected Rpt_ExceptionDashboard table names (2026-06-25)
-- =============================================================================
-- NOTE: This export is the interim Power BI connection method pending
--       Snowflake migration. Production deployment will use Power BI native
--       Snowflake connector once budget is approved.
--       To migrate: remove this script, connect Power BI directly to Snowflake.
-- =============================================================================

COPY (SELECT * FROM Rpt_ExecutiveSummary)
TO 'data/exports/Rpt_ExecutiveSummary.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM Rpt_FOBVarianceDetail)
TO 'data/exports/Rpt_FOBVarianceDetail.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM Rpt_FreightPerformance)
TO 'data/exports/Rpt_FreightPerformance.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM Rpt_ExceptionDashboard_Open)
TO 'data/exports/Rpt_ExceptionDashboard_Open.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM Rpt_ExceptionDashboard_Summary)
TO 'data/exports/Rpt_ExceptionDashboard_Summary.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM Rpt_CustomerScorecard)
TO 'data/exports/Rpt_CustomerScorecard.parquet' (FORMAT PARQUET);

SELECT 'Rpt_ExecutiveSummary'         AS TableName, COUNT(*) AS RowCount FROM Rpt_ExecutiveSummary
UNION ALL
SELECT 'Rpt_FOBVarianceDetail',        COUNT(*) FROM Rpt_FOBVarianceDetail
UNION ALL
SELECT 'Rpt_FreightPerformance',       COUNT(*) FROM Rpt_FreightPerformance
UNION ALL
SELECT 'Rpt_ExceptionDashboard_Open',  COUNT(*) FROM Rpt_ExceptionDashboard_Open
UNION ALL
SELECT 'Rpt_ExceptionDashboard_Summary', COUNT(*) FROM Rpt_ExceptionDashboard_Summary
UNION ALL
SELECT 'Rpt_CustomerScorecard',        COUNT(*) FROM Rpt_CustomerScorecard
ORDER BY TableName;
COPY (SELECT * FROM Rpt_LoadEfficiencyByShipTo) TO 'data/exports/Rpt_LoadEfficiencyByShipTo.parquet' (FORMAT PARQUET);
