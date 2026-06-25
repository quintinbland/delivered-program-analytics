CREATE OR REPLACE TABLE Rpt_LoadEfficiencyByShipTo AS
WITH
shipto_map AS (
    SELECT DISTINCT
        CAST(r.salesId AS VARCHAR)              AS SalesOrderID,
        CAST(r.loadId AS VARCHAR)               AS LoadID,
        CAST(r.Product_ID AS VARCHAR)           AS ItemID,
        UPPER(TRIM(CAST(r.shipTo AS VARCHAR)))  AS ShipTo
    FROM Raw_SalesOrderLine r
    WHERE r.salesId IS NOT NULL
      AND r.loadId  IS NOT NULL
      AND r.shipTo  IS NOT NULL
),
cases_per_load AS (
    SELECT
        LoadID,
        SUM(QuantityCases) AS TotalCasesOnLoad
    FROM Fact_SalesOrderLine
    GROUP BY LoadID
),
load_with_shipto AS (
    SELECT
        sm.ShipTo,
        fl.LoadID,
        fl.LoadPallets,
        fl.FreightCost,
        fl.FreightCharged,
        fl.LoadUtilizationBand,
        fl.Mode_Clean,
        cpl.TotalCasesOnLoad
    FROM Fact_LoadFreight fl
    JOIN Fact_SalesOrderLine sol ON fl.LoadID = sol.LoadID
    JOIN shipto_map sm
        ON sol.SalesOrderID = sm.SalesOrderID
       AND sol.LoadID        = sm.LoadID
       AND sol.ItemID        = sm.ItemID
    LEFT JOIN cases_per_load cpl ON fl.LoadID = cpl.LoadID
    WHERE fl.IsCleanRow = 1
    GROUP BY sm.ShipTo, fl.LoadID, fl.LoadPallets, fl.FreightCost,
             fl.FreightCharged, fl.LoadUtilizationBand, fl.Mode_Clean, cpl.TotalCasesOnLoad
),
shipto_load_avg AS (
    SELECT
        ShipTo,
        COUNT(DISTINCT LoadID)                                                          AS TotalLoads,
        AVG(LoadPallets)                                                                AS AvgPalletsPerLoad,
        MIN(LoadPallets)                                                                AS MinPalletsPerLoad,
        MAX(LoadPallets)                                                                AS MaxPalletsPerLoad,
        SUM(CASE WHEN LoadUtilizationBand = 'Full'          THEN 1 ELSE 0 END)       AS FullLoads,
        SUM(CASE WHEN LoadUtilizationBand = 'Partial'       THEN 1 ELSE 0 END)       AS PartialLoads,
        SUM(CASE WHEN LoadUtilizationBand = 'Underutilized' THEN 1 ELSE 0 END)       AS UnderutilizedLoads
    FROM load_with_shipto
    GROUP BY ShipTo
),
line_with_load AS (
    SELECT
        sol.SalesOrderLineKey,
        sol.SalesOrderID,
        sol.LoadID,
        sol.ItemID,
        sm.ShipTo,
        dc.CustomerHQID,
        dc.CustomerHQName,
        sol.ShipDateKey,
        sol.QuantityCases,
        sol.NetLineRevenue,
        sol.ActualFOB,
        sol.ContractFOBPrice,
        sol.FOBVariancePerCase,
        sol.TotalFOBVariance,
        sol.ContractMatchTier,
        fl.LoadPallets,
        fl.FreightCost,
        fl.FreightCharged,
        fl.LoadUtilizationBand,
        fl.Mode_Clean,
        CASE WHEN cpl.TotalCasesOnLoad IS NULL OR cpl.TotalCasesOnLoad = 0 THEN NULL
             ELSE fl.FreightCost * (sol.QuantityCases / cpl.TotalCasesOnLoad) END      AS AllocatedFreightCost,
        CASE WHEN cpl.TotalCasesOnLoad IS NULL OR cpl.TotalCasesOnLoad = 0 THEN NULL
             ELSE fl.FreightCost / cpl.TotalCasesOnLoad END                            AS FreightCostPerCase,
        sla.AvgPalletsPerLoad,
        sla.MinPalletsPerLoad,
        sla.MaxPalletsPerLoad,
        sla.TotalLoads,
        sla.FullLoads,
        sla.PartialLoads,
        sla.UnderutilizedLoads,
        CASE WHEN sla.TotalLoads = 0 THEN NULL
             ELSE ROUND(sla.FullLoads * 100.0 / sla.TotalLoads, 1) END                AS PctFullLoads,
        sol.Flag_NegativeFOBVariance,
        sol.Flag_NoContractMatch
    FROM Fact_SalesOrderLine sol
    JOIN shipto_map sm
        ON sol.SalesOrderID = sm.SalesOrderID
       AND sol.LoadID        = sm.LoadID
       AND sol.ItemID        = sm.ItemID
    LEFT JOIN Dim_Customer dc ON sol.CustomerKey = dc.CustomerKey
    LEFT JOIN Fact_LoadFreight fl ON sol.LoadID = fl.LoadID AND fl.IsCleanRow = 1
    LEFT JOIN cases_per_load cpl ON sol.LoadID = cpl.LoadID
    LEFT JOIN shipto_load_avg sla ON sm.ShipTo = sla.ShipTo
    WHERE sol.Flag_NoContractMatch = 0
)
SELECT * FROM line_with_load;