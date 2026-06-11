extends SceneTree

## Determinism guard for the 3D celestial visual pipeline: build_visual_config
## must return an identical pure-data dict for the same seed, for every world
## kind (metadata-override and fallback paths) and every star type. Different
## seeds must produce different palettes.

const PLANET_VISUAL_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralPlanetVisual.gd")
const STAR_VISUAL_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralStarVisual.gd")

const PLANET_KINDS := ["landmass", "dry_terran", "no_atmosphere", "ice_world", "lava_world", "gas_planet"]


func _initialize() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Celestial visual determinism test passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var system_details := _system_details()

	# Every kind via metadata override: two builds must match exactly.
	for kind_index in range(PLANET_KINDS.size()):
		var kind: String = PLANET_KINDS[kind_index]
		var orbital := _orbital_with_kind("planet_%s" % kind, kind, kind_index)
		var first: Dictionary = ProceduralPlanetVisual.build_visual_config(system_details, orbital, kind_index)
		var second: Dictionary = ProceduralPlanetVisual.build_visual_config(system_details, orbital, kind_index)
		_expect(first == second, "config for kind %s should be deterministic" % kind, failures)
		_expect(str(first.get("kind", "")) == kind, "metadata kind %s should be respected, got %s" % [kind, first.get("kind", "")], failures)
		_expect(first.get("palette", {}) is Dictionary and not (first.get("palette", {}) as Dictionary).is_empty(), "kind %s should carry a palette" % kind, failures)

	# Fallback path without visual metadata.
	var plain_orbital := {
		"id": "planet_plain",
		"name": "Plain World",
		"type": "planet",
		"size": 2.2,
		"orbit_radius": 26.0,
		"habitability": 0.75,
		"is_colonizable": true,
		"color": Color(0.55, 0.7, 0.5),
	}
	var plain_first: Dictionary = ProceduralPlanetVisual.build_visual_config(system_details, plain_orbital, 9)
	var plain_second: Dictionary = ProceduralPlanetVisual.build_visual_config(system_details, plain_orbital, 9)
	_expect(plain_first == plain_second, "metadata-less config should be deterministic", failures)
	_expect(PLANET_KINDS.has(str(plain_first.get("kind", ""))), "fallback kind should resolve to a known kind", failures)

	# describe_planet mirrors the resolved kind/label.
	var description: Dictionary = ProceduralPlanetVisual.describe_planet(
		system_details, _orbital_with_kind("planet_ice", "ice_world", 2), 2
	)
	_expect(str(description.get("kind", "")) == "ice_world", "describe_planet should respect metadata kind", failures)
	_expect(not str(description.get("label", "")).is_empty(), "describe_planet should carry a label", failures)

	# Different seeds -> different palettes (and configs).
	var other_system := _system_details()
	other_system["seed"] = 991
	var seed_a: Dictionary = ProceduralPlanetVisual.build_visual_config(system_details, plain_orbital, 9)
	var seed_b: Dictionary = ProceduralPlanetVisual.build_visual_config(other_system, plain_orbital, 9)
	_expect(seed_a.get("palette", {}) != seed_b.get("palette", {}), "different system seeds should yield different palettes", failures)

	# Stars: normal G, neutron, black hole, O class — deterministic each.
	var star_records := [
		{"id": "star_g", "name": "G Star", "star_class": "G", "color": Color(1.0, 0.88, 0.55), "scale": 1.0},
		{"id": "star_n", "name": "Neutron", "special_type": "Neutron star", "color": Color(0.85, 0.92, 1.0), "scale": 0.8},
		{"id": "star_bh", "name": "Singularity", "special_type": "Black hole", "color": Color(0.4, 0.5, 0.9), "scale": 1.4},
		{"id": "star_o", "name": "O Giant", "special_type": "O class star", "color": Color(0.62, 0.74, 1.0), "scale": 2.0},
	]
	var expected_kinds := ["star", "neutron", "black_hole", "star"]
	for star_index in range(star_records.size()):
		var star: Dictionary = star_records[star_index]
		var star_first: Dictionary = ProceduralStarVisual.build_visual_config(star)
		var star_second: Dictionary = ProceduralStarVisual.build_visual_config(star)
		_expect(star_first == star_second, "star config for %s should be deterministic" % star.get("id"), failures)
		_expect(
			str(star_first.get("kind", "")) == expected_kinds[star_index],
			"star %s should resolve kind %s, got %s" % [star.get("id"), expected_kinds[star_index], star_first.get("kind")],
			failures
		)
	var neutron_config: Dictionary = ProceduralStarVisual.build_visual_config(star_records[1])
	_expect(float(neutron_config.get("pulse_speed", 0.0)) > 0.0, "neutron star should pulse", failures)


func _system_details() -> Dictionary:
	return {
		"id": "sys_determinism",
		"name": "Determinism",
		"seed": 4242,
		"star_profile": {"star_class": "G", "special_type": "none"},
		"stars": [],
		"orbitals": [],
	}


func _orbital_with_kind(orbital_id: String, kind: String, orbital_index: int) -> Dictionary:
	return {
		"id": orbital_id,
		"name": "World %d" % orbital_index,
		"type": "planet",
		"size": 1.8 + float(orbital_index) * 0.6,
		"orbit_radius": 14.0 + float(orbital_index) * 9.0,
		"color": Color(0.6, 0.65, 0.9),
		"metadata": {
			"planet_visual": {"kind": kind},
		},
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
