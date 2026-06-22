-- =============================================================================
-- MODULE:      Calculation Engine
-- SCRIPT:      calc_customer_performance.sql
-- INPUT:       Fact_SalesOrderLine, Fact_LoadFreight, Dim_Customer,
--              Dim_CustomerStatus, Dim_Date
-- OUTPUT:      Calc_CustomerPerformance
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Fact_SalesOrderLine  (Module 3)
--   Fact_LoadFreight     (Module 3)
--   Dim_Customer         (Module 2)
--   Dim_CustomerStatus   (Module 2)
--   Dim_Date             (Module 2)
-- =============================================================================
-- BUSINESS RULES IMPLEMENTED:
--
--   RULE: CUSTOMER_REVENUE
--     Inputs:       NetLineRevenue per SalesOrderLine row
--     Condition:    CustomerKey IS NOT NULL AND CustomerKey <> -1
--     Output:       TotalRevenue = SUM(NetLineRevenue) per customer per period
--     Edge Cases:   Excludes unknown customer (-1)
--
--   RULE: CUSTOMER_FOB_VARIANCE
--     Inputs:       TotalFOBVariance from Fact_SalesOrderLine
--     Condition:    TotalFOBVariance IS NOT NULL
--     Output:       TotalFOBVariance aggregated per customer per period
--     Edge Cases:   NULL rows excluded from sum; counted separately
--
--   RULE: ALLOCATED_FREIGHT_MARGIN
--     Description:  Freight margin is allocated to customers via LoadID bridge.
--                   Each load's FreightMargin is split proportionally by
--                   QuantityCases shipped on that load per customer.
--     Inputs:       FreightMargin (Fact_LoadFreight), QuantityCases (Fact_SalesOrderLine)
--     Condition:    LoadID links SalesOrderLine to LoadFreight
--     Output:       AllocatedFreightMargin per customer per period
--     Edge Cases:   Loads with no sales lines receive no allocation.
--                   Loads with NULL FreightMargin contribute NULL allocation.
--
-- AGGREGATION GRAIN: CustomerKey + CalendarYear + CalendarMonth
-- =============================================================================

CREATE OR REPLACE TABLE Calc_CustomerPerformance AS

WITH

-- ---------------------------------------------------------------------------
-- STEP 1: Sales summary per customer per period
-- ---------------------------------------------------------------------------
sales_summary AS (
    SELECT
        f.CustomerKey,
        d.CalendarYear,
        d.CalendarMonth,
        d.FiscalYear,
        d.FiscalQuarter,
        d.FiscalPeriod,

        COUNT(*)                                        AS TotalLineCount,
        SUM(f.QuantityCases)                            AS TotalQuantityCases,
        SUM(f.NetLineRevenue)                           AS TotalRevenue,
        SUM(f.TotalFOBVariance)                         AS TotalFOBVariance,
        SUM(f.ExcessSalesProfit)                        AS TotalExcessSalesProfit,

        COUNT(DISTINCT f.LoadID)                        AS LoadCount,

        SUM(f.Flag_NegativeFOBVariance)                 AS Count_NegativeFOBVarianceLines,
        SUM(f.Flag_NoContractMatch)                     AS Count_NoContractMatchLines,
        MAX(f.Flag_CandidateHierarchy_UNK001)           AS Flag_CandidateHierarchy_UNK001

    FROM Fact_SalesOrderLine f
    JOIN Dim_Date d ON f.ShipDateKey = d.DateKey
    WHERE f.ShipDateKey <> -1
      AND f.CustomerKey <> -1
    GROUP BY
        f.CustomerKey,
        d.CalendarYear,
        d.CalendarMonth,
        d.FiscalYear,
        d.FiscalQuarter,
        d.FiscalPeriod
),

-- ---------------------------------------------------------------------------
-- STEP 2: Freight margin allocation
-- Proportional split by QuantityCases per customer per load
-- ---------------------------------------------------------------------------
load_cases AS (
    -- Total cases per load across all customers
    SELECT
        LoadID,
        SUM(QuantityCases)                              AS TotalCasesOnLoad
    FROM Fact_SalesOrderLine
    WHERE LoadID IS NOT NULL
    GROUP BY LoadID
),

customer_cases_per_load AS (
    -- Cases per customer per load
    SELECT
        f.CustomerKey,
        f.LoadID,
        SUM(f.QuantityCases)                            AS CustomerCasesOnLoad,
        d.CalendarYear,
        d.CalendarMonth
    FROM Fact_SalesOrderLine f
    JOIN Dim_Date d ON f.ShipDateKey = d.DateKey
    WHERE f.LoadID IS NOT NULL
      AND f.CustomerKey <> -1
      AND f.ShipDateKey <> -1
    GROUP BY f.CustomerKey, f.LoadID, d.CalendarYear, d.CalendarMonth
),

freight_allocation AS (
    SELECT
        ccl.CustomerKey,
        ccl.CalendarYear,
        ccl.CalendarMonth,
        SUM(
            CASE
                WHEN lc.TotalCasesOnLoad > 0 AND fl.FreightMargin IS NOT NULL
                THEN fl.FreightMargin
                     * (ccl.CustomerCasesOnLoad / lc.TotalCasesOnLoad)
                ELSE NULL
            END
        )                                               AS AllocatedFreightMargin,
        SUM(
            CASE
                WHEN lc.TotalCasesOnLoad > 0 AND fl.FreightCharged IS NOT NULL
                THEN fl.FreightCharged
                     * (ccl.CustomerCasesOnLoad / lc.TotalCasesOnLoad)
                ELSE NULL
            END
        )                                               AS AllocatedFreightCharged
    FROM customer_cases_per_load ccl
    JOIN load_cases lc
        ON ccl.LoadID = lc.LoadID
    JOIN Fact_LoadFreight fl
        ON ccl.LoadID = fl.LoadID
    GROUP BY ccl.CustomerKey, ccl.CalendarYear, ccl.CalendarMonth
)

-- ---------------------------------------------------------------------------
-- STEP 3: Final join and projection
-- ---------------------------------------------------------------------------
SELECT
    s.CustomerKey,
    dc.CustomerID,
    dc.CustomerName,
    dc.CustomerHQID,
    dc.CustomerStatusCode,
    cs.CustomerStatusLabel,
    dc.CustomerRegion,
    dc.CustomerSegment,

    s.CalendarYear,
    s.CalendarMonth,
    s.FiscalYear,
    s.FiscalQuarter,
    s.FiscalPeriod,

    -- Sales metrics
    s.TotalLineCount,
    s.TotalQuantityCases,
    s.TotalRevenue,
    s.LoadCount,

    -- FOB variance metrics
    s.TotalFOBVariance,
    s.TotalExcessSalesProfit,
    CASE
        WHEN s.TotalQuantityCases > 0
        THEN s.TotalFOBVariance / s.TotalQuantityCases
        ELSE NULL
    END                                                 AS AvgFOBVariancePerCase,

    -- Freight allocation
    fa.AllocatedFreightMargin,
    fa.AllocatedFreightCharged,
    CASE
        WHEN fa.AllocatedFreightCharged > 0
        THEN fa.AllocatedFreightMargin / fa.AllocatedFreightCharged
        ELSE NULL
    END                                                 AS AllocatedFreightMarginPct,

    -- Combined margin (FOB variance + allocated freight)
    CASE
        WHEN s.TotalFOBVariance IS NOT NULL
          OR fa.AllocatedFreightMargin IS NOT NULL
        THEN COALESCE(s.TotalFOBVariance, 0)
           + COALESCE(fa.AllocatedFreightMargin, 0)
        ELSE NULL
    END                                                 AS TotalCombinedMargin,

    -- Exception counts
    s.Count_NegativeFOBVarianceLines,
    s.Count_NoContractMatchLines,
    s.Flag_CandidateHierarchy_UNK001,

    CURRENT_TIMESTAMP                                   AS CalcLoadedAt

FROM sales_summary s
JOIN Dim_Customer dc
    ON s.CustomerKey = dc.CustomerKey
JOIN Dim_CustomerStatus cs
    ON dc.CustomerStatusKey = cs.CustomerStatusKey
LEFT JOIN freight_allocation fa
    ON  s.CustomerKey    = fa.CustomerKey
    AND s.CalendarYear   = fa.CalendarYear
    AND s.CalendarMonth  = fa.CalendarMonth;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Revenue reconciliation: must match Fact_SalesOrderLine total
-- SELECT SUM(TotalRevenue) FROM Calc_CustomerPerformance;
-- SELECT SUM(NetLineRevenue) FROM Fact_SalesOrderLine WHERE CustomerKey <> -1 AND ShipDateKey <> -1;

-- Allocated freight reconciliation: must not exceed total freight margin
-- SELECT SUM(AllocatedFreightMargin) FROM Calc_CustomerPerformance;
-- SELECT SUM(FreightMargin) FROM Fact_LoadFreight;
