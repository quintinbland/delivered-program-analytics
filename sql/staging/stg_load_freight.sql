-- ============================================================
-- MODULE 1: STAGING LAYER
-- stg_load_freight.sql
--
-- Purpose: Load and standardize raw load/freight data
--          into staging table for downstream fact build.
--
-- Inputs:  Raw_LoadFreight (ERP or freight system export)
-- Outputs: Stg_LoadFreight
-- Status:  STUB — pending source connection confirmation
-- ============================================================

-- DEPENDENCY: Source connection method UNKNOWN (UNK-006)
-- DEPENDENCY: Whether FreightCharged = billed/budgeted/allocated UNKNOWN (UNK-007)

CREATE TABLE Stg_LoadFreight AS
SELECT
    LoadID,
    CAST(ShipDate AS DATE)   AS ShipDate,
    ShipToID,
    CustomerID,
    CustomerName,
    CustomerHQName,
    CustomerStatus,
    LoadPallets,
    FreightCharged,
    FreightPaid,
    CarrierID,
    CarrierName,
    OriginLocationID,
    DestinationLocationID,
    PurchaseOrderID,
    SourceLoadStatus,
    SourceSystem,
    CURRENT_TIMESTAMP        AS StagedAt
FROM Raw_LoadFreight
WHERE LoadID IS NOT NULL;
