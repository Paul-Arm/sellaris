# Economy Runtime

This subsystem owns deterministic empire resources, monthly settlement, and recurring source bookkeeping.

## Model

- `ResourceDefinition.gd`: Data-driven description of a resource type.
- `ResourceAmountDef.gd`: Authoring pair of `resource_id` + `milliunits`.
- `ResourceBundle.gd`: Compiled sparse runtime bundle using dense resource indices.
- `EconomySourceRecord.gd`: Recurring source record for deposits, upkeep, and future buildings.
- `ResourceRegistry.gd`: Deterministic loader and indexer for resource definitions.
- `autoload/EconomyManager.gd`: Authoritative stockpiles, monthly nets, source updates, and snapshots.

## Rules

- Authoritative amounts are stored as integer milliunits.
- Instant actions call `commit_cost()` / `grant_resources()` immediately.
- Recurring production and upkeep are only settled on `SimClock.month_tick`.
- New resource types are added by authoring a new `.tres` resource definition under `core/economy/resources/`.
