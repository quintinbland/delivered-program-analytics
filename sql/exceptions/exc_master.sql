-- =============================================================================
-- MODULE:      Exception System
-- SCRIPT:      exc_master.sql
-- INPUT:       All Exc_* tables (this module)
-- OUTPUT:      Exc_Master
-- DIALECT:     ANSI SQL (T-SQL / Snowflake compatible; dialect notes inline)
-- VERSION:     1.0.0
-- DEPENDENCIES:
--   Exc_MissingContractPricing  (this module)
--   Exc_NegativeFOBVariance     (this module)
--   Exc_NegativeFreightMargin   (this module)
--   Exc_MissingMappings         (this module)
--   Exc_DataQuality             (this module)
-- BUILD ORDER: Run after all other exception scripts in this module
-- =============================================================================
-- PURPOSE:
--   Provides a single unified exception log across all exception types.
--   Each row represents one exception instance with standardized metadata.
--   Supports:
--     - Exception triage and prioritization
--     - Resolution tracking
--     - Batch-level quality reporting
--     - Downstream alerting or notification routing
--
-- RESOLUTION STATES:
--   OPEN        — Exception identified, no action taken
--   IN_REVIEW   — Exception acknowledged, under investigation
--   RESOLVED    — Exception corrected at source
--   SUPPRESSED  — Exception acknowledged as expected/acceptable; not actioned
--   ESCALATED   — Exception routed to senior review
-- =============================================================================

CREATE OR REPLACE TABLE Exc_Master AS

-- ---------------------------------------------------------------------------
-- SOURCE 1: Missing Contract Pricing
-- ---------------------------------------------------------------------------
SELECT
    -- Exception identity
    CONCAT('MCP-', f.SalesOrderLineKey)                 AS ExceptionID,
    f.ExceptionType,
    f.Severity,
    f.ExceptionDescription,

    -- Routing
    'CONTRACT_MANAGEMENT'                               AS OwnerDomain,
    'Add or correct contract record in Raw_ContractPricing for this customer/item/date.' AS ResolutionGuidance,

    -- Entity references
    f.SalesOrderID                                      AS PrimaryEntityID,
    'SalesOrderLine'                                    AS PrimaryEntityType,
    f.CustomerID                                        AS SecondaryEntityID,
    'Customer'                                          AS SecondaryEntityType,

    -- Financial impact
    CAST(NULL AS DECIMAL(18,4))                         AS FinancialImpact,
    'USD'                                               AS ImpactCurrency,
    'Variance calculation blocked — impact UNKNOWN until contract resolved' AS ImpactNote,

    -- Open unknown flag
    CASE WHEN f.Flag_CandidateHierarchy_UNK001 = 1
         THEN 'UNK-001: Contract hierarchy is candidate — exception may change after confirmation'
         ELSE NULL
    END                                                 AS OpenUnknownNote,

    -- Resolution tracking
    'OPEN'                                              AS ResolutionStatus,
    NULL                                                AS ResolutionNote,
    NULL                                                AS ResolvedAt,
    NULL                                                AS ResolvedBy,

    -- Lineage
    f.SourceSystem,
    f.BatchID,
    f.ExceptionLoadedAt

FROM Exc_MissingContractPricing f

UNION ALL

-- ---------------------------------------------------------------------------
-- SOURCE 2: Negative FOB Variance
-- ---------------------------------------------------------------------------
SELECT
    CONCAT('NFV-', f.SalesOrderLineKey)                 AS ExceptionID,
    f.ExceptionType,
    f.Severity,
    f.ExceptionDescription,
    'PRICING'                                           AS OwnerDomain,
    'Review pricing at order date; verify ActualFOB vs ContractFOB; confirm contract terms are current.' AS ResolutionGuidance,
    f.SalesOrderID,
    'SalesOrderLine',
    f.CustomerID,
    'Customer',
    f.TotalFOBVariance                                  AS FinancialImpact,
    'USD',
    CONCAT('TotalFOBVariance = ', CAST(f.TotalFOBVariance AS VARCHAR), ' | Band: ', f.ImpactBand),
    CASE WHEN f.Flag_CandidateHierarchy_UNK001 = 1
         THEN 'UNK-001: Contract hierarchy is candidate — variance tier assignment may change'
         ELSE NULL
    END,
    'OPEN',
    NULL, NULL, NULL,
    f.SourceSystem,
    f.BatchID,
    f.ExceptionLoadedAt

FROM Exc_NegativeFOBVariance f

UNION ALL

-- ---------------------------------------------------------------------------
-- SOURCE 3: Negative Freight Margin
-- ---------------------------------------------------------------------------
SELECT
    CONCAT('NFM-', f.LoadID)                            AS ExceptionID,
    f.ExceptionType,
    f.Severity,
    f.ExceptionDescription,
    'FREIGHT_OPERATIONS'                                AS OwnerDomain,
    'Review FreightCharged vs FreightPaid for this load; verify carrier invoice accuracy.' AS ResolutionGuidance,
    f.LoadID,
    'Load',
    f.CarrierID,
    'Carrier',
    f.FreightMargin                                     AS FinancialImpact,
    'USD',
    CONCAT('FreightMargin = ', CAST(f.FreightMargin AS VARCHAR), ' | Band: ', f.ImpactBand),
    f.OpenUnknownNote,
    'OPEN',
    NULL, NULL, NULL,
    f.SourceSystem,
    f.BatchID,
    f.ExceptionLoadedAt

FROM Exc_NegativeFreightMargin f

UNION ALL

-- ---------------------------------------------------------------------------
-- SOURCE 4: Missing Mappings
-- ---------------------------------------------------------------------------
SELECT
    CONCAT('MAP-', m.ExceptionType, '-', m.EntityID)   AS ExceptionID,
    m.ExceptionType,
    m.Severity,
    m.ExceptionDescription,
    CASE m.ExceptionType
        WHEN 'MISSING_COMMODITY_MAPPING'  THEN 'PRODUCT_MASTER'
        WHEN 'MISSING_CUSTOMER_MAPPING'   THEN 'CUSTOMER_MASTER'
        WHEN 'MISSING_SHIPTO_MAPPING'     THEN 'CUSTOMER_MASTER'
    END                                                 AS OwnerDomain,
    CASE m.ExceptionType
        WHEN 'MISSING_COMMODITY_MAPPING'  THEN 'Add CommodityID to Raw_ProductMaster for this ItemID.'
        WHEN 'MISSING_CUSTOMER_MAPPING'   THEN 'Add CustomerID to Raw_CustomerReference.'
        WHEN 'MISSING_SHIPTO_MAPPING'     THEN 'Add ShipToID to Raw_ShipToReference.'
    END                                                 AS ResolutionGuidance,
    m.EntityID,
    m.EntityType,
    m.TransactionContext,
    'Transaction',
    CAST(NULL AS DECIMAL(18,4)),
    'USD',
    m.ExceptionDescription,
    NULL,
    'OPEN',
    NULL, NULL, NULL,
    m.SourceSystem,
    m.BatchID,
    m.ExceptionLoadedAt

FROM Exc_MissingMappings m

UNION ALL

-- ---------------------------------------------------------------------------
-- SOURCE 5: Data Quality
-- ---------------------------------------------------------------------------
SELECT
    CONCAT('DQ-', q.ExceptionType, '-', q.EntityID)    AS ExceptionID,
    q.ExceptionType,
    q.Severity,
    q.ExceptionDescription,
    'DATA_OPERATIONS'                                   AS OwnerDomain,
    CASE q.ExceptionType
        WHEN 'DUPLICATE_SALES_LINE_KEY'  THEN 'Identify and remove duplicate rows in source ERP export for this SalesOrderID.'
        WHEN 'INVALID_QUANTITY'          THEN 'Correct QuantityCases in source; zero and negative quantities are not valid.'
        WHEN 'MISSING_LOAD_ID'           THEN 'Assign LoadID to this sales order line in source system.'
        WHEN 'DUPLICATE_LOAD_ID'         THEN 'Identify and remove duplicate LoadID rows in source freight export.'
        WHEN 'DUPLICATE_CONTRACT_KEY'    THEN 'Identify and resolve duplicate ContractPriceKey in contract pricing source.'
        WHEN 'INVERTED_CONTRACT_DATE'    THEN 'Correct EffectiveDate and ExpirationDate for this contract record.'
        ELSE 'Review source record and correct data quality issue.'
    END                                                 AS ResolutionGuidance,
    q.EntityID,
    q.EntityType,
    q.EntityDetail,
    'SourceRecord',
    CAST(NULL AS DECIMAL(18,4)),
    'USD',
    q.ExceptionDescription,
    NULL,
    'OPEN',
    NULL, NULL, NULL,
    q.SourceSystem,
    q.BatchID,
    q.ExceptionLoadedAt

FROM Exc_DataQuality q;

-- =============================================================================
-- POST-LOAD VALIDATION
-- =============================================================================

-- Full exception summary by type and severity
-- SELECT ExceptionType, Severity, OwnerDomain, COUNT(*) AS ExceptionCount,
--        SUM(COALESCE(FinancialImpact, 0)) AS TotalFinancialImpact
-- FROM Exc_Master
-- GROUP BY ExceptionType, Severity, OwnerDomain
-- ORDER BY Severity, ExceptionCount DESC;

-- Open HIGH severity exceptions (priority triage list)
-- SELECT ExceptionID, ExceptionType, OwnerDomain, PrimaryEntityID,
--        FinancialImpact, ResolutionGuidance
-- FROM Exc_Master
-- WHERE Severity = 'HIGH'
--   AND ResolutionStatus = 'OPEN'
-- ORDER BY COALESCE(FinancialImpact, 0) ASC;

-- Batch-level quality score
-- SELECT
--     BatchID,
--     COUNT(*) AS TotalExceptions,
--     SUM(CASE WHEN Severity = 'HIGH'   THEN 1 ELSE 0 END) AS HighCount,
--     SUM(CASE WHEN Severity = 'MEDIUM' THEN 1 ELSE 0 END) AS MediumCount
-- FROM Exc_Master
-- GROUP BY BatchID;
