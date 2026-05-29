# Space Runtime

This module keeps ships, stations, creatures, fleets, construction projects, and exploration orders data-oriented so the game can scale without one scene tree node per object.

## Model

- `SpaceUnitClass.gd`: Shared definition for ships, stations, or creatures, including capability components and loadout metadata.
- `SpaceUnitRuntime.gd`: Lightweight live unit record with owner, controller, system, hull, fleet assignment, movement, and metadata.
- `SpaceFleetRuntime.gd`: Lightweight live fleet record with member ids, route state, command queue, and local movement state.
- `components/SpaceUnitOwnershipComponent.gd`: Ownership and controller rules.
- `components/SpaceUnitUpkeepComponent.gd`: Build costs, monthly costs, crew requirement, and command point cost.
- `components/SpaceUnitMobilityComponent.gd`: In-system movement, hyperlane usage, formation radius, and fleet eligibility.
- `components/SpaceUnitBuilderComponent.gd`: Build tags and the single-active-project rule for builder ships.
- `components/SpaceUnitBuildableComponent.gd`: Build time and required tags for stations or other buildable units.
- `components/SpaceUnitExplorerComponent.gd`: Survey scan timing, body type support, anomaly discovery, and intel rewards.
- `autoload/SpaceManager.gd`: Central registry, indexes, deterministic movement, construction, exploration, economy source syncing, and snapshots.
- `autoload/EconomyManager.gd`: Authoritative resource settlement for unit upkeep and collector output.
- `autoload/ColonyManager.gd`: Creates/removes hosted colonies for unit classes with `ColonyHostComponent`.

## Built-in Unit Classes

`SpaceManager.register_builtin_unit_classes()` currently registers:

- `science_ship`: Mobile civilian scout with an explorer component.
- `builder_ship`: Mobile civilian construction unit with builder tags for orbital, stellar, mining, and research stations.
- `basic_station`: Stationary buildable orbital station.
- `stellar_station`: Stationary buildable star/stellar station.
- `resource_collector_station`: Stationary buildable collector that can harvest body deposits when targeted at a valid deposit body.

Debug unit classes used by tests and panels are registered outside the built-ins.

## Rules

- A unit is mobile only when its class has a mobile `SpaceUnitMobilityComponent`.
- Stations are normal `SpaceUnitClass` records without mobility.
- Fleets only accept mobile units and keep member positions in formation.
- Hyperlane travel and in-system movement advance on `SimClock.day_tick`.
- A unit in a fleet cannot receive an independent builder or exploration order.
- Builder ships validate station options against the target body's `buildable_component.allowed_build_tags`.
- Resource collector options are only offered when the target body has harvestable deposits and no completed or active collector already targets it.
- Construction starts by moving the builder to the site, then ticks down `build_time_days`; the built station inherits owner, system, display name, target body metadata, and local position.
- Science ships can request exploration orders, scan supported body types, discover anomalies, and raise system intel.
- Unit upkeep sources register into `EconomyManager` immediately, but their recurring effect is applied only on `SimClock.month_tick`.

## Example

```gdscript
var scout := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, "empire_01", "sys_0001", {
	"display_name": "ISS Curie",
	"controller_kind": SpaceUnitOwnershipComponent.CONTROLLER_AI,
})

var builder := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "empire_01", "sys_0001", {
	"display_name": "ISS Mason",
})

var fleet := SpaceManager.create_fleet("empire_01", "sys_0001", [scout.unit_id], {
	"display_name": "1st Survey Group",
})

SpaceManager.issue_fleet_hyperlane_move(fleet.fleet_id, "sys_0002", 8)

var body_context := {
	"body_id": "planet_00",
	"body_type": "planet",
	"body_name": "Alpha I",
	"local_position": Vector3(18.0, 0.0, 0.0),
	"buildable_component": {
		"allowed_build_tags": ["orbital_station"],
		"max_active_projects": 1,
	},
}

var options := SpaceManager.get_build_options_for_body(builder.unit_id, "sys_0001", body_context)
if not options.is_empty():
	SpaceManager.request_build_order_for_body(builder.unit_id, "sys_0001", body_context, options[0]["class_id"])
```

## Snapshots

- `SpaceManager.build_snapshot()` emits `space_unit_classes`, `space_units`, `fleets`, `construction_projects`, and `exploration_orders`.
- Legacy snapshot keys such as `ships` and `ship_classes` are intentionally not emitted.
- `SpaceManager.load_snapshot()` rebuilds runtime indexes, active project metadata, exploration metadata, and economy sources.
