extends Node3D

const GALAXY_GENERATOR_SCRIPT := preload("res://scene/galaxy/GalaxyGenerator.gd")
const GALAXY_STATE_SCRIPT := preload("res://scene/galaxy/GalaxyState.gd")
const EMPIRE_FACTORY_SCRIPT := preload("res://scene/galaxy/EmpireFactory.gd")
const STAR_CORE_SHADER := preload("res://scene/galaxy/StarCore.gdshader")
const STAR_GLOW_SHADER := preload("res://scene/galaxy/StarGlow.gdshader")
const BLACK_HOLE_TYPE := "Black hole"
const NEUTRON_TYPE := "Neutron star"
const O_CLASS_TYPE := "O class star"
const DEFAULT_EMPIRE_COUNT := 6
const SYSTEM_PICK_RADIUS := 26.0
const OWNERSHIP_BLOB_RADIUS_FACTOR := 1.9
const OWNERSHIP_EXCLUSION_RADIUS_FACTOR := 1.12
const OWNERSHIP_CONNECTOR_RADIUS_FACTOR := 0.72
const OWNERSHIP_CONNECTION_DISTANCE_FACTOR := 5.75
const OWNERSHIP_BORDER_WIDTH_FACTOR := 0.38
const OWNERSHIP_CIRCLE_SEGMENTS := 28

@export var star_count: int = 900
@export var galaxy_radius: float = 3000.0
@export var min_system_distance: float = 44.0
@export_range(1, 6, 1) var spiral_arms: int = 4
@export_enum("spiral", "ring", "elliptical", "clustered") var galaxy_shape: String = "spiral"
@export_range(1, 8, 1) var hyperlane_density: int = 2
@export var custom_systems: Array[Resource] = []

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var stars: Node3D = $Stars
@onready var core_stars: MultiMeshInstance3D = $Stars/CoreStars
@onready var glow_stars: MultiMeshInstance3D = $Stars/GlowStars
@onready var ownership_markers: MeshInstance3D = $Stars/OwnershipMarkers
@onready var ownership_connectors: MeshInstance3D = $Stars/OwnershipConnectors
@onready var hyperlanes: MeshInstance3D = $Hyperlanes
@onready var info_label: Label = $CanvasLayer/InfoLabel
@onready var loading_overlay: Control = $CanvasLayer/LoadingOverlay
@onready var loading_status: Label = $CanvasLayer/LoadingOverlay/Panel/MarginContainer/VBoxContainer/LoadingStatus
@onready var loading_progress: ProgressBar = $CanvasLayer/LoadingOverlay/Panel/MarginContainer/VBoxContainer/LoadingProgress
@onready var system_panel: PanelContainer = $CanvasLayer/SystemPanel
@onready var empire_status_label: Label = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/EmpireStatusLabel
@onready var change_empire_button: Button = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/ChangeEmpireButton
@onready var selected_system_title: Label = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/SelectedSystemTitle
@onready var selected_system_meta: Label = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/SelectedSystemMeta
@onready var claim_system_button: Button = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/ClaimSystemButton
@onready var clear_owner_button: Button = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/ClearOwnerButton
@onready var empire_picker_overlay: Control = $CanvasLayer/EmpirePickerOverlay
@onready var empire_picker_list: ItemList = $CanvasLayer/EmpirePickerOverlay/Panel/MarginContainer/VBoxContainer/EmpirePickerList
@onready var select_empire_button: Button = $CanvasLayer/EmpirePickerOverlay/Panel/MarginContainer/VBoxContainer/ButtonRow/SelectEmpireButton
@onready var cancel_empire_picker_button: Button = $CanvasLayer/EmpirePickerOverlay/Panel/MarginContainer/VBoxContainer/ButtonRow/CancelEmpirePickerButton

var seed_text: String = ""
var generated_seed: int = 0
var system_positions: Array[Vector3] = []
var system_records: Array[Dictionary] = []
var hyperlane_links: Array[Vector2i] = []
var hyperlane_graph: Dictionary = {}
var generation_settings: Dictionary = {}
var generator: RefCounted = GALAXY_GENERATOR_SCRIPT.new()
var galaxy_state: RefCounted = GALAXY_STATE_SCRIPT.new()
var empire_factory: RefCounted = EMPIRE_FACTORY_SCRIPT.new()
var systems_by_id: Dictionary = {}
var system_indices_by_id: Dictionary = {}
var empire_records: Array[Dictionary] = []
var empires_by_id: Dictionary = {}
var active_empire_id: String = ""
var selected_system_id: String = ""
var _is_generating: bool = false
var _empire_picker_requires_selection: bool = true


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
	change_empire_button.pressed.connect(_on_change_empire_pressed)
	claim_system_button.pressed.connect(_on_claim_selected_system_pressed)
	clear_owner_button.pressed.connect(_on_clear_owner_pressed)
	select_empire_button.pressed.connect(_on_select_empire_pressed)
	cancel_empire_picker_button.pressed.connect(_on_cancel_empire_picker_pressed)
	empire_picker_list.item_selected.connect(_on_empire_picker_item_selected)
	empire_picker_list.item_activated.connect(_on_empire_picker_item_activated)
	_update_system_panel()
	call_deferred("_generate_galaxy_async")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if empire_picker_overlay.visible and not _empire_picker_requires_selection:
			_set_empire_picker_visible(false, false)
			return
		get_tree().change_scene_to_file("res://scene/MainMenue/MainMenue.tscn")
		return

	if _is_generating:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			call_deferred("_generate_galaxy_async")
			return
		if event.keycode == KEY_E:
			_open_empire_picker(false)
			return

	if empire_picker_overlay.visible:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_pointer_over_gui():
			return

		selected_system_id = _pick_system_at_screen_position(event.position)
		_update_system_panel()
		_update_info_label()


func _generate_galaxy_async() -> void:
	if _is_generating:
		return

	_is_generating = true
	selected_system_id = ""
	active_empire_id = ""
	_set_empire_picker_visible(false, false)
	_set_loading_state(true, "Preparing generator...", 0.0)
	await get_tree().process_frame

	system_positions.clear()
	system_records.clear()
	hyperlane_links.clear()
	hyperlane_graph.clear()
	empire_records.clear()
	systems_by_id.clear()
	system_indices_by_id.clear()
	empires_by_id.clear()
	galaxy_state.reset()
	core_stars.multimesh = null
	glow_stars.multimesh = null
	ownership_markers.mesh = null
	ownership_connectors.mesh = null
	hyperlanes.mesh = null
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
	galaxy_state.load_from_layout(layout)
	generated_seed = int(layout.get("seed", 0))
	galaxy_shape = str(layout.get("shape", galaxy_shape))
	hyperlane_density = int(layout.get("hyperlane_density", hyperlane_density))
	_sync_cached_state()

	_set_loading_state(true, "Preparing empire shells...", 0.6)
	await get_tree().process_frame
	_initialize_empires()

	_set_loading_state(true, "Preparing scene data...", 0.72)
	await get_tree().process_frame

	_set_loading_state(true, "Rendering stars...", 0.84)
	await get_tree().process_frame
	_render_stars()

	_set_loading_state(true, "Rendering hyperlanes...", 0.92)
	await get_tree().process_frame
	_render_hyperlanes()
	_render_ownership_markers()
	_update_system_panel()
	_update_info_label()

	_set_loading_state(true, "Finalizing...", 1.0)
	await get_tree().process_frame
	_set_loading_state(false)
	_is_generating = false
	_open_empire_picker(true)


func get_system_details(system_id: String) -> Dictionary:
	if not systems_by_id.has(system_id):
		return {}

	var details: Dictionary = generator.generate_system_details(generated_seed, systems_by_id[system_id], custom_systems)
	var owner_id: String = galaxy_state.get_system_owner_id(system_id)
	var owner_name := "Unclaimed"
	if empires_by_id.has(owner_id):
		owner_name = str(empires_by_id[owner_id].get("name", owner_name))

	details["owner_empire_id"] = owner_id
	details["owner_name"] = owner_name
	return details


func get_galaxy_state_snapshot() -> Dictionary:
	return galaxy_state.build_snapshot()


func assign_active_empire(empire_id: String) -> bool:
	if not galaxy_state.set_local_player_empire(empire_id):
		return false

	active_empire_id = empire_id
	_sync_cached_state()
	_populate_empire_picker()
	_update_system_panel()
	_update_info_label()
	return true


func set_system_owner(system_id: String, empire_id: String) -> bool:
	if not galaxy_state.set_system_owner(system_id, empire_id):
		return false

	_sync_cached_state()
	_render_ownership_markers()
	_update_system_panel()
	_update_info_label()
	return true


func clear_system_owner(system_id: String) -> bool:
	return set_system_owner(system_id, "")


func add_runtime_system(system_record: Dictionary) -> bool:
	if not galaxy_state.add_system(system_record):
		return false

	_sync_cached_state()
	_render_stars()
	_render_hyperlanes()
	_render_ownership_markers()
	_update_system_panel()
	_update_info_label()
	return true


func add_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if not galaxy_state.add_hyperlane(system_a_id, system_b_id):
		return false

	_sync_cached_state()
	_render_hyperlanes()
	_update_system_panel()
	_update_info_label()
	return true


func remove_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if not galaxy_state.remove_hyperlane(system_a_id, system_b_id):
		return false

	_sync_cached_state()
	_render_hyperlanes()
	_update_system_panel()
	_update_info_label()
	return true


func _initialize_empires() -> void:
	var default_empires: Array[Dictionary] = empire_factory.build_default_empires(generated_seed, system_records.size(), DEFAULT_EMPIRE_COUNT)
	galaxy_state.set_empires(default_empires)
	_sync_cached_state()
	_populate_empire_picker()


func _sync_cached_state() -> void:
	generated_seed = int(galaxy_state.generated_seed)
	system_positions = galaxy_state.system_positions
	system_records = galaxy_state.system_records
	hyperlane_links = galaxy_state.hyperlane_links
	hyperlane_graph = galaxy_state.hyperlane_graph
	systems_by_id = galaxy_state.systems_by_id
	system_indices_by_id = galaxy_state.system_indices_by_id
	empire_records = galaxy_state.empires
	empires_by_id = galaxy_state.empires_by_id


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


func _render_ownership_markers() -> void:
	var empire_owned_systems: Dictionary = {}
	for system_record in system_records:
		var owner_empire_id: String = str(system_record.get("owner_empire_id", ""))
		if owner_empire_id.is_empty() or not empires_by_id.has(owner_empire_id):
			continue
		var aura_record: Dictionary = {
			"system_id": str(system_record.get("id", "")),
			"position": system_record["position"],
			"color": empires_by_id[owner_empire_id].get("color", Color.WHITE),
		}
		var owned_by_empire: Array = empire_owned_systems.get(owner_empire_id, [])
		owned_by_empire.append(aura_record)
		empire_owned_systems[owner_empire_id] = owned_by_empire

	if empire_owned_systems.is_empty():
		ownership_markers.mesh = null
		ownership_connectors.mesh = null
		ownership_markers.material_override = null
		ownership_connectors.material_override = null
		return

	var fill_tool := SurfaceTool.new()
	fill_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var border_tool := SurfaceTool.new()
	border_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for owner_empire_id_variant in empire_owned_systems.keys():
		var owner_empire_id: String = str(owner_empire_id_variant)
		var systems_for_empire: Array = empire_owned_systems.get(owner_empire_id, [])
		var region_color: Color = empires_by_id[owner_empire_id].get("color", Color.WHITE)
		var clustered_regions: Array[Dictionary] = _build_empire_blob_regions(owner_empire_id, systems_for_empire)

		for region_data_variant in clustered_regions:
			var region_data: Dictionary = region_data_variant
			var region_polygon: PackedVector2Array = region_data["polygon"]
			var region_height: float = float(region_data["height"])
			if region_polygon.size() < 3:
				continue
			_append_region_fill(fill_tool, region_polygon, region_height + 1.2, region_color)
			_append_region_border(border_tool, region_polygon, region_height + 2.4, region_color)

	ownership_markers.mesh = fill_tool.commit()
	ownership_connectors.mesh = border_tool.commit()
	ownership_markers.material_override = _build_ownership_fill_material()
	ownership_connectors.material_override = _build_ownership_border_material()


func _build_empire_blob_regions(owner_empire_id: String, systems_for_empire: Array) -> Array[Dictionary]:
	var clustered_regions: Array[Dictionary] = []
	var blob_radius: float = _get_ownership_blob_radius()
	var clusters: Array = _build_owned_system_clusters(systems_for_empire)

	for cluster_variant in clusters:
		var cluster_systems: Array = cluster_variant
		var primitive_regions: Array[PackedVector2Array] = []
		for system_variant in cluster_systems:
			var system_record: Dictionary = system_variant
			var system_position: Vector3 = system_record["position"]
			primitive_regions.append(_build_circle_polygon(Vector2(system_position.x, system_position.z), blob_radius, OWNERSHIP_CIRCLE_SEGMENTS))

		for connector_variant in _build_cluster_connector_polygons(cluster_systems):
			var connector_polygon: PackedVector2Array = connector_variant
			if connector_polygon.size() >= 3:
				primitive_regions.append(connector_polygon)

		var merged_polygons: Array[PackedVector2Array] = _merge_overlapping_polygons(primitive_regions)
		merged_polygons = _subtract_non_owned_systems(owner_empire_id, merged_polygons)

		for merged_polygon in merged_polygons:
			if merged_polygon.size() < 3:
				continue
			clustered_regions.append({
				"polygon": merged_polygon,
				"height": _get_region_height(cluster_systems),
			})

	return clustered_regions


func _build_circle_polygon(center: Vector2, radius: float, segment_count: int) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point_index in range(segment_count):
		var angle: float = float(point_index) * TAU / float(segment_count)
		polygon.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return polygon


func _build_owned_system_clusters(systems_for_empire: Array) -> Array:
	var clusters: Array = []
	var visited: Dictionary = {}
	var max_distance_sq: float = _get_ownership_connection_distance()
	max_distance_sq *= max_distance_sq

	for system_index in range(systems_for_empire.size()):
		if visited.has(system_index):
			continue

		var cluster: Array = []
		var queue: Array[int] = [system_index]
		visited[system_index] = true

		while not queue.is_empty():
			var current_index: int = int(queue.pop_front())
			var current_system: Dictionary = systems_for_empire[current_index]
			cluster.append(current_system)
			var current_position: Vector3 = current_system["position"]

			for candidate_index in range(systems_for_empire.size()):
				if visited.has(candidate_index):
					continue
				var candidate_system: Dictionary = systems_for_empire[candidate_index]
				var candidate_position: Vector3 = candidate_system["position"]
				if current_position.distance_squared_to(candidate_position) > max_distance_sq:
					continue
				visited[candidate_index] = true
				queue.append(candidate_index)

		clusters.append(cluster)

	return clusters


func _build_cluster_connector_polygons(cluster_systems: Array) -> Array[PackedVector2Array]:
	var connector_polygons: Array[PackedVector2Array] = []
	if cluster_systems.size() <= 1:
		return connector_polygons

	var dedupe: Dictionary = {}
	var max_distance_sq: float = _get_ownership_connection_distance()
	max_distance_sq *= max_distance_sq
	var connector_radius: float = _get_ownership_connector_radius()

	for system_index in range(cluster_systems.size()):
		var origin: Dictionary = cluster_systems[system_index]
		var origin_position: Vector3 = origin["position"]
		var nearest_index: int = -1
		var nearest_distance_sq: float = INF

		for candidate_index in range(cluster_systems.size()):
			if candidate_index == system_index:
				continue
			var candidate: Dictionary = cluster_systems[candidate_index]
			var distance_sq: float = origin_position.distance_squared_to(candidate["position"])
			if distance_sq > max_distance_sq or distance_sq >= nearest_distance_sq:
				continue
			nearest_index = candidate_index
			nearest_distance_sq = distance_sq

		if nearest_index == -1:
			continue

		var edge_a: int = mini(system_index, nearest_index)
		var edge_b: int = maxi(system_index, nearest_index)
		var edge_key: String = "%s:%s" % [edge_a, edge_b]
		if dedupe.has(edge_key):
			continue

		dedupe[edge_key] = true
		var target: Dictionary = cluster_systems[nearest_index]
		connector_polygons.append(_build_capsule_polygon(
			Vector2(origin_position.x, origin_position.z),
			Vector2(target["position"].x, target["position"].z),
			connector_radius
		))

	return connector_polygons


func _build_capsule_polygon(start_point: Vector2, end_point: Vector2, radius: float) -> PackedVector2Array:
	var direction: Vector2 = end_point - start_point
	if direction.length_squared() <= 0.001:
		return _build_circle_polygon(start_point, radius, OWNERSHIP_CIRCLE_SEGMENTS)

	var polygon := PackedVector2Array()
	var axis: Vector2 = direction.normalized()
	var normal := Vector2(-axis.y, axis.x)
	var start_angle: float = normal.angle()
	var end_angle: float = start_angle + PI
	var arc_steps: int = maxi(6, OWNERSHIP_CIRCLE_SEGMENTS / 2)

	for step in range(arc_steps + 1):
		var t: float = float(step) / float(arc_steps)
		var angle: float = start_angle + PI * t
		polygon.append(start_point + Vector2(cos(angle), sin(angle)) * radius)

	for step in range(arc_steps + 1):
		var t: float = float(step) / float(arc_steps)
		var angle: float = end_angle + PI * t
		polygon.append(end_point + Vector2(cos(angle), sin(angle)) * radius)

	return polygon


func _merge_overlapping_polygons(polygons: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var merged_regions: Array[PackedVector2Array] = polygons.duplicate()
	var did_merge: bool = true

	while did_merge:
		did_merge = false
		for first_index in range(merged_regions.size()):
			for second_index in range(first_index + 1, merged_regions.size()):
				var merge_result: Array = Geometry2D.merge_polygons(merged_regions[first_index], merged_regions[second_index])
				if merge_result.size() != 1:
					continue

				var merged_polygon: PackedVector2Array = merge_result[0]
				if merged_polygon.size() >= 2 and merged_polygon[0].is_equal_approx(merged_polygon[merged_polygon.size() - 1]):
					merged_polygon.remove_at(merged_polygon.size() - 1)
				merged_regions.remove_at(second_index)
				merged_regions.remove_at(first_index)
				merged_regions.append(merged_polygon)
				did_merge = true
				break
			if did_merge:
				break

	return merged_regions


func _subtract_non_owned_systems(owner_empire_id: String, polygons: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var exclusion_records: Array[Dictionary] = []
	var exclusion_radius: float = _get_ownership_exclusion_radius()

	for system_record in system_records:
		var system_owner_id: String = str(system_record.get("owner_empire_id", ""))
		if system_owner_id == owner_empire_id:
			continue
		var system_position: Vector3 = system_record["position"]
		exclusion_records.append({
			"center": Vector2(system_position.x, system_position.z),
			"polygon": _build_circle_polygon(Vector2(system_position.x, system_position.z), exclusion_radius, 16),
		})

	var result_polygons: Array[PackedVector2Array] = polygons.duplicate()
	for exclusion_record_variant in exclusion_records:
		var exclusion_record: Dictionary = exclusion_record_variant
		var exclusion_center: Vector2 = exclusion_record["center"]
		var exclusion_polygon: PackedVector2Array = exclusion_record["polygon"]
		var next_result: Array[PackedVector2Array] = []
		for region_polygon in result_polygons:
			if not _is_point_near_polygon_bounds(exclusion_center, region_polygon, exclusion_radius * 1.5):
				next_result.append(region_polygon)
				continue

			var overlap_regions: Array = Geometry2D.intersect_polygons(region_polygon, exclusion_polygon)
			if overlap_regions.is_empty():
				next_result.append(region_polygon)
				continue

			var clipped_regions: Array = Geometry2D.clip_polygons(region_polygon, exclusion_polygon)
			for clipped_region_variant in clipped_regions:
				var clipped_region: PackedVector2Array = clipped_region_variant
				if clipped_region.size() >= 3:
					if clipped_region[0].is_equal_approx(clipped_region[clipped_region.size() - 1]):
						clipped_region.remove_at(clipped_region.size() - 1)
					next_result.append(clipped_region)
		result_polygons = next_result

	return result_polygons


func _is_point_near_polygon_bounds(point: Vector2, polygon: PackedVector2Array, margin: float) -> bool:
	if polygon.is_empty():
		return false

	var min_x: float = polygon[0].x
	var max_x: float = polygon[0].x
	var min_y: float = polygon[0].y
	var max_y: float = polygon[0].y

	for polygon_point in polygon:
		min_x = minf(min_x, polygon_point.x)
		max_x = maxf(max_x, polygon_point.x)
		min_y = minf(min_y, polygon_point.y)
		max_y = maxf(max_y, polygon_point.y)

	return point.x >= min_x - margin and point.x <= max_x + margin and point.y >= min_y - margin and point.y <= max_y + margin


func _append_region_fill(surface_tool: SurfaceTool, region_polygon: PackedVector2Array, region_height: float, region_color: Color) -> void:
	var fill_color := region_color
	fill_color.a = 0.18
	var triangulated_indices: PackedInt32Array = Geometry2D.triangulate_polygon(region_polygon)

	for triangle_index in range(0, triangulated_indices.size(), 3):
		for point_offset in range(3):
			var polygon_index: int = triangulated_indices[triangle_index + point_offset]
			var region_point: Vector2 = region_polygon[polygon_index]
			surface_tool.set_color(fill_color)
			surface_tool.add_vertex(Vector3(region_point.x, region_height, region_point.y))


func _append_region_border(surface_tool: SurfaceTool, region_polygon: PackedVector2Array, region_height: float, region_color: Color) -> void:
	var half_width: float = _get_ownership_border_half_width()
	var outer_results: Array = Geometry2D.offset_polygon(region_polygon, half_width)
	if outer_results.is_empty():
		return
	var outer_polygon: PackedVector2Array = outer_results[0]
	var inner_results: Array = Geometry2D.offset_polygon(region_polygon, -half_width * 0.82)
	var inner_polygon: PackedVector2Array = region_polygon
	if not inner_results.is_empty():
		inner_polygon = inner_results[0]

	var border_color := region_color
	border_color.a = 0.92
	var segment_count: int = mini(outer_polygon.size(), inner_polygon.size())
	if segment_count < 3:
		return

	for point_index in range(segment_count):
		var next_index: int = (point_index + 1) % segment_count
		var outer_current: Vector2 = outer_polygon[point_index]
		var outer_next: Vector2 = outer_polygon[next_index]
		var inner_current: Vector2 = inner_polygon[point_index]
		var inner_next: Vector2 = inner_polygon[next_index]
		_append_triangle(surface_tool, outer_current, outer_next, inner_next, region_height, border_color)
		_append_triangle(surface_tool, outer_current, inner_next, inner_current, region_height, border_color)


func _append_triangle(surface_tool: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, height: float, color: Color) -> void:
	surface_tool.set_color(color)
	surface_tool.add_vertex(Vector3(a.x, height, a.y))
	surface_tool.set_color(color)
	surface_tool.add_vertex(Vector3(b.x, height, b.y))
	surface_tool.set_color(color)
	surface_tool.add_vertex(Vector3(c.x, height, c.y))


func _update_info_label() -> void:
	var displayed_seed := seed_text if not seed_text.is_empty() else str(generated_seed)
	var active_empire_name := "None"
	if empires_by_id.has(active_empire_id):
		active_empire_name = str(empires_by_id[active_empire_id].get("name", active_empire_name))

	var selected_summary := "Selected: None"
	if not selected_system_id.is_empty() and systems_by_id.has(selected_system_id):
		var selected_owner: Dictionary = galaxy_state.get_system_owner(selected_system_id)
		var selected_owner_name := "Unclaimed"
		if not selected_owner.is_empty():
			selected_owner_name = str(selected_owner.get("name", selected_owner_name))
		selected_summary = "Selected: %s (%s)" % [systems_by_id[selected_system_id].get("name", selected_system_id), selected_owner_name]

	info_label.text = "Seed: %s\nSystems: %d  Shape: %s  Hyperlanes: %d  Empires: %d\nActive Empire: %s  %s\nPan: WASD / Arrows / Edge / Middle Drag  Orbit: Right Drag  Zoom: Mouse Wheel  Pick Empire: E  Regenerate: R  Back: Esc" % [
		displayed_seed,
		system_positions.size(),
		galaxy_shape.capitalize(),
		hyperlane_density,
		empire_records.size(),
		active_empire_name,
		selected_summary,
	]


func _update_system_panel() -> void:
	var active_empire_name := "None selected"
	change_empire_button.text = "Choose Empire"
	claim_system_button.text = "Claim Selected System"
	claim_system_button.modulate = Color.WHITE

	if empires_by_id.has(active_empire_id):
		var active_empire: Dictionary = empires_by_id[active_empire_id]
		active_empire_name = str(active_empire.get("name", active_empire_name))
		change_empire_button.text = "Change Empire"
		claim_system_button.text = "Claim for %s" % active_empire_name
		claim_system_button.modulate = active_empire.get("color", Color.WHITE)

	empire_status_label.text = "Active Empire: %s" % active_empire_name

	if selected_system_id.is_empty() or not systems_by_id.has(selected_system_id):
		selected_system_title.text = "No system selected"
		selected_system_meta.text = "Left-click a star system to inspect it. Ownership is stored in galaxy state so it can be reused later for multiplayer, AI, and navigation."
		claim_system_button.disabled = active_empire_id.is_empty()
		clear_owner_button.disabled = true
		return

	var system_record: Dictionary = systems_by_id[selected_system_id]
	var owner_empire_id: String = galaxy_state.get_system_owner_id(selected_system_id)
	var owner_name := "Unclaimed"
	if empires_by_id.has(owner_empire_id):
		owner_name = str(empires_by_id[owner_empire_id].get("name", owner_name))

	var star_profile: Dictionary = system_record.get("star_profile", {})
	var neighbor_count: int = galaxy_state.get_neighbor_system_ids(selected_system_id).size()
	var star_count_label: int = int(star_profile.get("star_count", 1))
	var star_class: String = str(star_profile.get("star_class", "G"))

	selected_system_title.text = str(system_record.get("name", selected_system_id))
	selected_system_meta.text = "Owner: %s\nStar Class: %s  Stars: %d\nHyperlane Connections: %d" % [
		owner_name,
		star_class,
		star_count_label,
		neighbor_count,
	]
	claim_system_button.disabled = active_empire_id.is_empty() or owner_empire_id == active_empire_id
	clear_owner_button.disabled = owner_empire_id.is_empty()


func _populate_empire_picker() -> void:
	empire_picker_list.clear()

	for empire_index in range(empire_records.size()):
		var empire_record: Dictionary = empire_records[empire_index]
		var empire_id: String = str(empire_record.get("id", ""))
		var controller_kind: String = str(empire_record.get("controller_kind", "unassigned"))
		var item_text := "%s  [%s]" % [empire_record.get("name", empire_id), _format_controller_kind(controller_kind)]
		empire_picker_list.add_item(item_text)
		var item_index := empire_picker_list.get_item_count() - 1
		empire_picker_list.set_item_metadata(item_index, empire_id)
		empire_picker_list.set_item_custom_fg_color(item_index, empire_record.get("color", Color.WHITE))

		if empire_id == active_empire_id:
			empire_picker_list.select(item_index)

	select_empire_button.disabled = _get_selected_empire_id_from_picker().is_empty()
	cancel_empire_picker_button.visible = not _empire_picker_requires_selection
	cancel_empire_picker_button.disabled = _empire_picker_requires_selection


func _open_empire_picker(requires_selection: bool) -> void:
	_empire_picker_requires_selection = requires_selection
	_populate_empire_picker()
	_set_empire_picker_visible(true, requires_selection)


func _set_empire_picker_visible(visible_state: bool, requires_selection: bool = false) -> void:
	_empire_picker_requires_selection = requires_selection
	empire_picker_overlay.visible = visible_state
	cancel_empire_picker_button.visible = visible_state and not requires_selection
	cancel_empire_picker_button.disabled = requires_selection
	_refresh_camera_input_block()


func _set_loading_state(visible_state: bool, status_text: String = "", progress_ratio: float = 0.0) -> void:
	loading_overlay.visible = visible_state
	if not status_text.is_empty():
		loading_status.text = status_text
	loading_progress.value = clampf(progress_ratio, 0.0, 1.0) * 100.0
	_refresh_camera_input_block()


func _refresh_camera_input_block() -> void:
	if camera_rig.has_method("set_input_blocked"):
		camera_rig.set_input_blocked(_is_generating or loading_overlay.visible or empire_picker_overlay.visible)


func _pick_system_at_screen_position(screen_position: Vector2) -> String:
	var viewport_rect := get_viewport().get_visible_rect()
	var best_system_id := ""
	var best_distance_sq := SYSTEM_PICK_RADIUS * SYSTEM_PICK_RADIUS
	var best_camera_distance_sq := INF

	for system_record in system_records:
		var system_position: Vector3 = system_record.get("position", Vector3.ZERO)
		if camera.is_position_behind(system_position):
			continue

		var projected_position := camera.unproject_position(system_position)
		if not viewport_rect.has_point(projected_position):
			continue

		var screen_distance_sq := projected_position.distance_squared_to(screen_position)
		if screen_distance_sq > best_distance_sq:
			continue

		var camera_distance_sq := camera.global_position.distance_squared_to(system_position)
		if screen_distance_sq < best_distance_sq or (is_equal_approx(screen_distance_sq, best_distance_sq) and camera_distance_sq < best_camera_distance_sq):
			best_distance_sq = screen_distance_sq
			best_camera_distance_sq = camera_distance_sq
			best_system_id = str(system_record.get("id", ""))

	return best_system_id


func _is_pointer_over_gui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _build_glow_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STAR_GLOW_SHADER
	material.set_shader_parameter("fresnel_power", 2.4)
	material.set_shader_parameter("glow_strength", 1.5)
	material.set_shader_parameter("pulse_strength", 0.06)
	material.set_shader_parameter("pulse_speed", 0.95)
	material.set_shader_parameter("center_fill", 0.22)
	return material


func _build_ownership_fill_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.55
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_ownership_border_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.65
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _get_ownership_blob_radius() -> float:
	return maxf(min_system_distance * OWNERSHIP_BLOB_RADIUS_FACTOR, 42.0)


func _get_ownership_exclusion_radius() -> float:
	return maxf(min_system_distance * OWNERSHIP_EXCLUSION_RADIUS_FACTOR, 28.0)


func _get_ownership_connector_radius() -> float:
	return maxf(min_system_distance * OWNERSHIP_CONNECTOR_RADIUS_FACTOR, 18.0)


func _get_ownership_connection_distance() -> float:
	return maxf(min_system_distance * OWNERSHIP_CONNECTION_DISTANCE_FACTOR, 180.0)


func _get_ownership_border_half_width() -> float:
	return maxf(min_system_distance * OWNERSHIP_BORDER_WIDTH_FACTOR, 9.0)


func _get_region_height(systems_for_empire: Array) -> float:
	if systems_for_empire.is_empty():
		return 0.0

	var total_height: float = 0.0
	for system_variant in systems_for_empire:
		var system_record: Dictionary = system_variant
		total_height += float(system_record["position"].y)
	return total_height / float(systems_for_empire.size())


func _get_star_offset(star_index: int, system_star_count: int, orbit_radius: float) -> Vector3:
	if system_star_count <= 1:
		return Vector3.ZERO

	if system_star_count == 2:
		var direction := -1.0 if star_index == 0 else 1.0
		return Vector3(direction * orbit_radius, 0.0, 0.0)

	var angle := float(star_index) * TAU / float(system_star_count)
	return Vector3(cos(angle) * orbit_radius, 0.0, sin(angle) * orbit_radius)


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


func _get_selected_empire_id_from_picker() -> String:
	var selected_items := empire_picker_list.get_selected_items()
	if selected_items.size() == 0:
		return ""
	return str(empire_picker_list.get_item_metadata(int(selected_items[0])))


func _format_controller_kind(controller_kind: String) -> String:
	match controller_kind:
		"local_player":
			return "Local Player"
		"remote_player":
			return "Remote Player"
		"ai":
			return "AI"
		_:
			return "Open"


func _on_change_empire_pressed() -> void:
	_open_empire_picker(false)


func _on_claim_selected_system_pressed() -> void:
	if selected_system_id.is_empty() or active_empire_id.is_empty():
		return
	set_system_owner(selected_system_id, active_empire_id)


func _on_clear_owner_pressed() -> void:
	if selected_system_id.is_empty():
		return
	clear_system_owner(selected_system_id)


func _on_empire_picker_item_selected(_index: int) -> void:
	select_empire_button.disabled = _get_selected_empire_id_from_picker().is_empty()


func _on_empire_picker_item_activated(_index: int) -> void:
	_on_select_empire_pressed()


func _on_select_empire_pressed() -> void:
	var empire_id := _get_selected_empire_id_from_picker()
	if empire_id.is_empty():
		return
	assign_active_empire(empire_id)
	_set_empire_picker_visible(false, false)


func _on_cancel_empire_picker_pressed() -> void:
	if _empire_picker_requires_selection:
		return
	_set_empire_picker_visible(false, false)
