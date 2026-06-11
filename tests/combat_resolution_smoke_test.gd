extends Node

const EMPIRE_A := "empire_combat_a"
const EMPIRE_B := "empire_combat_b"
const SYSTEM_ID := "sys_combat"
const GALAXY_SEED := 7
const MAX_BATTLE_DAYS := 300


func _ready() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Combat resolution smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _bootstrap() -> void:
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()
	SpaceManager.reset_runtime_state(true)
	EconomyManager.bootstrap(PackedStringArray([EMPIRE_A, EMPIRE_B]), {
		"generated_seed": GALAXY_SEED,
		"systems": [],
	})
	SpaceManager.bootstrap_empires(PackedStringArray([EMPIRE_A, EMPIRE_B]))


func _run(failures: Array[String]) -> void:
	_test_peaceful_mode(failures)
	_test_passive_units_do_not_engage(failures)
	_test_two_versus_one_resolution(failures)
	_test_civilian_is_engaged_and_flees(failures)
	_test_manual_shockwave_ability(failures)
	_cleanup()


func _test_peaceful_mode(failures: Array[String]) -> void:
	_bootstrap()
	SpaceManager.set_hostility_mode(SpaceManager.HOSTILITY_PEACEFUL)
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {"unit_id": "peace_a", "local_position": Vector3.ZERO})
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_B, SYSTEM_ID, {"unit_id": "peace_b", "local_position": Vector3(5.0, 0.0, 0.0)})
	for _day in range(3):
		SpaceManager._on_sim_day_tick({})
	_expect(SpaceManager.get_active_battle_ids().is_empty(), "peaceful mode should prevent battles", failures)


func _test_passive_units_do_not_engage(failures: Array[String]) -> void:
	_bootstrap()
	var unit_a := SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {"unit_id": "passive_a", "local_position": Vector3.ZERO})
	var unit_b := SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_B, SYSTEM_ID, {"unit_id": "passive_b", "local_position": Vector3(5.0, 0.0, 0.0)})
	_expect(unit_a != null and unit_a.is_aggressive(), "combat units should default to aggressive stance", failures)
	SpaceManager.set_unit_stance("passive_a", SpaceUnitRuntime.STANCE_PASSIVE)
	SpaceManager.set_unit_stance("passive_b", SpaceUnitRuntime.STANCE_PASSIVE)
	for _day in range(3):
		SpaceManager._on_sim_day_tick({})
	_expect(SpaceManager.get_active_battle_ids().is_empty(), "passive units should not initiate battles", failures)
	_expect(unit_b != null and unit_b.current_hull_points == unit_b.max_hull_points, "no shots should be fired between passive units", failures)


func _test_two_versus_one_resolution(failures: Array[String]) -> void:
	_bootstrap()
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {"unit_id": "corvette_a1", "local_position": Vector3.ZERO})
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {"unit_id": "corvette_a2", "local_position": Vector3(2.0, 0.0, 0.0)})
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_B, SYSTEM_ID, {"unit_id": "corvette_b1", "local_position": Vector3(8.0, 0.0, 0.0)})

	SpaceManager._on_sim_day_tick({})
	var battle_id := SpaceManager.get_battle_id_for_system(SYSTEM_ID)
	_expect(not battle_id.is_empty(), "aggressive hostiles in range should open a battle", failures)
	var unit_b := SpaceManager.get_unit("corvette_b1")
	_expect(unit_b != null and unit_b.battle_id == battle_id, "engaged target should join the battle", failures)

	var days_elapsed := 1
	while days_elapsed < MAX_BATTLE_DAYS and SpaceManager.get_unit("corvette_b1") != null:
		SpaceManager._on_sim_day_tick({})
		days_elapsed += 1

	_expect(SpaceManager.get_unit("corvette_b1") == null, "outnumbered corvette should be destroyed within %d days" % MAX_BATTLE_DAYS, failures)
	var survivors := 0
	for unit_id in ["corvette_a1", "corvette_a2"]:
		if SpaceManager.get_unit(unit_id) != null:
			survivors += 1
	_expect(survivors >= 1, "attacking side should keep at least one survivor", failures)

	for _day in range(3):
		SpaceManager._on_sim_day_tick({})
	_expect(SpaceManager.get_active_battle_ids().is_empty(), "battle should end after one side is destroyed", failures)
	for unit_id in ["corvette_a1", "corvette_a2"]:
		var unit := SpaceManager.get_unit(unit_id)
		if unit != null:
			_expect(unit.battle_id.is_empty(), "survivors should leave the battle: %s" % unit_id, failures)


func _test_civilian_is_engaged_and_flees(failures: Array[String]) -> void:
	_bootstrap()
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {"unit_id": "hunter_a", "local_position": Vector3.ZERO})
	var science := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, EMPIRE_B, SYSTEM_ID, {"unit_id": "science_b", "local_position": Vector3(5.0, 0.0, 0.0)})
	_expect(science != null and not science.is_aggressive(), "civilian ships should default to passive stance", failures)

	SpaceManager._on_sim_day_tick({})
	science = SpaceManager.get_unit("science_b")
	_expect(science != null and science.is_in_battle(), "civilian within engage radius should be pulled into the battle", failures)
	if science != null:
		var distance_after_first_day := science.local_position.distance_to(SpaceManager.get_unit("hunter_a").local_position)
		_expect(distance_after_first_day > 5.0, "unarmed civilian should flee away from the attacker", failures)

	# The science ship's drive matches the hunter's combat speed, so fleeing
	# outruns the pursuit (the hunter holds at weapon range) and the battle
	# ends via disengage once the gap exceeds the contact radius.
	for _day in range(30):
		SpaceManager._on_sim_day_tick({})
	science = SpaceManager.get_unit("science_b")
	_expect(science != null, "fast civilian should escape the pursuit alive", failures)
	if science != null:
		_expect(not science.is_in_battle(), "escaped civilian should leave the battle", failures)
	_expect(SpaceManager.get_active_battle_ids().is_empty(), "battle should end via disengage after the civilian escapes", failures)


func _test_manual_shockwave_ability(failures: Array[String]) -> void:
	_bootstrap()
	_expect(SpaceManager.unlock_ship_component(EMPIRE_A, "shockwave_emitter"), "shockwave emitter should unlock", failures)
	var design_id := SpaceManager.create_ship_design(EMPIRE_A, SpaceManager.CORVETTE_CLASS_ID, {
		"weapon_1": "basic_laser",
		"utility_1": "shockwave_emitter",
		"drive": "basic_drive",
	}, {"display_name": "Shockwave Corvette"})
	_expect(not design_id.is_empty(), "shockwave design should validate: %s" % ", ".join(SpaceManager.get_last_ship_design_errors()), failures)
	if design_id.is_empty():
		return

	var caster := SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {
		"unit_id": "caster_a",
		"design_id": design_id,
		"local_position": Vector3.ZERO,
		"stance": SpaceUnitRuntime.STANCE_PASSIVE,
	})
	var victim := SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_B, SYSTEM_ID, {
		"unit_id": "victim_b",
		"local_position": Vector3(5.0, 0.0, 0.0),
		"stance": SpaceUnitRuntime.STANCE_PASSIVE,
	})
	_expect(caster != null and victim != null, "shockwave scenario units should spawn", failures)
	if caster == null or victim == null:
		return

	_expect(not SpaceManager.queue_unit_ability_command("caster_a", "weapon_1"), "weapon slots should not accept manual ability commands", failures)
	_expect(SpaceManager.queue_unit_ability_command("caster_a", "utility_1"), "manual ability command should queue", failures)
	_expect(not SpaceManager.queue_unit_ability_command("caster_a", "utility_1"), "duplicate pending ability command should be rejected", failures)

	var victim_shield_before := victim.current_shield_points
	SpaceManager._on_sim_day_tick({})

	victim = SpaceManager.get_unit("victim_b")
	_expect(victim != null, "shockwave should not outright destroy the victim", failures)
	if victim != null:
		# Shockwave params: 25 damage vs 60 shield -> 35 shield left, 2 stun days.
		_expect(victim.current_shield_points < victim_shield_before, "shockwave should damage the victim's shields, got %d -> %d" % [victim_shield_before, victim.current_shield_points], failures)
		_expect(victim.is_stunned(), "shockwave should stun the victim", failures)
		_expect(victim.is_in_battle(), "shockwave should pull the victim into a battle", failures)
	_expect(caster.ability_cooldowns.has("utility_1"), "shockwave should go on cooldown after firing", failures)
	_expect(not SpaceManager.queue_unit_ability_command("caster_a", "utility_1"), "ability on cooldown should reject new commands", failures)

	var ability_event_found := false
	var battle_id := SpaceManager.get_battle_id_for_system(SYSTEM_ID)
	for event in SpaceManager.get_battle_event_log(battle_id):
		if str(event.get("type", "")) == "ability" and str(event.get("effect_id", "")) == "shockwave":
			ability_event_found = true
			break
	_expect(ability_event_found, "ability event should be recorded in the battle log", failures)


func _cleanup() -> void:
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
