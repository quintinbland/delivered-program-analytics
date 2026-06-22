-- =============================================================================
-- MODULE:      Fact Tables
-- SCRIPT:      fact_sales_order_line.sql
-- INPUT:       Stg_SalesOrderLine, Dim_Customer, Dim_Product, Dim_ShipTo,
--              Dim_Date, Stg_ContractPricing (for historical contract matching)
-- OUTPUT:      Fact_SalesOrderLine
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Stg_SalesOrderLine   (Module 1)
--   Stg_ContractPricing  (Module 1) — used directly for historical matching
--   Dim_Customer         (Module 2)
--   Dim_Product          (Module 2)
--   Dim_ShipTo           (Module 2)
--   Dim_Date             (Module 2)
--   Fact_LoadFreight     (Module 3, Script 1)
-- BUILD ORDER:  3 of 3 — must be built last in Module 3
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Grain is one row per SalesOrderID + LoadID + ItemID.
--       Duplicate natural keys use DeduplicationRank = 1 from staging.
--   A2: Only rows with IsCleanRow = 1 in staging are promoted to the fact
--       table. Dirty rows are routed to the exception layer (Module 5).
--   A3: CONTRACT MATCHING — CANDIDATE HIERARCHY (UNK-001):
--       Applied in the following ranked order per transaction row:
--         Tier 1: s.CustomerID   = cp.CustomerID   AND s.ItemID = cp.ItemID
--                 AND s.ShipDate BETWEEN cp.EffectiveDate AND cp.ExpirationDate
--         Tier 2: c.CustomerHQID = cp.CustomerHQID AND s.ItemID = cp.ItemID
--                 AND s.ShipDate BETWEEN cp.EffectiveDate AND cp.ExpirationDate
--         Tier 3: c.CustomerHQID = cp.CustomerHQID AND p.CommodityID = cp.CommodityID
--                 AND s.ShipDate BETWEEN cp.EffectiveDate AND cp.ExpirationDate
--         Tier 4: No match → ContractFOBPrice = NULL, ContractMatchTier = 'NoMatch'
--       Contract lookup uses Stg_ContractPricing (all statuses, all dates)
--       to support historical matching. Active-only Fact_ContractPrice is
--       NOT used for this lookup.
--       ALL matching is flagged with Flag_CandidateHierarchy_UNK001 = 1.
--   A4: CALCULATED MEASURES — applied at this layer:
--       ActualFOB            = NetLineRevenue / QuantityCases
--                              NULL if QuantityCases = 0 or NULL
--       FOBVariancePerCase   = ActualFOB - ContractFOBPrice
--                              NULL if either is NULL
--       TotalFOBVariance     = FOBVariancePerCase * QuantityCases
--       ExcessSalesProfit    = TotalFOBVariance
--   A5: LoadFreightKey resolves via LoadID to Fact_LoadFreight.
--       NULL LoadID rows carry LoadFreightKey = NULL (no freight linkage).
--   A6: ShipDateKey and OrderDateKey use YYYYMMDD integer format.
--       NULL dates resolve to DateKey = -1.
-- OPEN UNKNOWNS:
--   UNK-001: Contract matching hierarchy — candidate applied, all rows flagged.
--   UNK-003: OnTargetFlag — excluded. Definition not confirmed.
-- =============================================================================

CREATE OR REPLACE TABLE Fact_SalesOrderLine AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Source from staging — primary record per natural key, clean only
-- ---------------------------------------------------------------------------
source AS (
    SELECT *
    FROM Stg_SalesOrderLine
    WHERE DeduplicationRank = 1
      AND IsCleanRow = 1
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
        s.ShipToID                                      AS ShipToID_Source,

        -- CustomerKey
        COALESCE(dc.CustomerKey, -1)                    AS CustomerKey,
        -- CustomerHQID carried for contract matching (Tier 2/3)
        dc.CustomerHQID                                 AS CustomerHQID,

        -- ProductKey + CommodityID (CommodityID needed for Tier 3 matching)
        COALESCE(dp.ProductKey, -1)                     AS ProductKey,
        dp.CommodityID                                  AS CommodityID,

        -- ShipToKey
        COALESCE(dst.ShipToKey, -1)                     AS ShipToKey,

        -- DateKeys
        CASE
            WHEN s.ShipDate IS NOT NULL
            THEN CAST(TO_CHAR(s.ShipDate,  'YYYYMMDD') AS INTEGER)
            ELSE -1
        END                                             AS ShipDateKey,
        CASE
            WHEN s.OrderDate IS NOT NULL
            THEN CAST(TO_CHAR(s.OrderDate, 'YYYYMMDD') AS INTEGER)
            ELSE -1
        END                                             AS OrderDateKey,

        -- Raw dates retained for contract range matching
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
        s.Flag_MissingShipToID,
        s.Flag_MissingItemID,
        s.Flag_NegativeRevenue,

        -- FK resolution flags
        CASE WHEN dc.CustomerKey IS NULL THEN 1 ELSE 0 END  AS Flag_CustomerNotInDim,
        CASE WHEN dp.ProductKey  IS NULL THEN 1 ELSE 0 END  AS Flag_ProductNotInDim,
        CASE WHEN dst.ShipToKey  IS NULL THEN 1 ELSE 0 END  AS Flag_ShipToNotInDim,

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

    LEFT JOIN Dim_ShipTo dst
        ON s.ShipToID = dst.ShipToID
       AND dst.ShipToKey <> -1
),

-- ---------------------------------------------------------------------------
-- STEP 3: Contract matching — CANDIDATE HIERARCHY (UNK-001)
-- Source: Stg_ContractPricing (all records, all date statuses)
-- One contract row per transaction; lowest MatchTier wins.
-- ---------------------------------------------------------------------------

-- Tier 1: CustomerID + ItemID + date range
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
       AND d.ShipDate BETWEEN cp.EffectiveDate AND cp.ExpirationDate
       AND cp.IsCleanRow         = 1
       AND cp.Flag_InvertedDateRange = 0
),

-- Tier 2: CustomerHQID + ItemID + date range
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
       AND d.ShipDate BETWEEN cp.EffectiveDate AND cp.ExpirationDate
       AND cp.IsCleanRow          = 1
       AND cp.Flag_InvertedDateRange = 0
    -- Only apply Tier 2 where Tier 1 produced no match
    WHERE NOT EXISTS (
        SELECT 1 FROM tier1 t
        WHERE t.SalesOrderID = d.SalesOrderID
          AND t.LoadID       = d.LoadID
          AND t.ItemID_Source = d.ItemID_Source
    )
),

-- Tier 3: CustomerHQID + CommodityID + date range
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
       AND d.ShipDate BETWEEN cp.EffectiveDate AND cp.ExpirationDate
       AND cp.IsCleanRow         = 1
       AND cp.Flag_InvertedDateRange = 0
    WHERE NOT EXISTS (
        SELECT 1 FROM tier1 t
        WHERE t.SalesOrderID = d.SalesOrderID
          AND t.LoadID       = d.LoadID
          AND t.ItemID_Source = d.ItemID_Source
    )
    AND NOT EXISTS (
        SELECT 1 FROM tier2 t
        WHERE t.SalesOrderID = d.SalesOrderID
          AND t.LoadID       = d.LoadID
          AND t.ItemID_Source = d.ItemID_Source
    )
),

-- Union all tiers; each transaction row appears at most once (lowest tier wins)
contract_matched AS (
    SELECT * FROM tier1
    UNION ALL
    SELECT * FROM tier2
    UNION ALL
    SELECT * FROM tier3
),

-- ---------------------------------------------------------------------------
-- STEP 4: Join contract match result back to transaction rows
-- Unmatched rows carry NULL ContractFOBPrice (Tier 4 = NoMatch)
-- ---------------------------------------------------------------------------
with_contract AS (
    SELECT
        d.*,
        COALESCE(cm.ContractFOBPrice, NULL)             AS ContractFOBPrice,
        COALESCE(cm.ContractPriceKey, NULL)             AS ContractPriceKey,
        COALESCE(cm.ContractMatchTier, 'NoMatch')       AS ContractMatchTier,
        COALESCE(cm.MatchTier, 4)                       AS MatchTierNumber,

        -- UNK-001 candidate flag on every row
        1                                               AS Flag_CandidateHierarchy_UNK001,

        -- Exception flag: contract customer with no contract match
        -- Requires Dim_Customer join to check CustomerStatus
        CASE
            WHEN cm.ContractFOBPrice IS NULL THEN 1
            ELSE 0
        END                                             AS Flag_NoContractMatch

    FROM dim_resolved d
    LEFT JOIN contract_matched cm
        ON d.SalesOrderID   = cm.SalesOrderID
       AND d.LoadID          = cm.LoadID
       AND d.ItemID_Source   = cm.ItemID_Source
),

-- ---------------------------------------------------------------------------
-- STEP 5: Calculated measures
-- RULE: ActualFOB = NetLineRevenue / QuantityCases
-- RULE: FOBVariancePerCase = ActualFOB - ContractFOBPrice
-- RULE: TotalFOBVariance = FOBVariancePerCase * QuantityCases
-- RULE: ExcessSalesProfit = TotalFOBVariance
-- ---------------------------------------------------------------------------
calculated AS (
    SELECT
        w.*,

        -- ActualFOB: NULL if QuantityCases = 0 or NULL
        CASE
            WHEN w.QuantityCases IS NULL OR w.QuantityCases = 0 THEN NULL
            ELSE w.NetLineRevenue / w.QuantityCases
        END                                             AS ActualFOB,

        -- FOBVariancePerCase: NULL if ActualFOB or ContractFOBPrice is NULL
        CASE
            WHEN w.QuantityCases IS NULL OR w.QuantityCases = 0 THEN NULL
            WHEN w.ContractFOBPrice IS NULL THEN NULL
            ELSE (w.NetLineRevenue / w.QuantityCases) - w.ContractFOBPrice
        END                                             AS FOBVariancePerCase,

        -- TotalFOBVariance and ExcessSalesProfit
        CASE
            WHEN w.QuantityCases IS NULL OR w.QuantityCases = 0 THEN NULL
            WHEN w.ContractFOBPrice IS NULL THEN NULL
            ELSE ((w.NetLineRevenue / w.QuantityCases) - w.ContractFOBPrice)
                 * w.QuantityCases
        END                                             AS TotalFOBVariance,

        -- ExcessSalesProfit = TotalFOBVariance (same calculation, explicit alias)
        CASE
            WHEN w.QuantityCases IS NULL OR w.QuantityCases = 0 THEN NULL
            WHEN w.ContractFOBPrice IS NULL THEN NULL
            ELSE ((w.NetLineRevenue / w.QuantityCases) - w.ContractFOBPrice)
                 * w.QuantityCases
        END                                             AS ExcessSalesProfit,

        -- Exception flags on calculated values
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
    -- Surrogate key
    StagingKey                                          AS SalesOrderLineKey,

    -- Natural key components
    SalesOrderID,
    LoadID,
    ItemID_Source                                       AS ItemID,

    -- Dimension keys
    CustomerKey,
    ProductKey,
    ShipToKey,
    ShipDateKey,
    OrderDateKey,

    -- Contract reference
    ContractPriceKey,
    ContractMatchTier,
    MatchTierNumber,

    -- Measures (raw)
    QuantityCases,
    NetLineRevenue,
    UnitPrice,
    ContractFOBPrice,

    -- Measures (calculated)
    ActualFOB,
    FOBVariancePerCase,
    TotalFOBVariance,
    ExcessSalesProfit,

    -- Operational attributes
    ContractID,
    OrderType,
    SalesChannel,

    -- Exception and quality flags
    Flag_CandidateHierarchy_UNK001,
    Flag_NoContractMatch,
    Flag_NegativeFOBVariance,
    Flag_CustomerNotInDim,
    Flag_ProductNotInDim,
    Flag_ShipToNotInDim,
    Flag_MissingCustomerID,
    Flag_MissingShipToID,
    Flag_MissingItemID,
    Flag_NegativeRevenue,

    -- Lineage
    SourceSystem,
    BatchID,
    CURRENT_TIMESTAMP                                   AS FactLoadedAt

FROM calculated;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Contract match tier distribution
-- SELECT ContractMatchTier, COUNT(*) AS LineCount
-- FROM Fact_SalesOrderLine GROUP BY ContractMatchTier ORDER BY MatchTierNumber;

-- Lines with negative FOB variance (exception type)
-- SELECT SalesOrderID, LoadID, ItemID, ActualFOB, ContractFOBPrice,
--        TotalFOBVariance, ContractMatchTier
-- FROM Fact_SalesOrderLine
-- WHERE Flag_NegativeFOBVariance = 1;

-- Contract customers with no contract match (exception type: Missing Contract Pricing)
-- SELECT f.SalesOrderID, f.LoadID, f.ItemID, c.CustomerStatusCode
-- FROM Fact_SalesOrderLine f
-- JOIN Dim_Customer c ON f.CustomerKey = c.CustomerKey
-- WHERE f.Flag_NoContractMatch = 1
--   AND c.CustomerStatusCode = 'CONTRACT';

-- Measure integrity check: ExcessSalesProfit = TotalFOBVariance
-- SELECT COUNT(*) AS MismatchCount
-- FROM Fact_SalesOrderLine
-- WHERE TotalFOBVariance <> ExcessSalesProfit
--   AND TotalFOBVariance IS NOT NULL;
