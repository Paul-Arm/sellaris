extends Node3D
class_name ProceduralStarVisual

const STAR_SCENE: PackedScene = preload("res://Planets/Star/Star.tscn")
const BLACK_HOLE_SCENE: PackedScene = preload("res://Planets/BlackHole/BlackHole.tscn")
const HALO_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/AtmosphereHalo.gdshader")

const VIEWPORT_TARGET_SIZE := 768.0
const DEFAULT_PIXELS := 2400.0
const MIN_PIXELS := 1600.0
const MAX_PIXELS := 3400.0
const STAR_SCALE_MULTIPLIER := 2.0

var _star: Dictionary = {}
var _visual_config: Dictionary = {}


func configure(star: Dictionary) -> void:
	_star = star.duplicate(true)
	_visual_config = build_visual_config(_star)
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	if not _visual_config.is_empty():
		_rebuild()


static func build_visual_config(star: Dictionary) -> Dictionary:
	var metadata_variant: Variant = star.get("metadata", {})
	var metadata: Dictionary = metadata_variant if metadata_variant is Dictionary else {}
	var visual_variant: Variant = metadata.get("star_visual", {})
	var visual: Dictionary = visual_variant if visual_variant is Dictionary else {}
	var seed_value: int = _get_star_seed(star)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var special_type: String = str(star.get("special_type", "none"))
	var is_black_hole: bool = special_type == "Black hole"
	var scene: PackedScene = BLACK_HOLE_SCENE if is_black_hole else STAR_SCENE
	var base_color: Color = star.get("color", Color(1.0, 0.9, 0.7, 1.0))
	var star_scale: float = float(star.get("scale", 1.0))
	var halo_color: Color = base_color
	var halo_alpha := 0.18
	var halo_scale := 1.26
	var emission_color: Color = base_color
	var emission_energy := 0.64

	if is_black_hole:
		halo_color = Color(0.52, 0.72, 1.0, 1.0)
		halo_alpha = 0.08
		halo_scale = 1.34
		emission_color = Color(0.86, 0.78, 0.66, 1.0)
		emission_energy = 0.42

	return {
		"scene": scene,
		"seed": seed_value,
		"pixels": clampf(float(visual.get("pixels", DEFAULT_PIXELS)), MIN_PIXELS, MAX_PIXELS),
		"rotation": float(visual.get("rotation", rng.randf_range(-PI, PI))),
		"base_diameter": (5.0 if is_black_hole else 4.0) * star_scale * STAR_SCALE_MULTIPLIER,
		"halo_color": halo_color,
		"halo_alpha": halo_alpha,
		"halo_scale": halo_scale,
		"emission_color": emission_color,
		"emission_energy": emission_energy,
		"scene_colors": PackedColorArray() if is_black_hole else _build_star_scene_colors(base_color),
	}


func _rebuild() -> void:
	for child in get_children():
		child.free()

	var scene_variant: Variant = _visual_config.get("scene", null)
	var scene: PackedScene = scene_variant as PackedScene
	if scene == null:
		return

	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(int(VIEWPORT_TARGET_SIZE), int(VIEWPORT_TARGET_SIZE))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var holder := Control.new()
	holder.position = Vector2.ZERO
	holder.size = Vector2.ONE * VIEWPORT_TARGET_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(holder)

	var star_canvas := scene.instantiate()
	holder.add_child(star_canvas)

	var pixels: float = float(_visual_config.get("pixels", DEFAULT_PIXELS))
	if star_canvas != null and star_canvas.has_method("set_pixels"):
		star_canvas.call("set_pixels", pixels)

	var relative_scale := 1.0
	if star_canvas != null:
		var relative_scale_variant: Variant = star_canvas.get("relative_scale")
		if relative_scale_variant != null:
			relative_scale = maxf(float(relative_scale_variant), 1.0)
		var content_extent: float = maxf(pixels * relative_scale, 1.0)
		holder.scale = Vector2.ONE * (VIEWPORT_TARGET_SIZE / content_extent)
	if star_canvas is Control:
		var star_control: Control = star_canvas as Control
		star_control.position = Vector2.ONE * pixels * 0.5 * (relative_scale - 1.0)

	var seed_value: int = int(_visual_config.get("seed", 0))
	if star_canvas != null and star_canvas.has_method("set_seed"):
		star_canvas.call("set_seed", seed_value)
	if star_canvas != null and star_canvas.has_method("set_rotates"):
		star_canvas.call("set_rotates", float(_visual_config.get("rotation", 0.0)))

	var scene_colors: PackedColorArray = _visual_config.get("scene_colors", PackedColorArray())
	if not scene_colors.is_empty() and star_canvas != null and star_canvas.has_method("set_colors"):
		star_canvas.call("set_colors", scene_colors)

	if _visual_config.get("halo_alpha", 0.0) > 0.001:
		var halo := MeshInstance3D.new()
		var halo_mesh := QuadMesh.new()
		var halo_size: float = float(_visual_config.get("base_diameter", 4.0)) * float(_visual_config.get("halo_scale", 1.26))
		halo_mesh.size = Vector2.ONE * halo_size
		halo.mesh = halo_mesh
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo.material_override = _build_halo_material(
			_visual_config.get("halo_color", Color.WHITE),
			float(_visual_config.get("halo_alpha", 0.18))
		)
		add_child(halo)

	var body := MeshInstance3D.new()
	var body_mesh := QuadMesh.new()
	body_mesh.size = Vector2.ONE * float(_visual_config.get("base_diameter", 4.0)) * relative_scale
	body.mesh = body_mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.material_override = _build_body_material(
		viewport.get_texture(),
		_visual_config.get("emission_color", Color.WHITE),
		float(_visual_config.get("emission_energy", 0.64))
	)
	add_child(body)


func _build_body_material(texture: Texture2D, emission_color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = emission_energy
	return material


func _build_halo_material(color: Color, alpha: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HALO_SHADER
	var halo_color: Color = color
	halo_color.a = alpha
	material.set_shader_parameter("halo_color", halo_color)
	material.set_shader_parameter("inner_radius", 0.18)
	material.set_shader_parameter("outer_radius", 0.55)
	material.set_shader_parameter("softness", 0.18)
	return material


static func _get_star_seed(star: Dictionary) -> int:
	return str(star.get("id", star.get("name", "star"))).hash() * 131 + int(round(float(star.get("scale", 1.0)) * 100.0))


static func _build_star_scene_colors(base_color: Color) -> PackedColorArray:
	var warm_high := _soften_color(base_color.lightened(0.45), 0.18)
	var mid := _soften_color(base_color.lightened(0.14), 0.1)
	var low := _soften_color(base_color.darkened(0.18), 0.12)
	var shadow := _soften_color(base_color.darkened(0.52), 0.22)
	return PackedColorArray([
		warm_high.lightened(0.18),
		warm_high,
		mid,
		low,
		shadow,
		mid.lightened(0.24),
		warm_high.lightened(0.32),
	])


static func _soften_color(color: Color, desaturate_amount: float) -> Color:
	return Color.from_hsv(color.h, clampf(color.s * (1.0 - desaturate_amount), 0.0, 1.0), color.v, color.a)
