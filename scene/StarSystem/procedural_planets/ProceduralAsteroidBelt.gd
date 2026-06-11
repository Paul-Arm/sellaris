extends Node3D
class_name ProceduralAsteroidBelt

## Asteroid belt as instanced low-poly 3D rocks: one MultiMeshInstance3D per
## globally cached rock variant (~6 draw calls per belt instead of dozens of
## SubViewport billboards). Placement is deterministic: a single RNG seeded
## from _get_belt_seed fills all instances in index order.

const ROCK_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/AsteroidRock.gdshader")

const ASTEROID_SCALE_MULTIPLIER := 2.0
const BELT_BASE_COLOR := Color(0.6, 0.58, 0.54, 1.0)

var _orbital: Dictionary = {}
var _sun_world_position := Vector3.ZERO
var _has_sun_position := false
var _rock_material: ShaderMaterial = null


func configure(orbital: Dictionary) -> void:
	_orbital = orbital.duplicate(true)
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	if not _orbital.is_empty():
		_rebuild()


func set_sun_world_position(sun_position: Vector3) -> void:
	_sun_world_position = sun_position
	_has_sun_position = true
	_apply_sun_to_material()


func _rebuild() -> void:
	for child in get_children():
		child.free()
	_rock_material = null

	if _orbital.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _get_belt_seed(_orbital)
	var visual_metadata: Dictionary = _get_belt_visual_metadata(_orbital)
	var belt_radius: float = float(_orbital.get("orbit_radius", 0.0))
	var belt_width: float = maxf(float(_orbital.get("orbit_width", 8.0)), 6.0)
	var belt_height: float = float(_orbital.get("vertical_offset", 0.0))
	var density: int = int(visual_metadata.get("density", clampi(int(round(belt_width * 2.1)) + 24, 28, 72)))
	var rock_count: int = clampi(density * 4, 96, 320)
	var base_diameter: float = maxf(float(_orbital.get("size", 1.0)) * 0.72, 0.5) * ASTEROID_SCALE_MULTIPLIER

	_rock_material = _build_rock_material()

	var variant_count: int = CelestialMeshLibrary.ROCK_VARIANT_COUNT
	var instances_per_variant := PackedInt32Array()
	instances_per_variant.resize(variant_count)
	for rock_index in range(rock_count):
		instances_per_variant[rock_index % variant_count] += 1

	var multimeshes: Array[MultiMesh] = []
	for variant_index in range(variant_count):
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = CelestialMeshLibrary.get_rock_mesh(variant_index)
		multimesh.instance_count = instances_per_variant[variant_index]
		multimeshes.append(multimesh)

	# Placement: one RNG, fixed draw order per rock (angle jitter, radius x2
	# for a triangular spread, height, 3 Euler angles, scale, tint, tumble
	# phase, tumble speed) — append new draws only, never reorder.
	var variant_cursor := PackedInt32Array()
	variant_cursor.resize(variant_count)
	for rock_index in range(rock_count):
		var angle: float = float(rock_index) * TAU / float(maxi(rock_count, 1)) + rng.randf_range(-0.12, 0.12)
		var radius: float = belt_radius + (rng.randf() + rng.randf() - 1.0) * belt_width * 0.5
		var height: float = belt_height + rng.randf_range(-0.5, 0.5)
		var euler := Vector3(
			rng.randf_range(0.0, TAU),
			rng.randf_range(0.0, TAU),
			rng.randf_range(0.0, TAU)
		)
		var rock_scale: float = base_diameter * rng.randf_range(0.4, 1.9)
		var tint: float = rng.randf()
		var tumble_phase: float = rng.randf_range(0.0, TAU)
		var tumble_speed: float = rng.randf_range(0.05, 0.3)

		var variant_index: int = rock_index % variant_count
		var instance_index: int = variant_cursor[variant_index]
		variant_cursor[variant_index] += 1
		var basis := Basis.from_euler(euler).scaled(Vector3.ONE * rock_scale)
		var origin := Vector3(cos(angle) * radius, height, sin(angle) * radius)
		multimeshes[variant_index].set_instance_transform(instance_index, Transform3D(basis, origin))
		multimeshes[variant_index].set_instance_custom_data(
			instance_index,
			Color(tint, tumble_phase, tumble_speed, 0.0)
		)

	for variant_index in range(variant_count):
		if multimeshes[variant_index].instance_count <= 0:
			continue
		var instance := MultiMeshInstance3D.new()
		instance.name = "Rocks%d" % variant_index
		instance.multimesh = multimeshes[variant_index]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.material_override = _rock_material
		add_child(instance)

	if _has_sun_position:
		_apply_sun_to_material()


func _build_rock_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ROCK_SHADER
	var anchor: Color = _orbital.get("color", BELT_BASE_COLOR)
	var color_a := CelestialBodyPalette.pastelize(anchor.lerp(Color(0.72, 0.62, 0.5), 0.5), 0.25, 0.4, 0.9)
	var color_b := CelestialBodyPalette.pastelize(anchor.lerp(Color(0.52, 0.56, 0.68), 0.5), 0.25, 0.4, 0.9)
	material.set_shader_parameter("belt_color_a", color_a)
	material.set_shader_parameter("belt_color_b", color_b)
	return material


func _apply_sun_to_material() -> void:
	if _rock_material == null:
		return
	_rock_material.set_shader_parameter("sun_mode", 1.0)
	_rock_material.set_shader_parameter("sun_position", _sun_world_position)


static func _get_belt_seed(orbital: Dictionary) -> int:
	return str(orbital.get("id", orbital.get("name", "belt"))).hash() * 41 + int(round(float(orbital.get("orbit_radius", 0.0)) * 100.0))


static func _get_belt_visual_metadata(orbital: Dictionary) -> Dictionary:
	var metadata_variant: Variant = orbital.get("metadata", {})
	if metadata_variant is Dictionary:
		var metadata: Dictionary = metadata_variant
		var belt_variant: Variant = metadata.get("belt_visual", {})
		if belt_variant is Dictionary:
			return belt_variant
	return {}
