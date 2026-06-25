@echo off
REM =============================================================================
REM  PIPELINE RUNNER -- Delivered Program Analytics
REM  TARGET:   DuckDB (local)
REM  PLATFORM: Windows
REM  VERSION:  2.1.0 -- Phase 8 extended (rpt_load_efficiency_by_shipto);
REM            Phase 10 added (Parquet export for Power BI) (2026-06-25)
REM  USAGE:    run_pipeline.bat [phase]
REM            run_pipeline.bat         runs all phases 1-10
REM            run_pipeline.bat 1       runs Phase 1 only
REM            ... etc through 10
REM =============================================================================
REM  PREREQUISITES:
REM    1. DuckDB CLI installed and on PATH (or in repo root)
REM    2. Run from repo root directory
REM    3. CSVs exported to data\real\ before running Phase 2
REM    4. dim_date_duckdb.sql patch in implementation\duckdb_patches\
REM    5. data\exports\ directory must exist before Phase 10
REM =============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

SET DB=delivered_program_analytics.duckdb
SET DDB=duckdb
SET LOG=pipeline_run.log
SET PHASE=%1

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo [!TS!] Pipeline run started >> %LOG%
echo [!TS!] Pipeline run started

IF "%PHASE%"=="" (
    echo Running ALL phases 1-10...
) ELSE (
    echo Running Phase %PHASE% only...
)

REM =============================================================================
REM  PHASE 1 -- Raw Table Creation
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="1" GOTO SKIP_P1
echo.
echo ============================================================
echo  PHASE 1 -- Raw Table Creation
echo ============================================================
FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 1: Raw table creation
%DDB% %DB% < "implementation\duckdb_patches\phase1_create_raw_tables.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 1: Raw table creation & echo [!TS!] FAIL: Phase 1: Raw table creation >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 1: Raw table creation & echo [!TS!] PASS: Phase 1: Raw table creation >> %LOG%
:SKIP_P1
IF "%PHASE%"=="1" GOTO DONE

REM =============================================================================
REM  PHASE 2 -- Data Load
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="2" GOTO SKIP_P2
echo.
echo ============================================================
echo  PHASE 2 -- Data Load
echo ============================================================
FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 2: Data load
%DDB% %DB% < "implementation\duckdb_patches\phase2_load_raw_data.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 2: Data load & echo [!TS!] FAIL: Phase 2: Data load >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 2: Data load & echo [!TS!] PASS: Phase 2: Data load >> %LOG%
:SKIP_P2
IF "%PHASE%"=="2" GOTO DONE

REM =============================================================================
REM  PHASE 3 -- Staging Layer
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="3" GOTO SKIP_P3
echo.
echo ============================================================
echo  PHASE 3 -- Staging Layer
echo ============================================================

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 3: stg_customer_reference
%DDB% %DB% < "sql\staging\stg_customer_reference.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 3: stg_customer_reference & echo [!TS!] FAIL: Phase 3: stg_customer_reference >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 3: stg_customer_reference & echo [!TS!] PASS: Phase 3: stg_customer_reference >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 3: stg_product_master
%DDB% %DB% < "sql\staging\stg_product_master.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 3: stg_product_master & echo [!TS!] FAIL: Phase 3: stg_product_master >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 3: stg_product_master & echo [!TS!] PASS: Phase 3: stg_product_master >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 3: stg_contract_pricing
%DDB% %DB% < "sql\staging\stg_contract_pricing.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 3: stg_contract_pricing & echo [!TS!] FAIL: Phase 3: stg_contract_pricing >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 3: stg_contract_pricing & echo [!TS!] PASS: Phase 3: stg_contract_pricing >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 3: stg_sales_order_line
%DDB% %DB% < "sql\staging\stg_sales_order_line.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 3: stg_sales_order_line & echo [!TS!] FAIL: Phase 3: stg_sales_order_line >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 3: stg_sales_order_line & echo [!TS!] PASS: Phase 3: stg_sales_order_line >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 3: stg_load_freight
%DDB% %DB% < "sql\staging\stg_load_freight.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 3: stg_load_freight & echo [!TS!] FAIL: Phase 3: stg_load_freight >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 3: stg_load_freight & echo [!TS!] PASS: Phase 3: stg_load_freight >> %LOG%

:SKIP_P3
IF "%PHASE%"=="3" GOTO DONE

REM =============================================================================
REM  PHASE 4 -- Dimension Build
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="4" GOTO SKIP_P4
echo.
echo ============================================================
echo  PHASE 4 -- Dimension Build
echo ============================================================

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 4: dim_date
%DDB% %DB% < "implementation\duckdb_patches\dim_date_duckdb.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 4: dim_date & echo [!TS!] FAIL: Phase 4: dim_date >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 4: dim_date & echo [!TS!] PASS: Phase 4: dim_date >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 4: dim_customer_status
%DDB% %DB% < "sql\dimensions\dim_customer_status.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 4: dim_customer_status & echo [!TS!] FAIL: Phase 4: dim_customer_status >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 4: dim_customer_status & echo [!TS!] PASS: Phase 4: dim_customer_status >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 4: dim_commodity
%DDB% %DB% < "sql\dimensions\dim_commodity.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 4: dim_commodity & echo [!TS!] FAIL: Phase 4: dim_commodity >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 4: dim_commodity & echo [!TS!] PASS: Phase 4: dim_commodity >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 4: dim_carrier
%DDB% %DB% < "sql\dimensions\dim_carrier.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 4: dim_carrier & echo [!TS!] FAIL: Phase 4: dim_carrier >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 4: dim_carrier & echo [!TS!] PASS: Phase 4: dim_carrier >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 4: dim_shipto
%DDB% %DB% < "sql\dimensions\dim_shipto.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 4: dim_shipto & echo [!TS!] FAIL: Phase 4: dim_shipto >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 4: dim_shipto & echo [!TS!] PASS: Phase 4: dim_shipto >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 4: dim_product
%DDB% %DB% < "sql\dimensions\dim_product.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 4: dim_product & echo [!TS!] FAIL: Phase 4: dim_product >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 4: dim_product & echo [!TS!] PASS: Phase 4: dim_product >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 4: dim_customer
%DDB% %DB% < "sql\dimensions\dim_customer.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 4: dim_customer & echo [!TS!] FAIL: Phase 4: dim_customer >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 4: dim_customer & echo [!TS!] PASS: Phase 4: dim_customer >> %LOG%

:SKIP_P4
IF "%PHASE%"=="4" GOTO DONE

REM =============================================================================
REM  PHASE 5 -- Fact Tables
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="5" GOTO SKIP_P5
echo.
echo ============================================================
echo  PHASE 5 -- Fact Tables
echo ============================================================

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 5: fact_load_freight
%DDB% %DB% < "sql\facts\fact_load_freight.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 5: fact_load_freight & echo [!TS!] FAIL: Phase 5: fact_load_freight >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 5: fact_load_freight & echo [!TS!] PASS: Phase 5: fact_load_freight >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 5: fact_contract_price
%DDB% %DB% < "sql\facts\fact_contract_price.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 5: fact_contract_price & echo [!TS!] FAIL: Phase 5: fact_contract_price >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 5: fact_contract_price & echo [!TS!] PASS: Phase 5: fact_contract_price >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 5: fact_sales_order_line
%DDB% %DB% < "sql\facts\fact_sales_order_line.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 5: fact_sales_order_line & echo [!TS!] FAIL: Phase 5: fact_sales_order_line >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 5: fact_sales_order_line & echo [!TS!] PASS: Phase 5: fact_sales_order_line >> %LOG%

:SKIP_P5
IF "%PHASE%"=="5" GOTO DONE

REM =============================================================================
REM  PHASE 6 -- Calculation Engine
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="6" GOTO SKIP_P6
echo.
echo ============================================================
echo  PHASE 6 -- Calculation Engine
echo ============================================================

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 6: calc_freight_summary
%DDB% %DB% < "sql\calculations\calc_freight_summary.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 6: calc_freight_summary & echo [!TS!] FAIL: Phase 6: calc_freight_summary >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 6: calc_freight_summary & echo [!TS!] PASS: Phase 6: calc_freight_summary >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 6: calc_fob_variance_summary
%DDB% %DB% < "sql\calculations\calc_fob_variance_summary.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 6: calc_fob_variance_summary & echo [!TS!] FAIL: Phase 6: calc_fob_variance_summary >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 6: calc_fob_variance_summary & echo [!TS!] PASS: Phase 6: calc_fob_variance_summary >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 6: calc_load_utilization
%DDB% %DB% < "sql\calculations\calc_load_utilization.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 6: calc_load_utilization & echo [!TS!] FAIL: Phase 6: calc_load_utilization >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 6: calc_load_utilization & echo [!TS!] PASS: Phase 6: calc_load_utilization >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 6: calc_customer_performance
%DDB% %DB% < "sql\calculations\calc_customer_performance.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 6: calc_customer_performance & echo [!TS!] FAIL: Phase 6: calc_customer_performance >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 6: calc_customer_performance & echo [!TS!] PASS: Phase 6: calc_customer_performance >> %LOG%

:SKIP_P6
IF "%PHASE%"=="6" GOTO DONE

REM =============================================================================
REM  PHASE 7 -- Exception System
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="7" GOTO SKIP_P7
echo.
echo ============================================================
echo  PHASE 7 -- Exception System
echo ============================================================

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 7: exc_missing_contract_pricing
%DDB% %DB% < "sql\exceptions\exc_missing_contract_pricing.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 7: exc_missing_contract_pricing & echo [!TS!] FAIL: Phase 7: exc_missing_contract_pricing >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 7: exc_missing_contract_pricing & echo [!TS!] PASS: Phase 7: exc_missing_contract_pricing >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 7: exc_negative_fob_variance
%DDB% %DB% < "sql\exceptions\exc_negative_fob_variance.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 7: exc_negative_fob_variance & echo [!TS!] FAIL: Phase 7: exc_negative_fob_variance >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 7: exc_negative_fob_variance & echo [!TS!] PASS: Phase 7: exc_negative_fob_variance >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 7: exc_negative_freight_margin
%DDB% %DB% < "sql\exceptions\exc_negative_freight_margin.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 7: exc_negative_freight_margin & echo [!TS!] FAIL: Phase 7: exc_negative_freight_margin >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 7: exc_negative_freight_margin & echo [!TS!] PASS: Phase 7: exc_negative_freight_margin >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 7: exc_missing_mappings
%DDB% %DB% < "sql\exceptions\exc_missing_mappings.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 7: exc_missing_mappings & echo [!TS!] FAIL: Phase 7: exc_missing_mappings >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 7: exc_missing_mappings & echo [!TS!] PASS: Phase 7: exc_missing_mappings >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 7: exc_data_quality
%DDB% %DB% < "sql\exceptions\exc_data_quality.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 7: exc_data_quality & echo [!TS!] FAIL: Phase 7: exc_data_quality >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 7: exc_data_quality & echo [!TS!] PASS: Phase 7: exc_data_quality >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 7: exc_master
%DDB% %DB% < "sql\exceptions\exc_master.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 7: exc_master & echo [!TS!] FAIL: Phase 7: exc_master >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 7: exc_master & echo [!TS!] PASS: Phase 7: exc_master >> %LOG%

:SKIP_P7
IF "%PHASE%"=="7" GOTO DONE

REM =============================================================================
REM  PHASE 8 -- Reporting Layer
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="8" GOTO SKIP_P8
echo.
echo ============================================================
echo  PHASE 8 -- Reporting Layer
echo ============================================================

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 8: rpt_executive_summary
%DDB% %DB% < "sql\reporting\rpt_executive_summary.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 8: rpt_executive_summary & echo [!TS!] FAIL: Phase 8: rpt_executive_summary >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 8: rpt_executive_summary & echo [!TS!] PASS: Phase 8: rpt_executive_summary >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 8: rpt_fob_variance_detail
%DDB% %DB% < "sql\reporting\rpt_fob_variance_detail.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 8: rpt_fob_variance_detail & echo [!TS!] FAIL: Phase 8: rpt_fob_variance_detail >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 8: rpt_fob_variance_detail & echo [!TS!] PASS: Phase 8: rpt_fob_variance_detail >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 8: rpt_freight_performance
%DDB% %DB% < "sql\reporting\rpt_freight_performance.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 8: rpt_freight_performance & echo [!TS!] FAIL: Phase 8: rpt_freight_performance >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 8: rpt_freight_performance & echo [!TS!] PASS: Phase 8: rpt_freight_performance >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 8: rpt_exception_dashboard
%DDB% %DB% < "sql\reporting\rpt_exception_dashboard.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 8: rpt_exception_dashboard & echo [!TS!] FAIL: Phase 8: rpt_exception_dashboard >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 8: rpt_exception_dashboard & echo [!TS!] PASS: Phase 8: rpt_exception_dashboard >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 8: rpt_customer_scorecard
%DDB% %DB% < "sql\reporting\rpt_customer_scorecard.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 8: rpt_customer_scorecard & echo [!TS!] FAIL: Phase 8: rpt_customer_scorecard >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 8: rpt_customer_scorecard & echo [!TS!] PASS: Phase 8: rpt_customer_scorecard >> %LOG%

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 8: rpt_load_efficiency_by_shipto
%DDB% %DB% < "sql\reporting\rpt_load_efficiency_by_shipto.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 8: rpt_load_efficiency_by_shipto & echo [!TS!] FAIL: Phase 8: rpt_load_efficiency_by_shipto >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 8: rpt_load_efficiency_by_shipto & echo [!TS!] PASS: Phase 8: rpt_load_efficiency_by_shipto >> %LOG%

:SKIP_P8
IF "%PHASE%"=="8" GOTO DONE

REM =============================================================================
REM  PHASE 9 -- End-to-End Reconciliation
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="9" GOTO SKIP_P9
echo.
echo ============================================================
echo  PHASE 9 -- End-to-End Reconciliation
echo ============================================================

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 9: reconciliation
%DDB% %DB% < "implementation\duckdb_patches\phase9_reconciliation.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 9: reconciliation & echo [!TS!] FAIL: Phase 9: reconciliation >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 9: reconciliation & echo [!TS!] PASS: Phase 9: reconciliation >> %LOG%

:SKIP_P9
IF "%PHASE%"=="9" GOTO DONE

REM =============================================================================
REM  PHASE 10 -- Parquet Export for Power BI
REM =============================================================================
IF NOT "%PHASE%"=="" IF NOT "%PHASE%"=="10" GOTO SKIP_P10
echo.
echo ============================================================
echo  PHASE 10 -- Parquet Export for Power BI
echo ============================================================

FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo   [!TS!] Running: Phase 10: parquet export
%DDB% %DB% < "implementation\duckdb_patches\phase10_export_parquet.sql" >> %LOG% 2>&1
IF !ERRORLEVEL! NEQ 0 ( echo   [FAIL] Phase 10: parquet export & echo [!TS!] FAIL: Phase 10: parquet export >> %LOG% & GOTO FAILED )
echo   [PASS] Phase 10: parquet export & echo [!TS!] PASS: Phase 10: parquet export >> %LOG%

:SKIP_P10

REM =============================================================================
REM  DONE
REM =============================================================================
:DONE
FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo.
echo ============================================================
echo  PIPELINE COMPLETE -- !TS!
echo ============================================================
echo [!TS!] Pipeline run COMPLETE >> %LOG%
ENDLOCAL
EXIT /B 0

:FAILED
FOR /F "tokens=*" %%T IN ('powershell -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') DO SET TS=%%T
echo.
echo ============================================================
echo  PIPELINE FAILED -- See %LOG% for error detail
echo ============================================================
echo [!TS!] Pipeline run FAILED >> %LOG%
ENDLOCAL
EXIT /B 1