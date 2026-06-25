-- =============================================================================
-- MODULE:      Fact Tables
-- SCRIPT:      fact_sales_order_line.sql
-- INPUT:       Stg_SalesOrderLine, Stg_ProductMaster, Dim_Customer, Dim_Product,
--              Dim_ShipTo, Dim_Date, Stg_ContractPricing, Fact_LoadFreight
-- OUTPUT:      Fact_SalesOrderLine
-- DIALECT:     DuckDB (STRFTIME patch applied)
-- VERSION:     1.1.0 — Non-produce exclusion via Stg_ProductMaster (2026-06-25)
-- =============================================================================
-- CHANGE LOG (v1.1.0):
--   - Non-produce items excluded from fact output via LEFT JOIN to
--     Stg_ProductMaster on ItemID; rows where Flag_NonProduce = 1 filtered
--     in source CTE. Resolves UNK-009.
-- CHANGE LOG (v1.0.2):
--   - Removed s.ShipToID reference (not in Stg_SalesOrderLine v2.0)
--     ShipToKey hardcoded to -1; Flag_ShipToNotInDim hardcoded to 0
--   - Removed s.Flag_MissingShipToID (not in Stg_SalesOrderLine v2.0)
--   - Removed BETWEEN date range filter from tier1/tier2/tier3 CTEs (UNK-001 resolved)
--   - Removed cp.Flag_InvertedDateRange from tier1/tier2/tier3 CTEs (column removed)
--   - Flag_CandidateHierarchy_UNK001 retained for schema compatibility
-- =============================================================================

CREATE OR REPLACE TABLE Fact_SalesOrderLine AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Source from staging — primary record per natural key, clean only
-- Non-produce items excluded via LEFT JOIN to Stg_ProductMaster
-- ---------------------------------------------------------------------------
source AS (
    SELECT s.*
    FROM Stg_SalesOrderLine s
    LEFT JOIN Stg_ProductMaster pm
        ON UPPER(TRIM(s.ItemID)) = UPPER(TRIM(pm.ItemID))
       AND pm.DeduplicationRank = 1
    WHERE s.DeduplicationRank = 1
      AND s.IsCleanRow = 1
      AND COALESCE(pm.Flag_NonProduce, 0) = 0
),

-- ---------------------------------------------------------------------------
-- STEP 2: Resolve dimension foreign keys
-- ---------------------------------------------------------------------------
dim_resolved AS (
    SELECT
        s.SalesOrderID,
        s.LoadID,
        s.ItemID                                        AS ItemID_Source,
        s.CustomerID                                    AS CustomerID_Source,

        -- CustomerKey
        COALESCE(dc.CustomerKey, -1)                    AS CustomerKey,
        -- CustomerHQID carried for contract matching (Tier 2/3)
        dc.CustomerHQID                                 AS CustomerHQID,

        -- ProductKey + CommodityID (needed for Tier 3 matching)
        COALESCE(dp.ProductKey, -1)                     AS ProductKey,
        dp.CommodityID_Source                           AS CommodityID,

        -- ShipToKey: no ShipToID in staging v2.0; hardcoded -1
        -1                                              AS ShipToKey,

        -- DateKeys
        CASE
            WHEN s.ShipDate IS NOT NULL
            THEN CAST(STRFTIME(s.ShipDate,  '%Y%m%d') AS INTEGER)
            ELSE -1
        END                                             AS ShipDateKey,
        CASE
            WHEN s.OrderDate IS NOT NULL
            THEN CAST(STRFTIME(s.OrderDate, '%Y%m%d') AS INTEGER)
            ELSE -1
        END                                             AS OrderDateKey,

        -- Raw dates retained for downstream use
        s.ShipDate,
        s.OrderDate,

        -- Measures from staging
        s.QuantityCases,
        s.NetLineRevenue,
        s.UnitPrice,

        -- Operational attributes
        s.ContractID,
        s.OrderType,
        s.SalesChannel,

        -- Staging flags carried forward
        s.Flag_MissingCustomerID,
        s.Flag_MissingItemID,
        s.Flag_NegativeRevenue,

        -- FK resolution flags
        CASE WHEN dc.CustomerKey IS NULL THEN 1 ELSE 0 END  AS Flag_CustomerNotInDim,
        CASE WHEN dp.ProductKey  IS NULL THEN 1 ELSE 0 END  AS Flag_ProductNotInDim,
        0                                                   AS Flag_ShipToNotInDim,

        -- Lineage
        s.StagingKey,
        s.SourceSystem,
        s.BatchID

    FROM source s

    LEFT JOIN Dim_Customer dc
        ON s.CustomerID = dc.CustomerID
       AND dc.CustomerKey <> -1

    LEFT JOIN Dim_Product dp
        ON s.ItemID = dp.ItemID
       AND dp.ProductKey <> -1
),

-- ---------------------------------------------------------------------------
-- STEP 3: Contract matching — confirmed hierarchy (UNK-001 RESOLVED)
-- Contract > Commit > Open Market
-- Date range filter removed: real contracts have no date range
-- (EffectiveDate = 1900-01-01, ExpirationDate = 9999-12-31 by default)
-- ---------------------------------------------------------------------------

-- Tier 1: CustomerID + ItemID
-- No matches expected with real data (contracts are HQ-level only)
tier1 AS (
    SELECT
        d.SalesOrderID,
        d.LoadID,
        d.ItemID_Source,
        cp.ContractFOBPrice                             AS ContractFOBPrice,
        cp.ContractPriceKey                             AS ContractPriceKey,
        1                                               AS MatchTier,
        'Tier1_CustomerItem'                            AS ContractMatchTier
    FROM dim_resolved d
    JOIN Stg_ContractPricing cp
        ON d.CustomerID_Source  = cp.CustomerID
       AND d.ItemID_Source       = cp.ItemID
       AND cp.IsCleanRow         = 1
),

-- Tier 2: CustomerHQID + ItemID
-- No matches expected with real data (ItemID is NULL on all contract records)
tier2 AS (
    SELECT
        d.SalesOrderID,
        d.LoadID,
        d.ItemID_Source,
        cp.ContractFOBPrice,
        cp.ContractPriceKey,
        2                                               AS MatchTier,
        'Tier2_HQItem'                                  AS ContractMatchTier
    FROM dim_resolved d
    JOIN Stg_ContractPricing cp
        ON d.CustomerHQID        = cp.CustomerHQID
       AND d.ItemID_Source        = cp.ItemID
       AND cp.IsCleanRow          = 1
    WHERE NOT EXISTS (
        SELECT 1 FROM tier1 t
        WHERE t.SalesOrderID  = d.SalesOrderID
          AND t.LoadID         = d.LoadID
          AND t.ItemID_Source  = d.ItemID_Source
    )
),

-- Tier 3: CustomerHQID + CommodityID
-- Primary matching tier with real data
tier3 AS (
    SELECT
        d.SalesOrderID,
        d.LoadID,
        d.ItemID_Source,
        cp.ContractFOBPrice,
        cp.ContractPriceKey,
        3                                               AS MatchTier,
        'Tier3_HQCommodity'                             AS ContractMatchTier
    FROM dim_resolved d
    JOIN Stg_ContractPricing cp
        ON d.CustomerHQID        = cp.CustomerHQID
       AND d.CommodityID         = cp.CommodityID
       AND cp.IsCleanRow         = 1
    WHERE NOT EXISTS (
        SELECT 1 FROM tier1 t
        WHERE t.SalesOrderID  = d.SalesOrderID
          AND t.LoadID         = d.LoadID
          AND t.ItemID_Source  = d.ItemID_Source
    )
    AND NOT EXISTS (
        SELECT 1 FROM tier2 t
        WHERE t.SalesOrderID  = d.SalesOrderID
          AND t.LoadID         = d.LoadID
          AND t.ItemID_Source  = d.ItemID_Source
    )
),

all_tiers AS (
    SELECT * FROM tier1
    UNION ALL
    SELECT * FROM tier2
    UNION ALL
    SELECT * FROM tier3
),

contract_matched AS (
    SELECT
        SalesOrderID,
        LoadID,
        ItemID_Source,
        ContractFOBPrice,
        ContractPriceKey,
        MatchTier,
        ContractMatchTier
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY SalesOrderID, LoadID, ItemID_Source
                ORDER BY MatchTier ASC, ContractFOBPrice ASC
            ) AS _rn
        FROM all_tiers
    ) ranked
    WHERE _rn = 1
),

-- ---------------------------------------------------------------------------
-- STEP 4: Join contract match back to transaction rows
-- ---------------------------------------------------------------------------
with_contract AS (
    SELECT
        d.*,
        cm.ContractFOBPrice                             AS ContractFOBPrice,
        cm.ContractPriceKey                             AS ContractPriceKey,
        COALESCE(cm.ContractMatchTier, 'NoMatch')       AS ContractMatchTier,
        COALESCE(cm.MatchTier, 4)                       AS MatchTierNumber,

        -- Retained for schema compatibility (UNK-001 now resolved)
        1                                               AS Flag_CandidateHierarchy_UNK001,

        CASE
            WHEN cm.ContractFOBPrice IS NULL THEN 1
            ELSE 0
        END                                             AS Flag_NoContractMatch

    FROM dim_resolved d
    LEFT JOIN contract_matched cm
        ON d.SalesOrderID  = cm.SalesOrderID
       AND d.LoadID         = cm.LoadID
       AND d.ItemID_Source  = cm.ItemID_Source
),

-- ---------------------------------------------------------------------------
-- STEP 5: Calculated measures
-- ---------------------------------------------------------------------------
calculated AS (
    SELECT
        w.*,

        CASE
            WHEN w.QuantityCases IS NULL OR w.QuantityCases = 0 THEN NULL
            ELSE w.NetLineRevenue / w.QuantityCases
        END                                             AS ActualFOB,

        CASE
            WHEN w.QuantityCases IS NULL OR w.QuantityCases = 0 THEN NULL
            WHEN w.ContractFOBPrice IS NULL THEN NULL
            ELSE (w.NetLineRevenue / w.QuantityCases) - w.ContractFOBPrice
        END                                             AS FOBVariancePerCase,

        CASE
            WHEN w.QuantityCases IS NULL OR w.QuantityCases = 0 THEN NULL
            WHEN w.ContractFOBPrice IS NULL THEN NULL
            ELSE ((w.NetLineRevenue / w.QuantityCases) - w.ContractFOBPrice)
                 * w.QuantityCases
        END                                             AS TotalFOBVariance,

        CASE
            WHEN w.QuantityCases IS NULL OR w.QuantityCases = 0 THEN NULL
            WHEN w.ContractFOBPrice IS NULL THEN NULL
            ELSE ((w.NetLineRevenue / w.QuantityCases) - w.ContractFOBPrice)
                 * w.QuantityCases
        END                                             AS ExcessSalesProfit,

        CASE
            WHEN w.ContractFOBPrice IS NOT NULL
             AND w.QuantityCases > 0
             AND ((w.NetLineRevenue / w.QuantityCases) - w.ContractFOBPrice)
                 * w.QuantityCases < 0
            THEN 1 ELSE 0
        END                                             AS Flag_NegativeFOBVariance

    FROM with_contract w
)

-- ---------------------------------------------------------------------------
-- STEP 6: Final projection
-- ---------------------------------------------------------------------------
SELECT
    StagingKey                                          AS SalesOrderLineKey,
    SalesOrderID,
    LoadID,
    ItemID_Source                                       AS ItemID,
    CustomerKey,
    ProductKey,
    ShipToKey,
    ShipDateKey,
    OrderDateKey,
    ContractPriceKey,
    ContractMatchTier,
    MatchTierNumber,
    QuantityCases,
    NetLineRevenue,
    UnitPrice,
    ContractFOBPrice,
    ActualFOB,
    FOBVariancePerCase,
    TotalFOBVariance,
    ExcessSalesProfit,
    ContractID,
    OrderType,
    SalesChannel,
    Flag_CandidateHierarchy_UNK001,
    Flag_NoContractMatch,
    Flag_NegativeFOBVariance,
    Flag_CustomerNotInDim,
    Flag_ProductNotInDim,
    Flag_ShipToNotInDim,
    Flag_MissingCustomerID,
    Flag_MissingItemID,
    Flag_NegativeRevenue,
    SourceSystem,
    BatchID,
    CURRENT_TIMESTAMP                                   AS FactLoadedAt

FROM calculated;