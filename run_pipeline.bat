@echo off
REM =============================================================================
REM  PIPELINE RUNNER — Delivered Program Analytics
REM  TARGET:   DuckDB (local)
REM  PLATFORM: Windows
REM  VERSION:  1.0.1 — fixed label resolution bug in phase dispatch
REM  USAGE:    run_pipeline.bat [phase]
REM            run_pipeline.bat         runs all phases 1-9
REM            run_pipeline.bat 1       runs Phase 1 only
REM            run_pipeline.bat 2       runs Phase 2 only
REM            ... etc through 9
REM =============================================================================
REM  PREREQUISITES:
REM    1. DuckDB CLI installed and on PATH (or in repo root)
REM    2. Run from repo root directory
REM    3. CSVs exported to data\load\ before running Phase 2
REM    4. dim_date_duckdb.sql patch in implementation\duckdb_patches\
REM =============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

SET DB_FILE=delivered_program_analytics.duckdb
SET DUCKDB=duckdb
SET LOG_FILE=pipeline_run.log
SET PHASE=%1
SET FAILED=0

FOR /F "tokens=*" %%A IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%A
echo [%TS%] Pipeline run started >> %LOG_FILE%
echo [%TS%] Pipeline run started

IF "%PHASE%"=="" (
    echo Running ALL phases 1-9...
) ELSE (
    echo Running Phase %PHASE% only...
)

REM =============================================================================
REM  PHASE 1 — Raw Table Creation
REM =============================================================================
IF "%PHASE%"=="1" GOTO DO_PHASE_1
IF "%PHASE%"==""  GOTO DO_PHASE_1
GOTO CHECK_PHASE_2

:DO_PHASE_1
echo.
echo ============================================================
echo  PHASE 1 -- Raw Table Creation
echo ============================================================
CALL :EXEC "implementation\duckdb_patches\phase1_create_raw_tables.sql" "Phase 1: Raw table creation"
IF !FAILED! NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END

:CHECK_PHASE_2
REM =============================================================================
REM  PHASE 2 — Synthetic Data Load
REM =============================================================================
IF "%PHASE%"=="2" GOTO DO_PHASE_2
IF "%PHASE%"==""  GOTO DO_PHASE_2
GOTO CHECK_PHASE_3

:DO_PHASE_2
echo.
echo ============================================================
echo  PHASE 2 -- Synthetic Data Load
echo ============================================================
CALL :EXEC "implementation\duckdb_patches\phase2_load_raw_data.sql" "Phase 2: Data load"
IF !FAILED! NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END

:CHECK_PHASE_3
REM =============================================================================
REM  PHASE 3 — Staging Layer
REM =============================================================================
IF "%PHASE%"=="3" GOTO DO_PHASE_3
IF "%PHASE%"==""  GOTO DO_PHASE_3
GOTO CHECK_PHASE_4

:DO_PHASE_3
echo.
echo ============================================================
echo  PHASE 3 -- Staging Layer
echo ============================================================
CALL :EXEC "sql\staging\stg_customer_reference.sql"  "Phase 3: stg_customer_reference"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\staging\stg_product_master.sql"       "Phase 3: stg_product_master"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\staging\stg_contract_pricing.sql"     "Phase 3: stg_contract_pricing"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\staging\stg_sales_order_line.sql"     "Phase 3: stg_sales_order_line"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\staging\stg_load_freight.sql"         "Phase 3: stg_load_freight"
IF !FAILED! NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END

:CHECK_PHASE_4
REM =============================================================================
REM  PHASE 4 — Dimension Build
REM =============================================================================
IF "%PHASE%"=="4" GOTO DO_PHASE_4
IF "%PHASE%"==""  GOTO DO_PHASE_4
GOTO CHECK_PHASE_5

:DO_PHASE_4
echo.
echo ============================================================
echo  PHASE 4 -- Dimension Build
echo ============================================================
CALL :EXEC "implementation\duckdb_patches\dim_date_duckdb.sql"  "Phase 4: dim_date"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\dimensions\dim_customer_status.sql"              "Phase 4: dim_customer_status"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\dimensions\dim_commodity.sql"                    "Phase 4: dim_commodity"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\dimensions\dim_carrier.sql"                      "Phase 4: dim_carrier"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\dimensions\dim_shipto.sql"                       "Phase 4: dim_shipto"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\dimensions\dim_product.sql"                      "Phase 4: dim_product"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\dimensions\dim_customer.sql"                     "Phase 4: dim_customer"
IF !FAILED! NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END

:CHECK_PHASE_5
REM =============================================================================
REM  PHASE 5 — Fact Tables
REM =============================================================================
IF "%PHASE%"=="5" GOTO DO_PHASE_5
IF "%PHASE%"==""  GOTO DO_PHASE_5
GOTO CHECK_PHASE_6

:DO_PHASE_5
echo.
echo ============================================================
echo  PHASE 5 -- Fact Tables
echo ============================================================
CALL :EXEC "sql\facts\fact_load_freight.sql"     "Phase 5: fact_load_freight"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\facts\fact_contract_price.sql"   "Phase 5: fact_contract_price"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\facts\fact_sales_order_line.sql" "Phase 5: fact_sales_order_line"
IF !FAILED! NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END

:CHECK_PHASE_6
REM =============================================================================
REM  PHASE 6 — Calculation Engine
REM =============================================================================
IF "%PHASE%"=="6" GOTO DO_PHASE_6
IF "%PHASE%"==""  GOTO DO_PHASE_6
GOTO CHECK_PHASE_7

:DO_PHASE_6
echo.
echo ============================================================
echo  PHASE 6 -- Calculation Engine
echo ============================================================
CALL :EXEC "sql\calculations\calc_freight_summary.sql"       "Phase 6: calc_freight_summary"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\calculations\calc_fob_variance_summary.sql"  "Phase 6: calc_fob_variance_summary"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\calculations\calc_load_utilization.sql"      "Phase 6: calc_load_utilization"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\calculations\calc_customer_performance.sql"  "Phase 6: calc_customer_performance"
IF !FAILED! NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END

:CHECK_PHASE_7
REM =============================================================================
REM  PHASE 7 — Exception System
REM =============================================================================
IF "%PHASE%"=="7" GOTO DO_PHASE_7
IF "%PHASE%"==""  GOTO DO_PHASE_7
GOTO CHECK_PHASE_8

:DO_PHASE_7
echo.
echo ============================================================
echo  PHASE 7 -- Exception System
echo ============================================================
CALL :EXEC "sql\exceptions\exc_missing_contract_pricing.sql" "Phase 7: exc_missing_contract_pricing"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\exceptions\exc_negative_fob_variance.sql"    "Phase 7: exc_negative_fob_variance"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\exceptions\exc_negative_freight_margin.sql"  "Phase 7: exc_negative_freight_margin"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\exceptions\exc_missing_mappings.sql"         "Phase 7: exc_missing_mappings"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\exceptions\exc_data_quality.sql"             "Phase 7: exc_data_quality"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\exceptions\exc_master.sql"                   "Phase 7: exc_master"
IF !FAILED! NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END

:CHECK_PHASE_8
REM =============================================================================
REM  PHASE 8 — Reporting Layer
REM =============================================================================
IF "%PHASE%"=="8" GOTO DO_PHASE_8
IF "%PHASE%"==""  GOTO DO_PHASE_8
GOTO CHECK_PHASE_9

:DO_PHASE_8
echo.
echo ============================================================
echo  PHASE 8 -- Reporting Layer
echo ============================================================
CALL :EXEC "sql\reporting\rpt_executive_summary.sql"   "Phase 8: rpt_executive_summary"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\reporting\rpt_fob_variance_detail.sql" "Phase 8: rpt_fob_variance_detail"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\reporting\rpt_freight_performance.sql" "Phase 8: rpt_freight_performance"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\reporting\rpt_exception_dashboard.sql" "Phase 8: rpt_exception_dashboard"
IF !FAILED! NEQ 0 GOTO ERROR
CALL :EXEC "sql\reporting\rpt_customer_scorecard.sql"  "Phase 8: rpt_customer_scorecard"
IF !FAILED! NEQ 0 GOTO ERROR
IF NOT "%PHASE%"=="" GOTO END

:CHECK_PHASE_9
REM =============================================================================
REM  PHASE 9 — End-to-End Reconciliation
REM =============================================================================
IF "%PHASE%"=="9" GOTO DO_PHASE_9
IF "%PHASE%"==""  GOTO DO_PHASE_9
GOTO END

:DO_PHASE_9
echo.
echo ============================================================
echo  PHASE 9 -- End-to-End Reconciliation
echo ============================================================
CALL :EXEC "implementation\duckdb_patches\phase9_reconciliation.sql" "Phase 9: reconciliation"
IF !FAILED! NEQ 0 GOTO ERROR
GOTO END

REM =============================================================================
REM  SUBROUTINE: EXEC
REM  %~1 = script path, %~2 = label
REM =============================================================================
:EXEC
SET _SCRIPT=%~1
SET _LABEL=%~2
FOR /F "tokens=*" %%A IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%A
echo   [%TS%] Running: %_LABEL%
%DUCKDB% %DB_FILE% < "%_SCRIPT%" >> %LOG_FILE% 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo   [FAIL] %_LABEL% -- check %LOG_FILE% for details
    echo [%TS%] FAIL: %_LABEL% >> %LOG_FILE%
    SET FAILED=1
) ELSE (
    echo   [PASS] %_LABEL%
    echo [%TS%] PASS: %_LABEL% >> %LOG_FILE%
)
EXIT /B 0

REM =============================================================================
REM  ERROR / END
REM =============================================================================
:ERROR
FOR /F "tokens=*" %%A IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%A
echo.
echo ============================================================
echo  PIPELINE FAILED -- See %LOG_FILE% for error detail
echo ============================================================
echo [%TS%] Pipeline run FAILED >> %LOG_FILE%
ENDLOCAL
EXIT /B 1

:END
FOR /F "tokens=*" %%A IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%A
echo.
echo ============================================================
echo  PIPELINE COMPLETE -- %TS%
echo ============================================================
echo [%TS%] Pipeline run COMPLETE >> %LOG_FILE%
ENDLOCAL
EXIT /B 0
