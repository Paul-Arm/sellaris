extends RefCounted
class_name ShipDesignCompiler

const RESOURCE_AMOUNT_DEF_SCRIPT := preload("res://core/economy/ResourceAmountDef.gd")

const DEFAULT_AUTO_ENGAGE_RADIUS := 12.0


static func validate(
	unit_class: SpaceUnitClass,
	slot_assignments: Dictionary,
	component_catalog: ShipComponentCatalog,
	unlocked_component_ids: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	if unit_class == null:
		errors.append("unknown_unit_class")
		return errors
	if component_catalog == null:
		errors.append("missing_component_catalog")
		return errors

	var slots_by_id: Dictionary = {}
	for slot in unit_class.get_design_slots():
		slots_by_id[str(slot.get("slot_id", ""))] = slot

	for slot_id_variant in slot_assignments.keys():
		var slot_id := str(slot_id_variant)
		var component_id := str(slot_assignments.get(slot_id_variant, "")).strip_edges()
		if component_id.is_empty():
			continue
		if not slots_by_id.has(slot_id):
			errors.append("unknown_slot:%s" % slot_id)
			continue
		var slot: Dictionary = slots_by_id[slot_id]
		var definition := component_catalog.get_component(component_id)
		if definition == null:
			errors.append("unknown_component:%s" % component_id)
			continue
		if not definition.fits_slot(str(slot.get("slot_kind", "")), str(slot.get("slot_size", ShipComponentDefinition.SLOT_SIZE_MEDIUM))):
			errors.append("slot_mismatch:%s:%s" % [slot_id, component_id])
		if not definition.allows_unit_kind(unit_class.unit_kind):
			errors.append("unit_kind_not_allowed:%s" % component_id)
		if definition.requires_mobility and not unit_class.has_mobility():
			errors.append("requires_mobility:%s" % component_id)
		if not unlocked_component_ids.has(component_id):
			errors.append("component_locked:%s" % component_id)

	for slot_id_variant in slots_by_id.keys():
		var slot: Dictionary = slots_by_id[slot_id_variant]
		if not bool(slot.get("required", false)):
			continue
		var assigned := str(slot_assignments.get(str(slot_id_variant), "")).strip_edges()
		if assigned.is_empty():
			errors.append("required_slot_empty:%s" % str(slot_id_variant))

	return errors


static func compile(
	unit_class: SpaceUnitClass,
	slot_assignments: Dictionary,
	component_catalog: ShipComponentCatalog
) -> Dictionary:
	var stats := {
		"max_hull_points": 1,
		"max_shield_points": 0,
		"shield_regen_per_day": 0,
		"armor_points": 0,
		"evasion_bp": 0,
		"cruise_speed": -1.0,
		"combat_speed": -1.0,
		"auto_engage_radius": DEFAULT_AUTO_ENGAGE_RADIUS,
		"sensor_range_add": 0.0,
		"weapons": [],
		"abilities": [],
		"build_costs": [],
		"monthly_upkeep": [],
		"build_time_days": 0,
	}
	if unit_class == null or component_catalog == null:
		return stats

	unit_class.ensure_defaults()
	var hull_points := unit_class.max_hull_points
	var shield_points := 0
	var shield_regen := 0
	var armor_points := 0
	var evasion_bp := 0
	var cruise_speed := -1.0
	var combat_speed := -1.0
	var auto_engage_radius := DEFAULT_AUTO_ENGAGE_RADIUS
	var sensor_range_add := 0.0
	var weapons: Array[Dictionary] = []
	var abilities: Array[Dictionary] = []
	var build_time_days := unit_class.get_build_time_days()
	var build_cost_entries: Array = RESOURCE_AMOUNT_DEF_SCRIPT.to_dict_array(unit_class.get_build_costs())
	var upkeep_entries: Array = RESOURCE_AMOUNT_DEF_SCRIPT.to_dict_array(unit_class.get_monthly_upkeep())

	var slot_ids: Array[String] = []
	for slot in unit_class.get_design_slots():
		slot_ids.append(str(slot.get("slot_id", "")))

	for slot_id in slot_ids:
		var component_id := str(slot_assignments.get(slot_id, "")).strip_edges()
		if component_id.is_empty():
			continue
		var definition := component_catalog.get_component(component_id)
		if definition == null:
			continue

		hull_points += definition.get_stat_int("hull_add")
		shield_points += definition.get_stat_int("shield_add")
		shield_regen += definition.get_stat_int("shield_regen_per_day")
		armor_points += definition.get_stat_int("armor_add")
		evasion_bp += definition.get_stat_int("evasion_bp")
		auto_engage_radius += definition.get_stat_float("auto_engage_radius_add")
		sensor_range_add += definition.get_stat_float("sensor_range_add")
		if definition.stats.has("cruise_speed"):
			cruise_speed = maxf(cruise_speed, definition.get_stat_float("cruise_speed"))
		if definition.stats.has("combat_speed"):
			combat_speed = maxf(combat_speed, definition.get_stat_float("combat_speed"))

		if definition.is_weapon():
			var weapon_entry := definition.weapon.duplicate(true)
			weapon_entry["slot_id"] = slot_id
			weapon_entry["component_id"] = component_id
			weapons.append(weapon_entry)
		if definition.has_ability():
			var ability_entry := definition.ability.duplicate(true)
			ability_entry["slot_id"] = slot_id
			ability_entry["component_id"] = component_id
			abilities.append(ability_entry)

		build_time_days += definition.build_time_days_add
		build_cost_entries.append_array(definition.build_cost)
		upkeep_entries.append_array(definition.monthly_upkeep)

	stats["max_hull_points"] = maxi(hull_points, 1)
	stats["max_shield_points"] = maxi(shield_points, 0)
	stats["shield_regen_per_day"] = maxi(shield_regen, 0)
	stats["armor_points"] = maxi(armor_points, 0)
	stats["evasion_bp"] = clampi(evasion_bp, 0, 9500)
	stats["cruise_speed"] = cruise_speed
	stats["combat_speed"] = combat_speed
	stats["auto_engage_radius"] = maxf(auto_engage_radius, 0.0)
	stats["sensor_range_add"] = maxf(sensor_range_add, 0.0)
	stats["weapons"] = weapons
	stats["abilities"] = abilities
	stats["build_costs"] = RESOURCE_AMOUNT_DEF_SCRIPT.to_dict_array(RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(build_cost_entries))
	stats["monthly_upkeep"] = RESOURCE_AMOUNT_DEF_SCRIPT.to_dict_array(RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(upkeep_entries))
	stats["build_time_days"] = maxi(build_time_days, 1) if unit_class.is_buildable() else maxi(build_time_days, 0)
	return stats
