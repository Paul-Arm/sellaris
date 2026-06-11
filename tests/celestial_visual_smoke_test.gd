extends Node

## Structure smoke test for the 3D celestial pipeline: a synthetic system with
## all star types, one planet per world kind (ringed gas giant included) and
## an asteroid belt must build sphere meshes with ShaderMaterials, MultiMesh
## belts — and, the replacement guarantee, zero SubViewports anywhere.

const PREVIEW_SCENE: PackedScene = preload("res://scene/StarSystem/StarSystemPreview.tscn")
const ASTEROID_BELT_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralAsteroidBelt.gd")

const PLANET_KINDS := ["landmass", "dry_terran", "no_atmosphere", "ice_world", "lava_world", "gas_planet"]


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Celestial visual smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	var preview := PREVIEW_SCENE.instantiate() as StarSystemPreview
	add_child(preview)
	await get_tree().process_frame

	preview.set_system_details(_system_details())
	await get_tree().process_frame
	await get_tree().process_frame

	var bodies := preview.get_node("Pivot/Bodies") as Node3D
	_expect(bodies != null and bodies.get_child_count() > 0, "bodies container should hold celestial visuals", failures)

	# The replacement guarantee: no SubViewport-based rendering remains.
	_expect(preview.find_children("", "SubViewport", true, false).is_empty(), "preview should contain no SubViewports", failures)

	# Planets: every kind has a sphere surface with a ShaderMaterial.
	var planet_visuals: Array[ProceduralPlanetVisual] = []
	for child in bodies.get_children():
		if child is ProceduralPlanetVisual:
			planet_visuals.append(child)
	_expect(planet_visuals.size() == PLANET_KINDS.size(), "expected %d planet visuals, got %d" % [PLANET_KINDS.size(), planet_visuals.size()], failures)
	var seen_clouds := false
	var seen_ring := false
	var seen_atmosphere := false
	for planet in planet_visuals:
		var surface := planet.find_child("Surface", true, false) as MeshInstance3D
		_expect(surface != null, "planet should build a Surface mesh", failures)
		if surface != null:
			_expect(surface.mesh is SphereMesh, "planet surface should be a sphere mesh", failures)
			_expect(surface.material_override is ShaderMaterial, "planet surface should use a ShaderMaterial", failures)
		seen_clouds = seen_clouds or planet.find_child("Clouds", true, false) != null
		seen_ring = seen_ring or planet.find_child("Ring", true, false) != null
		seen_atmosphere = seen_atmosphere or planet.find_child("Atmosphere", true, false) != null
	_expect(seen_clouds, "the terran planet should carry a cloud shell", failures)
	_expect(seen_ring, "the gas giant should carry a ring", failures)
	_expect(seen_atmosphere, "at least one planet should carry an atmosphere shell", failures)

	# Stars: normal star, neutron beams, black hole with accretion disk.
	var star_visuals: Array[ProceduralStarVisual] = []
	for child in bodies.get_children():
		if child is ProceduralStarVisual:
			star_visuals.append(child)
	_expect(star_visuals.size() == 3, "expected 3 star visuals, got %d" % star_visuals.size(), failures)
	var seen_corona := false
	var seen_beams := false
	var seen_disk := false
	var seen_plasma_arms := false
	for star in star_visuals:
		seen_corona = seen_corona or star.find_child("Corona", true, false) != null
		seen_beams = seen_beams or star.find_child("BeamsPivot", true, false) != null
		seen_disk = seen_disk or star.find_child("AccretionDisk", true, false) != null
		var arms_root := star.find_child("PlasmaArms", true, false)
		seen_plasma_arms = seen_plasma_arms or (arms_root != null and arms_root.find_children("", "MeshInstance3D", true, false).size() >= 3)
	_expect(seen_corona, "stars should carry corona billboards", failures)
	_expect(seen_beams, "the neutron star should carry beam cones", failures)
	_expect(seen_disk, "the black hole should carry an accretion disk", failures)
	_expect(seen_plasma_arms, "normal stars should carry plasma arm prominences", failures)

	# Belt: MultiMesh instances with rocks.
	var belt := _find_belt(bodies)
	_expect(belt != null, "the belt orbital should build a ProceduralAsteroidBelt", failures)
	if belt != null:
		var rock_instances: Array[MultiMeshInstance3D] = []
		for child in belt.get_children():
			if child is MultiMeshInstance3D:
				rock_instances.append(child)
		_expect(not rock_instances.is_empty(), "belt should hold MultiMeshInstance3D rocks", failures)
		var total_rocks := 0
		for instance in rock_instances:
			total_rocks += instance.multimesh.instance_count
		_expect(total_rocks >= 96, "belt should instance at least 96 rocks, got %d" % total_rocks, failures)

	# Belt determinism: same orbital -> identical instance buffers.
	var belt_orbital := _belt_orbital()
	var belt_a := ASTEROID_BELT_SCRIPT.new() as ProceduralAsteroidBelt
	var belt_b := ASTEROID_BELT_SCRIPT.new() as ProceduralAsteroidBelt
	belt_a.configure(belt_orbital)
	belt_b.configure(belt_orbital)
	add_child(belt_a)
	add_child(belt_b)
	await get_tree().process_frame
	_expect(_collect_belt_buffers(belt_a) == _collect_belt_buffers(belt_b), "belt placement should be deterministic", failures)
	belt_a.free()
	belt_b.free()

	# Clearing empties the containers.
	preview.set_system_details({})
	await get_tree().process_frame
	_expect(bodies.get_child_count() == 0, "clearing the system should empty the bodies container", failures)

	preview.free()


func _find_belt(bodies: Node3D) -> ProceduralAsteroidBelt:
	for child in bodies.get_children():
		if child is ProceduralAsteroidBelt:
			return child
	return null


func _collect_belt_buffers(belt: ProceduralAsteroidBelt) -> Array:
	var buffers := []
	for child in belt.get_children():
		if child is MultiMeshInstance3D:
			buffers.append((child as MultiMeshInstance3D).multimesh.buffer)
	return buffers


func _system_details() -> Dictionary:
	var orbitals := []
	for kind_index in range(PLANET_KINDS.size()):
		var kind: String = PLANET_KINDS[kind_index]
		orbitals.append({
			"id": "planet_%s" % kind,
			"name": "World %d" % kind_index,
			"type": "planet",
			"size": 3.4 if kind == "gas_planet" else 1.8,
			"orbit_radius": 16.0 + float(kind_index) * 10.0,
			"orbit_angle": float(kind_index) * 0.8,
			"color": Color(0.6, 0.65, 0.9),
			"metadata": {
				"planet_visual": {"kind": kind, "has_ring": kind == "gas_planet"},
			},
		})
	orbitals.append(_belt_orbital())
	return {
		"id": "sys_celestial",
		"name": "Celestial",
		"seed": 1337,
		"has_full_intel": false,
		"star_profile": {"star_class": "G", "special_type": "none"},
		"stars": [
			{"id": "star_primary", "name": "Primary", "star_class": "G", "color": Color(1.0, 0.88, 0.55), "scale": 1.2, "is_primary": true},
			{"id": "star_neutron", "name": "Pulse", "special_type": "Neutron star", "color": Color(0.85, 0.92, 1.0), "scale": 0.7, "orbit_radius": 30.0},
			{"id": "star_hole", "name": "Maw", "special_type": "Black hole", "color": Color(0.4, 0.5, 0.9), "scale": 1.0, "orbit_radius": 60.0},
		],
		"orbitals": orbitals,
		"space_renderables": {},
	}


func _belt_orbital() -> Dictionary:
	return {
		"id": "belt_main",
		"name": "Main Belt",
		"type": "asteroid_belt",
		"size": 1.0,
		"orbit_radius": 84.0,
		"orbit_width": 9.0,
		"color": Color(0.62, 0.58, 0.52),
		"metadata": {"belt_visual": {"density": 40}},
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
