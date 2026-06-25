# Unknowns Log

Tracks all open unknowns, unconfirmed assumptions, and candidate values across the pipeline. Items remain open until confirmed by a domain stakeholder.

**Status values:** OPEN | CONFIRMED | SUPERSEDED

---

## UNK-001 — Contract Matching Hierarchy

| Field | Value |
|---|---|
| Status | CONFIRMED — Session 6 |
| Impact | HIGH |
| Resolution | Contract > Commit > Open Market. Tier3 (CustomerHQID + CommodityID) is the primary matching tier. Tier1 (CustomerID + ItemID) and Tier2 (CustomerHQID + ItemID) do not fire because contracts do not carry ItemID. NoMatch is expected for HQs without a contract. |
| Affected Scripts | `fact_sales_order_line.sql`, `fact_contract_price.sql`, `calc_fob_variance_summary.sql`, `calc_customer_performance.sql`, `exc_missing_contract_pricing.sql`, `rpt_fob_variance_detail.sql`, `rpt_customer_scorecard.sql` |

---

## UNK-002 — Target Full Truckload Pallet Threshold

| Field | Value |
|---|---|
| Status | CONFIRMED — Session 6 |
| Impact | MEDIUM |
| Resolution | 24 pallets = standard truck default. Full >= 22 pallets (>= 92%). Partial >= 18 pallets (>= 75%). Underutilized < 18 pallets. Flag_CandidateThreshold_UNK002 removed. |
| Affected Scripts | `stg_load_freight.sql`, `fact_load_freight.sql`, `calc_freight_summary.sql`, `calc_load_utilization.sql`, `rpt_freight_performance.sql` |

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
| Resolution Action | Confirm fiscal year start month; update MOD expression for FiscalPeriod and CASE for FiscalYear/FiscalQuarter |

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
| Status | CONFIRMED — Session 6 |
| Impact | HIGH |
| Resolution | FreightCharged = loadShippingCharged = total dollar amount billed to the customer for the load. It is a load-level total, not a per-case rate. FreightMargin = FreightCharged - FreightCost. |
| Affected Scripts | `stg_load_freight.sql`, `fact_load_freight.sql`, `calc_freight_summary.sql` |

---

## UNK-008 — FreightCharged = 0: Valid Operational Value vs Data Gap

| Field | Value |
|---|---|
| Status | CONFIRMED — Session 7 |
| Impact | HIGH |
| Resolution | Zero is valid ONLY for PUP (FOB/Pickup) loads. Zero on DLV (Delivered) loads = missing or unrecorded freight data. Mode_of_Delivery source column confirmed: exists in line-level dataset (Raw_SalesOrderLine) with values 'DLV' and 'PUP'. Derived to load level via MAX aggregation with DLV priority. |
| Mode Source | `Raw_SalesOrderLine.Mode_of_Delivery`. Values: `'DLV'` = Delivered, `'PUP'` = FOB/Pickup. |
| Load-Level Derivation | DLV takes priority: if ANY line on load = 'DLV' → Mode = 'DLV'; else if ANY line = 'PUP' → Mode = 'PUP'; else NULL. |
| Affected Scripts | `stg_load_freight.sql` v2.2.0, `stg_sales_order_line.sql` v2.1.0, `fact_load_freight.sql` v1.1.0 |
| Flag Behavior | `Flag_FreightChargedSuspect`: PUP + zero = 0 (valid). DLV + zero = 1 (data gap). Unknown mode + zero = 1. |
| IsCleanRow | DLV + zero/null FreightCharged = 0. PUP + zero FreightCharged = 1. |
| FreightStatus | New column: 'Valid Zero (FOB)', 'Missing Freight (DLV)', 'Freight Charged (DLV)', 'FOB with Freight (Review)', 'Missing (Null)', 'Review'. |
| FreightMargin | NULL for all PUP loads — customer-arranged freight; margin not measurable. |

---

## UNK-009 — 23 Items with Unknown Commodity Mapping

| Field | Value |
|---|---|
| Status | CONFIRMED — Session 10 (2026-06-25) |
| Impact | MEDIUM |
| Resolution | All 23 items resolved via Copilot. 13 produce items mapped and appended to `data/commodity_mapping.csv`. 10 non-produce items added to `data/non_produce_items.csv` and excluded from produce analytics via `Raw_NonProduceItems` reference table +