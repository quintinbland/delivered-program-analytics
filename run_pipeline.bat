@echo off
REM =============================================================================
REM  PIPELINE RUNNER — Delivered Program Analytics
REM  TARGET:   DuckDB (local)
REM  PLATFORM: Windows
REM  USAGE:    run_pipeline.bat [phase]
REM            run_pipeline.bat         — runs all phases
REM            run_pipeline.bat 1       — runs Phase 1 only (raw tables)
REM            run_pipeline.bat 2       — runs Phase 2 only (data load)
REM            run_pipeline.bat 3       — runs Phase 3 only (staging)
REM            run_pipeline.bat 4       — runs Phase 4 only (dimensions)
REM            run_pipeline.bat 5       — runs Phase 5 only (facts)
REM            run_pipeline.bat 6       — runs Phase 6 only (calculations)
REM            run_pipeline.bat 7       — runs Phase 7 only (exceptions)
REM            run_pipeline.bat 8       — runs Phase 8 only (reporting)
REM            run_pipeline.bat 9       — runs Phase 9 only (reconciliation)
REM =============================================================================
REM  PREREQUISITES:
REM    1. DuckDB CLI installed and accessible as 'duckdb' on system PATH
REM       Download: https://duckdb.org/docs/installation
REM    2. Run from repo root directory:
REM       C:\Users\Quintin.Bland\Documents\delivered-program-analytics-repo\
REM    3. CSVs exported to data\load\ before running Phase 2
REM    4. dim_date.sql replaced with DuckDB patch before running Phase 4
REM =============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

REM --- Configuration ---
SET DB_FILE=delivered_program_analytics.duckdb
SET DUCKDB=duckdb
SET LOG_FILE=pipeline_run.log
SET PHASE=%1

REM --- Timestamp ---
FOR /F "tokens=*" %%A IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TIMESTAMP=%%A
echo [%TIMESTAMP%] Pipeline run started >> %LOG_FILE%
echo [%TIMESTAMP%] Pipeline run started

IF "%PHASE%"=="" (
    echo Running ALL phases...
    GOTO RUN_ALL
)
echo Running Phase %PHASE% only...
GOTO RUN_PHASE_%PHASE%

REM =============================================================================
REM  PHASE EXECUTION BLOCKS
REM =============================================================================

:RUN_ALL
GOTO RUN_PHASE_1

:RUN_PHASE_1
echo.
echo ============================================================
echo  PHASE 1 — Raw Table Creation
echo ============================================================
CALL :RUN_SCRIPT "implementation\duckdb_patches\phase1_create_raw_tables.sql" "Phase 1: Raw table creation"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END
GOTO RUN_PHASE_2

:RUN_PHASE_2
echo.
echo ============================================================
echo  PHASE 2 — Synthetic Data Load
echo ============================================================
CALL :RUN_SCRIPT "implementation\duckdb_patches\phase2_load_raw_data.sql" "Phase 2: Data load"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END
GOTO RUN_PHASE_3

:RUN_PHASE_3
echo.
echo ============================================================
echo  PHASE 3 — Staging Layer
echo ============================================================
CALL :RUN_SCRIPT "sql\staging\stg_customer_reference.sql"   "Phase 3: stg_customer_reference"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\staging\stg_product_master.sql"        "Phase 3: stg_product_master"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\staging\stg_contract_pricing.sql"      "Phase 3: stg_contract_pricing"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\staging\stg_sales_order_line.sql"      "Phase 3: stg_sales_order_line"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\staging\stg_load_freight.sql"          "Phase 3: stg_load_freight"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END
GOTO RUN_PHASE_4

:RUN_PHASE_4
echo.
echo ============================================================
echo  PHASE 4 — Dimension Build
echo ============================================================
CALL :RUN_SCRIPT "implementation\duckdb_patches\dim_date_duckdb.sql"   "Phase 4: dim_date (DuckDB patch)"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\dimensions\dim_customer_status.sql"               "Phase 4: dim_customer_status"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\dimensions\dim_commodity.sql"                     "Phase 4: dim_commodity"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\dimensions\dim_carrier.sql"                       "Phase 4: dim_carrier"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\dimensions\dim_shipto.sql"                        "Phase 4: dim_shipto"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\dimensions\dim_product.sql"                       "Phase 4: dim_product"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\dimensions\dim_customer.sql"                      "Phase 4: dim_customer"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END
GOTO RUN_PHASE_5

:RUN_PHASE_5
echo.
echo ============================================================
echo  PHASE 5 — Fact Tables
echo ============================================================
CALL :RUN_SCRIPT "sql\facts\fact_load_freight.sql"      "Phase 5: fact_load_freight"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\facts\fact_contract_price.sql"    "Phase 5: fact_contract_price"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\facts\fact_sales_order_line.sql"  "Phase 5: fact_sales_order_line"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END
GOTO RUN_PHASE_6

:RUN_PHASE_6
echo.
echo ============================================================
echo  PHASE 6 — Calculation Engine
echo ============================================================
CALL :RUN_SCRIPT "sql\calculations\calc_freight_summary.sql"        "Phase 6: calc_freight_summary"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\calculations\calc_fob_variance_summary.sql"   "Phase 6: calc_fob_variance_summary"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\calculations\calc_load_utilization.sql"       "Phase 6: calc_load_utilization"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\calculations\calc_customer_performance.sql"   "Phase 6: calc_customer_performance"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END
GOTO RUN_PHASE_7

:RUN_PHASE_7
echo.
echo ============================================================
echo  PHASE 7 — Exception System
echo ============================================================
CALL :RUN_SCRIPT "sql\exceptions\exc_missing_contract_pricing.sql"  "Phase 7: exc_missing_contract_pricing"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\exceptions\exc_negative_fob_variance.sql"     "Phase 7: exc_negative_fob_variance"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\exceptions\exc_negative_freight_margin.sql"   "Phase 7: exc_negative_freight_margin"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\exceptions\exc_missing_mappings.sql"          "Phase 7: exc_missing_mappings"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\exceptions\exc_data_quality.sql"              "Phase 7: exc_data_quality"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\exceptions\exc_master.sql"                    "Phase 7: exc_master"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END
GOTO RUN_PHASE_8

:RUN_PHASE_8
echo.
echo ============================================================
echo  PHASE 8 — Reporting Layer
echo ============================================================
CALL :RUN_SCRIPT "sql\reporting\rpt_executive_summary.sql"      "Phase 8: rpt_executive_summary"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\reporting\rpt_fob_variance_detail.sql"    "Phase 8: rpt_fob_variance_detail"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\reporting\rpt_freight_performance.sql"    "Phase 8: rpt_freight_performance"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\reporting\rpt_exception_dashboard.sql"    "Phase 8: rpt_exception_dashboard"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
CALL :RUN_SCRIPT "sql\reporting\rpt_customer_scorecard.sql"     "Phase 8: rpt_customer_scorecard"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END
GOTO RUN_PHASE_9

:RUN_PHASE_9
echo.
echo ============================================================
echo  PHASE 9 — End-to-End Reconciliation
echo ============================================================
CALL :RUN_SCRIPT "implementation\duckdb_patches\phase9_reconciliation.sql" "Phase 9: reconciliation"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
GOTO END

REM =============================================================================
REM  SUBROUTINE: RUN_SCRIPT
REM  Executes a single SQL file against the DuckDB database
REM  Logs result (PASS / FAIL) with timestamp
REM =============================================================================
:RUN_SCRIPT
SET SCRIPT=%~1
SET LABEL=%~2
FOR /F "tokens=*" %%A IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%A
echo   [%TS%] Running: %LABEL%
%DUCKDB% %DB_FILE% < "%SCRIPT%" >> %LOG_FILE% 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo   [FAIL] %LABEL% — check %LOG_FILE% for details
    echo [%TS%] FAIL: %LABEL% >> %LOG_FILE%
    EXIT /B 1
)
echo   [PASS] %LABEL%
echo [%TS%] PASS: %LABEL% >> %LOG_FILE%
EXIT /B 0

REM =============================================================================
REM  ERROR HANDLER
REM =============================================================================
:ERROR
FOR /F "tokens=*" %%A IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%A
echo.
echo ============================================================
echo  PIPELINE FAILED — See %LOG_FILE% for error detail
echo  Last failed script logged above
echo ============================================================
echo [%TS%] Pipeline run FAILED >> %LOG_FILE%
EXIT /B 1

REM =============================================================================
REM  END
REM =============================================================================
:END
FOR /F "tokens=*" %%A IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%A
echo.
echo ============================================================
echo  PIPELINE COMPLETE — %TS%
echo ============================================================
echo [%TS%] Pipeline run COMPLETE >> %LOG_FILE%
ENDLOCAL
EXIT /B 0
