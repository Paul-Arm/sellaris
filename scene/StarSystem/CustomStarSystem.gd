extends Resource
class_name CustomStarSystem

@export var system_id: String = ""
@export var system_name: String = ""
@export var position: Vector3 = Vector3.ZERO
@export_group("Legacy Quick Setup")
@export var star_color: Color = Color(1.0, 0.95, 0.82, 1.0)
@export var star_class: String = "G"
@export var planet_count_override: int = -1
@export var planet_names: PackedStringArray = PackedStringArray()
@export_range(0, 3, 1) var asteroid_belt_count: int = 0
@export var structure_names: PackedStringArray = PackedStringArray()
@export var ruin_names: PackedStringArray = PackedStringArray()
@export_group("Custom Layout")
@export var stars: Array[CustomSystemStar] = []
@export var orbitals: Array[CustomSystemOrbital] = []
@export_multiline var notes: String = ""


func get_resolved_id(index: int) -> String:
	if not system_id.is_empty():
		return system_id
	return "custom_%03d" % index


func get_resolved_name(index: int) -> String:
	if not system_name.is_empty():
		return system_name
	return "Custom System %03d" % index


func has_custom_layout() -> bool:
	return (
		not stars.is_empty()
		or not orbitals.is_empty()
		or asteroid_belt_count > 0
		or not structure_names.is_empty()
		or not ruin_names.is_empty()
		or not planet_names.is_empty()
		or planet_count_override >= 0
	)


func build_star_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for index in range(stars.size()):
		var star: CustomSystemStar = stars[index]
		if star == null:
			continue
		entries.append(star.to_dictionary(index))

	if not entries.is_empty():
		return entries

	return [{
		"id": "star_00",
		"name": "Primary",
		"index": 0,
		"kind": "star",
		"color_name": "",
		"color": star_color,
		"size_name": "Normal",
		"scale": 1.3,
		"is_primary": true,
		"special_type": "none",
		"star_class": star_class,
		"orbit_radius": 0.0,
		"orbit_angle": 0.0,
		"vertical_offset": 0.0,
	}]


func build_orbital_entries(resolved_system_name: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for index in range(orbitals.size()):
		var orbital: CustomSystemOrbital = orbitals[index]
		if orbital == null:
			continue
		entries.append(orbital.to_dictionary(index))

	var has_planets := _has_orbital_type(entries, CustomSystemOrbital.TYPE_PLANET)
	var has_belts := _has_orbital_type(entries, CustomSystemOrbital.TYPE_ASTEROID_BELT)
	var has_structures := _has_orbital_type(entries, CustomSystemOrbital.TYPE_STRUCTURE)
	var has_ruins := _has_orbital_type(entries, CustomSystemOrbital.TYPE_RUIN)
	var next_orbit_radius := _get_next_orbit_radius(entries)

	if not has_planets:
		var requested_planet_count := planet_count_override
		if requested_planet_count < 0:
			requested_planet_count = planet_names.size()
		var resolved_planet_count := maxi(requested_planet_count, planet_names.size())
		for index in range(resolved_planet_count):
			var planet_name := "%s %s" % [resolved_system_name, _to_roman(index + 1)]
			if index < planet_names.size():
				planet_name = planet_names[index]
			entries.append(_build_quick_orbital(
				"planet_%02d" % index,
				planet_name,
				CustomSystemOrbital.TYPE_PLANET,
				next_orbit_radius,
				1.35 + float(index % 3) * 0.28,
				Color.from_hsv(fmod(0.08 + float(index) * 0.17, 1.0), 0.38, 0.92),
				0.0,
				index < 2,
				0.58 if index < 2 else 0.16
			))
			next_orbit_radius += 18.0

	if not has_belts:
		for index in range(asteroid_belt_count):
			entries.append(_build_quick_orbital(
				"belt_%02d" % index,
				"%s Belt %d" % [resolved_system_name, index + 1],
				CustomSystemOrbital.TYPE_ASTEROID_BELT,
				next_orbit_radius + 6.0,
				1.2,
				Color(0.62, 0.58, 0.52, 1.0),
				12.0 + float(index) * 2.0
			))
			next_orbit_radius += 22.0

	if not has_structures:
		for index in range(structure_names.size()):
			entries.append(_build_quick_orbital(
				"structure_%02d" % index,
				structure_names[index],
				CustomSystemOrbital.TYPE_STRUCTURE,
				next_orbit_radius + 4.0,
				0.9,
				Color(0.44, 0.76, 1.0, 1.0)
			))
			next_orbit_radius += 12.0

	if not has_ruins:
		for index in range(ruin_names.size()):
			entries.append(_build_quick_orbital(
				"ruin_%02d" % index,
				ruin_names[index],
				CustomSystemOrbital.TYPE_RUIN,
				next_orbit_radius + 2.0,
				0.95,
				Color(0.72, 0.72, 0.78, 1.0)
			))
			next_orbit_radius += 10.0

	return entries


func _build_quick_orbital(
	orbital_id: String,
	orbital_name: String,
	orbital_type: String,
	orbit_radius: float,
	size: float,
	color: Color,
	orbit_width: float = 0.0,
	is_colonizable: bool = false,
	habitability: float = 0.0
) -> Dictionary:
	return {
		"id": orbital_id,
		"name": orbital_name,
		"type": orbital_type,
		"color": color,
		"size": size,
		"orbit_radius": orbit_radius,
		"orbit_angle": 0.0,
		"vertical_offset": 0.0,
		"orbit_width": orbit_width,
		"is_colonizable": is_colonizable,
		"habitability": habitability,
		"habitability_points": int(round(clampf(habitability, 0.0, 1.0) * 100.0)),
		"resource_richness_points": 50,
		"resource_richness": 0.5,
		"metadata": {},
	}


func _has_orbital_type(entries: Array[Dictionary], orbital_type: String) -> bool:
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if str(entry.get("type", "")) == orbital_type:
			return true
	return false


func _get_next_orbit_radius(entries: Array[Dictionary]) -> float:
	var radius := 30.0
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		radius = maxf(radius, float(entry.get("orbit_radius", radius)) + 18.0)
	return radius


func _to_roman(value: int) -> String:
	var remaining := maxi(value, 1)
	var numerals := [
		{"value": 10, "symbol": "X"},
		{"value": 9, "symbol": "IX"},
		{"value": 5, "symbol": "V"},
		{"value": 4, "symbol": "IV"},
		{"value": 1, "symbol": "I"},
	]
	var result := ""
	for numeral_variant in numerals:
		var numeral: Dictionary = numeral_variant
		var numeral_value: int = numeral["value"]
		while remaining >= numeral_value:
			result += str(numeral["symbol"])
			remaining -= numeral_value
	return result
