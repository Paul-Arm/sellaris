extends Node3D
class_name ProceduralAsteroidBelt

const ASTEROID_SCENE: PackedScene = preload("res://Planets/Asteroids/Asteroid.tscn")

const VIEWPORT_TARGET_SIZE := 256.0
const DEFAULT_PIXELS := 2100.0
const MIN_PIXELS := 1500.0
const MAX_PIXELS := 2800.0
const ASTEROID_SCALE_MULTIPLIER := 2.0

var _orbital: Dictionary = {}


func configure(orbital: Dictionary) -> void:
	_orbital = orbital.duplicate(true)
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	if not _orbital.is_empty():
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = _get_belt_seed(_orbital)
	var visual_metadata: Dictionary = _get_belt_visual_metadata(_orbital)
	var belt_radius: float = float(_orbital.get("orbit_radius", 0.0))
	var belt_width: float = maxf(float(_orbital.get("orbit_width", 8.0)), 6.0)
	var belt_height: float = float(_orbital.get("vertical_offset", 0.0))
	var asteroid_count: int = clampi(int(visual_metadata.get("density", clampi(int(round(belt_width * 2.1)) + 24, 28, 72))), 24, 84)
	var base_diameter: float = maxf(float(_orbital.get("size", 1.0)) * 0.72, 0.5) * ASTEROID_SCALE_MULTIPLIER

	for asteroid_index in range(asteroid_count):
		var asteroid_rng := RandomNumberGenerator.new()
		asteroid_rng.seed = _get_belt_seed(_orbital) + asteroid_index * 977
		var texture: Texture2D = _build_asteroid_texture(asteroid_rng, asteroid_index, visual_metadata)
		var asteroid := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		var diameter: float = base_diameter * rng.randf_range(0.45, 1.95)
		var aspect := Vector2(rng.randf_range(0.78, 1.32), rng.randf_range(0.78, 1.32))
		mesh.size = Vector2(diameter * aspect.x, diameter * aspect.y)
		asteroid.mesh = mesh
		asteroid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		asteroid.material_override = _build_asteroid_material(texture)

		var angle: float = float(asteroid_index) * TAU / float(maxi(asteroid_count, 1)) + rng.randf_range(-0.1, 0.1)
		var radius: float = belt_radius + rng.randf_range(-belt_width * 0.5, belt_width * 0.5)
		asteroid.position = Vector3(
			cos(angle) * radius,
			belt_height + rng.randf_range(-0.35, 0.35),
			sin(angle) * radius
		)
		add_child(asteroid)


func _build_asteroid_texture(rng: RandomNumberGenerator, variant_index: int, visual_metadata: Dictionary) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(int(VIEWPORT_TARGET_SIZE), int(VIEWPORT_TARGET_SIZE))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var holder := Control.new()
	holder.position = Vector2.ZERO
	holder.size = Vector2.ONE * VIEWPORT_TARGET_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(holder)

	var asteroid_canvas := ASTEROID_SCENE.instantiate()
	holder.add_child(asteroid_canvas)
	_ensure_unique_asteroid_material(asteroid_canvas)

	var pixels: float = clampf(float(visual_metadata.get("pixels", DEFAULT_PIXELS)) * rng.randf_range(0.9, 1.1), MIN_PIXELS, MAX_PIXELS)
	if asteroid_canvas != null and asteroid_canvas.has_method("set_pixels"):
		asteroid_canvas.call("set_pixels", pixels)

	var relative_scale := 1.0
	if asteroid_canvas != null:
		var relative_scale_variant: Variant = asteroid_canvas.get("relative_scale")
		if relative_scale_variant != null:
			relative_scale = maxf(float(relative_scale_variant), 1.0)
		var content_extent: float = maxf(pixels * relative_scale, 1.0)
		holder.scale = Vector2.ONE * (VIEWPORT_TARGET_SIZE / content_extent)
	if asteroid_canvas is Control:
		var asteroid_control: Control = asteroid_canvas as Control
		asteroid_control.position = Vector2.ONE * pixels * 0.5 * (relative_scale - 1.0)

	var asteroid_seed: int = _get_belt_seed(_orbital) + variant_index * 73
	if asteroid_canvas != null and asteroid_canvas.has_method("set_seed"):
		asteroid_canvas.call("set_seed", asteroid_seed)
	if asteroid_canvas != null and asteroid_canvas.has_method("set_rotates"):
		asteroid_canvas.call("set_rotates", rng.randf_range(-PI, PI))
	if asteroid_canvas != null and asteroid_canvas.has_method("set_light"):
		asteroid_canvas.call("set_light", Vector2(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.12, 0.12)))
	if asteroid_canvas != null and asteroid_canvas.has_method("set_dither"):
		asteroid_canvas.call("set_dither", true)
	_randomize_asteroid_shape(asteroid_canvas, rng, variant_index)

	return viewport.get_texture()


func _build_asteroid_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.emission_enabled = true
	material.emission = Color(0.92, 0.92, 0.96, 1.0)
	material.emission_energy_multiplier = 0.12
	return material


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


func _randomize_asteroid_shape(asteroid_canvas: Node, rng: RandomNumberGenerator, variant_index: int) -> void:
	if asteroid_canvas == null:
		return
	var asteroid_rect := asteroid_canvas.get_node_or_null("Asteroid") as ColorRect
	if asteroid_rect == null:
		return
	var material := asteroid_rect.material as ShaderMaterial
	if material == null:
		return

	material.set_shader_parameter("size", rng.randf_range(3.2, 8.8) + float(variant_index % 3) * 0.25)
	material.set_shader_parameter("octaves", rng.randi_range(1, 4))


func _ensure_unique_asteroid_material(asteroid_canvas: Node) -> void:
	if asteroid_canvas == null:
		return
	var asteroid_rect := asteroid_canvas.get_node_or_null("Asteroid") as ColorRect
	if asteroid_rect == null or asteroid_rect.material == null:
		return
	asteroid_rect.material = asteroid_rect.material.duplicate()
