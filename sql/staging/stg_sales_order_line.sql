-- ============================================================
-- MODULE 1: STAGING LAYER
-- stg_sales_order_line.sql
-- 
-- Purpose: Load and standardize raw sales/order line data
--          into staging table for downstream fact build.
--
-- Inputs:  Raw_SalesOrderLine (ERP export)
-- Outputs: Stg_SalesOrderLine
-- Status:  STUB — pending source connection confirmation
-- ============================================================

-- DEPENDENCY: Source connection method UNKNOWN (UNK-006)
-- DEPENDENCY: Refresh cadence UNKNOWN (UNK-005)

CREATE TABLE Stg_SalesOrderLine AS
SELECT
    SalesOrderID,
    LoadID,
    ItemID,
    ShipToID,
    CustomerID,
    CAST(ShipDateTime AS DATE)          AS ShipDate,
    QuantityCases,
    UnitPrice,
    AdjustmentAmount,
    TotalAdjustmentAmount,
    QuantityCases * UnitPrice           AS GrossLineRevenue,
    LineRevenue                         AS SourceLineRevenue,
    PerCaseAdjustment,
    CustomerHQName,
    CustomerStatus,
    CommodityName,
    HarvestManager,
    ProductManager,
    'AX'                                AS SourceSystem,
    CURRENT_TIMESTAMP                   AS StagedAt
FROM Raw_SalesOrderLine
WHERE LoadID          IS NOT NULL
  AND ItemID          IS NOT NULL
  AND QuantityCases   IS NOT NULL;
