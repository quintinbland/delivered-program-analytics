-- =============================================================================
-- MODULE:      Exception System
-- SCRIPT:      exc_negative_freight_margin.sql
-- INPUT:       Fact_LoadFreight, Dim_Carrier, Dim_Date
-- OUTPUT:      Exc_NegativeFreightMargin
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Fact_LoadFreight  (Module 3)
--   Dim_Carrier       (Module 2)
--   Dim_Date          (Module 2)
-- =============================================================================
-- EXCEPTION RULE: NEGATIVE_FREIGHT_MARGIN
--   Description:  A load has a FreightMargin below zero, meaning the freight
--                 cost paid to the carrier exceeds the freight amount charged
--                 to the customer or program.
--   Inputs:       Fact_LoadFreight.FreightMargin
--                 Fact_LoadFreight.Flag_NegativeFreightMargin
--   Condition:    FreightMargin < 0
--   Output:       One exception row per affected LoadID
--   Severity:     HIGH — direct cost overrun per load
--   Resolution:   Review FreightCharged vs FreightPaid for this load;
--                 verify carrier invoice; confirm FreightCharged semantics
--                 (UNK-007 remains open)
-- OPEN UNKNOWNS:
--   UNK-007: FreightCharged semantics unconfirmed. Exception may be
--            an artifact of misclassified FreightCharged values.
-- =============================================================================

CREATE OR REPLACE TABLE Exc_NegativeFreightMargin AS

SELECT
    -- Exception metadata
    'NEGATIVE_FREIGHT_MARGIN'                           AS ExceptionType,
    'HIGH'                                              AS Severity,
    'FreightPaid exceeds FreightCharged on this load — negative freight margin.' AS ExceptionDescription,

    -- Source identifiers
    f.LoadID,

    -- Carrier context
    f.CarrierKey,
    dc.CarrierID,

    -- Period context
    f.LoadDateKey,
    d.CalendarYear,
    d.CalendarMonth,

    -- Freight detail
    f.FreightCharged,
    f.FreightPaid,
    f.FreightMargin,
    f.FreightMarginPct,

    -- Load context
    f.LoadPallets,
    f.LoadUtilizationBand,
    f.OriginWarehouse,

    -- Impact magnitude classification
    CASE
        WHEN f.FreightMargin >= -100    THEN 'Low'
        WHEN f.FreightMargin >= -500    THEN 'Medium'
        WHEN f.FreightMargin >= -2000   THEN 'High'
        ELSE                                 'Critical'
    END                                                 AS ImpactBand,

    -- Open unknown flag
    f.Flag_FreightChargedSuspect,
    'UNK-007: FreightCharged semantics unconfirmed — exception may require restatement after resolution'
                                                        AS OpenUnknownNote,

    -- Lineage
    f.SourceSystem,
    f.BatchID,
    CURRENT_TIMESTAMP                                   AS ExceptionLoadedAt

FROM Fact_LoadFreight f
JOIN Dim_Carrier dc ON f.CarrierKey  = dc.CarrierKey
JOIN Dim_Date    d  ON f.LoadDateKey = d.DateKey
WHERE f.Flag_NegativeFreightMargin = 1
  AND f.CarrierKey  <> -1
  AND f.LoadDateKey <> -1;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Total negative margin exposure
-- SELECT SUM(FreightMargin) AS TotalNegativeExposure, COUNT(*) AS AffectedLoads
-- FROM Exc_NegativeFreightMargin;

-- Breakdown by carrier
-- SELECT CarrierID, COUNT(*) AS LoadCount, SUM(FreightMargin) AS TotalMargin
-- FROM Exc_NegativeFreightMargin
-- GROUP BY CarrierID ORDER BY TotalMargin ASC;
