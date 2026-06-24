-- =============================================================================
-- IMPLEMENTATION: Phase 1 — Raw Table Creation
-- TARGET:         DuckDB
-- PURPOSE:        Create all raw landing tables using real source column names
-- VERSION:        2.0.0 — Real data column names (2026-06-23)
-- =============================================================================

CREATE OR REPLACE TABLE Raw_SalesOrderLine (
    salesId                 VARCHAR,
    FactKey                 VARCHAR,
    loadId                  VARCHAR,
    shipTo                  VARCHAR,
    HQ_Name                 VARCHAR,
    CustomerProgramStatus   VARCHAR,
    Product_ID              VARCHAR,
    checkOut                VARCHAR,
    qty                     DECIMAL(18,4),
    FOB_Post_Adj            DECIMAL(18,6),
    price                   DECIMAL(18,6),
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

CREATE OR REPLACE TABLE Raw_LoadFreight (
    loadId                  VARCHAR,
    carrierName             VARCHAR,
    warehouse               VARCHAR,
    shipDate                VARCHAR,
    loadShippingCharged     DECIMAL(18,4),
    loadShippingCost        DECIMAL(18,4),
    loadPallets             DECIMAL(10,2),
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

CREATE OR REPLACE TABLE Raw_ContractPricing (
    Customer_HQ             VARCHAR,
    Commodity               VARCHAR,
    Contract_FOB            DECIMAL(18,6),
    CustomerProgramStatus   VARCHAR,
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

CREATE OR REPLACE TABLE Raw_Customer (
    shipTo                  VARCHAR,
    Name                    VARCHAR,
    HQ_Name                 VARCHAR,
    CustomerProgramStatus   VARCHAR,
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

CREATE OR REPLACE TABLE Raw_Item (
    Product_ID              VARCHAR,
    Commodity_Name          VARCHAR,
    Product_Name            VARCHAR,
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

-- Retain stub tables referenced by dimension scripts
-- These will be empty with real data but prevent dimension scripts from erroring
CREATE OR REPLACE TABLE Raw_CustomerReference (
    CustomerID              VARCHAR,
    CustomerHQID            VARCHAR,
    CustomerName            VARCHAR,
    CustomerHQName          VARCHAR,
    CustomerStatusKey       VARCHAR,
    CustomerStatus          VARCHAR,
    CustomerRegion          VARCHAR,
    CustomerSegment         VARCHAR,
    SalesRepID              VARCHAR,
    ActiveFlag              VARCHAR,
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

CREATE OR REPLACE TABLE Raw_ProductMaster (
    ItemID                  VARCHAR,
    CommodityID             VARCHAR,
    ItemDescription         VARCHAR,
    ItemCategory            VARCHAR,
    PackSize                VARCHAR,
    UnitOfMeasure           VARCHAR,
    OrganicConventionalFlag VARCHAR,
    ActiveFlag              VARCHAR,
    WeightPerCase           VARCHAR,
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

CREATE OR REPLACE TABLE Raw_ShipToReference (
    ShipToID                VARCHAR,
    CustomerID              VARCHAR,
    ShipToName              VARCHAR,
    City                    VARCHAR,
    StateProvince           VARCHAR,
    ActiveFlag              VARCHAR,
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

CREATE OR REPLACE TABLE Raw_CommodityReference (
    CommodityID             VARCHAR,
    CommodityName           VARCHAR,
    CommodityGroup          VARCHAR,
    CommodityCategory       VARCHAR,
    SeasonalityWindow       VARCHAR,
    ActiveFlag              VARCHAR
);

-- =============================================================================
-- VALIDATION
-- =============================================================================
SELECT table_name, estimated_size AS RowCount
FROM duckdb_tables()
WHERE table_name LIKE 'Raw_%'
ORDER BY table_name;

-- =============================================================================
-- PATCH:   Add Raw_CommodityMapping table to phase1_create_raw_tables.sql
-- ACTION:  Append this CREATE TABLE statement to the end of
--          implementation/duckdb_patches/phase1_create_raw_tables.sql
-- VERSION: v2.1.0 (2026-06-24)
-- =============================================================================
-- Raw_CommodityMapping — ItemID → canonical CommodityID lookup
-- Source: data/commodity_mapping.csv (Copilot-generated, manually reviewed)
-- Consumed by: stg_product_master.sql (replaces NULL CommodityID from Raw_Item)
-- =============================================================================

CREATE OR REPLACE TABLE Raw_CommodityMapping (
    ItemID              VARCHAR,    -- matches Raw_Item.Product_ID / Stg_ProductMaster.ItemID
    CommodityID_Mapped  VARCHAR,    -- canonical commodity name; 'UNKNOWN' treated as NULL
    SourceSystem        VARCHAR,
    BatchID             VARCHAR
);
