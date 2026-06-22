-- =============================================================================
-- MODULE:      Staging Layer
-- SCRIPT:      stg_sales_order_line.sql
-- INPUT:       Raw_SalesOrderLine
-- OUTPUT:      Stg_SalesOrderLine
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Source grain is one row per SalesOrderID + LoadID + ItemID.
--       Duplicate keys in source are a data quality issue — flagged, not dropped.
--   A2: NetLineRevenue is the post-discount, post-adjustment revenue figure.
--       No revenue derivation occurs at staging; value is passed through as-is.
--   A3: ShipDate arrives as a character string; format assumed YYYY-MM-DD.
--       If source format differs, adjust TRY_CAST expression accordingly.
--   A4: CustomerID and ShipToID are passed through as-is. Resolution to
--       Dim_Customer and Dim_ShipTo occurs in the dimension build layer.
--   A5: QuantityCases of zero is flagged as invalid. Zero-case rows are
--       retained in staging for exception routing; they are NOT dropped.
--   A6: LoadID NULL is flagged. Rows with NULL LoadID are retained in staging.
--   A7: BatchID and SourceSystem are supplied by the calling ETL process.
--       If not available, defaults are applied (see COALESCE below).
-- OPEN UNKNOWNS AFFECTING THIS SCRIPT:
--   UNK-003: OnTargetFlag — field is excluded; definition not confirmed.
--   UNK-007: FreightCharged semantics — not applicable to this script.
-- =============================================================================

CREATE OR REPLACE TABLE Stg_SalesOrderLine AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Raw ingest with type casting and NULL normalization
-- ---------------------------------------------------------------------------
raw_cast AS (
    SELECT
        -- Natural key components (cast to VARCHAR for safe dedup hashing)
        CAST(SalesOrderID    AS VARCHAR(50))   AS SalesOrderID,
        CAST(LoadID          AS VARCHAR(50))   AS LoadID,
        CAST(ItemID          AS VARCHAR(50))   AS ItemID,

        -- Customer / location dimensions
        CAST(CustomerID      AS VARCHAR(50))   AS CustomerID,
        CAST(ShipToID        AS VARCHAR(50))   AS ShipToID,

        -- Dates
        -- [DIALECT NOTE] TRY_CAST is T-SQL / Snowflake.
        -- In strict ANSI: CAST(ShipDate AS DATE) — no error suppression.
        TRY_CAST(ShipDate    AS DATE)          AS ShipDate,
        TRY_CAST(OrderDate   AS DATE)          AS OrderDate,

        -- Quantities and revenue
        -- [DIALECT NOTE] TRY_CAST suppresses bad numeric values to NULL.
        TRY_CAST(QuantityCases       AS DECIMAL(18, 4))  AS QuantityCases,
        TRY_CAST(NetLineRevenue      AS DECIMAL(18, 4))  AS NetLineRevenue,
        TRY_CAST(UnitPrice           AS DECIMAL(18, 6))  AS UnitPrice,

        -- Contract reference (raw; not resolved at staging)
        CAST(ContractID      AS VARCHAR(50))   AS ContractID,

        -- Operational flags from source (pass-through)
        CAST(OrderType       AS VARCHAR(50))   AS OrderType,
        CAST(SalesChannel    AS VARCHAR(50))   AS SalesChannel,

        -- Batch metadata
        -- [DIALECT NOTE] COALESCE + CURRENT_TIMESTAMP is ANSI-compatible.
        COALESCE(
            CAST(SourceSystem AS VARCHAR(100)),
            'ERP_SALESORDERLINE'
        )                                       AS SourceSystem,
        COALESCE(
            CAST(BatchID AS VARCHAR(100)),
            CAST(CURRENT_TIMESTAMP AS VARCHAR(30))
        )                                       AS BatchID,
        CURRENT_TIMESTAMP                       AS StagedAt

    FROM Raw_SalesOrderLine
),

-- ---------------------------------------------------------------------------
-- STEP 2: Deduplication detection
-- Duplicate = same SalesOrderID + LoadID + ItemID appearing more than once.
-- All duplicates are RETAINED and flagged. Deduplication decision is
-- delegated to the exception layer.
-- ---------------------------------------------------------------------------
dedup_flag AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY SalesOrderID, LoadID, ItemID
            ORDER BY
                -- Prefer rows with more complete data; NULLs rank last.
                -- [DIALECT NOTE] CASE expression is ANSI-compatible.
                CASE
                    WHEN QuantityCases IS NOT NULL
                     AND NetLineRevenue IS NOT NULL
                     AND ShipDate IS NOT NULL
                    THEN 0
                    ELSE 1
                END ASC,
                StagedAt ASC
        ) AS DeduplicationRank,
        COUNT(*) OVER (
            PARTITION BY SalesOrderID, LoadID, ItemID
        ) AS DuplicateCount
    FROM raw_cast
),

-- ---------------------------------------------------------------------------
-- STEP 3: Row-level data quality flags
-- Each flag is independently evaluated. Multiple flags per row are allowed.
-- ---------------------------------------------------------------------------
dq_flags AS (
    SELECT
        d.*,

        -- Surrogate key candidate (deterministic hash of natural key)
        -- [DIALECT NOTE] CONCAT is ANSI. MD5/SHA2 hash varies by platform:
        --   T-SQL:      CONVERT(VARCHAR, HASHBYTES('SHA2_256', ...), 2)
        --   Snowflake:  SHA2(CONCAT(...), 256)
        -- Using CONCAT for portability; replace with platform hash if needed.
        CONCAT(
            COALESCE(SalesOrderID, 'NULL'), '|',
            COALESCE(LoadID,       'NULL'), '|',
            COALESCE(ItemID,       'NULL')
        )                                           AS NaturalKeyHash,

        -- DQ FLAG: Duplicate natural key
        CASE WHEN DuplicateCount > 1 THEN 1 ELSE 0 END
                                                    AS Flag_DuplicateKey,

        -- DQ FLAG: NULL or invalid QuantityCases
        CASE
            WHEN QuantityCases IS NULL THEN 1
            WHEN QuantityCases <= 0    THEN 1
            ELSE 0
        END                                         AS Flag_InvalidQuantity,

        -- DQ FLAG: NULL LoadID
        CASE WHEN LoadID IS NULL THEN 1 ELSE 0 END  AS Flag_MissingLoadID,

        -- DQ FLAG: NULL CustomerID
        CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingCustomerID,

        -- DQ FLAG: NULL ShipToID
        CASE WHEN ShipToID IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingShipToID,

        -- DQ FLAG: NULL ItemID
        CASE WHEN ItemID IS NULL THEN 1 ELSE 0 END  AS Flag_MissingItemID,

        -- DQ FLAG: NULL or unparseable ShipDate
        CASE WHEN ShipDate IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingShipDate,

        -- DQ FLAG: NULL NetLineRevenue
        CASE WHEN NetLineRevenue IS NULL THEN 1 ELSE 0 END
                                                    AS Flag_MissingRevenue,

        -- DQ FLAG: Negative NetLineRevenue (allowed but flagged for review)
        CASE WHEN NetLineRevenue < 0 THEN 1 ELSE 0 END
                                                    AS Flag_NegativeRevenue,

        -- COMPOSITE: Row is clean (all critical DQ flags = 0)
        CASE
            WHEN QuantityCases IS NULL  THEN 0
            WHEN QuantityCases <= 0     THEN 0
            WHEN LoadID IS NULL         THEN 0
            WHEN CustomerID IS NULL     THEN 0
            WHEN ShipToID IS NULL       THEN 0
            WHEN ItemID IS NULL         THEN 0
            WHEN ShipDate IS NULL       THEN 0
            WHEN NetLineRevenue IS NULL THEN 0
            ELSE 1
        END                                         AS IsCleanRow

    FROM dedup_flag d
)

-- ---------------------------------------------------------------------------
-- STEP 4: Final projection — staging output
-- ---------------------------------------------------------------------------
SELECT
    -- Surrogate and natural keys
    NaturalKeyHash                          AS StagingKey,
    SalesOrderID,
    LoadID,
    ItemID,

    -- Dimension FKs (unresolved; resolution in dimension build layer)
    CustomerID,
    ShipToID,

    -- Dates (typed)
    ShipDate,
    OrderDate,

    -- Measures
    QuantityCases,
    NetLineRevenue,
    UnitPrice,

    -- Source references
    ContractID,
    OrderType,
    SalesChannel,

    -- Deduplication metadata
    DeduplicationRank,
    DuplicateCount,

    -- Data quality flags
    Flag_DuplicateKey,
    Flag_InvalidQuantity,
    Flag_MissingLoadID,
    Flag_MissingCustomerID,
    Flag_MissingShipToID,
    Flag_MissingItemID,
    Flag_MissingShipDate,
    Flag_MissingRevenue,
    Flag_NegativeRevenue,
    IsCleanRow,

    -- Batch metadata
    SourceSystem,
    BatchID,
    StagedAt

FROM dq_flags;

-- =============================================================================
-- POST-LOAD VALIDATION QUERIES
-- Run after load to confirm row counts and flag distribution.
-- =============================================================================

-- Row count by clean/dirty status
-- SELECT IsCleanRow, COUNT(*) AS RowCount
-- FROM Stg_SalesOrderLine
-- GROUP BY IsCleanRow;

-- Flag summary
-- SELECT
--     SUM(Flag_DuplicateKey)       AS Cnt_DuplicateKey,
--     SUM(Flag_InvalidQuantity)    AS Cnt_InvalidQuantity,
--     SUM(Flag_MissingLoadID)      AS Cnt_MissingLoadID,
--     SUM(Flag_MissingCustomerID)  AS Cnt_MissingCustomerID,
--     SUM(Flag_MissingShipToID)    AS Cnt_MissingShipToID,
--     SUM(Flag_MissingItemID)      AS Cnt_MissingItemID,
--     SUM(Flag_MissingShipDate)    AS Cnt_MissingShipDate,
--     SUM(Flag_MissingRevenue)     AS Cnt_MissingRevenue,
--     SUM(Flag_NegativeRevenue)    AS Cnt_NegativeRevenue
-- FROM Stg_SalesOrderLine;
