extends Node3D

const GALAXY_GENERATOR_SCRIPT := preload("res://scene/GalaxyGenerator.gd")

@export var star_count: int = 900
@export var galaxy_radius: float = 2600.0
@export var min_system_distance: float = 34.0
@export_range(1, 6, 1) var spiral_arms: int = 4
@export_enum("spiral", "ring", "elliptical", "clustered") var galaxy_shape: String = "spiral"
@export_range(1, 8, 1) var hyperlane_density: int = 2
@export var custom_systems: Array[Resource] = []

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var stars: MultiMeshInstance3D = $Stars
@onready var hyperlanes: MeshInstance3D = $Hyperlanes
@onready var info_label: Label = $CanvasLayer/InfoLabel

var seed_text: String = ""
var generated_seed: int = 0
var system_positions: Array[Vector3] = []
var system_records: Array[Dictionary] = []
var hyperlane_links: Array[Vector2i] = []
var generation_settings: Dictionary = {}
var generator: RefCounted = GALAXY_GENERATOR_SCRIPT.new()
var systems_by_id: Dictionary = {}


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
	_generate_galaxy()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scene/MainMenue.tscn")

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_generate_galaxy()


func _generate_galaxy() -> void:
	system_positions.clear()
	system_records.clear()
	hyperlane_links.clear()
	systems_by_id.clear()
	if camera_rig.has_method("reset_view"):
		camera_rig.reset_view(galaxy_radius)

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

	var layout: Dictionary = generator.build_layout(resolved_settings, custom_systems)
	generated_seed = int(layout.get("seed", 0))
	galaxy_shape = str(layout.get("shape", galaxy_shape))
	hyperlane_density = int(layout.get("hyperlane_density", hyperlane_density))
	system_records = layout.get("systems", [])
	hyperlane_links = layout.get("links", [])

	for system_record in system_records:
		system_positions.append(system_record["position"])
		systems_by_id[system_record["id"]] = system_record

	_render_stars()
	_render_hyperlanes()
	_update_info_label()


func get_system_details(system_id: String) -> Dictionary:
	if not systems_by_id.has(system_id):
		return {}
	return generator.generate_system_details(generated_seed, systems_by_id[system_id], custom_systems)

func _render_stars() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 6.0
	sphere.radial_segments = 6
	sphere.rings = 4

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color(1.0, 1.0, 1.0)
	material.emission_energy_multiplier = 1.3
	sphere.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = sphere
	multimesh.instance_count = system_records.size()

	var rng := RandomNumberGenerator.new()
	rng.seed = generated_seed

	for i in range(system_records.size()):
		var system_record: Dictionary = system_records[i]
		var star_scale := rng.randf_range(0.55, 1.9)
		var transform := Transform3D(Basis().scaled(Vector3.ONE * star_scale), system_record["position"])
		multimesh.set_instance_transform(i, transform)
		multimesh.set_instance_color(i, system_record["star_color"])

	stars.multimesh = multimesh


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
	info_label.text = "Seed: %s\nSystems: %d  Shape: %s  Hyperlanes: %d\nPan: WASD / Arrows / Edge / Middle Drag  Zoom: Mouse Wheel  Regenerate: R  Back: Esc" % [
		displayed_seed,
		system_positions.size(),
		galaxy_shape.capitalize(),
		hyperlane_density,
	]
