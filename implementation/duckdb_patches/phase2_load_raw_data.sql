-- =============================================================================
-- IMPLEMENTATION: Phase 2 — Synthetic Data Load
-- TARGET:         DuckDB
-- PURPOSE:        Load CSV exports from synthetic dataset into raw tables
-- RUN:            After Phase 1 (raw tables created) and after CSVs exported
-- =============================================================================
-- ASSUMPTIONS:
--   A1: CSVs exported from DeliveredProgram_DummyDataset.xlsx
--   A2: All CSV files saved to the data/load/ folder in the repo
--   A3: CSV column headers match Raw table column names exactly
--   A4: File path below uses Windows path format — update if directory differs
-- =============================================================================
-- INSTRUCTION: Update the base path on the line below to match your system.
-- Current default: relative path assumes DuckDB is launched from repo root.
-- If running from a different directory, use an absolute path instead.
-- Example absolute path: 'C:/Users/Quintin.Bland/Documents/delivered-program-analytics-repo/data/load/'
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STEP 1: Load Raw_SalesOrderLine
-- ---------------------------------------------------------------------------
DELETE FROM Raw_SalesOrderLine;

COPY Raw_SalesOrderLine FROM 'data/load/raw_sales_order_line.csv' (
    HEADER TRUE,
    DELIMITER ',',
    QUOTE '"',
    NULL ''
);

-- ---------------------------------------------------------------------------
-- STEP 2: Load Raw_LoadFreight
-- ---------------------------------------------------------------------------
DELETE FROM Raw_LoadFreight;

COPY Raw_LoadFreight FROM 'data/load/raw_load_freight.csv' (
    HEADER TRUE,
    DELIMITER ',',
    QUOTE '"',
    NULL ''
);

-- ---------------------------------------------------------------------------
-- STEP 3: Load Raw_ContractPricing
-- ---------------------------------------------------------------------------
DELETE FROM Raw_ContractPricing;

COPY Raw_ContractPricing FROM 'data/load/raw_contract_pricing.csv' (
    HEADER TRUE,
    DELIMITER ',',
    QUOTE '"',
    NULL ''
);

-- ---------------------------------------------------------------------------
-- STEP 4: Load Raw_ProductMaster
-- ---------------------------------------------------------------------------
DELETE FROM Raw_ProductMaster;

COPY Raw_ProductMaster FROM 'data/load/raw_product_master.csv' (
    HEADER TRUE,
    DELIMITER ',',
    QUOTE '"',
    NULL ''
);

-- ---------------------------------------------------------------------------
-- STEP 5: Load Raw_CustomerReference
-- ---------------------------------------------------------------------------
DELETE FROM Raw_CustomerReference;

COPY Raw_CustomerReference FROM 'data/load/raw_customer_reference.csv' (
    HEADER TRUE,
    DELIMITER ',',
    QUOTE '"',
    NULL ''
);

-- ---------------------------------------------------------------------------
-- STEP 6: Load Raw_ShipToReference
-- ---------------------------------------------------------------------------
DELETE FROM Raw_ShipToReference;

COPY Raw_ShipToReference FROM 'data/load/raw_shipto_reference.csv' (
    HEADER TRUE,
    DELIMITER ',',
    QUOTE '"',
    NULL ''
);

-- ---------------------------------------------------------------------------
-- STEP 7: Load Raw_CommodityReference
-- ---------------------------------------------------------------------------
DELETE FROM Raw_CommodityReference;

COPY Raw_CommodityReference FROM 'data/load/raw_commodity_reference.csv' (
    HEADER TRUE,
    DELIMITER ',',
    QUOTE '"',
    NULL ''
);

-- =============================================================================
-- VALIDATION: Run after all loads complete
-- Record row counts — these are the pipeline reconciliation baseline
-- =============================================================================
SELECT 'Raw_SalesOrderLine'    AS TableName, COUNT(*) AS RowCount FROM Raw_SalesOrderLine    UNION ALL
SELECT 'Raw_LoadFreight',                    COUNT(*)             FROM Raw_LoadFreight        UNION ALL
SELECT 'Raw_ContractPricing',               COUNT(*)             FROM Raw_ContractPricing    UNION ALL
SELECT 'Raw_ProductMaster',                 COUNT(*)             FROM Raw_ProductMaster      UNION ALL
SELECT 'Raw_CustomerReference',             COUNT(*)             FROM Raw_CustomerReference  UNION ALL
SELECT 'Raw_ShipToReference',               COUNT(*)             FROM Raw_ShipToReference    UNION ALL
SELECT 'Raw_CommodityReference',            COUNT(*)             FROM Raw_CommodityReference
ORDER BY TableName;
-- EXPECTED: All 7 rows return RowCount > 0
