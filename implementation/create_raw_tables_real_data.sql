-- =============================================================================
-- IMPLEMENTATION
-- SCRIPT:      create_raw_tables_real_data.sql
-- PURPOSE:     Raw table DDL using confirmed real source column names
--              from Copilot column mapping (2026-06-23)
-- DIALECT:     DuckDB
-- VERSION:     1.0.0
-- =============================================================================
-- USAGE:
--   Run this script ONCE before loading real data CSVs.
--   Replaces create_raw_tables_duckdb.sql for real data runs.
--   Synthetic data raw tables used different column names.
--
-- SOURCE OBJECTS:
--   Raw_SalesOrderLine  ← FACT_Base / BI_FactTable (line-level data)
--   Raw_LoadFreight     ← Order Level Query (load-level data)
--   Raw_ContractPricing ← Contract_Unified (contract FOB prices)
--   Raw_Customer        ← FACT_Base / Order Level Query (customer reference)
--   Raw_Item            ← FACT_Base / Product.Table (item/commodity reference)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Raw_SalesOrderLine
--    Source: FACT_Base (primary) + BI_FactTable (FOB_Post_Adj supplement)
--    One row per delivered line item
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE Raw_SalesOrderLine (
    -- Natural key components
    salesId                 VARCHAR,    -- SalesOrderID
    FactKey                 VARCHAR,    -- SalesOrderLineID (line-level identifier)
    loadId                  VARCHAR,    -- LoadID

    -- Customer
    shipTo                  VARCHAR,    -- CustomerID
    HQ_Name                 VARCHAR,    -- CustomerHQID (parent account)
    CustomerProgramStatus   VARCHAR,    -- 'Contract' / 'Commit' / 'Open Market'

    -- Product
    Product_ID              VARCHAR,    -- ItemID / CommodityID

    -- Dates
    -- checkOut is a timestamp in source (date + time); cast to DATE in staging
    checkOut                VARCHAR,    -- ShipDate + OrderDate (same value)

    -- Quantity
    qty                     DECIMAL(18,4),  -- QuantityCases (delivered qty only)

    -- Pricing
    -- FOB_Post_Adj: preferred FOB price (post-adjustment)
    -- price: fallback if FOB_Post_Adj is NULL
    FOB_Post_Adj            DECIMAL(18,6),  -- ActualFOBPrice (preferred)
    price                   DECIMAL(18,6),  -- ActualFOBPrice (fallback)

    -- Batch metadata (populated by load process)
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

-- ---------------------------------------------------------------------------
-- 2. Raw_LoadFreight
--    Source: Order Level Query
--    One row per LoadID
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE Raw_LoadFreight (
    -- Natural key
    loadId                  VARCHAR,    -- LoadID

    -- Carrier
    carrierName             VARCHAR,    -- CarrierID (natural key for Dim_Carrier)

    -- Origin
    warehouse               VARCHAR,    -- OriginWarehouse

    -- Dates
    shipDate                VARCHAR,    -- LoadDate

    -- Freight financials
    loadShippingCharged     DECIMAL(18,4),  -- FreightCharged (billed to customer)
    loadShippingCost        DECIMAL(18,4),  -- FreightCost (paid to carrier)

    -- Load metrics
    loadPallets             DECIMAL(10,2),  -- LoadPallets

    -- Batch metadata
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

-- ---------------------------------------------------------------------------
-- 3. Raw_ContractPricing
--    Source: Contract_Unified
--    One row per CustomerHQ + Commodity contract agreement
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE Raw_ContractPricing (
    -- Contract scope
    Customer_HQ             VARCHAR,    -- CustomerHQID
    Commodity               VARCHAR,    -- CommodityID

    -- Pricing
    Contract_FOB            DECIMAL(18,6),  -- ContractFOBPrice (per case)

    -- Program type
    CustomerProgramStatus   VARCHAR,    -- 'Contract' / 'Commit' / 'Open Market'

    -- Batch metadata
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

-- ---------------------------------------------------------------------------
-- 4. Raw_Customer
--    Source: FACT_Base.shipTo + Name; Order Level Query.shipToName / billTo
--    One row per CustomerID (distinct accounts)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE Raw_Customer (
    -- Customer identity
    shipTo                  VARCHAR,    -- CustomerID
    Name                    VARCHAR,    -- CustomerName (from FACT_Base)
    HQ_Name                 VARCHAR,    -- CustomerHQID + CustomerHQName

    -- Program status
    CustomerProgramStatus   VARCHAR,    -- 'Contract' / 'Commit' / 'Open Market'

    -- Batch metadata
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

-- ---------------------------------------------------------------------------
-- 5. Raw_Item
--    Source: FACT_Base columns (Product_ID, Commodity_Name, Product_Name)
--    One row per Product_ID (distinct items/commodities)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE Raw_Item (
    -- Item identity
    Product_ID              VARCHAR,    -- CommodityID / ItemID
    Commodity_Name          VARCHAR,    -- CommodityName (display name)
    Product_Name            VARCHAR,    -- CommodityCategory (category grouping)

    -- Batch metadata
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

-- =============================================================================
-- POST-CREATE VALIDATION
-- =============================================================================

-- Confirm all 5 tables created
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'main'
--   AND table_name LIKE 'Raw_%'
-- ORDER BY table_name;
