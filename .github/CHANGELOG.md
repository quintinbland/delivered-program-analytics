# Changelog

All notable changes to this project are documented here.

Format: `[version] — date — description`

---

## [0.6.0] — 2026 — Module 6: Reporting Layer

### Added
- `sql/reporting/rpt_executive_summary.sql` — Period-level executive summary with MoM comparison via LAG()
- `sql/reporting/rpt_fob_variance_detail.sql` — Customer + product + period FOB variance detail with variance ranking
- `sql/reporting/rpt_freight_performance.sql` — Carrier + period freight performance with candidate PerformanceTier classification
- `sql/reporting/rpt_exception_dashboard.sql` — Two-surface exception dashboard: summary metrics + HIGH severity triage queue
- `sql/reporting/rpt_customer_scorecard.sql` — Customer scorecard with all-period aggregates, rolling 3-month window, exception counts, and candidate CustomerHealthTier

### Open Unknowns Added
- UNK-011: Freight performance tier thresholds (candidate values applied)
- UNK-012: Customer health tier thresholds (candidate values applied)

---

## [0.5.0] — 2026 — Module 5: Exception System

### Added
- `sql/exceptions/exc_missing_contract_pricing.sql` — Contract customers with no contract FOB match
- `sql/exceptions/exc_negative_fob_variance.sql` — TotalFOBVariance < 0 with ImpactBand classification
- `sql/exceptions/exc_negative_freight_margin.sql` — FreightMargin < 0 with UNK-007 propagation
- `sql/exceptions/exc_missing_mappings.sql` — Commodity, customer, and ShipTo mapping gaps
- `sql/exceptions/exc_data_quality.sql` — Duplicate keys, invalid quantities, missing LoadIDs, inverted contract dates
- `sql/exceptions/exc_master.sql` — Unified exception log with ExceptionID, OwnerDomain, ResolutionGuidance, ResolutionStatus, and FinancialImpact

---

## [0.4.0] — 2026 — Module 4: Calculation Engine

### Added
- `sql/calculations/calc_freight_summary.sql` — Freight margin and load utilization aggregated by carrier and period
- `sql/calculations/calc_fob_variance_summary.sql` — FOB variance aggregated by customer, product, and period with weighted average FOB metrics
- `sql/calculations/calc_customer_performance.sql` — Customer-level revenue, FOB variance, and proportional freight margin allocation via LoadID bridge
- `sql/calculations/calc_load_utilization.sql` — Load fill rate and pallet shortfall by carrier and period; CandidateTargetPallets_UNK002 stored in output

### Open Unknowns Added
- UNK-010: Freight margin allocation basis (proportional by QuantityCases — candidate)

---

## [0.3.0] — 2026 — Module 3: Fact Tables

### Added
- `sql/facts/fact_load_freight.sql` — Freight fact with dimension key resolution; dirty rows excluded except Flag_FreightChargedSuspect rows retained
- `sql/facts/fact_contract_price.sql` — Contract pricing reference fact; active + future contracts only; expired records excluded from live fact
- `sql/facts/fact_sales_order_line.sql` — Sales fact with three-tier contract matching hierarchy, four calculated measures (ActualFOB, FOBVariancePerCase, TotalFOBVariance, ExcessSalesProfit), and full exception flagging

### Design Decisions
- Contract matching in fact_sales_order_line uses Stg_ContractPricing directly (not Fact_ContractPrice) to support historical transaction matching against expired contracts
- UNK-001 candidate hierarchy applied; Flag_CandidateHierarchy_UNK001 = 1 on every matched and unmatched row
- OnTargetFlag (UNK-003) excluded pending definition

---

## [0.2.0] — 2026 — Module 2: Dimension Build

### Added
- `sql/dimensions/dim_customer_status.sql` — Static controlled-value dimension; labels owned by script
- `sql/dimensions/dim_commodity.sql` — Commodity reference with CommodityGroup defaulting to CommodityID when absent
- `sql/dimensions/dim_date.sql` — Generated date dimension covering 2020–2030; Snowflake primary + T-SQL commented block; fiscal calendar flagged as candidate (UNK-004)
- `sql/dimensions/dim_carrier.sql` — Derived from Stg_LoadFreight distinct values; CarrierName/Type/Mode stubbed for future enrichment
- `sql/dimensions/dim_product.sql` — Products with missing commodity map to CommodityKey = -1; not excluded
- `sql/dimensions/dim_shipto.sql` — ShipTo location master; CustomerID represents primary owner only
- `sql/dimensions/dim_customer.sql` — CustomerStatusKey resolved via join to Dim_CustomerStatus; standalone contract customers included

### Design Decisions
- Default/unknown member (Key = -1) present on every dimension
- NULL FK lookups in fact tables always resolve without join failure

---

## [0.1.0] — 2026 — Module 1: Staging Layer

### Added
- `sql/staging/stg_sales_order_line.sql` — 9 DQ flags, NaturalKeyHash surrogate key
- `sql/staging/stg_load_freight.sql` — 8 DQ flags, FreightMargin/Pct derived at staging, LoadUtilizationBand with candidate thresholds
- `sql/staging/stg_contract_pricing.sql` — 10 DQ flags, ContractMatchTier structural classification, ContractDateStatus, ScopeCount overlap detection
- `sql/staging/stg_product_master.sql` — 7 DQ flags, UOM controlled value validation
- `sql/staging/stg_customer_reference.sql` — 7 DQ flags, Flag_ContractCustomerMissingHQ

### Confirmed Unknowns (Session 5)
- UNK-005: Standalone contract customers valid (CustomerHQID IS NULL is not an error)
- UNK-006: FreightMargin derivation confirmed at staging layer
- UNK-008: UOM controlled value set confirmed: CASE, LB, EACH, BOX, PALLET
- UNK-009: ContractID is pass-through only; no FK validation at staging

---

## [0.0.3] — 2026 — Session 4: Repository Documentation

### Added
- `README.md` — Initial project overview
- `docs/data_model.md` — Entity definitions, field types, relationships
- `docs/business_rules.md` — Structured rule set across all logic domains
- `docs/unknowns_log.md` — 19 open items tracked with candidate values
- `.github/CHANGELOG.md` — Version history
- SQL stubs for first two staging scripts

---

## [0.0.2] — 2026 — Session 3: GitHub Setup

### Added
- Repository initialized and pushed to GitHub
- MIT license applied
- `.gitignore` configured to block real data and credentials
- Branch cleanup completed — single `main` branch

---

## [0.0.1] — 2026 — Sessions 1–2: Specification and Synthetic Dataset

### Added
- Full system rebuild specification (sanitized)
- 6 raw input sources defined
- 17 transformations documented
- 8 reporting outputs specified
- 19 open unknowns logged
- Synthetic dataset: `data/dummy/DeliveredProgram_DummyDataset.xlsx`
- 12 entities with intentional data quality issues
