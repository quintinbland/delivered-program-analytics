# Open Items — Unknowns Log

Items requiring business confirmation before production implementation.  
Candidate values or placeholder logic are noted where applied.

---

| ID | Area | Question | Impact | Candidate Value Applied | Status |
|---|---|---|---|---|---|
| UNK-001 | Contract Matching | Exact priority order for contract price matching (item vs. commodity vs. HQ vs. ship-to) | High — affects ContractFOB on every eligible sales line | Item > HQ+Commodity applied as candidate | Open |
| UNK-002 | Load Utilization | Target full truckload pallet threshold | Medium — affects LoadUtilizationBand and underutilized load exceptions | 24 pallets applied as candidate | Open |
| UNK-003 | Contract Performance | Exact row-level definition of OnTargetFlag | High — affects OnTargetPct and PerformanceRating | Not implemented pending confirmation | Open |
| UNK-004 | Time Periods | Whether rolling periods use current system date, latest ship date, or user-selected report date | Medium — affects IsRolling4Weeks, IsRolling8Weeks | System date used as candidate | Open |
| UNK-005 | Data Refresh | Source refresh cadence (daily, weekly, on-demand) | Medium — affects pipeline scheduling | UNKNOWN | Open |
| UNK-006 | Data Refresh | Credential ownership and source connection method for ERP export | High — blocks production ingestion build | UNKNOWN | Open |
| UNK-007 | Freight | Whether FreightCharged represents billed, budgeted, allocated, or contractual freight | High — affects business interpretation of FreightMargin | UNKNOWN | Open |
| UNK-008 | Contract Pricing | Whether contracts vary by ship-to (or only at customer/HQ level) | Medium — affects matching hierarchy design | HQ-level only in candidate model | Open |
| UNK-009 | Contract Pricing | Whether item-level or commodity-level pricing takes priority when both exist | High — affects ContractFOB on item-matched lines | Item-level applied as higher priority | Open |
| UNK-010 | Contract Pricing | Contract effective date handling when multiple active versions overlap | Medium — affects which contract price is selected | Active + date range filter applied | Open |
| UNK-011 | Product | Whether OrganicFlag is a formal governed field or inferred from item description text | Low-Medium — affects organic/conventional segmentation | Formal field assumed | Open |
| UNK-012 | Product | Whether commodity hierarchy is governed in ERP or manually maintained | Medium — affects dimension stability | Governed assumed | Open |
| UNK-013 | Customer | Whether customer HQ mapping is one-to-one or many-to-one | Low — affects rollup aggregation design | Many-to-one (multiple customers per HQ) applied | Open |
| UNK-014 | Exceptions | Alert recipients by exception type | Low — affects exception routing design | UNKNOWN | Open |
| UNK-015 | Exceptions | Exception owner assignments and escalation rules | Low — affects exception workflow | UNKNOWN | Open |
| UNK-016 | Forecasting | Forecasting methodology and data sources | Low (future module) | UNKNOWN | Future |
| UNK-017 | Inventory | Whether inventory logic is in scope for this system | Low (future module) | Out of scope for current build | Future |
| UNK-018 | Reporting | Dashboard refresh cadence and audience distribution method | Low — affects reporting layer design | UNKNOWN | Open |
| UNK-019 | Contract Pricing | Whether ContractDeliveredPrice exists separately from ContractFOB | Medium — affects delivered vs FOB analysis | Both fields modeled; population UNKNOWN | Open |
