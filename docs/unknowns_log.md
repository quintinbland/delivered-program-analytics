# Unknowns Log

Tracks all open unknowns, unconfirmed assumptions, and candidate values across the pipeline. Items remain open until confirmed by a domain stakeholder.

**Status values:** OPEN | CONFIRMED | SUPERSEDED

---

## UNK-001 — Contract Matching Hierarchy

| Field | Value |
|---|---|
| Status | OPEN |
| Impact | HIGH |
| Candidate Value | Tier 1: CustomerID + ItemID + date range; Tier 2: CustomerHQID + ItemID + date range; Tier 3: CustomerHQID + CommodityID + date range; Tier 4: NoMatch |
| Affected Scripts | `fact_sales_order_line.sql`, `fact_contract_price.sql`, `calc_fob_variance_summary.sql`, `calc_customer_performance.sql`, `exc_missing_contract_pricing.sql`, `rpt_fob_variance_detail.sql`, `rpt_customer_scorecard.sql` |
| Pipeline Flag | `Flag_CandidateHierarchy_UNK001 = 1` on all affected rows |
| Resolution Action | Confirm tier precedence and whether CustomerID-level match (Tier 1) always supersedes HQ-level match |

---

## UNK-002 — Target Full Truckload Pallet Threshold

| Field | Value |
|---|---|
| Status | OPEN |
| Impact | MEDIUM |
| Candidate Value | 24 pallets (Full), 18 pallets (Partial floor) |
| Affected Scripts | `stg_load_freight.sql`, `fact_load_freight.sql`, `calc_freight_summary.sql`, `calc_load_utilization.sql`, `rpt_freight_performance.sql` |
| Pipeline Flag | `Flag_CandidateThreshold_UNK002 = 1` on all affected rows; `CandidateTargetPallets_UNK002 = 24` stored in `Calc_LoadUtilization` output |
| Resolution Action | Confirm pallet threshold for Full and Partial bands with freight operations; update candidate values in staging and remove flag columns |

---

## UNK-003 — OnTargetFlag Row-Level Definition

| Field | Value |
|---|---|
| Status | OPEN |
| Impact | HIGH |
| Candidate Value | UNKNOWN |
| Affected Scripts | Excluded from all scripts pending definition |
| Pipeline Flag | N/A — field not implemented |
| Resolution Action | Define the exact condition that sets OnTargetFlag = 1 vs 0 at the sales order line level; confirm whether it is derived or source-supplied |

---

## UNK-004 — Rolling Period Date Basis / Fiscal Year Start

| Field | Value |
|---|---|
| Status | OPEN |
| Impact | MEDIUM |
| Candidate Value | Fiscal year start = October 1 (FY = calendar year + 1 when month >= 10) |
| Affected Scripts | `dim_date.sql` — FiscalYear, FiscalQuarter, FiscalPeriod fields |
| Pipeline Flag | `Flag_CandidateFiscalCalendar = 1` on all rows in `Dim_Date` |
| Resolution Action | Confirm fiscal year start month; update `dim_date.sql` MOD expression for FiscalPeriod and CASE for FiscalYear/FiscalQuarter |

---

## UNK-005 — CustomerHQID for Standalone Contract Customers

| Field | Value |
|---|---|
| Status | CONFIRMED — Session 5 |
| Impact | LOW |
| Resolution | Standalone contract customers (CustomerHQID IS NULL) are valid and expected. `Flag_ContractCustomerMissingHQ` is informational only — not an error condition. |
| Affected Scripts | `stg_customer_reference.sql`, `dim_customer.sql` |

---

## UNK-006 — Freight Margin Derivation Layer

| Field | Value |
|---|---|
| Status | CONFIRMED — Session 5 |
| Impact | LOW |
| Resolution | FreightMargin and FreightMarginPct are derived at the staging layer (not deferred to the fact layer). This is the confirmed design. |
| Affected Scripts | `stg_load_freight.sql` |

---

## UNK-007 — FreightCharged Semantics

| Field | Value |
|---|---|
| Status | OPEN |
| Impact | HIGH |
| Candidate Value | UNKNOWN — could represent billed amount, budgeted amount, or allocated amount |
| Affected Scripts | `stg_load_freight.sql`, `fact_load_freight.sql`, `exc_negative_freight_margin.sql`, `rpt_freight_performance.sql` |
| Pipeline Flag | `Flag_FreightChargedSuspect = 1` when FreightCharged IS NULL or = 0; `OpenUnknownNote` propagated to `Exc_Master` |
| Resolution Action | Confirm whether FreightCharged represents: (a) amount billed to customer, (b) budgeted freight cost, or (c) allocated freight cost; restate affected exceptions after confirmation |

---

## UNK-008 — UnitOfMeasure Controlled Value Set

| Field | Value |
|---|---|
| Status | CONFIRMED — Session 5 |
| Impact | LOW |
| Resolution | Allowed values confirmed as: `CASE`, `LB`, `EACH`, `BOX`, `PALLET`. `Flag_UnexpectedUOM` fires for any value outside this set. |
| Affected Scripts | `stg_product_master.sql` |

---

## UNK-009 — ContractID as Direct FK

| Field | Value |
|---|---|
| Status | CONFIRMED — Session 5 |
| Impact | LOW |
| Resolution | ContractID on Stg_SalesOrderLine is a pass-through field only. No referential integrity check is applied at staging. Contract resolution uses the matching hierarchy (UNK-001), not ContractID. |
| Affected Scripts | `stg_sales_order_line.sql`, `fact_sales_order_line.sql` |

---

## UNK-010 — Freight Margin Allocation Basis

| Field | Value |
|---|---|
| Status | OPEN |
| Impact | MEDIUM |
| Candidate Value | Proportional by QuantityCases per LoadID per customer |
| Affected Scripts | `calc_customer_performance.sql`, `rpt_customer_scorecard.sql` |
| Pipeline Flag | None — allocation method is implicit in CTE logic |
| Resolution Action | Confirm whether freight margin allocation should use QuantityCases (current), revenue-weighted, flat per-line, or another basis; update `freight_allocation` CTE in `calc_customer_performance.sql` |

---

## UNK-011 — Freight Performance Tier Thresholds

| Field | Value |
|---|---|
| Status | OPEN |
| Impact | LOW |
| Candidate Value | Strong: FreightMarginPct >= 0.15 AND UtilizationRate >= 0.80; Adequate: FreightMarginPct >= 0.05 AND UtilizationRate >= 0.65; At_Risk: below Adequate; Negative: FreightMarginPct < 0 |
| Affected Scripts | `rpt_freight_performance.sql` |
| Pipeline Flag | `Flag_CandidatePerformanceTier = 1` on all rows |
| Resolution Action | Confirm margin and utilization thresholds for each performance tier with freight operations leadership |

---

## UNK-012 — Customer Health Tier Thresholds

| Field | Value |
|---|---|
| Status | OPEN |
| Impact | LOW |
| Candidate Value | Healthy: TotalFOBVariance >= 0 AND NoContractMatchLines = 0; At_Risk: either condition fails; Critical: both conditions fail |
| Affected Scripts | `rpt_customer_scorecard.sql` |
| Pipeline Flag | `Flag_CandidateHealthTier = 1` on all rows |
| Resolution Action | Confirm health tier definition with sales and contract management; determine whether quantitative thresholds (e.g., variance > -$X) should replace binary conditions |

---

## Summary

| Status | Count |
|---|---|
| OPEN | 9 (UNK-001, 002, 003, 004, 007, 010, 011, 012, and UNK-004) |
| CONFIRMED | 4 (UNK-005, 006, 008, 009) |
| SUPERSEDED | 0 |

Resolution of UNK-001 and UNK-007 will have the highest downstream impact on pipeline correctness and should be prioritized.
