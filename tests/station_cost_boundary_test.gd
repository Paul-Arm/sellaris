extends Node

func _ready() -> void:
	SimClock.pause_sim()
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()
	EconomyManager.bootstrap(PackedStringArray(["owner", "other"]), {"generated_seed": 7, "systems": []})
	var runtime := GameSceneRuntimeSystem.new()
	var state := GameSceneState.new()
	state.active_empire_id = "owner"
	runtime.setup(state, null, null, null, null)
	var builder := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "owner", "alpha", {})
	var foreign := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "other", "alpha", {})
	assert(builder != null and foreign != null)
	var body := {"body_id": "planet_01", "body_type": "planet", "body_name": "Alpha I", "local_position": Vector3(18, 0, 0), "size": 2.0, "buildable_component": {"body_type": "planet", "allowed_build_tags": ["orbital_station"], "max_active_projects": 1}}
	var costs := SpaceManager.get_unit_class(SpaceManager.BASIC_STATION_CLASS_ID).get_build_costs()
	assert(not costs.is_empty())
	var before: Dictionary = {}
	for cost: ResourceAmountDef in costs:
		before[cost.resource_id] = EconomyManager.get_amount("owner", cost.resource_id)
	assert(not runtime.request_build_order_for_body(foreign.unit_id, "alpha", body, SpaceManager.BASIC_STATION_CLASS_ID), "Foreign builders cannot be commanded")
	assert(runtime.request_build_order_for_body(builder.unit_id, "alpha", body, SpaceManager.BASIC_STATION_CLASS_ID))
	for cost: ResourceAmountDef in costs:
		assert(int(before[cost.resource_id]) - EconomyManager.get_amount("owner", cost.resource_id) == cost.milliunits, "Player station builds must debit exactly the defined cost")
	assert(not runtime.request_build_order_for_body(builder.unit_id, "alpha", body, SpaceManager.BASIC_STATION_CLASS_ID), "Duplicate order is rejected")
	for cost: ResourceAmountDef in costs:
		assert(int(before[cost.resource_id]) - EconomyManager.get_amount("owner", cost.resource_id) == cost.milliunits, "Rejected orders must not debit again")
	var poor := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "owner", "alpha", {})
	for cost: ResourceAmountDef in costs:
		EconomyManager.commit_cost("owner", [{"resource_id": cost.resource_id, "milliunits": EconomyManager.get_amount("owner", cost.resource_id)}])
	body["body_id"] = "planet_02"
	assert(not runtime.request_build_order_for_body(poor.unit_id, "alpha", body, SpaceManager.BASIC_STATION_CLASS_ID), "Insufficient funds must reject construction")
	assert(not SpaceManager.is_unit_constructing(poor.unit_id))
	runtime.teardown()
	runtime.free()
	print("PASS: station cost boundary, ownership, duplicate rejection and insufficient funds")
	get_tree().quit(0)
