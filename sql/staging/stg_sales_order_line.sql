-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_sales_order_line.sql
-- INPUT:       Raw_SalesOrderLine
-- OUTPUT:      Stg_SalesOrderLine
-- DIALECT:     DuckDB (ANSI-compatible)
-- VERSION:     2.1.0 — Mode_of_Delivery added; FactKey/SalesOrderLineID removed (2026-06-24)
-- =============================================================================
-- CHANGE LOG (v2.1.0):
--   - Mode_of_Delivery added: CAST(Mode_of_Delivery AS VARCHAR(50))
--     Source: Raw_SalesOrderLine.Mode_of_Delivery (AX DlvMode field)
--     Values: 'Dlv' (Delivered), 'PUP' (FOB/Pickup)
--     Consumed by: stg_load_freight v2.2.0 mode_map CTE (reads Raw_SalesOrderLine directly)
--     Also carried in Stg_SalesOrderLine for auditability and future mode-level reporting.
--   - FactKey / SalesOrderLineID removed: column no longer present in fact_base.csv export.
--     SalesOrderLineID defaulted to NULL for schema compatibility.
--   - checkOut: source now exports as VARCHAR date string (no serial conversion needed).
--   - A8 added: Mode_of_Delivery source value documentation.
-- CHANGE LOG (v2.0.0):
--   - Mapped all columns to confirmed real source columns from Copilot mapping
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per SalesOrderID + LoadID + ItemID.
--   A2: NetLineRevenue is derived at staging as ActualFOBPrice * QuantityCases.
--   A3: checkOut arrives as VARCHAR date string from Power Query export; TRY_CAST to DATE.
--   A4: OrderDate = ShipDate (confirmed; no independent order date in source).
--   A5: CustomerProgramStatus (Contract/Commit/Open Market) stored as OrderType.
--   A6: UOM hardcoded to 'CASE' pending formal confirmation.
--   A7: QuantityCases reflects delivered quantity only. Ordered qty unavailable.
--   A8: Mode_of_Delivery source values are 'Dlv' and 'PUP'.
--       'Dlv' = Delivered (Bonipak arranges and bills freight).
--       'PUP' = Pickup / FOB (customer arranges freight; zero freight charge valid).
--       stg_load_freight v2.2.0 derives load-level Mode by aggregating this column
--       directly from Raw_SalesOrderLine using UPPER(TRIM()) for case normalization.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_SalesOrderLine AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting and NULL normalization
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Natural key components
        CAST(salesId        AS VARCHAR(50))     AS SalesOrderID,
        -- SalesOrderLineID: FactKey removed from source in v2.1.0; defaulted NULL
        CAST(NULL           AS VARCHAR(50))     AS SalesOrderLineID,
        CAST(loadId         AS VARCHAR(50))     AS LoadID,
        CAST(Product_ID     AS VARCHAR(50))     AS ItemID,

        -- Customer dimension FKs
        CAST(shipTo         AS VARCHAR(50))     AS CustomerID,
        CAST(HQ_Name        AS VARCHAR(200))    AS CustomerHQID,

        -- CustomerProgramStatus → stored as OrderType for status resolution
        -- Values: 'Contract', 'Commit', 'Open Market'
        CAST(CustomerProgramStatus AS VARCHAR(50)) AS OrderType,

        -- Dates
        -- v2.1.1: checkOut format is M/D/YYYY H:MM from Power Query export
        -- DuckDB strptime handles single-digit month/day with %-m/%-d on Linux
        -- On Windows DuckDB use TRY_STRPTIME with explicit format
        TRY_STRPTIME(checkOut, '%m/%d/%Y %H:%M')::DATE   AS ShipDate,
        TRY_STRPTIME(checkOut, '%m/%d/%Y %H:%M')::DATE   AS OrderDate,

        -- Quantity (delivered only; ordered qty unavailable)
        TRY_CAST(qty        AS DECIMAL(18, 4))  AS QuantityCases,

        -- FOB Price: prefer FOB_Post_Adj; fallback to price
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

        -- Mode of Delivery: 'Dlv' (Delivered) or 'PUP' (FOB/Pickup)
        -- Consumed by stg_load_freight v2.2.0 via direct Raw_SalesOrderLine query.
        -- Carried here for auditability and mode-level reporting.
        CAST(Mode_of_Delivery AS VARCHAR(50))   AS Mode_of_Delivery,

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
-- ---------------------------------------------------------------------------
derived AS (
    SELECT
        r.*,

        -- NetLineRevenue: ActualFOBPrice * QuantityCases
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

        -- DQ FLAG: NULL CustomerHQID
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

        -- DQ FLAG: NULL NetLineRevenue
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

        -- COMPOSITE: Row is clean
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

    -- Dimension FKs
    CustomerID,
    CustomerHQID,

    -- Dates
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
    OrderType,
    SalesChannel,
    Mode_of_Delivery,

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

-- Mode_of_Delivery distribution
-- SELECT Mode_of_Delivery, COUNT(*) AS RowCount FROM Stg_SalesOrderLine GROUP BY Mode_of_Delivery;

-- CustomerProgramStatus distribution
-- SELECT OrderType, COUNT(*) AS RowCount FROM Stg_SalesOrderLine GROUP BY OrderType;

-- NetLineRevenue reconciliation
-- SELECT SUM(NetLineRevenue) AS TotalRevenue FROM Stg_SalesOrderLine WHERE IsCleanRow = 1;
