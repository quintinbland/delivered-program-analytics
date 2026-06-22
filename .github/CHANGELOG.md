# Changelog

## [Unreleased]

### Planned
- SQL staging layer (Module 1)
- SQL dimension builds (Module 2)
- SQL fact table builds (Module 3)
- SQL calculation engine (Module 4)
- SQL exception detection queries (Module 5)
- SQL reporting layer (Module 6)
- Power BI semantic model

---

## [0.2.0] — 2024-10 — Dummy Dataset

### Added
- Synthetic dataset: `data/dummy/DeliveredProgram_DummyDataset.xlsx`
  - 12 sheets covering all fact, dimension, exception, and reference entities
  - 366 sales order lines, 121 loads, 55 contract price rules, 8 commodities, 24 products, 11 customers, 12 ship-to locations
  - Intentional data quality issues for pipeline and exception testing
  - Full exception log pre-populated from dummy data
- `scripts/generate_dummy_data.py` — reproducible dataset generator

---

## [0.1.0] — 2024-10 — System Specification

### Added
- `README.md` — project overview, architecture, data model summary, build sequence
- `docs/data_model.md` — full entity definitions, field-level schemas, relationships
- `docs/business_rules.md` — complete structured rule set for all logic domains
- `docs/unknowns_log.md` — 19 open items requiring business confirmation
- Repository structure scaffolded
