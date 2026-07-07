extends Node3D

## Dev harness: renders every registered ship set through the real MultiMesh
## pipeline (instance colors, material override rules identical to
## SystemRuntimePlaceholderRenderer) and saves one lineup screenshot per set
## to res://tools/screenshots/. Run windowed (not headless):
##   & $env:GODOT_CONSOLE --path "O:\Spiele\sellaris" "res://tools/shipset_screenshot.tscn"

const VISUAL_KEYS := [
	"corvette", "destroyer", "cruiser", "battleship",
	"science", "builder", "station", "stellar_station",
]
const SPACING := 7.0
const OWNER_COLOR := Color(0.55, 0.72, 1.0)

var _camera: Camera3D = null
var _stage: Node3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://tools/screenshots")
	_setup_environment()
	_stage = Node3D.new()
	add_child(_stage)
	_camera = Camera3D.new()
	_camera.fov = 32.0
	_camera.near = 0.1
	_camera.far = 800.0
	add_child(_camera)
	_camera.current = true

	for set_id in ShipSetRegistry.get_registered_set_ids():
		_clear_stage()
		ShipSetRegistry.set_active_set_id(set_id)
		var bounds := _spawn_lineup()
		_frame_camera(bounds)
		await _settle(24)
		await _capture("res://tools/screenshots/shipset_%s.png" % set_id)

	ShipSetRegistry.set_active_set_id(ShipSetRegistry.DEFAULT_SET_ID)
	get_tree().quit(0)


func _spawn_lineup() -> AABB:
	var bounds := AABB()
	var has_bounds := false
	for key_index in range(VISUAL_KEYS.size()):
		var visual_key: String = VISUAL_KEYS[key_index]
		var mesh := ShipSetRegistry.get_mesh(visual_key)
		if mesh == null:
			continue
		var marker := MultiMeshInstance3D.new()
		marker.name = "Lineup_%s" % visual_key
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = 1
		var position := Vector3(0.0, 0.0, float(key_index) * SPACING)
		multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, position))
		# Same tint rule as the system renderer: ships get a light owner tint.
		multimesh.set_instance_color(0, Color.WHITE.lerp(OWNER_COLOR, 0.15))
		marker.multimesh = multimesh
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not _mesh_provides_materials(mesh):
			marker.material_override = _placeholder_material()
		_stage.add_child(marker)
		var mesh_bounds := mesh.get_aabb()
		mesh_bounds.position += position
		bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
		has_bounds = true
	return bounds


func _frame_camera(bounds: AABB) -> void:
	var center := bounds.get_center()
	var extent := bounds.size.length()
	var direction := Vector3(0.62, 0.55, -0.56).normalized()
	_camera.look_at_from_position(center + direction * extent * 0.85, center, Vector3.UP)


static func _mesh_provides_materials(mesh: Mesh) -> bool:
	for surface_index in range(mesh.get_surface_count()):
		if mesh.surface_get_material(surface_index) != null:
			return true
	return false


func _placeholder_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.4
	return material


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.045, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85098, 0.823529, 0.980392)
	environment.ambient_light_energy = 0.9
	environment.tonemap_exposure = 1.15
	environment.glow_enabled = true
	environment.glow_intensity = 0.22
	environment.glow_bloom = 0.16
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	add_child(sun)


func _clear_stage() -> void:
	for child in _stage.get_children():
		child.free()


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("Saved %s" % path)
