-- =============================================================================
-- IMPLEMENTATION: Phase 9 — End-to-End Reconciliation
-- TARGET:         DuckDB
-- PURPOSE:        Confirm pipeline integrity from raw to reporting layer
-- RUN:            After Phase 8 completes successfully
-- =============================================================================

SELECT
    'Raw → Staging: SalesOrderLine'         AS CheckPoint,
    (SELECT COUNT(*) FROM Raw_SalesOrderLine)                                               AS InputCount,
    (SELECT COUNT(*) FROM Stg_SalesOrderLine)                                              AS OutputCount,
    CASE WHEN (SELECT COUNT(*) FROM Raw_SalesOrderLine)
              = (SELECT COUNT(*) FROM Stg_SalesOrderLine)
         THEN 'PASS' ELSE 'INVESTIGATE' END                                                AS Status

UNION ALL SELECT
    'Raw → Staging: LoadFreight',
    (SELECT COUNT(*) FROM Raw_LoadFreight),
    (SELECT COUNT(*) FROM Stg_LoadFreight),
    CASE WHEN (SELECT COUNT(*) FROM Raw_LoadFreight)
              = (SELECT COUNT(*) FROM Stg_LoadFreight)
         THEN 'PASS' ELSE 'INVESTIGATE' END

UNION ALL SELECT
    'Staging → Fact: SalesOrderLine (clean rows)',
    (SELECT COUNT(*) FROM Stg_SalesOrderLine WHERE IsCleanRow = 1 AND DeduplicationRank = 1),
    (SELECT COUNT(*) FROM Fact_SalesOrderLine),
    CASE WHEN (SELECT COUNT(*) FROM Stg_SalesOrderLine WHERE IsCleanRow = 1 AND DeduplicationRank = 1)
              = (SELECT COUNT(*) FROM Fact_SalesOrderLine)
         THEN 'PASS' ELSE 'INVESTIGATE' END

UNION ALL SELECT
    'Staging → Fact: LoadFreight',
    (SELECT COUNT(*) FROM Stg_LoadFreight WHERE DeduplicationRank = 1 AND (IsCleanRow = 1 OR Flag_FreightChargedSuspect = 1)),
    (SELECT COUNT(*) FROM Fact_LoadFreight),
    CASE WHEN (SELECT COUNT(*) FROM Stg_LoadFreight WHERE DeduplicationRank = 1 AND (IsCleanRow = 1 OR Flag_FreightChargedSuspect = 1))
              = (SELECT COUNT(*) FROM Fact_LoadFreight)
         THEN 'PASS' ELSE 'INVESTIGATE' END

UNION ALL SELECT
    'Dimension default members present',
    7,
    (SELECT COUNT(*) FROM (
        SELECT MIN(CustomerStatusKey) AS k FROM Dim_CustomerStatus WHERE CustomerStatusKey = -1 UNION ALL
        SELECT MIN(CommodityKey)      FROM Dim_Commodity      WHERE CommodityKey = -1      UNION ALL
        SELECT MIN(DateKey)           FROM Dim_Date           WHERE DateKey = -1            UNION ALL
        SELECT MIN(CarrierKey)        FROM Dim_Carrier        WHERE CarrierKey = -1         UNION ALL
        SELECT MIN(ShipToKey)         FROM Dim_ShipTo         WHERE ShipToKey = -1          UNION ALL
        SELECT MIN(ProductKey)        FROM Dim_Product        WHERE ProductKey = -1         UNION ALL
        SELECT MIN(CustomerKey)       FROM Dim_Customer       WHERE CustomerKey = -1
    ) x WHERE k = -1),
    CASE WHEN (SELECT COUNT(*) FROM (
        SELECT MIN(CustomerStatusKey) AS k FROM Dim_CustomerStatus WHERE CustomerStatusKey = -1 UNION ALL
        SELECT MIN(CommodityKey)      FROM Dim_Commodity      WHERE CommodityKey = -1      UNION ALL
        SELECT MIN(DateKey)           FROM Dim_Date           WHERE DateKey = -1            UNION ALL
        SELECT MIN(CarrierKey)        FROM Dim_Carrier        WHERE CarrierKey = -1         UNION ALL
        SELECT MIN(ShipToKey)         FROM Dim_ShipTo         WHERE ShipToKey = -1          UNION ALL
        SELECT MIN(ProductKey)        FROM Dim_Product        WHERE ProductKey = -1         UNION ALL
        SELECT MIN(CustomerKey)       FROM Dim_Customer       WHERE CustomerKey = -1
    ) x WHERE k = -1) = 7
    THEN 'PASS' ELSE 'INVESTIGATE — one or more dimensions missing default member' END

UNION ALL SELECT
    'Fact → Calc: Revenue reconciliation',
    NULL,
    NULL,
    CASE WHEN ABS(
        COALESCE((SELECT SUM(NetLineRevenue)  FROM Fact_SalesOrderLine WHERE CustomerKey <> -1 AND ShipDateKey <> -1), 0)
      - COALESCE((SELECT SUM(TotalRevenue)    FROM Calc_CustomerPerformance), 0)
    ) < 0.01 THEN 'PASS' ELSE 'INVESTIGATE — revenue mismatch between fact and calc layers' END

UNION ALL SELECT
    'Calc → Exceptions: Exc_Master populated',
    (SELECT COUNT(*) FROM Fact_SalesOrderLine),
    (SELECT COUNT(*) FROM Exc_Master),
    CASE WHEN (SELECT COUNT(*) FROM Exc_Master) > 0
         THEN 'PASS — exceptions present as expected from synthetic data'
         ELSE 'INVESTIGATE — synthetic data should produce exceptions; none found' END

UNION ALL SELECT
    'ExcessSalesProfit = TotalFOBVariance (no mismatches)',
    (SELECT COUNT(*) FROM Fact_SalesOrderLine WHERE TotalFOBVariance IS NOT NULL),
    (SELECT COUNT(*) FROM Fact_SalesOrderLine WHERE TotalFOBVariance <> ExcessSalesProfit AND TotalFOBVariance IS NOT NULL),
    CASE WHEN (SELECT COUNT(*) FROM Fact_SalesOrderLine WHERE TotalFOBVariance <> ExcessSalesProfit AND TotalFOBVariance IS NOT NULL) = 0
         THEN 'PASS' ELSE 'INVESTIGATE — calculation integrity failure' END

ORDER BY CheckPoint;
