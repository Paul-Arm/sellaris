extends Node3D

const STAR_COLORS := [
	Color(0.55, 0.75, 1.0),
	Color(0.67, 0.82, 1.0),
	Color(0.93, 0.94, 1.0),
	Color(1.0, 0.95, 0.82),
	Color(1.0, 0.8, 0.62),
]

@export_range(500, 1500, 1) var min_system_count: int = 500
@export_range(500, 1500, 1) var max_system_count: int = 1500
@export var galaxy_radius: float = 2600.0
@export var min_system_distance: float = 34.0
@export_range(1, 6, 1) var spiral_arms: int = 4
@export_range(1, 5, 1) var hyperlanes_per_system: int = 2

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var stars: MultiMeshInstance3D = $Stars
@onready var hyperlanes: MeshInstance3D = $Hyperlanes
@onready var info_label: Label = $CanvasLayer/InfoLabel

var seed_text: String = ""
var generated_seed: int = 0
var system_count: int = 0
var system_positions: Array[Vector3] = []


func set_seed_text(value: String) -> void:
	seed_text = value


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
	if camera_rig.has_method("reset_view"):
		camera_rig.reset_view(galaxy_radius)

	var rng := RandomNumberGenerator.new()
	generated_seed = _resolve_seed()
	rng.seed = generated_seed
	system_count = rng.randi_range(min(min_system_count, max_system_count), max(min_system_count, max_system_count))

	system_positions = _build_system_positions(rng, system_count)
	_render_stars(rng)
	_render_hyperlanes()
	_update_info_label()


func _resolve_seed() -> int:
	if seed_text.is_empty():
		return int(Time.get_unix_time_from_system() * 1000000.0) + int(Time.get_ticks_usec())

	return seed_text.hash()


func _build_system_positions(rng: RandomNumberGenerator, target_count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var cell_size := min_system_distance
	var grid: Dictionary = {}
	var max_attempts := target_count * 60
	var attempt := 0

	while positions.size() < target_count and attempt < max_attempts:
		attempt += 1
		var candidate := _sample_system_position(rng)
		var cell := Vector2i(
			int(floor(candidate.x / cell_size)),
			int(floor(candidate.z / cell_size))
		)

		if _has_nearby_system(candidate, cell, grid):
			continue

		positions.append(candidate)
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(candidate)

	if positions.size() < target_count:
		push_warning("Galaxy generator reached the placement limit before hitting the requested system count.")

	return positions


func _sample_system_position(rng: RandomNumberGenerator) -> Vector3:
	var radius_roll: float = pow(rng.randf(), 0.58)
	var radius: float = radius_roll * galaxy_radius
	var arm_index: int = rng.randi_range(0, maxi(spiral_arms - 1, 0))
	var arm_count: float = maxf(float(spiral_arms), 1.0)
	var arm_angle: float = float(arm_index) * TAU / arm_count
	var swirl: float = (radius / galaxy_radius) * 2.6
	var random_scatter: float = rng.randf_range(-0.28, 0.28)
	var angle: float = arm_angle + swirl + random_scatter

	if rng.randf() < 0.25:
		angle = rng.randf_range(0.0, TAU)
		radius *= rng.randf_range(0.15, 0.55)

	var x := cos(angle) * radius * rng.randf_range(0.9, 1.1)
	var z := sin(angle) * radius
	var y := rng.randf_range(-18.0, 18.0)
	return Vector3(x, y, z)


func _has_nearby_system(candidate: Vector3, cell: Vector2i, grid: Dictionary) -> bool:
	var min_distance_sq := min_system_distance * min_system_distance

	for x_offset in range(-1, 2):
		for y_offset in range(-1, 2):
			var neighbor_cell := Vector2i(cell.x + x_offset, cell.y + y_offset)
			if not grid.has(neighbor_cell):
				continue

			for existing: Vector3 in grid[neighbor_cell]:
				if candidate.distance_squared_to(existing) < min_distance_sq:
					return true

	return false


func _render_stars(rng: RandomNumberGenerator) -> void:
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
	multimesh.instance_count = system_positions.size()

	for i in range(system_positions.size()):
		var star_scale := rng.randf_range(0.55, 1.9)
		var transform := Transform3D(Basis().scaled(Vector3.ONE * star_scale), system_positions[i])
		multimesh.set_instance_transform(i, transform)
		multimesh.set_instance_color(i, STAR_COLORS[rng.randi_range(0, STAR_COLORS.size() - 1)])

	stars.multimesh = multimesh


func _render_hyperlanes() -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)

	var lane_material := StandardMaterial3D.new()
	lane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lane_material.albedo_color = Color(0.32, 0.56, 0.95, 0.42)
	lane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var links: Dictionary = {}

	for i in range(system_positions.size()):
		var nearest := _find_nearest_neighbors(i, hyperlanes_per_system)
		for neighbor_index in nearest:
			var a: int = mini(i, neighbor_index)
			var b: int = maxi(i, neighbor_index)
			var key := "%s:%s" % [a, b]
			if links.has(key):
				continue

			links[key] = true
			surface_tool.set_color(Color(0.32, 0.56, 0.95, 0.42))
			surface_tool.add_vertex(system_positions[a])
			surface_tool.set_color(Color(0.32, 0.56, 0.95, 0.42))
			surface_tool.add_vertex(system_positions[b])

	hyperlanes.mesh = surface_tool.commit()
	hyperlanes.material_override = lane_material


func _find_nearest_neighbors(system_index: int, desired_count: int) -> Array[int]:
	var origin := system_positions[system_index]
	var nearest: Array[int] = []
	var nearest_distances: Array[float] = []

	for candidate_index in range(system_positions.size()):
		if candidate_index == system_index:
			continue

		var distance_sq := origin.distance_squared_to(system_positions[candidate_index])
		var insert_at := nearest_distances.size()

		for i in range(nearest_distances.size()):
			if distance_sq < nearest_distances[i]:
				insert_at = i
				break

		if insert_at < desired_count:
			nearest.insert(insert_at, candidate_index)
			nearest_distances.insert(insert_at, distance_sq)

			if nearest.size() > desired_count:
				nearest.resize(desired_count)
				nearest_distances.resize(desired_count)
		elif nearest.size() < desired_count:
			nearest.append(candidate_index)
			nearest_distances.append(distance_sq)

	return nearest


func _update_info_label() -> void:
	var displayed_seed := seed_text if not seed_text.is_empty() else str(generated_seed)
	info_label.text = "Seed: %s\nSystems: %d\nPan: WASD / Arrows / Edge / Middle Drag  Zoom: Mouse Wheel  Regenerate: R  Back: Esc" % [
		displayed_seed,
		system_positions.size(),
	]
