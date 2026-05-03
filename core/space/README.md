# Space Runtime

This module keeps space units, stations, creatures, and fleets data-oriented so the game can scale to thousands of units without one scene tree node per object.

## Model

- `SpaceUnitClass.gd`: Shared definition for a ship, station, or creature.
- `SpaceUnitOwnershipComponent.gd`: Ownership and controller rules.
- `SpaceUnitUpkeepComponent.gd`: Build and monthly upkeep costs.
- `SpaceUnitMobilityComponent.gd`: Optional movement profile. If missing, the class behaves like a station.
- `SpaceUnitRuntime.gd`: Lightweight live unit record.
- `SpaceFleetRuntime.gd`: Lightweight live fleet record.
- `autoload/SpaceManager.gd`: Central registry, indexes, deterministic movement, and snapshots for units and fleets.
- `autoload/EconomyManager.gd`: Authoritative monthly resource settlement and source ledger.

## Example

```gdscript
SpaceManager.register_unit_class_from_data({
	"class_id": "corvette",
	"display_name": "Corvette",
	"unit_kind": "ship",
	"category": "combat",
	"max_hull_points": 300.0,
	"default_ai_role": "screen",
	"command_tags": ["combat", "escort"],
	"upkeep_component": {
		"monthly_costs": [
			{"resource_id": "energy", "milliunits": 1000},
			{"resource_id": "alloys", "milliunits": 150},
		],
	},
	"mobility_component": {
		"cruise_speed": 1.0,
		"acceleration": 1.8,
		"turn_rate_degrees": 220.0,
	},
})

var unit := SpaceManager.spawn_unit("corvette", "empire_01", "sys_0001", {
	"display_name": "ISS Resolute",
	"controller_kind": SpaceUnitOwnershipComponent.CONTROLLER_AI,
})

var fleet := SpaceManager.create_fleet("empire_01", "sys_0001", [unit.unit_id], {
	"display_name": "1st Patrol Fleet",
	"ai_role": "border_patrol",
})

SpaceManager.issue_fleet_move(fleet.fleet_id, Vector3(32.0, 0.0, 12.0))
```

## Notes

- Stations use the same `SpaceUnitClass` but omit `mobility_component`.
- The built-in `science_ship` class is registered by `SpaceManager` for civilian scout shells.
- Fleets only accept mobile units.
- `SpaceManager.build_system_presence()` and `SpaceManager.build_owner_presence()` are intended as fast AI/query helpers.
- `SpaceManager.build_snapshot()` is designed for save/load and multiplayer replication layers.
- Unit upkeep sources register into `EconomyManager` immediately, but their recurring effect is only applied on `SimClock.month_tick`.
