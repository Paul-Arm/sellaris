extends RefCounted
class_name CombatSystem

## Deterministic day-tick combat resolver (COMBAT_DESIGN.md Phase B).
## All combat decisions use integer math, stable string-hash rolls, and
## unit-id-sorted iteration so the same scenario always produces the same
## event log. Positions are quantized to milli-units before any range check.

const EVENT_BATTLE_STARTED := "battle_started"
const EVENT_BATTLE_ENDED := "battle_ended"
const EVENT_SHOT := "shot"
const EVENT_KILL := "kill"
const EVENT_ABILITY := "ability"

const EFFECT_SHOCKWAVE := "shockwave"

const DISENGAGE_RADIUS_FACTOR := 1.5
const MAX_EVENT_LOG_ENTRIES := 4000
const HIT_CHANCE_MIN_BP := 0
const HIT_CHANCE_MAX_BP := 10000

var _space_manager = null
var _next_battle_id: int = 1
var _battles_by_id: Dictionary = {}
var _battle_id_by_system_id: Dictionary = {}
var _last_tick_events: Array[Dictionary] = []


func setup(space_manager) -> void:
	_space_manager = space_manager


func reset_state() -> void:
	_next_battle_id = 1
	_battles_by_id.clear()
	_battle_id_by_system_id.clear()
	_last_tick_events.clear()


func get_battle(battle_id: String) -> Dictionary:
	var battle: Dictionary = _battles_by_id.get(battle_id, {})
	return battle.duplicate(true)


func get_active_battle_ids() -> Array[String]:
	var result: Array[String] = []
	for battle_id_variant in _battles_by_id.keys():
		result.append(str(battle_id_variant))
	result.sort()
	return result


func get_battle_id_for_system(system_id: String) -> String:
	return str(_battle_id_by_system_id.get(system_id, ""))


func get_battle_event_log(battle_id: String) -> Array[Dictionary]:
	var battle: Dictionary = _battles_by_id.get(battle_id, {})
	var result: Array[Dictionary] = []
	for event_variant in battle.get("event_log", []):
		if event_variant is Dictionary:
			result.append((event_variant as Dictionary).duplicate(true))
	return result


func get_last_tick_events() -> Array[Dictionary]:
	return _last_tick_events.duplicate(true)


func handle_unit_removed(unit: SpaceUnitRuntime) -> void:
	if unit == null or unit.battle_id.is_empty():
		return
	var battle: Dictionary = _battles_by_id.get(unit.battle_id, {})
	if battle.is_empty():
		unit.battle_id = ""
		return
	var members: Dictionary = battle.get("member_unit_ids", {})
	members.erase(unit.unit_id)
	battle["member_unit_ids"] = members
	_battles_by_id[unit.battle_id] = battle
	unit.battle_id = ""


# --- Tick entry point ---

func tick(day_serial: int) -> Array[Dictionary]:
	_last_tick_events = []
	if _space_manager == null:
		return _last_tick_events

	_tick_cooldowns_and_stun()
	_process_pending_ability_commands(day_serial)
	_detect_engagements(day_serial)

	for battle_id in get_active_battle_ids():
		_resolve_battle_round(battle_id, day_serial)

	for battle_id in get_active_battle_ids():
		_check_battle_end(battle_id, day_serial)

	return _last_tick_events


func _tick_cooldowns_and_stun() -> void:
	for unit_id in _get_sorted_unit_ids():
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit == null:
			continue
		for slot_id_variant in unit.weapon_cooldowns.keys().duplicate():
			var remaining := int(unit.weapon_cooldowns.get(slot_id_variant, 0)) - 1
			if remaining <= 0:
				unit.weapon_cooldowns.erase(slot_id_variant)
			else:
				unit.weapon_cooldowns[slot_id_variant] = remaining
		for slot_id_variant in unit.ability_cooldowns.keys().duplicate():
			var remaining := int(unit.ability_cooldowns.get(slot_id_variant, 0)) - 1
			if remaining <= 0:
				unit.ability_cooldowns.erase(slot_id_variant)
			else:
				unit.ability_cooldowns[slot_id_variant] = remaining
		if unit.stunned_days_remaining > 0:
			unit.stunned_days_remaining -= 1


# --- Manual abilities ---

func _process_pending_ability_commands(day_serial: int) -> void:
	for unit_id in _get_sorted_unit_ids():
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit == null or unit.pending_ability_commands.is_empty():
			continue
		var commands := unit.pending_ability_commands
		unit.pending_ability_commands = []
		for command in commands:
			_execute_ability_command(unit, command, day_serial)


func _execute_ability_command(unit: SpaceUnitRuntime, command: Dictionary, day_serial: int) -> void:
	if unit.current_hull_points <= 0 or unit.is_stunned():
		return
	var slot_id := str(command.get("slot_id", ""))
	if unit.ability_cooldowns.has(slot_id):
		return
	var ability := _find_ability(unit, slot_id)
	if ability.is_empty():
		return

	match str(ability.get("effect_id", "")):
		EFFECT_SHOCKWAVE:
			_execute_shockwave(unit, ability, day_serial)
		_:
			return
	unit.ability_cooldowns[slot_id] = maxi(int(ability.get("cooldown_days", 1)), 1)
	unit.command_revision += 1


func _execute_shockwave(unit: SpaceUnitRuntime, ability: Dictionary, day_serial: int) -> void:
	var params_variant: Variant = ability.get("params", {})
	var params: Dictionary = params_variant if params_variant is Dictionary else {}
	var damage := maxi(int(params.get("damage", 0)), 0)
	var stun_days := maxi(int(params.get("stun_days", 0)), 0)
	var radius_q := _quantize(maxf(float(ability.get("radius", 0.0)), 0.0))
	var radius_q2 := radius_q * radius_q

	var hit_unit_ids: Array[String] = []
	for other_id in _get_sorted_unit_ids_in_system(unit.current_system_id):
		if other_id == unit.unit_id:
			continue
		var other: SpaceUnitRuntime = _space_manager.get_unit(other_id)
		if other == null or other.current_hull_points <= 0:
			continue
		if not _space_manager.are_empires_hostile(unit.owner_empire_id, other.owner_empire_id):
			continue
		if _distance2_q(unit, other) > radius_q2:
			continue
		_apply_damage(other, damage, 10000, 0)
		if stun_days > 0:
			other.stunned_days_remaining = maxi(other.stunned_days_remaining, stun_days)
		other.command_revision += 1
		hit_unit_ids.append(other_id)

	if not hit_unit_ids.is_empty():
		var battle_id := _ensure_battle(unit.current_system_id, day_serial)
		_add_unit_to_battle(battle_id, unit, day_serial)
		for hit_unit_id in hit_unit_ids:
			var hit_unit: SpaceUnitRuntime = _space_manager.get_unit(hit_unit_id)
			if hit_unit != null:
				_add_unit_to_battle(battle_id, hit_unit, day_serial)

	_record_event({
		"type": EVENT_ABILITY,
		"day_serial": day_serial,
		"battle_id": unit.battle_id,
		"system_id": unit.current_system_id,
		"unit_id": unit.unit_id,
		"effect_id": EFFECT_SHOCKWAVE,
		"radius": float(ability.get("radius", 0.0)),
		"target_unit_ids": hit_unit_ids,
		"position": SpaceUnitRuntime._vector3_to_dict(unit.local_position),
	}, unit.battle_id)


func _find_ability(unit: SpaceUnitRuntime, slot_id: String) -> Dictionary:
	if unit.design_id.is_empty():
		return {}
	var stats: Dictionary = _space_manager.get_compiled_ship_design_stats(unit.design_id)
	for ability_variant in stats.get("abilities", []):
		if ability_variant is not Dictionary:
			continue
		var ability: Dictionary = ability_variant
		if str(ability.get("slot_id", "")) == slot_id:
			return ability
	return {}


# --- Engagement detection ---

func _detect_engagements(day_serial: int) -> void:
	for system_id in _get_sorted_system_ids():
		var unit_ids := _get_sorted_unit_ids_in_system(system_id)
		if unit_ids.size() < 2:
			continue
		for unit_id in unit_ids:
			var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
			if unit == null or unit.current_hull_points <= 0 or unit.is_stunned():
				continue
			if not unit.is_aggressive() or not _has_weapons(unit):
				continue
			var engage_q := _quantize(unit.auto_engage_radius)
			var engage_q2 := engage_q * engage_q
			for other_id in unit_ids:
				if other_id == unit_id:
					continue
				var other: SpaceUnitRuntime = _space_manager.get_unit(other_id)
				if other == null or other.current_hull_points <= 0:
					continue
				if not _space_manager.are_empires_hostile(unit.owner_empire_id, other.owner_empire_id):
					continue
				if _distance2_q(unit, other) > engage_q2:
					continue
				var battle_id := _ensure_battle(system_id, day_serial)
				_add_unit_to_battle(battle_id, unit, day_serial)
				_add_unit_to_battle(battle_id, other, day_serial)


# --- Battle round resolution ---

func _resolve_battle_round(battle_id: String, day_serial: int) -> void:
	var battle: Dictionary = _battles_by_id.get(battle_id, {})
	if battle.is_empty():
		return
	# Hit rolls key off the battle-local round counter instead of the global
	# day serial so combat stays deterministic regardless of SimClock state.
	var round_index := int(battle.get("round_counter", 0)) + 1
	battle["round_counter"] = round_index
	_battles_by_id[battle_id] = battle
	var member_ids := _get_sorted_battle_member_ids(battle)
	var target_by_unit_id: Dictionary = {}
	for unit_id in member_ids:
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit == null or unit.current_hull_points <= 0:
			continue
		var target_id := _select_target(unit, member_ids)
		if not target_id.is_empty():
			target_by_unit_id[unit_id] = target_id

	var hit_this_round: Dictionary = {}
	var any_contact := false

	# Combat movement: close to weapon range, or flee when passive and unarmed.
	for unit_id in member_ids:
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit == null or unit.current_hull_points <= 0 or unit.is_stunned():
			continue
		if not unit.is_mobile() or not unit.fleet_id.is_empty() or unit.has_active_movement():
			continue
		if _has_weapons(unit):
			if unit.is_aggressive() and target_by_unit_id.has(unit_id):
				_move_toward_target(unit, target_by_unit_id[unit_id], day_serial)
		else:
			_flee_from_nearest_hostile(unit, member_ids, day_serial)

	# Weapon fire, in deterministic member order.
	for unit_id in member_ids:
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit == null or unit.current_hull_points <= 0 or unit.is_stunned():
			continue
		var target_id := str(target_by_unit_id.get(unit_id, ""))
		if target_id.is_empty():
			continue
		var target: SpaceUnitRuntime = _space_manager.get_unit(target_id)
		if target == null or target.current_hull_points <= 0:
			continue
		var fired := _fire_weapons(unit, target, battle_id, round_index, day_serial, hit_this_round)
		any_contact = any_contact or fired

	# Shield regeneration for members that were not hit this round.
	for unit_id in member_ids:
		if hit_this_round.has(unit_id):
			continue
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit == null or unit.current_hull_points <= 0 or unit.max_shield_points <= 0:
			continue
		var regen := _get_shield_regen(unit)
		if regen > 0 and unit.current_shield_points < unit.max_shield_points:
			unit.current_shield_points = mini(unit.current_shield_points + regen, unit.max_shield_points)
			unit.command_revision += 1

	# Deaths.
	for unit_id in member_ids:
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit == null or unit.current_hull_points > 0:
			continue
		_record_event({
			"type": EVENT_KILL,
			"day_serial": day_serial,
			"battle_id": battle_id,
			"system_id": unit.current_system_id,
			"unit_id": unit_id,
			"class_id": unit.class_id,
			"display_name": unit.display_name,
			"owner_empire_id": unit.owner_empire_id,
			"position": SpaceUnitRuntime._vector3_to_dict(unit.local_position),
		}, battle_id)
		handle_unit_removed(unit)
		_space_manager.remove_unit(unit_id)

	if any_contact:
		battle = _battles_by_id.get(battle_id, {})
		if not battle.is_empty():
			battle["last_contact_day_serial"] = day_serial
			_battles_by_id[battle_id] = battle


func _select_target(unit: SpaceUnitRuntime, member_ids: Array[String]) -> String:
	var best_target_id := ""
	var best_distance2 := 0
	for other_id in member_ids:
		if other_id == unit.unit_id:
			continue
		var other: SpaceUnitRuntime = _space_manager.get_unit(other_id)
		if other == null or other.current_hull_points <= 0:
			continue
		if other.current_system_id != unit.current_system_id:
			continue
		if not _space_manager.are_empires_hostile(unit.owner_empire_id, other.owner_empire_id):
			continue
		var distance2 := _distance2_q(unit, other)
		if best_target_id.is_empty() or distance2 < best_distance2:
			best_target_id = other_id
			best_distance2 = distance2
	return best_target_id


func _move_toward_target(unit: SpaceUnitRuntime, target_id: String, day_serial: int) -> void:
	var target: SpaceUnitRuntime = _space_manager.get_unit(target_id)
	if target == null:
		return
	var stop_range := _get_min_weapon_range(unit) * 0.9
	var offset: Vector3 = target.local_position - unit.local_position
	var distance := offset.length()
	if distance <= stop_range or distance <= 0.001:
		return
	var speed := _get_combat_speed(unit)
	if speed <= 0.0:
		return
	var step := minf(speed, distance - stop_range)
	# Phase B keeps combat movement as a per-day reposition; Phase C interpolates
	# visuals from the combat event stream instead of movement_state.
	unit.previous_local_position = unit.local_position
	unit.local_position += offset.normalized() * step
	unit.target_local_position = unit.local_position
	unit.last_movement_day_serial = day_serial
	unit.command_revision += 1


func _flee_from_nearest_hostile(unit: SpaceUnitRuntime, member_ids: Array[String], day_serial: int) -> void:
	var threat_id := _select_target(unit, member_ids)
	if threat_id.is_empty():
		return
	var threat: SpaceUnitRuntime = _space_manager.get_unit(threat_id)
	if threat == null:
		return
	var speed := maxf(_get_combat_speed(unit), _space_manager.get_unit_in_system_speed(unit))
	if speed <= 0.0:
		return
	var away: Vector3 = unit.local_position - threat.local_position
	if away.length() <= 0.001:
		away = Vector3(1.0, 0.0, 0.0)
	unit.previous_local_position = unit.local_position
	unit.local_position += away.normalized() * speed
	unit.target_local_position = unit.local_position
	unit.last_movement_day_serial = day_serial
	unit.command_revision += 1


func _fire_weapons(
	attacker: SpaceUnitRuntime,
	target: SpaceUnitRuntime,
	battle_id: String,
	round_index: int,
	day_serial: int,
	hit_this_round: Dictionary
) -> bool:
	var weapons := _get_weapons(attacker)
	if weapons.is_empty():
		return false
	var fired := false
	for weapon in weapons:
		var slot_id := str(weapon.get("slot_id", ""))
		if attacker.weapon_cooldowns.has(slot_id):
			continue
		if target.current_hull_points <= 0:
			break
		var range_q := _quantize(float(weapon.get("range", 0.0)))
		if _distance2_q(attacker, target) > range_q * range_q:
			continue

		fired = true
		attacker.weapon_cooldowns[slot_id] = maxi(int(weapon.get("cooldown_days", 1)), 1)
		var hit_chance_bp := clampi(int(weapon.get("accuracy_bp", 10000)) - target.evasion_bp, HIT_CHANCE_MIN_BP, HIT_CHANCE_MAX_BP)
		var roll := _stable_roll_bp(battle_id, round_index, attacker.unit_id, slot_id)
		var is_hit := roll < hit_chance_bp
		var damage_result := {"shield_damage": 0, "hull_damage": 0}
		if is_hit:
			damage_result = _apply_damage(
				target,
				maxi(int(weapon.get("damage", 0)), 0),
				int(weapon.get("shield_damage_bp", 10000)),
				int(weapon.get("armor_penetration_bp", 0))
			)
			hit_this_round[target.unit_id] = true
			target.command_revision += 1
		_record_event({
			"type": EVENT_SHOT,
			"day_serial": day_serial,
			"battle_id": battle_id,
			"system_id": attacker.current_system_id,
			"attacker_unit_id": attacker.unit_id,
			"target_unit_id": target.unit_id,
			"slot_id": slot_id,
			"component_id": str(weapon.get("component_id", "")),
			"hit": is_hit,
			"shield_damage": int(damage_result.get("shield_damage", 0)),
			"hull_damage": int(damage_result.get("hull_damage", 0)),
			"target_shield_points": target.current_shield_points,
			"target_hull_points": target.current_hull_points,
			"attacker_position": SpaceUnitRuntime._vector3_to_dict(attacker.local_position),
			"target_position": SpaceUnitRuntime._vector3_to_dict(target.local_position),
		}, battle_id)
	return fired


func _apply_damage(target: SpaceUnitRuntime, damage: int, shield_damage_bp: int, armor_penetration_bp: int) -> Dictionary:
	var shield_damage := 0
	var hull_facing_damage := damage

	if target.current_shield_points > 0:
		# Damage is scaled against shields; overflow converts back to base damage.
		var damage_vs_shield := damage * maxi(shield_damage_bp, 0) / 10000
		if damage_vs_shield <= target.current_shield_points:
			shield_damage = damage_vs_shield
			target.current_shield_points -= damage_vs_shield
			hull_facing_damage = 0
		else:
			shield_damage = target.current_shield_points
			var overflow_vs_shield := damage_vs_shield - target.current_shield_points
			target.current_shield_points = 0
			hull_facing_damage = overflow_vs_shield * 10000 / maxi(shield_damage_bp, 1)

	var hull_damage := 0
	if hull_facing_damage > 0:
		var effective_armor := target.armor_points * (10000 - clampi(armor_penetration_bp, 0, 10000)) / 10000
		hull_damage = maxi(hull_facing_damage - effective_armor, 1)
		target.current_hull_points = maxi(target.current_hull_points - hull_damage, 0)

	return {"shield_damage": shield_damage, "hull_damage": hull_damage}


# --- Battle lifecycle ---

func _ensure_battle(system_id: String, day_serial: int) -> String:
	var existing_battle_id := str(_battle_id_by_system_id.get(system_id, ""))
	if not existing_battle_id.is_empty() and _battles_by_id.has(existing_battle_id):
		return existing_battle_id

	var battle_id := "battle_%04d" % _next_battle_id
	_next_battle_id += 1
	_battles_by_id[battle_id] = {
		"battle_id": battle_id,
		"system_id": system_id,
		"member_unit_ids": {},
		"started_day_serial": day_serial,
		"last_contact_day_serial": day_serial,
		"event_log": [],
	}
	_battle_id_by_system_id[system_id] = battle_id
	_record_event({
		"type": EVENT_BATTLE_STARTED,
		"day_serial": day_serial,
		"battle_id": battle_id,
		"system_id": system_id,
	}, battle_id)
	return battle_id


func _add_unit_to_battle(battle_id: String, unit: SpaceUnitRuntime, day_serial: int) -> void:
	var battle: Dictionary = _battles_by_id.get(battle_id, {})
	if battle.is_empty() or unit == null:
		return
	var members: Dictionary = battle.get("member_unit_ids", {})
	if members.has(unit.unit_id):
		return
	members[unit.unit_id] = true
	battle["member_unit_ids"] = members
	battle["last_contact_day_serial"] = day_serial
	_battles_by_id[battle_id] = battle
	unit.battle_id = battle_id
	unit.command_revision += 1


func _check_battle_end(battle_id: String, day_serial: int) -> void:
	var battle: Dictionary = _battles_by_id.get(battle_id, {})
	if battle.is_empty():
		return
	var system_id := str(battle.get("system_id", ""))
	var member_ids := _get_sorted_battle_member_ids(battle)

	# Drop members that died or left the system.
	var live_member_ids: Array[String] = []
	for unit_id in member_ids:
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit == null or unit.current_system_id != system_id or unit.current_hull_points <= 0:
			if unit != null:
				handle_unit_removed(unit)
			continue
		live_member_ids.append(unit_id)

	var should_end := not _has_armed_hostile_contact(live_member_ids)
	if not should_end:
		var members: Dictionary = {}
		for unit_id in live_member_ids:
			members[unit_id] = true
		battle["member_unit_ids"] = members
		_battles_by_id[battle_id] = battle
		return

	for unit_id in live_member_ids:
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit != null:
			unit.battle_id = ""
			unit.command_revision += 1
	_record_event({
		"type": EVENT_BATTLE_ENDED,
		"day_serial": day_serial,
		"battle_id": battle_id,
		"system_id": system_id,
		"survivor_unit_ids": live_member_ids,
	}, battle_id)
	_battles_by_id.erase(battle_id)
	if str(_battle_id_by_system_id.get(system_id, "")) == battle_id:
		_battle_id_by_system_id.erase(system_id)


func _has_armed_hostile_contact(member_ids: Array[String]) -> bool:
	for unit_id in member_ids:
		var unit: SpaceUnitRuntime = _space_manager.get_unit(unit_id)
		if unit == null or unit.current_hull_points <= 0 or not _has_weapons(unit):
			continue
		var contact_q := _quantize(unit.auto_engage_radius * DISENGAGE_RADIUS_FACTOR)
		var contact_q2 := contact_q * contact_q
		for other_id in member_ids:
			if other_id == unit_id:
				continue
			var other: SpaceUnitRuntime = _space_manager.get_unit(other_id)
			if other == null or other.current_hull_points <= 0:
				continue
			if not _space_manager.are_empires_hostile(unit.owner_empire_id, other.owner_empire_id):
				continue
			if _distance2_q(unit, other) <= contact_q2:
				return true
	return false


# --- Design stat helpers ---

func _get_design_stats(unit: SpaceUnitRuntime) -> Dictionary:
	if unit.design_id.is_empty():
		return {}
	return _space_manager.get_compiled_ship_design_stats(unit.design_id)


func _get_weapons(unit: SpaceUnitRuntime) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon_variant in _get_design_stats(unit).get("weapons", []):
		if weapon_variant is Dictionary:
			result.append(weapon_variant)
	return result


func _has_weapons(unit: SpaceUnitRuntime) -> bool:
	return not _get_weapons(unit).is_empty()


func _get_min_weapon_range(unit: SpaceUnitRuntime) -> float:
	var min_range := 0.0
	var found := false
	for weapon in _get_weapons(unit):
		var weapon_range := maxf(float(weapon.get("range", 0.0)), 0.0)
		if not found or weapon_range < min_range:
			min_range = weapon_range
			found = true
	return min_range if found else 0.0


func _get_combat_speed(unit: SpaceUnitRuntime) -> float:
	var stats := _get_design_stats(unit)
	var combat_speed := float(stats.get("combat_speed", -1.0))
	if combat_speed >= 0.0:
		return combat_speed
	return _space_manager.get_unit_in_system_speed(unit)


func _get_shield_regen(unit: SpaceUnitRuntime) -> int:
	return maxi(int(_get_design_stats(unit).get("shield_regen_per_day", 0)), 0)


# --- Determinism helpers ---

static func _quantize(value: float) -> int:
	return int(round(value * 1000.0))


static func _distance2_between(a: Vector3, b: Vector3) -> int:
	var dx := _quantize(a.x) - _quantize(b.x)
	var dy := _quantize(a.y) - _quantize(b.y)
	var dz := _quantize(a.z) - _quantize(b.z)
	return dx * dx + dy * dy + dz * dz


func _distance2_q(a: SpaceUnitRuntime, b: SpaceUnitRuntime) -> int:
	return _distance2_between(a.local_position, b.local_position)


static func _stable_roll_bp(battle_id: String, round_index: int, attacker_unit_id: String, slot_id: String) -> int:
	var key := "%s|%d|%s|%s" % [battle_id, round_index, attacker_unit_id, slot_id]
	return absi(key.hash()) % 10000


func _get_sorted_unit_ids() -> Array[String]:
	var result: Array[String] = []
	for unit_id in _space_manager.get_all_unit_ids():
		result.append(unit_id)
	result.sort()
	return result


func _get_sorted_unit_ids_in_system(system_id: String) -> Array[String]:
	var result: Array[String] = []
	for unit_id in _space_manager.get_unit_ids_in_system(system_id):
		result.append(unit_id)
	result.sort()
	return result


func _get_sorted_system_ids() -> Array[String]:
	var result: Array[String] = []
	for system_id in _space_manager.get_system_ids_with_units():
		result.append(system_id)
	result.sort()
	return result


static func _get_sorted_battle_member_ids(battle: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var members: Dictionary = battle.get("member_unit_ids", {})
	for unit_id_variant in members.keys():
		result.append(str(unit_id_variant))
	result.sort()
	return result


func _record_event(event: Dictionary, battle_id: String) -> void:
	_last_tick_events.append(event)
	if battle_id.is_empty():
		return
	var battle: Dictionary = _battles_by_id.get(battle_id, {})
	if battle.is_empty():
		return
	var event_log: Array = battle.get("event_log", [])
	event_log.append(event.duplicate(true))
	if event_log.size() > MAX_EVENT_LOG_ENTRIES:
		event_log = event_log.slice(event_log.size() - MAX_EVENT_LOG_ENTRIES)
	battle["event_log"] = event_log
	_battles_by_id[battle_id] = battle


# --- Snapshots ---

func build_snapshot() -> Dictionary:
	var battle_snapshots: Array[Dictionary] = []
	for battle_id in get_active_battle_ids():
		var battle: Dictionary = _battles_by_id.get(battle_id, {})
		battle_snapshots.append(battle.duplicate(true))
	return {
		"next_battle_id": _next_battle_id,
		"battles": battle_snapshots,
	}


func load_snapshot(snapshot: Dictionary) -> void:
	reset_state()
	if snapshot.is_empty():
		return
	_next_battle_id = maxi(int(snapshot.get("next_battle_id", 1)), 1)
	for battle_variant in snapshot.get("battles", []):
		if battle_variant is not Dictionary:
			continue
		var battle: Dictionary = (battle_variant as Dictionary).duplicate(true)
		var battle_id := str(battle.get("battle_id", ""))
		var system_id := str(battle.get("system_id", ""))
		if battle_id.is_empty() or system_id.is_empty():
			continue
		_battles_by_id[battle_id] = battle
		_battle_id_by_system_id[system_id] = battle_id
