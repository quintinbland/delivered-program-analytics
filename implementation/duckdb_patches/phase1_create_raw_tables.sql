-- =============================================================================
-- IMPLEMENTATION: Phase 1 — Raw Table Creation
-- TARGET:         DuckDB
-- PURPOSE:        Create all 7 raw landing tables before data load
-- RUN:            Execute once before Phase 2 data load
-- =============================================================================

CREATE OR REPLACE TABLE Raw_SalesOrderLine (
    SalesOrderID            VARCHAR,
    LoadID                  VARCHAR,
    ItemID                  VARCHAR,
    CustomerID              VARCHAR,
    ShipToID                VARCHAR,
    ShipDate                VARCHAR,
    OrderDate               VARCHAR,
    QuantityCases           VARCHAR,
    NetLineRevenue          VARCHAR,
    UnitPrice               VARCHAR,
    ContractID              VARCHAR,
    OrderType               VARCHAR,
    SalesChannel            VARCHAR,
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

CREATE OR REPLACE TABLE Raw_LoadFreight (
    LoadID                  VARCHAR,
    CarrierID               VARCHAR,
    LoadDate                VARCHAR,
    DeliveryDate            VARCHAR,
    FreightCharged          VARCHAR,
    FreightPaid             VARCHAR,
    LoadPallets             VARCHAR,
    LoadWeight              VARCHAR,
    OriginWarehouse         VARCHAR,
    ShipToID                VARCHAR,
    SourceSystem            VARCHAR,
    BatchID                 VARCHAR
);

CREATE OR REPLACE TABLE Raw_ContractPricing (
    ContractPriceKey        VARCHAR,
    CustomerID              VARCHAR,
    CustomerHQID            VARCHAR,
    ItemID                  VARCHAR,
    CommodityID             VARCHAR,
    ContractFOBPrice        VARCHAR,
    EffectiveDate           VARCHAR,
    ExpirationDate          VARCHAR,
    ContractType            VARCHAR,
    ContractStatus          VARCHAR,
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

CREATE OR REPLACE TABLE Raw_ShipToReference (
    ShipToID                VARCHAR,
    CustomerID              VARCHAR,
    ShipToName              VARCHAR,
    AddressLine1            VARCHAR,
    AddressLine2            VARCHAR,
    City                    VARCHAR,
    StateProvince           VARCHAR,
    ZipPostalCode           VARCHAR,
    Country                 VARCHAR,
    Region                  VARCHAR,
    DeliveryDayOfWeek       VARCHAR,
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
-- VALIDATION: Run after execution
-- Expected: 7 rows, one per table, RowCount = 0 (empty — data not loaded yet)
-- =============================================================================
SELECT table_name, estimated_size AS RowCount
FROM duckdb_tables()
WHERE table_name LIKE 'Raw_%'
ORDER BY table_name;
