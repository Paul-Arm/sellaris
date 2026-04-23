# Space Runtime

This module keeps ships, stations, and fleets data-oriented so the game can scale to thousands of units without one scene tree node per object.

## Model

- `ShipClass.gd`: Shared definition for a ship or station.
- `ShipOwnershipComponent.gd`: Ownership and controller rules.
- `ShipUpkeepComponent.gd`: Build and monthly upkeep costs.
- `ShipMobilityComponent.gd`: Optional movement profile. If missing, the class behaves like a station.
- `ShipRuntime.gd`: Lightweight live unit record.
- `FleetRuntime.gd`: Lightweight live fleet record.
- `autoload/SpaceManager.gd`: Central registry, indexes, and snapshots for ships and fleets.
- `autoload/EconomyManager.gd`: Authoritative monthly resource settlement and source ledger.

## Example

```gdscript
SpaceManager.register_ship_class_from_data({
	"class_id": "corvette",
	"display_name": "Corvette",
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

var ship := SpaceManager.spawn_ship("corvette", "empire_01", "sys_0001", {
	"display_name": "ISS Resolute",
	"controller_kind": ShipOwnershipComponent.CONTROLLER_AI,
})

var fleet := SpaceManager.create_fleet("empire_01", "sys_0001", [ship.ship_id], {
	"display_name": "1st Patrol Fleet",
	"ai_role": "border_patrol",
})
```

## Notes

- Stations use the same `ShipClass` but omit `mobility_component`.
- Fleets only accept mobile ships.
- `SpaceManager.build_system_presence()` and `SpaceManager.build_owner_presence()` are intended as fast AI/query helpers.
- `SpaceManager.build_snapshot()` is designed for save/load and multiplayer replication layers.
- Ship upkeep sources register into `EconomyManager` immediately, but their recurring effect is only applied on `SimClock.month_tick`.
