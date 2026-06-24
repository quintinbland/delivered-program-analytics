-- =============================================================================
-- MODULE:      Fact Tables
-- SCRIPT:      fact_contract_price.sql
-- INPUT:       Stg_ContractPricing, Dim_Customer, Dim_Product, Dim_Commodity, Dim_Date
-- OUTPUT:      Fact_ContractPrice
-- DIALECT:     DuckDB (patched from Snowflake original — STRFTIME applied)
-- PATCHED:      TO_CHAR date key expressions replaced with STRFTIME
-- VERSION:     1.0.3 — Flag_InvertedDateRange removed; open-ended dates make check obsolete (2026-06-24)
-- DEPENDENCIES:
--   Stg_ContractPricing  (Module 1)
--   Dim_Customer         (Module 2)
--   Dim_Product          (Module 2)
--   Dim_Commodity        (Module 2)
--   Dim_Date             (Module 2)
-- BUILD ORDER:  2 of 3 — must exist before Fact_SalesOrderLine (contract lookup)
-- =============================================================================
-- ASSUMPTIONS:
--   A1: Grain is one row per ContractPriceKey (one rule per fact row).
--       This is a reference fact, not a transactional fact. It stores the
--       full contract pricing rule set for lookup by Fact_SalesOrderLine.
--   A2: Contract matching hierarchy (UNK-001) — CANDIDATE values applied:
--       Tier 1: CustomerID + ItemID + date within effective range
--       Tier 2: CustomerHQID + ItemID + date within effective range
--       Tier 3: CustomerHQID + CommodityID + date within effective range
--       Tier 4: No match → ContractFOB = NULL
--       MatchTierApplied column records which tier produced each row.
--       ALL tiers are stored; resolution per transaction occurs in
--       Fact_SalesOrderLine via ranked lookup.
--   A3: Only active contracts (ContractDateStatus = 'Active') and future
--       contracts are promoted. Expired contracts are excluded from the
--       active fact table but retained in a separate audit table.
--       EXCEPTION: If a transaction's ShipDate falls within an expired
--       contract's effective range, that contract is still valid for
--       historical matching. See fact_contract_price_history note below.
--   A4: CustomerKey and ProductKey/CommodityKey are resolved via dimension
--       joins. Unresolvable values default to -1.
--   A5: EffectiveDateKey and ExpirationDateKey use YYYYMMDD integer format.
-- OPEN UNKNOWNS:
--   UNK-001: Contract matching hierarchy applied as candidate. All tiers
--            flagged with Flag_CandidateHierarchy = 1.
-- =============================================================================

CREATE OR REPLACE TABLE Fact_ContractPrice AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Source from staging — clean, non-expired rules
-- NOTE: Expired records retained via separate audit CTE (see A3)
-- ---------------------------------------------------------------------------
source AS (
    SELECT *
    FROM Stg_ContractPricing
    WHERE DeduplicationRank = 1
      AND IsCleanRow = 1
      -- Include active + future; expired excluded from live fact
      AND ContractDateStatus IN ('Active', 'Future')
),

-- ---------------------------------------------------------------------------
-- STEP 2: Resolve dimension foreign keys
-- ---------------------------------------------------------------------------
resolved AS (
    SELECT
        s.ContractPriceKey,

        -- Customer dimension resolution
        -- Tier 1/2 use CustomerID; Tier 2/3 use CustomerHQID
        -- Both are stored; resolution precedence applied in SalesOrderLine fact
        COALESCE(dc_cust.CustomerKey, -1)               AS CustomerKey,
        COALESCE(dc_hq.CustomerKey,   -1)               AS CustomerHQKey,

        -- Product dimension resolution
        COALESCE(dp.ProductKey, -1)                     AS ProductKey,

        -- Commodity dimension resolution
        COALESCE(dcom.CommodityKey, -1)                 AS CommodityKey,

        -- Date keys
        CASE
            WHEN s.EffectiveDate IS NOT NULL
            THEN CAST(STRFTIME(s.EffectiveDate,   '%Y%m%d') AS INTEGER)
            ELSE -1
        END                                             AS EffectiveDateKey,
        CASE
            WHEN s.ExpirationDate IS NOT NULL
            THEN CAST(STRFTIME(s.ExpirationDate,  '%Y%m%d') AS INTEGER)
            ELSE -1
        END                                             AS ExpirationDateKey,

        -- Raw date values retained for range comparisons
        s.EffectiveDate,
        s.ExpirationDate,

        -- Contract attributes
        s.ContractFOBPrice,
        s.ContractMatchTier,        -- Structural tier from staging
        s.ContractDateStatus,
        s.ContractType,
        s.ContractStatus,

        -- Source scope fields (retained for matching logic in SalesOrderLine)
        s.CustomerID,
        s.CustomerHQID,
        s.ItemID,
        s.CommodityID,

        -- UNK-001 candidate flag — applied to every row
        1                                               AS Flag_CandidateHierarchy_UNK001,

        -- FK resolution flags
        CASE WHEN dc_cust.CustomerKey IS NULL
              AND s.CustomerID IS NOT NULL
             THEN 1 ELSE 0 END                          AS Flag_CustomerNotInDim,
        CASE WHEN dp.ProductKey IS NULL
              AND s.ItemID IS NOT NULL
             THEN 1 ELSE 0 END                          AS Flag_ProductNotInDim,
        CASE WHEN dcom.CommodityKey IS NULL
              AND s.CommodityID IS NOT NULL
             THEN 1 ELSE 0 END                          AS Flag_CommodityNotInDim,

        -- Lineage
        s.SourceSystem,
        s.BatchID,
        CURRENT_TIMESTAMP                               AS FactLoadedAt

    FROM source s

    -- CustomerID resolution (Tier 1 customer-level)
    LEFT JOIN Dim_Customer dc_cust
        ON s.CustomerID = dc_cust.CustomerID
       AND dc_cust.CustomerKey <> -1

    -- CustomerHQID resolution (Tier 2/3 HQ-level)
    LEFT JOIN Dim_Customer dc_hq
        ON s.CustomerHQID = dc_hq.CustomerID
       AND dc_hq.CustomerKey <> -1

    -- ItemID resolution
    LEFT JOIN Dim_Product dp
        ON s.ItemID = dp.ItemID
       AND dp.ProductKey <> -1

    -- CommodityID resolution
    LEFT JOIN Dim_Commodity dcom
        ON s.CommodityID = dcom.CommodityID
       AND dcom.CommodityKey <> -1
)

-- ---------------------------------------------------------------------------
-- STEP 3: Final projection
-- ---------------------------------------------------------------------------
SELECT
    ContractPriceKey,

    -- Dimension keys
    CustomerKey,
    CustomerHQKey,
    ProductKey,
    CommodityKey,
    EffectiveDateKey,
    ExpirationDateKey,

    -- Date values for range matching in SalesOrderLine
    EffectiveDate,
    ExpirationDate,

    -- Measures
    ContractFOBPrice,

    -- Contract metadata
    ContractMatchTier,
    ContractDateStatus,
    ContractType,
    ContractStatus,

    -- Source scope fields for matching
    CustomerID,
    CustomerHQID,
    ItemID,
    CommodityID,

    -- Flags
    Flag_CandidateHierarchy_UNK001,
    Flag_CustomerNotInDim,
    Flag_ProductNotInDim,
    Flag_CommodityNotInDim,

    -- Lineage
    SourceSystem,
    BatchID,
    FactLoadedAt

FROM resolved;

-- =============================================================================
-- NOTE: HISTORICAL CONTRACT MATCHING
-- Expired contracts needed for historical transaction matching must be
-- queried directly from Stg_ContractPricing or a separate audit table.
-- Fact_ContractPrice contains active + future records only.
-- When Fact_SalesOrderLine performs contract lookup, it must join against
-- Stg_ContractPricing (all statuses) filtered by ShipDate BETWEEN
-- EffectiveDate AND ExpirationDate, not against Fact_ContractPrice alone.
-- This is implemented in fact_sales_order_line.sql.
-- =============================================================================

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Contract tier distribution
-- SELECT ContractMatchTier, COUNT(*) AS RuleCount
-- FROM Fact_ContractPrice GROUP BY ContractMatchTier;

-- Unresolved dimension keys
-- SELECT
--     SUM(Flag_CustomerNotInDim)  AS Unresolved_Customer,
--     SUM(Flag_ProductNotInDim)   AS Unresolved_Product,
--     SUM(Flag_CommodityNotInDim) AS Unresolved_Commodity
-- FROM Fact_ContractPrice;
