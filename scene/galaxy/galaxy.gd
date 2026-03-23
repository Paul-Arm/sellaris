extends Node3D

const GALAXY_GENERATOR_SCRIPT := preload("res://scene/galaxy/GalaxyGenerator.gd")
const STAR_CORE_SHADER := preload("res://scene/galaxy/StarCore.gdshader")
const STAR_GLOW_SHADER := preload("res://scene/galaxy/StarGlow.gdshader")
const BLACK_HOLE_TYPE := "Black hole"
const NEUTRON_TYPE := "Neutron star"
const O_CLASS_TYPE := "O class star"

@export var star_count: int = 900
@export var galaxy_radius: float = 2600.0
@export var min_system_distance: float = 34.0
@export_range(1, 6, 1) var spiral_arms: int = 4
@export_enum("spiral", "ring", "elliptical", "clustered") var galaxy_shape: String = "spiral"
@export_range(1, 8, 1) var hyperlane_density: int = 2
@export var custom_systems: Array[Resource] = []

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var stars: Node3D = $Stars
@onready var core_stars: MultiMeshInstance3D = $Stars/CoreStars
@onready var glow_stars: MultiMeshInstance3D = $Stars/GlowStars
@onready var hyperlanes: MeshInstance3D = $Hyperlanes
@onready var info_label: Label = $CanvasLayer/InfoLabel
@onready var loading_overlay: Control = $CanvasLayer/LoadingOverlay
@onready var loading_status: Label = $CanvasLayer/LoadingOverlay/Panel/MarginContainer/VBoxContainer/LoadingStatus
@onready var loading_progress: ProgressBar = $CanvasLayer/LoadingOverlay/Panel/MarginContainer/VBoxContainer/LoadingProgress

var seed_text: String = ""
var generated_seed: int = 0
var system_positions: Array[Vector3] = []
var system_records: Array[Dictionary] = []
var hyperlane_links: Array[Vector2i] = []
var hyperlane_graph: Dictionary = {}
var generation_settings: Dictionary = {}
var generator: RefCounted = GALAXY_GENERATOR_SCRIPT.new()
var systems_by_id: Dictionary = {}
var system_indices_by_id: Dictionary = {}
var _is_generating: bool = false


func set_seed_text(value: String) -> void:
	seed_text = value


func configure(settings: Dictionary) -> void:
	generation_settings = settings.duplicate(true)
	if generation_settings.has("seed_text"):
		seed_text = str(generation_settings["seed_text"])
	if generation_settings.has("star_count"):
		star_count = int(generation_settings["star_count"])
	if generation_settings.has("shape"):
		galaxy_shape = str(generation_settings["shape"])
	if generation_settings.has("hyperlane_density"):
		hyperlane_density = int(generation_settings["hyperlane_density"])


func _ready() -> void:
	call_deferred("_generate_galaxy_async")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scene/MainMenue/MainMenue.tscn")

	if _is_generating:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			call_deferred("_generate_galaxy_async")


func _generate_galaxy_async() -> void:
	if _is_generating:
		return

	_is_generating = true
	_set_loading_state(true, "Preparing generator...", 0.0)
	await get_tree().process_frame

	system_positions.clear()
	system_records.clear()
	hyperlane_links.clear()
	hyperlane_graph.clear()
	systems_by_id.clear()
	system_indices_by_id.clear()
	if camera_rig.has_method("reset_view"):
		camera_rig.reset_view(galaxy_radius)

	_set_loading_state(true, "Resolving settings...", 0.1)
	await get_tree().process_frame

	var resolved_settings := {
		"seed_text": seed_text,
		"star_count": star_count,
		"galaxy_radius": galaxy_radius,
		"min_system_distance": min_system_distance,
		"spiral_arms": spiral_arms,
		"shape": galaxy_shape,
		"hyperlane_density": hyperlane_density,
	}
	for key in generation_settings.keys():
		resolved_settings[key] = generation_settings[key]

	_set_loading_state(true, "Placing systems and hyperlanes...", 0.45)
	await get_tree().process_frame

	var layout: Dictionary = generator.build_layout(resolved_settings, custom_systems)
	generated_seed = int(layout.get("seed", 0))
	galaxy_shape = str(layout.get("shape", galaxy_shape))
	hyperlane_density = int(layout.get("hyperlane_density", hyperlane_density))
	system_records = layout.get("systems", [])
	hyperlane_links = layout.get("links", [])
	hyperlane_graph = layout.get("hyperlane_graph", {})

	_set_loading_state(true, "Preparing scene data...", 0.68)
	await get_tree().process_frame

	for system_index in range(system_records.size()):
		var system_record: Dictionary = system_records[system_index]
		system_positions.append(system_record["position"])
		systems_by_id[system_record["id"]] = system_record
		system_indices_by_id[system_record["id"]] = system_index

	_set_loading_state(true, "Rendering stars...", 0.82)
	await get_tree().process_frame
	_render_stars()

	_set_loading_state(true, "Rendering hyperlanes...", 0.93)
	await get_tree().process_frame
	_render_hyperlanes()
	_update_info_label()
	_set_loading_state(true, "Finalizing...", 1.0)
	await get_tree().process_frame
	_set_loading_state(false)
	_is_generating = false


func get_system_details(system_id: String) -> Dictionary:
	if not systems_by_id.has(system_id):
		return {}
	return generator.generate_system_details(generated_seed, systems_by_id[system_id], custom_systems)


func _render_stars() -> void:
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 4.5
	core_mesh.height = 9.0
	core_mesh.radial_segments = 18
	core_mesh.rings = 12

	var core_material := ShaderMaterial.new()
	core_material.shader = STAR_CORE_SHADER
	core_material.set_shader_parameter("emission_strength", 1.2)
	core_material.set_shader_parameter("rim_strength", 0.18)
	core_material.set_shader_parameter("rim_power", 2.6)
	core_material.set_shader_parameter("saturation_boost", 1.45)
	core_mesh.material = core_material

	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 11.0
	glow_mesh.height = 22.0
	glow_mesh.radial_segments = 18
	glow_mesh.rings = 12

	var star_instances: Array[Dictionary] = []
	for system_record in system_records:
		var star_profile: Dictionary = system_record.get("star_profile", {})
		var profile_stars: Array = star_profile.get("stars", [])
		if profile_stars.is_empty():
			profile_stars = [{
				"index": 0,
				"color": Color(1.0, 0.93, 0.46, 1.0),
				"scale": 1.0,
				"special_type": "none",
			}]

		var orbit_radius := 12.0
		if profile_stars.size() == 2:
			orbit_radius = 9.5
		elif profile_stars.size() >= 3:
			orbit_radius = 13.0

		for star_data_variant in profile_stars:
			var star_data: Dictionary = star_data_variant
			var offset := _get_star_offset(int(star_data.get("index", 0)), profile_stars.size(), orbit_radius)
			star_instances.append({
				"position": system_record["position"] + offset,
				"color": star_data.get("color", star_profile.get("display_color", Color.WHITE)),
				"scale": float(star_data.get("scale", 1.0)),
				"special_type": str(star_data.get("special_type", "none")),
			})

	var core_multimesh := MultiMesh.new()
	core_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	core_multimesh.use_colors = true
	core_multimesh.mesh = core_mesh
	core_multimesh.instance_count = star_instances.size()

	var glow_multimesh := MultiMesh.new()
	glow_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	glow_multimesh.use_colors = true
	glow_multimesh.mesh = glow_mesh
	glow_multimesh.instance_count = star_instances.size()

	for i in range(star_instances.size()):
		var instance: Dictionary = star_instances[i]
		var star_scale: float = float(instance["scale"])
		var color: Color = instance["color"]
		var special_type: String = str(instance["special_type"])
		var star_position: Vector3 = instance["position"]
		var core_scale := star_scale * 1.05
		var glow_scale := star_scale * 2.0

		if special_type == BLACK_HOLE_TYPE:
			core_scale *= 0.72
			glow_scale *= 1.25
			color = color.darkened(0.55)
		elif special_type == NEUTRON_TYPE:
			core_scale *= 0.68
			glow_scale *= 0.95
		elif special_type == O_CLASS_TYPE:
			core_scale *= 1.18
			glow_scale *= 1.15

		core_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * core_scale), star_position))
		core_multimesh.set_instance_color(i, color)

		var glow_color := _get_glow_color(color, special_type)
		glow_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * glow_scale), star_position))
		glow_multimesh.set_instance_color(i, glow_color)

	core_stars.multimesh = core_multimesh
	glow_stars.multimesh = glow_multimesh
	glow_stars.material_override = _build_glow_material()


func _render_hyperlanes() -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)

	var lane_material := StandardMaterial3D.new()
	lane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lane_material.albedo_color = Color(0.32, 0.56, 0.95, 0.42)
	lane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for link in hyperlane_links:
		surface_tool.set_color(Color(0.32, 0.56, 0.95, 0.42))
		surface_tool.add_vertex(system_positions[link.x])
		surface_tool.set_color(Color(0.32, 0.56, 0.95, 0.42))
		surface_tool.add_vertex(system_positions[link.y])

	hyperlanes.mesh = surface_tool.commit()
	hyperlanes.material_override = lane_material


func _update_info_label() -> void:
	var displayed_seed := seed_text if not seed_text.is_empty() else str(generated_seed)
	info_label.text = "Seed: %s\nSystems: %d  Shape: %s  Hyperlanes: %d\nPan: WASD / Arrows / Edge / Middle Drag  Orbit: Right Drag  Zoom: Mouse Wheel  Regenerate: R  Back: Esc" % [
		displayed_seed,
		system_positions.size(),
		galaxy_shape.capitalize(),
		hyperlane_density,
	]


func _get_star_offset(star_index: int, system_star_count: int, orbit_radius: float) -> Vector3:
	if system_star_count <= 1:
		return Vector3.ZERO

	if system_star_count == 2:
		var direction := -1.0 if star_index == 0 else 1.0
		return Vector3(direction * orbit_radius, 0.0, 0.0)

	var angle := float(star_index) * TAU / float(system_star_count)
	return Vector3(cos(angle) * orbit_radius, 0.0, sin(angle) * orbit_radius)


func _build_glow_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STAR_GLOW_SHADER
	material.set_shader_parameter("fresnel_power", 2.4)
	material.set_shader_parameter("glow_strength", 1.5)
	material.set_shader_parameter("pulse_strength", 0.06)
	material.set_shader_parameter("pulse_speed", 0.95)
	material.set_shader_parameter("center_fill", 0.22)
	return material


func _get_glow_color(base_color: Color, special_type: String) -> Color:
	if special_type == BLACK_HOLE_TYPE:
		return Color(0.28, 0.46, 1.0, 0.46)
	if special_type == NEUTRON_TYPE:
		return Color(0.72, 0.9, 1.0, 0.52)
	if special_type == O_CLASS_TYPE:
		return Color(0.7, 0.88, 1.0, 0.6)

	var glow_color := base_color
	glow_color.a = 0.34
	return glow_color


func _set_loading_state(visible_state: bool, status_text: String = "", progress_ratio: float = 0.0) -> void:
	loading_overlay.visible = visible_state
	if not status_text.is_empty():
		loading_status.text = status_text
	loading_progress.value = clampf(progress_ratio, 0.0, 1.0) * 100.0
