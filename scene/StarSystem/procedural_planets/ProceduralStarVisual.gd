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
var _camera_facing_nodes: Array[Node3D] = []


func configure(star: Dictionary) -> void:
	_star = star.duplicate(true)
	_visual_config = build_visual_config(_star)
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	if not _visual_config.is_empty():
		_rebuild()


func _process(_delta: float) -> void:
	_update_camera_facing_nodes()


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
	var surface_rotation: float = float(visual.get("rotation", rng.randf_range(-PI, PI)))
	var disk_yaw: float = wrapf(surface_rotation * 0.55 + 0.7, -PI, PI)
	var disk_tilt: float = deg_to_rad(rng.randf_range(18.0, 30.0))

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
		"rotation": surface_rotation,
		"base_diameter": (5.0 if is_black_hole else 4.0) * star_scale * STAR_SCALE_MULTIPLIER,
		"halo_color": halo_color,
		"halo_alpha": halo_alpha,
		"halo_scale": halo_scale,
		"emission_color": emission_color,
		"emission_energy": emission_energy,
		"is_black_hole": is_black_hole,
		"split_disk": false,
		"disk_yaw": float(visual.get("disk_yaw", disk_yaw)),
		"disk_tilt": float(visual.get("disk_tilt", disk_tilt)),
		"scene_colors": PackedColorArray() if is_black_hole else _build_star_scene_colors(base_color),
	}


func _rebuild() -> void:
	for child in get_children():
		child.free()
	_camera_facing_nodes.clear()

	var scene_variant: Variant = _visual_config.get("scene", null)
	var scene: PackedScene = scene_variant as PackedScene
	if scene == null:
		return

	var body_layer: Dictionary = {}
	var disk_layer: Dictionary = {}
	if bool(_visual_config.get("split_disk", false)):
		body_layer = _build_star_texture_layer(scene, PackedStringArray(["Disk"]), 1.0)
		disk_layer = _build_star_texture_layer(scene, PackedStringArray(["BlackHole"]), 3.0)
	else:
		body_layer = _build_star_texture_layer(scene)
	if body_layer.is_empty():
		return

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
		_register_camera_facing_node(halo)

	if not disk_layer.is_empty():
		var disk_texture: Texture2D = disk_layer.get("texture", null) as Texture2D
		if disk_texture != null:
			var disk_quad := MeshInstance3D.new()
			var disk_mesh := QuadMesh.new()
			disk_mesh.size = Vector2.ONE * float(_visual_config.get("base_diameter", 4.0)) * float(disk_layer.get("relative_scale", 3.0))
			disk_quad.mesh = disk_mesh
			disk_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			disk_quad.transform = Transform3D(
				_build_disk_basis(
					float(_visual_config.get("disk_tilt", deg_to_rad(24.0))),
					float(_visual_config.get("disk_yaw", 0.0))
				),
				Vector3.ZERO
			)
			disk_quad.material_override = _build_body_material(
				disk_texture,
				_visual_config.get("emission_color", Color.WHITE),
				0.16,
				BaseMaterial3D.BILLBOARD_DISABLED,
				1
			)
			add_child(disk_quad)

	var body_texture: Texture2D = body_layer.get("texture", null) as Texture2D
	if body_texture == null:
		return

	var body := MeshInstance3D.new()
	var body_mesh := QuadMesh.new()
	body_mesh.size = Vector2.ONE * float(_visual_config.get("base_diameter", 4.0)) * float(body_layer.get("relative_scale", 1.0))
	body.mesh = body_mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.material_override = _build_body_material(
		body_texture,
		_visual_config.get("emission_color", Color.WHITE),
		float(_visual_config.get("emission_energy", 0.64)),
		BaseMaterial3D.BILLBOARD_ENABLED,
		0
	)
	add_child(body)
	_update_camera_facing_nodes()


func _build_star_texture_layer(
	scene: PackedScene,
	hidden_nodes: PackedStringArray = PackedStringArray(),
	relative_scale_override: float = -1.0
) -> Dictionary:
	if scene == null:
		return {}

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

	var star_canvas: Node = scene.instantiate()
	holder.add_child(star_canvas)
	_set_canvas_nodes_visible(star_canvas, hidden_nodes, false)

	var pixels: float = float(_visual_config.get("pixels", DEFAULT_PIXELS))
	if star_canvas.has_method("set_pixels"):
		star_canvas.call("set_pixels", pixels)

	var relative_scale := 1.0
	if relative_scale_override > 0.0:
		relative_scale = relative_scale_override
	else:
		var relative_scale_variant: Variant = star_canvas.get("relative_scale")
		if relative_scale_variant != null:
			relative_scale = maxf(float(relative_scale_variant), 1.0)
	var content_extent: float = maxf(pixels * relative_scale, 1.0)
	holder.scale = Vector2.ONE * (VIEWPORT_TARGET_SIZE / content_extent)

	if star_canvas is Control:
		var star_control: Control = star_canvas as Control
		star_control.position = Vector2.ONE * pixels * 0.5 * (relative_scale - 1.0)

	var seed_value: int = int(_visual_config.get("seed", 0))
	if star_canvas.has_method("set_seed"):
		star_canvas.call("set_seed", seed_value)
	if star_canvas.has_method("set_rotates"):
		star_canvas.call("set_rotates", float(_visual_config.get("rotation", 0.0)))

	var scene_colors: PackedColorArray = _visual_config.get("scene_colors", PackedColorArray())
	if not scene_colors.is_empty() and star_canvas.has_method("set_colors"):
		star_canvas.call("set_colors", scene_colors)

	return {
		"texture": viewport.get_texture(),
		"relative_scale": relative_scale,
	}


func _set_canvas_nodes_visible(star_canvas: Node, node_names: PackedStringArray, is_visible: bool) -> void:
	for node_name in node_names:
		var canvas_item: CanvasItem = star_canvas.find_child(node_name, true, false) as CanvasItem
		if canvas_item != null:
			canvas_item.visible = is_visible


func _build_body_material(
	texture: Texture2D,
	emission_color: Color,
	emission_energy: float,
	billboard_mode: BaseMaterial3D.BillboardMode,
	render_priority: int = 0
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = billboard_mode
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = emission_energy
	material.render_priority = render_priority
	return material


func _build_disk_basis(disk_tilt: float, disk_yaw: float) -> Basis:
	var disk_normal := Vector3.UP.rotated(Vector3.RIGHT, disk_tilt).rotated(Vector3.UP, disk_yaw).normalized()
	var x_axis := disk_normal.cross(Vector3.UP)
	if x_axis.length() < 0.001:
		x_axis = disk_normal.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var y_axis := disk_normal.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, disk_normal)


func _register_camera_facing_node(node: Node3D) -> void:
	if node == null:
		return
	_camera_facing_nodes.append(node)


func _update_camera_facing_nodes() -> void:
	if _camera_facing_nodes.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_basis: Basis = camera.global_transform.basis.orthonormalized()
	for node in _camera_facing_nodes:
		if not is_instance_valid(node):
			continue
		var node_transform: Transform3D = node.global_transform
		node_transform.basis = camera_basis
		node.global_transform = node_transform


func _build_halo_material(color: Color, alpha: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HALO_SHADER
	material.render_priority = 2
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
