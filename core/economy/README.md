# Economy Runtime

This subsystem owns deterministic resources, recurring source bookkeeping, colonies, population jobs, buildings, deposits, and economy snapshots.

## Model

- `ResourceDefinition.gd`: Data-driven resource type with sorting, capacity, starting stockpile, AI weight, and visibility metadata.
- `ResourceAmountDef.gd`: Authoring helper for `resource_id` plus integer `milliunits`; also normalizes dictionaries using whole-unit floats.
- `ResourceBundle.gd`: Dense-index runtime bundle used by managers to avoid repeated resource-id lookups.
- `ResourceRegistry.gd`: Deterministic loader and indexer for definitions under `core/economy/resources/`.
- `EconomySourceRecord.gd`: Recurring source record for unit upkeep, colony output, and resource collectors.
- `components/ResourceDepositComponent.gd`: Generated, fixed, additive, or disabled resource deposits on stars, planets, belts, structures, and ruins.
- `components/ColonyHostComponent.gd`: Optional space-unit or station component that can host a colony.
- `SpeciesRuntime.gd`: Runtime copy of an empire species, including archetype, type, visuals, names, and trait ids.
- `PopUnitRuntime.gd`: One population unit, its size, species id, and assigned job.
- `ColonyRuntime.gd`: Live colony state for orbital or space-unit hosts, buildings, building slots, pops, job caps, and snapshot data.
- `autoload/EconomyManager.gd`: Authoritative stockpiles, capacities, monthly nets, resource collector sources, and resource snapshots.
- `autoload/ColonyManager.gd`: Species registration, colony creation, job assignment, building placement, colony economy sources, and colony snapshots.

## Data Files

- Resources: `core/economy/resources/*.tres`
- Jobs: `core/economy/jobs/jobs.cfg`
- Buildings: `core/economy/buildings/buildings.cfg`
- Species traits used by colony math: `core/empire/species/traits/traits.cfg`

## Rules

- All authoritative resource amounts are integer milliunits. A value of `1000` means one displayed unit.
- `EconomyManager.bootstrap()` creates the dense empire/resource rows from empire ids and resource definitions.
- Instant actions use `commit_cost()`, `grant_resources()`, or `transfer_resources()` immediately.
- Recurring income, upkeep, and capacity changes are registered as sources and settled on `SimClock.month_tick`.
- Source changes update projected monthly rows immediately; stockpiles change only on instant actions or monthly settlement.
- Generated deposits are preview data until a completed `resource_collector_station` targets that body. The collector registers `resource_collector:<unit_id>`.
- Space-unit upkeep registers as `unit:<unit_id>` when `SpaceManager` spawns or updates units with monthly costs.
- Colonies register `colony:<colony_id>` based on assigned pops, job definitions, building slots, habitability, and species trait modifiers.
- Building placement spends `build_cost`, writes the target slot, refreshes job caps, rebalances jobs, and resyncs the colony source.
- Orbital colonies are indexed by host kind, system id, and host id. Space-unit colonies follow their host unit's owner and system.

## Colony Flow

1. `ColonyManager.bootstrap()` registers each empire's primary species from empire records or fallback species data.
2. The starting empire gets a capital colony through `create_capital_colony()` during game generation.
3. Additional explored, owned, colonizable planets call `GameSceneRuntimeSystem.request_colonize_orbital()`.
4. Ship or station habitats call `create_colony_for_space_unit()` when a unit class has `ColonyHostComponent`.
5. UI actions call `assign_pop_to_job()`, `set_job_cap()`, and `place_building()`.

## Snapshots

- `EconomyManager.build_snapshot()` stores registry hash, stockpiles, capacities, monthly rows, shortages, revisions, collector modifier, and source records.
- `ColonyManager.build_snapshot()` stores known species and colonies.
- `GameSceneRuntimeSystem.get_runtime_snapshot()` combines galaxy, space, economy, and colony snapshots for save/load work.
