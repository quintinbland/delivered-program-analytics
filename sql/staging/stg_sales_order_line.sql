-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_sales_order_line.sql
-- INPUT:       Raw_SalesOrderLine
-- OUTPUT:      Stg_SalesOrderLine
-- DIALECT:     DuckDB (ANSI-compatible; TRY_CAST replaced with TRY_CAST where
--              supported; fallback CAST used for DuckDB compatibility)
-- VERSION:     2.0.0 — Real data mapping applied (2026-06-23)
-- =============================================================================
-- CHANGE LOG (v2.0.0):
--   - Mapped all columns to confirmed real source columns from Copilot mapping
--   - SalesOrderID      ← FACT_Base.salesId
--   - SalesOrderLineID  ← FACT_Base.FactKey (new: line-level grain identifier)
--   - OrderDate         ← Order_Level_Query.shipDate (confirmed = DeliveryDate)
--   - ShipDate          ← FACT_Base.checkOut (CAST AS DATE)
--   - CustomerID        ← FACT_Base.shipTo
--   - CustomerHQID      ← FACT_Base.HQ_Name (replaces ShipToID)
--   - ItemID            ← FACT_Base.Product_ID
--   - QuantityCases     ← FACT_Base.qty (delivered qty only; ordered qty unavailable)
--   - ActualFOBPrice    ← BI_FactTable.FOB_Post_Adj (preferred); fallback FACT_Base.price
--   - NetLineRevenue    ← derived: ActualFOBPrice * QuantityCases
--   - LoadID            ← FACT_Base.loadId
--   - FreightCharged    ← REMOVED: moved to stg_load_freight.sql (load-level)
--   - UOM               ← hardcoded 'CASE' (pending confirmation)
--   - DivisionID        ← NULL (no direct source; future: derive from shipTo lookup)
--   - OrderType         ← CustomerProgramStatus (Contract/Commit/Open Market)
-- RESOLVED UNKNOWNS:
--   - UNK-007: FreightCharged is load-level total; moved to stg_load_freight
-- REMAINING OPEN:
--   - UNK-003: OnTargetFlag excluded; definition not confirmed
--   - QuantityOrdered has no source column; only QuantityDelivered available
--   - DivisionID has no direct source; defaulted to NULL
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per SalesOrderID + LoadID + ItemID.
--       FactKey (SalesOrderLineID) is a line-level identifier carried for
--       auditability but is not part of the deduplication key.
--   A2: NetLineRevenue is derived at staging as ActualFOBPrice * QuantityCases.
--       This differs from v1.0 which expected NetLineRevenue as a source column.
--   A3: checkOut column arrives as a timestamp; CAST to DATE applied.
--   A4: OrderDate = ShipDate (confirmed: no separate order date in source).
--   A5: CustomerProgramStatus (Contract/Commit/Open Market) is stored in
--       OrderType for downstream CustomerStatus dimension resolution.
--   A6: UOM is hardcoded to 'CASE' pending formal confirmation from source team.
--   A7: QuantityCases reflects delivered quantity only. Ordered quantity
--       is unavailable in this source; fulfillment rate calculations
--       must account for this limitation.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_SalesOrderLine AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting and NULL normalization
-- Source: Raw_SalesOrderLine
-- Column mapping: real source → pipeline column
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Natural key components
        CAST(salesId        AS VARCHAR(50))     AS SalesOrderID,
        CAST(FactKey        AS VARCHAR(50))     AS SalesOrderLineID,
        CAST(loadId         AS VARCHAR(50))     AS LoadID,
        CAST(Product_ID     AS VARCHAR(50))     AS ItemID,

        -- Customer dimension FKs
        CAST(shipTo         AS VARCHAR(50))     AS CustomerID,
        CAST(HQ_Name        AS VARCHAR(200))    AS CustomerHQID,

        -- CustomerProgramStatus → stored as OrderType for status resolution
        -- Values: 'Contract', 'Commit', 'Open Market'
        CAST(CustomerProgramStatus AS VARCHAR(50)) AS OrderType,

        -- Dates
        -- checkOut is a timestamp in source; cast to DATE
        TRY_CAST(checkOut   AS DATE)            AS ShipDate,
        -- OrderDate = ShipDate (confirmed; no independent order date in source)
        TRY_CAST(checkOut   AS DATE)            AS OrderDate,

        -- Quantity (delivered only; ordered qty unavailable)
        TRY_CAST(qty        AS DECIMAL(18, 4))  AS QuantityCases,

        -- FOB Price: prefer FOB_Post_Adj; fallback to price
        -- FOB_Post_Adj is the post-adjustment FOB used for variance calculations
        COALESCE(
            TRY_CAST(FOB_Post_Adj AS DECIMAL(18, 6)),
            TRY_CAST(price        AS DECIMAL(18, 6))
        )                                       AS ActualFOBPrice,

        -- UOM: hardcoded CASE pending confirmation
        'CASE'                                  AS UOM,

        -- Contract reference (pass-through only; not resolved at staging)
        CAST(NULL AS VARCHAR(50))               AS ContractID,

        -- SalesChannel: not available in source; defaulted NULL
        CAST(NULL AS VARCHAR(50))               AS SalesChannel,

        -- Batch metadata
        COALESCE(
            CAST(SourceSystem AS VARCHAR(100)),
            'FACT_BASE'
        )                                       AS SourceSystem,
        COALESCE(
            CAST(BatchID AS VARCHAR(100)),
            CAST(CURRENT_TIMESTAMP AS VARCHAR(30))
        )                                       AS BatchID,
        CURRENT_TIMESTAMP                       AS StagedAt

    FROM Raw_SalesOrderLine
),

-- ---------------------------------------------------------------------------
-- STEP 1b: Derived measures
-- NetLineRevenue derived here since source does not provide it directly.
-- UnitPrice = ActualFOBPrice (same value; retained for schema compatibility).
-- ---------------------------------------------------------------------------
derived AS (
    SELECT
        r.*,

        -- NetLineRevenue: ActualFOBPrice * QuantityCases
        -- NULL-safe: result is NULL if either input is NULL
        CASE
            WHEN r.ActualFOBPrice IS NOT NULL
             AND r.QuantityCases  IS NOT NULL
             AND r.QuantityCases  > 0
            THEN r.ActualFOBPrice * r.QuantityCases
            ELSE NULL
        END                                     AS NetLineRevenue,

        -- UnitPrice = ActualFOBPrice (schema compatibility alias)
        r.ActualFOBPrice                        AS UnitPrice

    FROM raw_cast r
),

-- ---------------------------------------------------------------------------
-- STEP 2: Deduplication detection
-- Duplicate = same SalesOrderID + LoadID + ItemID appearing more than once.
-- All duplicates RETAINED and flagged; not dropped.
-- ---------------------------------------------------------------------------
dedup_flag AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY SalesOrderID, LoadID, ItemID
            ORDER BY
                CASE
                    WHEN QuantityCases  IS NOT NULL
                     AND NetLineRevenue IS NOT NULL
                     AND ShipDate       IS NOT NULL
                    THEN 0
                    ELSE 1
                END ASC,
                StagedAt ASC
        ) AS DeduplicationRank,
        COUNT(*) OVER (
            PARTITION BY SalesOrderID, LoadID, ItemID
        ) AS DuplicateCount
    FROM derived
),

-- ---------------------------------------------------------------------------
-- STEP 3: Row-level data quality flags
-- ---------------------------------------------------------------------------
dq_flags AS (
    SELECT
        d.*,

        -- Surrogate key (deterministic hash of natural key)
        CONCAT(
            COALESCE(SalesOrderID, 'NULL'), '|',
            COALESCE(LoadID,       'NULL'), '|',
            COALESCE(ItemID,       'NULL')
        )                                       AS NaturalKeyHash,

        -- DQ FLAG: Duplicate natural key
        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                AS Flag_DuplicateKey,

        -- DQ FLAG: NULL or invalid QuantityCases
        CASE
            WHEN QuantityCases IS NULL THEN 1
            WHEN QuantityCases <= 0    THEN 1
            ELSE 0
        END                                     AS Flag_InvalidQuantity,

        -- DQ FLAG: NULL LoadID
        CASE WHEN LoadID IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingLoadID,

        -- DQ FLAG: NULL CustomerID
        CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingCustomerID,

        -- DQ FLAG: NULL CustomerHQID (replaces ShipToID flag from v1.0)
        CASE WHEN CustomerHQID IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingCustomerHQID,

        -- DQ FLAG: NULL ItemID
        CASE WHEN ItemID IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingItemID,

        -- DQ FLAG: NULL ShipDate
        CASE WHEN ShipDate IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingShipDate,

        -- DQ FLAG: NULL ActualFOBPrice
        CASE WHEN ActualFOBPrice IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingFOBPrice,

        -- DQ FLAG: NULL NetLineRevenue (derived; NULL means FOB or qty was missing)
        CASE WHEN NetLineRevenue IS NULL THEN 1 ELSE 0 END
                                                AS Flag_MissingRevenue,

        -- DQ FLAG: Negative NetLineRevenue
        CASE WHEN NetLineRevenue < 0 THEN 1 ELSE 0 END
                                                AS Flag_NegativeRevenue,

        -- DQ FLAG: CustomerProgramStatus outside controlled values
        CASE
            WHEN OrderType IS NULL THEN 1
            WHEN UPPER(TRIM(OrderType)) NOT IN ('CONTRACT','COMMIT','OPEN MARKET') THEN 1
            ELSE 0
        END                                     AS Flag_InvalidProgramStatus,

        -- COMPOSITE: Row is clean (all critical DQ flags = 0)
        CASE
            WHEN QuantityCases   IS NULL  THEN 0
            WHEN QuantityCases   <= 0     THEN 0
            WHEN LoadID          IS NULL  THEN 0
            WHEN CustomerID      IS NULL  THEN 0
            WHEN CustomerHQID    IS NULL  THEN 0
            WHEN ItemID          IS NULL  THEN 0
            WHEN ShipDate        IS NULL  THEN 0
            WHEN ActualFOBPrice  IS NULL  THEN 0
            WHEN NetLineRevenue  IS NULL  THEN 0
            WHEN DuplicateCount  > 1      THEN 0
            ELSE 1
        END                                     AS IsCleanRow

    FROM dedup_flag d
)

-- ---------------------------------------------------------------------------
-- STEP 4: Final projection — staging output
-- ---------------------------------------------------------------------------
SELECT
    -- Surrogate and natural keys
    NaturalKeyHash                              AS StagingKey,
    SalesOrderID,
    SalesOrderLineID,
    LoadID,
    ItemID,

    -- Dimension FKs (unresolved; resolution in dimension build layer)
    CustomerID,
    CustomerHQID,

    -- Dates (typed)
    ShipDate,
    OrderDate,

    -- Measures (raw)
    QuantityCases,
    ActualFOBPrice,
    UnitPrice,

    -- Measures (derived at staging)
    NetLineRevenue,

    -- Operational attributes
    UOM,
    ContractID,
    OrderType,          -- Contains CustomerProgramStatus values
    SalesChannel,

    -- Deduplication metadata
    DeduplicationRank,
    DuplicateCount,

    -- Data quality flags
    Flag_DuplicateKey,
    Flag_InvalidQuantity,
    Flag_MissingLoadID,
    Flag_MissingCustomerID,
    Flag_MissingCustomerHQID,
    Flag_MissingItemID,
    Flag_MissingShipDate,
    Flag_MissingFOBPrice,
    Flag_MissingRevenue,
    Flag_NegativeRevenue,
    Flag_InvalidProgramStatus,
    IsCleanRow,

    -- Batch metadata
    SourceSystem,
    BatchID,
    StagedAt

FROM dq_flags;

-- =============================================================================
-- POST-LOAD VALIDATION QUERIES
-- =============================================================================

-- Row count by clean/dirty status
-- SELECT IsCleanRow, COUNT(*) AS RowCount FROM Stg_SalesOrderLine GROUP BY IsCleanRow;

-- CustomerProgramStatus distribution
-- SELECT OrderType, COUNT(*) AS RowCount FROM Stg_SalesOrderLine GROUP BY OrderType;

-- Flag summary
-- SELECT
--     SUM(Flag_DuplicateKey)          AS Cnt_DuplicateKey,
--     SUM(Flag_InvalidQuantity)       AS Cnt_InvalidQuantity,
--     SUM(Flag_MissingLoadID)         AS Cnt_MissingLoadID,
--     SUM(Flag_MissingCustomerID)     AS Cnt_MissingCustomerID,
--     SUM(Flag_MissingCustomerHQID)   AS Cnt_MissingCustomerHQID,
--     SUM(Flag_MissingItemID)         AS Cnt_MissingItemID,
--     SUM(Flag_MissingShipDate)       AS Cnt_MissingShipDate,
--     SUM(Flag_MissingFOBPrice)       AS Cnt_MissingFOBPrice,
--     SUM(Flag_InvalidProgramStatus)  AS Cnt_InvalidProgramStatus
-- FROM Stg_SalesOrderLine;

-- NetLineRevenue reconciliation: sum must be positive
-- SELECT SUM(NetLineRevenue) AS TotalRevenue FROM Stg_SalesOrderLine WHERE IsCleanRow = 1;
