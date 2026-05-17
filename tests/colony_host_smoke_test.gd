extends Node

const DEBUG_COLONY_SHIP_CLASS_ID := "debug_colony_ship"
const DEBUG_HABITAT_STATION_CLASS_ID := "debug_habitat_station"


func _ready() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Colony host smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)
	ColonyManager.reset_runtime_state(false)
	_register_debug_colony_unit_classes()

	var empire_records: Array[Dictionary] = [
		{"id": "empire_alpha", "name": "Empire Alpha"},
		{"id": "empire_beta", "name": "Empire Beta"},
	]
	EconomyManager.bootstrap(["empire_alpha", "empire_beta"], {"generated_seed": 7, "systems": []})
	ColonyManager.bootstrap(empire_records)
	_test_runtime_colonize_orbital(empire_records, failures)

	var planet_record := {
		"id": "alpha_prime",
		"name": "Alpha Prime",
		"type": "planet",
		"planet_class_id": "landmass",
		"habitability_points": 82,
		"resource_richness_points": 60,
		"is_colonizable": true,
		"metadata": {"planet_visual": {"kind": "landmass"}},
	}
	var capital_colony_id := ColonyManager.create_colony_for_orbital("empire_alpha", "sys_alpha", planet_record, {
		"colony_id": "capital_empire_alpha_sys_alpha_alpha_prime",
		"colony_name": "Alpha Prime",
		"is_capital": true,
		"starter_buildings": ["capital_hub"],
		"starter_building_slots": {"q0_r0": "capital_hub"},
	})
	_expect(not capital_colony_id.is_empty(), "planet colony should be created", failures)
	_expect(ColonyManager.get_colony_id_for_host(ColonyRuntime.HOST_KIND_ORBITAL, "alpha_prime", "sys_alpha") == capital_colony_id, "planet host index should resolve colony in its system", failures)
	_expect(ColonyManager.get_colony_id_for_host(ColonyRuntime.HOST_KIND_ORBITAL, "alpha_prime").is_empty(), "orbital host lookup should require a system id", failures)
	var sibling_colony_id := ColonyManager.create_colony_for_orbital("empire_alpha", "sys_beta", planet_record, {
		"colony_name": "Beta Prime",
		"starter_buildings": ["capital_hub"],
		"starter_building_slots": {"q0_r0": "capital_hub"},
	})
	_expect(not sibling_colony_id.is_empty() and sibling_colony_id != capital_colony_id, "matching orbital ids in different systems should create distinct colonies", failures)
	_expect(ColonyManager.get_colony_id_for_host(ColonyRuntime.HOST_KIND_ORBITAL, "alpha_prime", "sys_beta") == sibling_colony_id, "orbital host index should include the system id", failures)
	var capital_details := ColonyManager.get_colony_details(capital_colony_id)
	_expect(str(capital_details.get("host_kind", "")) == ColonyRuntime.HOST_KIND_ORBITAL, "planet colony should use orbital host kind", failures)
	_expect(str(capital_details.get("planet_orbital_id", "")) == "alpha_prime", "planet alias should be preserved", failures)
	_expect(EconomyManager.has_source("colony:%s" % capital_colony_id), "planet colony should register economy source", failures)

	var restored_class := SpaceUnitClass.from_dict(SpaceManager.get_unit_class(DEBUG_COLONY_SHIP_CLASS_ID).to_dict())
	_expect(restored_class.has_colony_host(), "space unit class snapshot should preserve colony host component", failures)
	_expect(restored_class.get_capability_mask() & SpaceUnitClass.CAPABILITY_COLONY != 0, "space unit class should expose colony capability", failures)

	var colony_ship := SpaceManager.spawn_unit(DEBUG_COLONY_SHIP_CLASS_ID, "empire_alpha", "sys_alpha", {
		"unit_id": "ship_ark_alpha",
		"display_name": "Ark Alpha",
		"local_position": Vector3.ZERO,
	})
	_expect(colony_ship != null and colony_ship.can_host_colony(), "colony ship should spawn with colony capability", failures)
	var ship_colony_id := ColonyManager.create_colony_for_space_unit(colony_ship.unit_id)
	_expect(not ship_colony_id.is_empty(), "ship-hosted colony should be created", failures)
	_expect(ColonyManager.get_colony_id_for_host(ColonyRuntime.HOST_KIND_SPACE_UNIT, colony_ship.unit_id) == ship_colony_id, "ship host index should resolve colony", failures)
	var ship_colony_details := ColonyManager.get_colony_details(ship_colony_id)
	_expect(str(ship_colony_details.get("host_kind", "")) == ColonyRuntime.HOST_KIND_SPACE_UNIT, "ship colony should use space_unit host kind", failures)
	_expect(str(ship_colony_details.get("system_id", "")) == "sys_alpha", "ship colony should start in host unit system", failures)
	_expect(int(ship_colony_details.get("building_grid_radius", 0)) == 2, "ship colony should use component grid radius", failures)

	_expect(SpaceManager.set_unit_owner(colony_ship.unit_id, "empire_beta"), "unit owner transfer should succeed", failures)
	ship_colony_details = ColonyManager.get_colony_details(ship_colony_id)
	_expect(str(ship_colony_details.get("empire_id", "")) == "empire_beta", "ship colony owner should follow unit owner", failures)
	_expect(SpaceManager.issue_unit_hyperlane_move(colony_ship.unit_id, "sys_beta", 1), "colony ship hyperlane move should start", failures)
	SpaceManager._on_sim_day_tick({})
	ship_colony_details = ColonyManager.get_colony_details(ship_colony_id)
	_expect(str(ship_colony_details.get("system_id", "")) == "sys_beta", "ship colony system should follow unit movement", failures)
	_expect(not ColonyManager.get_colony_ids_for_system("sys_beta", "empire_beta").is_empty(), "moved ship colony should be indexed in destination system", failures)

	var station := SpaceManager.spawn_unit(DEBUG_HABITAT_STATION_CLASS_ID, "empire_alpha", "sys_alpha", {
		"unit_id": "station_hab_alpha",
		"display_name": "Habitat Alpha",
		"local_position": Vector3(0.0, 0.0, 6.0),
	})
	_expect(station != null and station.is_stationary(), "habitat station should spawn stationary", failures)
	var station_colony_id := ColonyManager.create_colony_for_space_unit(station.unit_id)
	_expect(not station_colony_id.is_empty(), "station-hosted colony should be created", failures)

	ColonyManager.transfer_colonies_in_system("sys_alpha", "empire_beta")
	_expect(str(ColonyManager.get_colony_summary(capital_colony_id).get("empire_id", "")) == "empire_beta", "orbital colony should transfer with system ownership", failures)
	_expect(str(ColonyManager.get_colony_summary(station_colony_id).get("empire_id", "")) == "empire_alpha", "space-unit colony should not transfer with system ownership", failures)

	EconomyManager.grant_resources("empire_beta", {"matter": 1000.0, "alloys": 1000.0, "energy": 1000.0})
	_expect(ColonyManager.place_building(capital_colony_id, "q1_r0", "basic_reactor"), "building placement should still work on orbital colony", failures)
	_expect(ColonyManager.get_colony_details(capital_colony_id).get("buildings", []).size() >= 2, "placed building should appear in colony details", failures)

	var snapshot := ColonyManager.build_snapshot()
	ColonyManager.load_snapshot(snapshot)
	_expect(ColonyManager.has_colony(ship_colony_id), "snapshot load should restore ship colony", failures)
	_expect(ColonyManager.get_colony_id_for_host(ColonyRuntime.HOST_KIND_SPACE_UNIT, colony_ship.unit_id) == ship_colony_id, "snapshot load should rebuild host index", failures)

	var legacy_colony = ColonyRuntime.from_dict({
		"id": "legacy_colony",
		"empire_id": "empire_alpha",
		"system_id": "sys_legacy",
		"planet_orbital_id": "legacy_planet",
		"planet_record": {"id": "legacy_planet", "name": "Legacy", "type": "planet", "habitability_points": 70},
		"pop_units": [],
	})
	_expect(legacy_colony.host_kind == ColonyRuntime.HOST_KIND_ORBITAL, "legacy colony should default to orbital host kind", failures)
	_expect(legacy_colony.host_id == "legacy_planet", "legacy colony should map planet_orbital_id to host_id", failures)
	_expect(legacy_colony.planet_orbital_id == "legacy_planet", "legacy planet alias should survive load", failures)


func _test_runtime_colonize_orbital(empire_records: Array[Dictionary], failures: Array[String]) -> void:
	var runtime := GameSceneRuntimeSystem.new()
	var state := GameSceneState.new()
	var colonizable_planet := _build_runtime_planet("runtime_world", "Runtime World", 70, true)
	var twin_planet := _build_runtime_planet("runtime_world", "Twin Runtime World", 72, true)
	var foreign_planet := _build_runtime_planet("foreign_world", "Foreign World", 75, true)
	var low_intel_planet := _build_runtime_planet("low_intel_world", "Low Intel World", 80, true)
	var barren_planet := _build_runtime_planet("barren_world", "Barren World", 10, false)
	state.galaxy_state.load_from_layout({
		"seed": 7,
		"systems": [
			{"id": "sys_runtime", "name": "Runtime", "position": Vector3.ZERO, "owner_empire_id": "empire_alpha"},
			{"id": "sys_twin", "name": "Runtime Twin", "position": Vector3(60.0, 0.0, 0.0), "owner_empire_id": "empire_alpha"},
			{"id": "sys_foreign", "name": "Foreign", "position": Vector3(120.0, 0.0, 0.0), "owner_empire_id": "empire_beta"},
			{"id": "sys_low_intel", "name": "Low Intel", "position": Vector3(240.0, 0.0, 0.0), "owner_empire_id": "empire_alpha"},
			{"id": "sys_barren", "name": "Barren", "position": Vector3(360.0, 0.0, 0.0), "owner_empire_id": "empire_alpha"},
		],
		"system_detail_overrides": {
			"sys_runtime": {"orbitals": [colonizable_planet], "anomaly_risk": 0.1},
			"sys_twin": {"orbitals": [twin_planet], "anomaly_risk": 0.1},
			"sys_foreign": {"orbitals": [foreign_planet], "anomaly_risk": 0.1},
			"sys_low_intel": {"orbitals": [low_intel_planet], "anomaly_risk": 0.1},
			"sys_barren": {"orbitals": [barren_planet], "anomaly_risk": 0.1},
		},
	})
	state.galaxy_state.set_empires(empire_records)
	state.active_empire_id = "empire_alpha"
	state.galaxy_state.reveal_system_intel("empire_alpha", "sys_runtime", GalaxyState.INTEL_EXPLORED)
	state.galaxy_state.reveal_system_intel("empire_alpha", "sys_twin", GalaxyState.INTEL_EXPLORED)
	state.galaxy_state.reveal_system_intel("empire_alpha", "sys_foreign", GalaxyState.INTEL_EXPLORED)
	state.galaxy_state.reveal_system_intel("empire_alpha", "sys_low_intel", GalaxyState.INTEL_SENSOR)
	state.galaxy_state.reveal_system_intel("empire_alpha", "sys_barren", GalaxyState.INTEL_EXPLORED)
	runtime.setup(state, null, null, null, null)
	runtime.sync_cached_state()

	var colony_id := runtime.request_colonize_orbital("sys_runtime", {"body_id": "runtime_world"})
	_expect(not colony_id.is_empty(), "runtime colonization should create colony for owned explored habitable planet", failures)
	_expect(ColonyManager.get_colony_id_for_host(ColonyRuntime.HOST_KIND_ORBITAL, "runtime_world", "sys_runtime") == colony_id, "runtime colony should be indexed by orbital host in its system", failures)
	_expect(ColonyManager.get_colony_id_for_host(ColonyRuntime.HOST_KIND_ORBITAL, "runtime_world", "sys_twin").is_empty(), "same orbital id in another system should not resolve the first colony", failures)
	var twin_colony_id := runtime.request_colonize_orbital("sys_twin", {"body_id": "runtime_world"})
	_expect(not twin_colony_id.is_empty() and twin_colony_id != colony_id, "same orbital id in another system should be colonizable separately", failures)
	_expect(runtime.request_colonize_orbital("sys_runtime", {"body_id": "runtime_world"}).is_empty(), "runtime colonization should reject occupied orbital", failures)
	_expect(runtime.request_colonize_orbital("sys_foreign", {"body_id": "foreign_world"}).is_empty(), "runtime colonization should reject foreign system", failures)
	_expect(runtime.request_colonize_orbital("sys_low_intel", {"body_id": "low_intel_world"}).is_empty(), "runtime colonization should reject insufficient intel", failures)
	_expect(runtime.request_colonize_orbital("sys_barren", {"body_id": "barren_world"}).is_empty(), "runtime colonization should reject non-colonizable planet", failures)
	runtime.free()


func _build_runtime_planet(planet_id: String, planet_name: String, habitability_points: int, is_colonizable: bool) -> Dictionary:
	return {
		"id": planet_id,
		"name": planet_name,
		"type": "planet",
		"orbit_radius": 30.0,
		"size": 2.0,
		"habitability_points": habitability_points,
		"habitability": float(habitability_points) / 100.0,
		"resource_richness_points": 55,
		"resource_richness": 0.55,
		"is_colonizable": is_colonizable,
		"metadata": {"planet_visual": {"kind": "landmass"}},
	}


func _register_debug_colony_unit_classes() -> void:
	SpaceManager.register_unit_class_from_data({
		"class_id": DEBUG_COLONY_SHIP_CLASS_ID,
		"display_name": "Debug Colony Ship",
		"unit_kind": SpaceUnitClass.UNIT_KIND_SHIP,
		"category": SpaceUnitClass.CATEGORY_SUPPORT,
		"max_hull_points": 700.0,
		"command_tags": ["colony", "habitat"],
		"upkeep_component": {"monthly_costs": {"energy": 2.0}},
		"mobility_component": {
			"cruise_speed": 4.0,
			"acceleration": 4.0,
			"turn_rate_degrees": 120.0,
			"formation_radius": 5.0,
			"can_join_fleets": false,
			"uses_hyperlanes": true,
			"can_move_in_system": true,
		},
		"colony_host_component": {
			"habitat_kind": "ark_ship",
			"base_habitability_points": 65,
			"building_grid_radius": 2,
			"starter_buildings": ["capital_hub"],
			"starter_building_slots": {"q0_r0": "capital_hub"},
		},
	}, true)
	SpaceManager.register_unit_class_from_data({
		"class_id": DEBUG_HABITAT_STATION_CLASS_ID,
		"display_name": "Debug Habitat Station",
		"unit_kind": SpaceUnitClass.UNIT_KIND_STATION,
		"category": SpaceUnitClass.CATEGORY_STATION,
		"max_hull_points": 1600.0,
		"command_tags": ["station", "habitat"],
		"upkeep_component": {"monthly_costs": {"energy": 3.0}},
		"colony_host_component": {
			"habitat_kind": "orbital_habitat",
			"base_habitability_points": 72,
			"building_grid_radius": 1,
			"starter_buildings": ["capital_hub"],
			"starter_building_slots": {"q0_r0": "capital_hub"},
		},
	}, true)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
