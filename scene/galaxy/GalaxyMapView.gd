extends Node3D
class_name GalaxyMapView

signal hovered_system_changed(system_id: String)
signal inspect_system_requested(system_id: String)
signal open_system_requested(system_id: String)
signal pinned_system_changed(system_id: String)
signal space_entity_selected(selection_data: Dictionary)
signal space_entity_move_requested(selection_data: Dictionary, destination_system_id: String)

const GALAXY_MAP_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyMapRenderer.gd")
const GALAXY_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyRuntimePlaceholderRenderer.gd")
const STAR_CORE_SHADER: Shader = preload("res://scene/galaxy/StarCore.gdshader")
const STAR_GLOW_SHADER: Shader = preload("res://scene/galaxy/StarGlow.gdshader")
const SYSTEM_PICK_RADIUS: float = 26.0
const COMMAND_DESTINATION_PICK_RADIUS: float = 56.0
const SPACE_ENTITY_PICK_RADIUS: float = 30.0
const FLEET_ICON_HEIGHT: float = 13.0
const SPACE_ROUTE_HEIGHT: float = 9.0
const SPACE_ROUTE_DASH_LENGTH: float = 28.0
const SPACE_ROUTE_GAP_LENGTH: float = 18.0
const SELECTION_RING_SEGMENT_COUNT: int = 48
const BACKGROUND_MIN_EXTENT: float = 9000.0
const BACKGROUND_RADIUS_FACTOR: float = 3.8
const BACKGROUND_STAR_COUNT: int = 680
const BACKGROUND_NEBULA_SEGMENTS: int = 28
const BACKGROUND_NEBULA_FAR_CLOUD_COUNT: int = 74
const BACKGROUND_NEBULA_NEAR_CLOUD_COUNT: int = 48
const BACKGROUND_NEBULA_FAR_HEIGHT: float = -320.0
const BACKGROUND_NEBULA_NEAR_HEIGHT: float = -170.0
const BACKGROUND_STAR_HEIGHT: float = -280.0
const BACKGROUND_RANDOM_SEED: int = 421337

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var background_root: Node3D = $Background
@onready var background_nebula_far: MeshInstance3D = $Background/NebulaFar
@onready var background_nebula_near: MeshInstance3D = $Background/NebulaNear
@onready var background_starfield: MultiMeshInstance3D = $Background/Starfield
@onready var stars: Node3D = $Stars
@onready var star_backplates: MultiMeshInstance3D = $Stars/StarBackplates
@onready var core_stars: MultiMeshInstance3D = $Stars/CoreStars
@onready var glow_stars: MultiMeshInstance3D = $Stars/GlowStars
@onready var ownership_markers: MeshInstance3D = $Stars/OwnershipMarkers
@onready var ownership_connectors: MeshInstance3D = $Stars/OwnershipConnectors
@onready var hyperlanes: MeshInstance3D = $Hyperlanes
@onready var runtime_placeholders: Node3D = $RuntimePlaceholders
@onready var station_markers: MultiMeshInstance3D = $RuntimePlaceholders/StationMarkers
@onready var fleet_markers: MultiMeshInstance3D = $RuntimePlaceholders/FleetMarkers
@onready var ship_markers: MultiMeshInstance3D = $RuntimePlaceholders/ShipMarkers

var system_positions: Array[Vector3] = []
var system_records: Array[Dictionary] = []
var hyperlane_links: Array[Vector2i] = []
var empires_by_id: Dictionary = {}
var min_system_distance: float = 48.0
var ownership_bright_rim_enabled: bool = true
var ownership_core_opacity: float = 0.0
var pinned_system_id: String = ""
var system_intel_by_id: Dictionary = {}
var debug_reveal_galaxy: bool = false
var _hovered_system_id: String = ""
var _selected_space_entity_kind: String = ""
var _selected_space_entity_id: String = ""
var _space_selection_indicator: MeshInstance3D = null
var _space_route_indicator: MeshInstance3D = null
var _map_renderer: RefCounted = GALAXY_MAP_RENDERER_SCRIPT.new()
var _runtime_placeholder_renderer: RefCounted = GALAXY_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT.new()
var _nebula_extent: float = 0.0
var _background_time: float = 0.0


func _ready() -> void:
	_map_renderer.bind(self, STAR_CORE_SHADER, STAR_GLOW_SHADER)
	_runtime_placeholder_renderer.bind(self)
	_resize_background(0.0)


func _exit_tree() -> void:
	if _map_renderer != null:
		_map_renderer.unbind()
	if _runtime_placeholder_renderer != null:
		_runtime_placeholder_renderer.unbind()


func _process(delta: float) -> void:
	_background_time += delta
	_animate_background()


func sync_state(
	next_system_positions: Array[Vector3],
	next_system_records: Array[Dictionary],
	next_hyperlane_links: Array[Vector2i],
	next_empires_by_id: Dictionary,
	next_min_system_distance: float,
	next_ownership_bright_rim_enabled: bool,
	next_ownership_core_opacity: float,
	next_pinned_system_id: String,
	next_system_intel_by_id: Dictionary = {},
	next_debug_reveal_galaxy: bool = false
) -> void:
	system_positions = next_system_positions
	system_records = next_system_records
	hyperlane_links = next_hyperlane_links
	empires_by_id = next_empires_by_id
	min_system_distance = next_min_system_distance
	ownership_bright_rim_enabled = next_ownership_bright_rim_enabled
	ownership_core_opacity = next_ownership_core_opacity
	pinned_system_id = next_pinned_system_id
	system_intel_by_id = next_system_intel_by_id.duplicate(true)
	debug_reveal_galaxy = next_debug_reveal_galaxy
	_resize_background(0.0)
	_update_space_selection_indicator()
	_update_space_route_indicator()


func sync_interaction_state(hovered_system_id: String, next_pinned_system_id: String) -> void:
	_hovered_system_id = hovered_system_id
	pinned_system_id = next_pinned_system_id


func handle_view_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		if _is_pointer_over_gui():
			return
		if pinned_system_id.is_empty():
			var hovered_system_id: String = _pick_system_at_screen_position(event.position)
			if hovered_system_id != _hovered_system_id:
				_hovered_system_id = hovered_system_id
				render_stars()
				hovered_system_changed.emit(_hovered_system_id)
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_pointer_over_gui():
			return

		var clicked_entity: Dictionary = _pick_space_entity_at_screen_position(event.position)
		if not clicked_entity.is_empty():
			_select_space_entity(clicked_entity)
			return

		var clicked_system_id: String = _pick_system_at_screen_position(event.position)
		if clicked_system_id.is_empty():
			_clear_space_entity_selection()
			return
		_clear_space_entity_selection()
		_hovered_system_id = clicked_system_id
		hovered_system_changed.emit(clicked_system_id)
		if event.double_click:
			open_system_requested.emit(clicked_system_id)
		else:
			inspect_system_requested.emit(clicked_system_id)
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _is_pointer_over_gui():
			return

		var selected_entity: Dictionary = _get_selected_space_entity_data()
		var clicked_system_id: String = _pick_system_at_screen_position(
			event.position,
			COMMAND_DESTINATION_PICK_RADIUS if not selected_entity.is_empty() else SYSTEM_PICK_RADIUS
		)
		if not selected_entity.is_empty() and not clicked_system_id.is_empty():
			space_entity_move_requested.emit(selected_entity, clicked_system_id)
			_update_space_route_indicator()
			return

		pinned_system_id = clicked_system_id
		_hovered_system_id = clicked_system_id
		render_stars()
		hovered_system_changed.emit(clicked_system_id)
		pinned_system_changed.emit(clicked_system_id)


func render_stars() -> void:
	_map_renderer.render_stars()


func render_hyperlanes() -> void:
	_map_renderer.render_hyperlanes()


func render_ownership_markers() -> void:
	_map_renderer.render_ownership_markers()


func clear_rendered_map() -> void:
	star_backplates.multimesh = null
	core_stars.multimesh = null
	glow_stars.multimesh = null
	ownership_markers.mesh = null
	ownership_connectors.mesh = null
	hyperlanes.mesh = null
	clear_runtime_placeholders()


func render_runtime_placeholders() -> void:
	_runtime_placeholder_renderer.render_runtime_placeholders()
	_update_space_selection_indicator()
	_update_space_route_indicator()


func clear_runtime_placeholders() -> void:
	_runtime_placeholder_renderer.clear_runtime_placeholders()
	_update_space_selection_indicator()
	_update_space_route_indicator()


func set_selected_space_entity(selection_kind: String, record_id: String) -> void:
	_selected_space_entity_kind = selection_kind
	_selected_space_entity_id = record_id
	_update_space_selection_indicator()
	_update_space_route_indicator()


func set_camera_input_blocked(blocked: bool) -> void:
	if camera_rig != null and camera_rig.has_method("set_input_blocked"):
		camera_rig.set_input_blocked(blocked)


func is_middle_dragging() -> bool:
	return camera_rig != null and camera_rig.has_method("is_middle_dragging") and camera_rig.is_middle_dragging()


func set_galaxy_radius(radius: float) -> void:
	if camera_rig != null and camera_rig.has_method("set_galaxy_radius"):
		camera_rig.set_galaxy_radius(radius)
	_resize_background(radius)


func reset_camera_view(galaxy_radius: float) -> void:
	if camera_rig != null and camera_rig.has_method("reset_view"):
		camera_rig.reset_view(galaxy_radius)


func focus_camera_on_system(system_id: String) -> void:
	if camera_rig == null or not camera_rig.has_method("configure_view"):
		return
	for system_record in system_records:
		if str(system_record.get("id", "")) != system_id:
			continue
		var focus_position: Vector3 = system_record.get("position", Vector3.ZERO)
		camera_rig.configure_view(focus_position, maxf(min_system_distance * 18.0, 760.0))
		return


func is_system_visible_on_map(system_id: String) -> bool:
	return has_sensor_system_intel_on_map(system_id)


func is_system_hint_visible_on_map(system_id: String) -> bool:
	return not system_id.is_empty()


func has_sensor_system_intel_on_map(system_id: String) -> bool:
	return debug_reveal_galaxy or int(system_intel_by_id.get(system_id, GalaxyState.INTEL_NONE)) >= GalaxyState.INTEL_SENSOR


func has_full_system_intel_on_map(system_id: String) -> bool:
	return debug_reveal_galaxy or int(system_intel_by_id.get(system_id, GalaxyState.INTEL_NONE)) >= GalaxyState.INTEL_EXPLORED


func get_system_intel_level_on_map(system_id: String) -> int:
	if debug_reveal_galaxy:
		return GalaxyState.INTEL_SURVEYED
	return int(system_intel_by_id.get(system_id, GalaxyState.INTEL_NONE))


func get_hovered_system_id_on_map() -> String:
	return _hovered_system_id


func _pick_system_at_screen_position(screen_position: Vector2, pick_radius: float = SYSTEM_PICK_RADIUS) -> String:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var best_system_id: String = ""
	var best_distance_sq: float = pick_radius * pick_radius
	var best_camera_distance_sq: float = INF

	for system_record in system_records:
		var system_id: String = str(system_record.get("id", ""))
		if not is_system_hint_visible_on_map(system_id):
			continue
		var system_position: Vector3 = system_record.get("position", Vector3.ZERO)
		if camera.is_position_behind(system_position):
			continue

		var projected_position: Vector2 = camera.unproject_position(system_position)
		if not viewport_rect.has_point(projected_position):
			continue

		var screen_distance_sq: float = projected_position.distance_squared_to(screen_position)
		if screen_distance_sq > best_distance_sq:
			continue

		var camera_distance_sq: float = camera.global_position.distance_squared_to(system_position)
		if screen_distance_sq < best_distance_sq or (is_equal_approx(screen_distance_sq, best_distance_sq) and camera_distance_sq < best_camera_distance_sq):
			best_distance_sq = screen_distance_sq
			best_camera_distance_sq = camera_distance_sq
			best_system_id = system_id

	return best_system_id


func _pick_space_entity_at_screen_position(screen_position: Vector2) -> Dictionary:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var best_entity: Dictionary = {}
	var best_distance_sq: float = SPACE_ENTITY_PICK_RADIUS * SPACE_ENTITY_PICK_RADIUS

	for system_record in system_records:
		var system_id: String = str(system_record.get("id", ""))
		if not is_system_visible_on_map(system_id):
			continue
		var entity_position := _get_space_entity_marker_position(system_id)
		if camera.is_position_behind(entity_position):
			continue

		var projected_position: Vector2 = camera.unproject_position(entity_position)
		if not viewport_rect.grow(SPACE_ENTITY_PICK_RADIUS).has_point(projected_position):
			continue

		var distance_sq: float = projected_position.distance_squared_to(screen_position)
		if distance_sq > best_distance_sq:
			continue

		var entity_data: Dictionary = _get_primary_mobile_entity_in_system(system_id)
		if entity_data.is_empty():
			continue
		best_distance_sq = distance_sq
		best_entity = entity_data

	return best_entity


func _get_primary_mobile_entity_in_system(system_id: String) -> Dictionary:
	if system_id.is_empty():
		return {}

	for fleet_id in SpaceManager.get_fleet_ids_in_system(system_id):
		var fleet: SpaceFleetRuntime = SpaceManager.get_fleet(fleet_id)
		if fleet == null or fleet.unit_ids.is_empty():
			continue
		return {
			"selection_kind": "fleet",
			"record_id": fleet.fleet_id,
			"system_id": system_id,
			"title": fleet.display_name,
		}

	for unit_id in SpaceManager.get_unit_ids_in_system(system_id):
		var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
		if unit == null or unit.is_stationary() or not unit.fleet_id.is_empty():
			continue
		return {
			"selection_kind": SpaceUnitClass.UNIT_KIND_SHIP,
			"record_id": unit.unit_id,
			"system_id": system_id,
			"title": unit.display_name,
		}

	return {}


func _select_space_entity(selection_data: Dictionary) -> void:
	_selected_space_entity_kind = str(selection_data.get("selection_kind", ""))
	_selected_space_entity_id = str(selection_data.get("record_id", ""))
	_update_space_selection_indicator()
	_update_space_route_indicator()
	space_entity_selected.emit(selection_data.duplicate(true))


func _clear_space_entity_selection() -> void:
	if _selected_space_entity_id.is_empty() and _selected_space_entity_kind.is_empty():
		return
	_selected_space_entity_kind = ""
	_selected_space_entity_id = ""
	_update_space_selection_indicator()
	_update_space_route_indicator()
	space_entity_selected.emit({})


func _get_selected_space_entity_data() -> Dictionary:
	if _selected_space_entity_id.is_empty():
		return {}

	match _selected_space_entity_kind:
		"fleet":
			var fleet: SpaceFleetRuntime = SpaceManager.get_fleet(_selected_space_entity_id)
			if fleet == null:
				return {}
			return {
				"selection_kind": "fleet",
				"record_id": fleet.fleet_id,
				"system_id": fleet.current_system_id,
				"destination_system_id": fleet.destination_system_id,
				"title": fleet.display_name,
			}
		SpaceUnitClass.UNIT_KIND_SHIP, SpaceUnitClass.UNIT_KIND_CREATURE, "unit":
			var unit: SpaceUnitRuntime = SpaceManager.get_unit(_selected_space_entity_id)
			if unit == null:
				return {}
			return {
				"selection_kind": _selected_space_entity_kind,
				"record_id": unit.unit_id,
				"system_id": unit.current_system_id,
				"destination_system_id": unit.destination_system_id,
				"title": unit.display_name,
			}
		_:
			return {}


func _get_space_entity_marker_position(system_id: String) -> Vector3:
	var system_position: Vector3 = _get_system_position(system_id)
	return system_position + Vector3(0.0, FLEET_ICON_HEIGHT, 0.0)


func _get_system_position(system_id: String) -> Vector3:
	for system_record in system_records:
		if str(system_record.get("id", "")) == system_id:
			return system_record.get("position", Vector3.ZERO)
	return Vector3.ZERO


func _ensure_space_selection_indicator() -> void:
	if is_instance_valid(_space_selection_indicator):
		return
	if runtime_placeholders == null:
		return
	_space_selection_indicator = MeshInstance3D.new()
	_space_selection_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	runtime_placeholders.add_child(_space_selection_indicator)


func _ensure_space_route_indicator() -> void:
	if is_instance_valid(_space_route_indicator):
		return
	if runtime_placeholders == null:
		return
	_space_route_indicator = MeshInstance3D.new()
	_space_route_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	runtime_placeholders.add_child(_space_route_indicator)


func _update_space_selection_indicator() -> void:
	_ensure_space_selection_indicator()
	if _space_selection_indicator == null:
		return

	var selected_entity: Dictionary = _get_selected_space_entity_data()
	if selected_entity.is_empty():
		_space_selection_indicator.mesh = null
		return

	var marker_position: Vector3 = _get_space_entity_marker_position(str(selected_entity.get("system_id", "")))
	var radius := 9.0
	var color := Color(0.62, 0.9, 1.0, 0.95)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)
	for point_index in range(SELECTION_RING_SEGMENT_COUNT):
		var from_angle: float = float(point_index) * TAU / float(SELECTION_RING_SEGMENT_COUNT)
		var to_angle: float = float(point_index + 1) * TAU / float(SELECTION_RING_SEGMENT_COUNT)
		surface_tool.set_color(color)
		surface_tool.add_vertex(Vector3(cos(from_angle) * radius, 0.0, sin(from_angle) * radius))
		surface_tool.set_color(color)
		surface_tool.add_vertex(Vector3(cos(to_angle) * radius, 0.0, sin(to_angle) * radius))

	_space_selection_indicator.mesh = surface_tool.commit()
	_space_selection_indicator.position = marker_position
	_space_selection_indicator.material_override = _build_space_selection_material()


func _update_space_route_indicator() -> void:
	_ensure_space_route_indicator()
	if _space_route_indicator == null:
		return

	var selected_entity: Dictionary = _get_selected_space_entity_data()
	if selected_entity.is_empty():
		_space_route_indicator.mesh = null
		return

	var start_system_id: String = str(selected_entity.get("system_id", ""))
	var destination_system_id: String = str(selected_entity.get("destination_system_id", ""))
	if start_system_id.is_empty() or destination_system_id.is_empty() or start_system_id == destination_system_id:
		_space_route_indicator.mesh = null
		return

	var path: PackedStringArray = _find_hyperlane_path(start_system_id, destination_system_id)
	if path.size() < 2:
		_space_route_indicator.mesh = null
		return

	_space_route_indicator.mesh = _build_dotted_route_mesh(path, Color(0.62, 0.9, 1.0, 0.78))
	_space_route_indicator.position = Vector3.ZERO
	_space_route_indicator.material_override = _build_space_selection_material()


func _find_hyperlane_path(start_system_id: String, destination_system_id: String) -> PackedStringArray:
	var empty_path: PackedStringArray = PackedStringArray()
	if start_system_id.is_empty() or destination_system_id.is_empty():
		return empty_path
	if start_system_id == destination_system_id:
		var single_path: PackedStringArray = PackedStringArray()
		single_path.append(start_system_id)
		return single_path

	var visited: Dictionary = {}
	var came_from: Dictionary = {}
	var queue: Array[String] = [start_system_id]
	var read_index: int = 0
	visited[start_system_id] = true

	while read_index < queue.size():
		var current_system_id: String = queue[read_index]
		read_index += 1
		for neighbor_system_id in _get_hyperlane_neighbors(current_system_id):
			if visited.has(neighbor_system_id):
				continue
			visited[neighbor_system_id] = true
			came_from[neighbor_system_id] = current_system_id
			if neighbor_system_id == destination_system_id:
				return _reconstruct_hyperlane_path(start_system_id, destination_system_id, came_from)
			queue.append(neighbor_system_id)

	return empty_path


func _get_hyperlane_neighbors(system_id: String) -> Array[String]:
	var neighbors: Array[String] = []
	var system_index: int = _get_system_index_by_id(system_id)
	if system_index < 0:
		return neighbors

	for link in hyperlane_links:
		var neighbor_index: int = -1
		if link.x == system_index:
			neighbor_index = link.y
		elif link.y == system_index:
			neighbor_index = link.x
		if neighbor_index < 0 or neighbor_index >= system_records.size():
			continue
		var neighbor_id: String = str(system_records[neighbor_index].get("id", ""))
		if neighbor_id.is_empty():
			continue
		neighbors.append(neighbor_id)

	return neighbors


func _get_system_index_by_id(system_id: String) -> int:
	for system_index in range(system_records.size()):
		if str(system_records[system_index].get("id", "")) == system_id:
			return system_index
	return -1


func _reconstruct_hyperlane_path(start_system_id: String, destination_system_id: String, came_from: Dictionary) -> PackedStringArray:
	var reversed_path: Array[String] = [destination_system_id]
	var current_system_id: String = destination_system_id
	while current_system_id != start_system_id:
		if not came_from.has(current_system_id):
			return PackedStringArray()
		current_system_id = str(came_from[current_system_id])
		reversed_path.append(current_system_id)

	var path: PackedStringArray = PackedStringArray()
	for path_index in range(reversed_path.size() - 1, -1, -1):
		path.append(reversed_path[path_index])
	return path


func _build_dotted_route_mesh(path: PackedStringArray, color: Color) -> Mesh:
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)

	for path_index in range(path.size() - 1):
		var start_position: Vector3 = _get_system_position(path[path_index])
		var end_position: Vector3 = _get_system_position(path[path_index + 1])
		start_position.y = SPACE_ROUTE_HEIGHT
		end_position.y = SPACE_ROUTE_HEIGHT
		_append_dotted_segment(surface_tool, start_position, end_position, SPACE_ROUTE_DASH_LENGTH, SPACE_ROUTE_GAP_LENGTH, color)

	return surface_tool.commit()


func _append_dotted_segment(
	surface_tool: SurfaceTool,
	start_position: Vector3,
	end_position: Vector3,
	dash_length: float,
	gap_length: float,
	color: Color
) -> void:
	var offset: Vector3 = end_position - start_position
	var distance: float = offset.length()
	if distance <= 0.001:
		return
	var direction: Vector3 = offset / distance
	var cursor: float = 0.0
	while cursor < distance:
		var segment_end: float = minf(cursor + dash_length, distance)
		surface_tool.set_color(color)
		surface_tool.add_vertex(start_position + direction * cursor)
		surface_tool.set_color(color)
		surface_tool.add_vertex(start_position + direction * segment_end)
		cursor += dash_length + gap_length


func _build_space_selection_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.85
	return material


func _is_pointer_over_gui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _resize_background(radius: float) -> void:
	var target_radius: float = maxf(radius, _get_current_system_extent())
	var background_extent: float = maxf(target_radius * BACKGROUND_RADIUS_FACTOR, BACKGROUND_MIN_EXTENT)
	if is_equal_approx(background_extent, _nebula_extent):
		return
	_nebula_extent = background_extent
	_configure_environment_backdrop()
	_rebuild_background(background_extent)


func _configure_environment_backdrop() -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	environment.background_color = Color(0.012, 0.018, 0.04, 1.0)
	environment.ambient_light_color = Color(0.7, 0.76, 0.94, 1.0)
	environment.ambient_light_energy = 0.58
	environment.tonemap_exposure = 1.05
	environment.glow_enabled = true
	environment.glow_intensity = 0.13
	environment.glow_bloom = 0.06
	environment.volumetric_fog_enabled = false


func _rebuild_background(background_extent: float) -> void:
	if background_root != null:
		background_root.position = Vector3.ZERO
	_rebuild_nebula_layer(
		background_nebula_far,
		background_extent,
		BACKGROUND_RANDOM_SEED + 17,
		BACKGROUND_NEBULA_FAR_CLOUD_COUNT,
		BACKGROUND_NEBULA_FAR_HEIGHT,
		false
	)
	_rebuild_nebula_layer(
		background_nebula_near,
		background_extent,
		BACKGROUND_RANDOM_SEED + 83,
		BACKGROUND_NEBULA_NEAR_CLOUD_COUNT,
		BACKGROUND_NEBULA_NEAR_HEIGHT,
		true
	)
	_rebuild_background_starfield(background_extent)


func _animate_background() -> void:
	if _nebula_extent <= 0.0:
		return

	if background_nebula_far != null:
		var far_drift := _nebula_extent * 0.014
		background_nebula_far.rotation.y = _background_time * 0.009
		background_nebula_far.position = Vector3(
			sin(_background_time * 0.035) * far_drift,
			0.0,
			cos(_background_time * 0.029) * far_drift
		)
		var far_pulse := 1.0 + sin(_background_time * 0.11) * 0.018
		background_nebula_far.scale = Vector3(far_pulse, 1.0, far_pulse)
		var far_material := background_nebula_far.material_override as StandardMaterial3D
		if far_material != null:
			far_material.emission_energy_multiplier = 0.5 + sin(_background_time * 0.18) * 0.035

	if background_nebula_near != null:
		var near_drift := _nebula_extent * 0.021
		background_nebula_near.rotation.y = -_background_time * 0.014
		background_nebula_near.position = Vector3(
			cos(_background_time * 0.031 + 1.7) * near_drift,
			0.0,
			sin(_background_time * 0.037 + 0.8) * near_drift
		)
		var near_pulse := 1.0 + sin(_background_time * 0.15 + 0.9) * 0.024
		background_nebula_near.scale = Vector3(near_pulse, 1.0, near_pulse)
		var near_material := background_nebula_near.material_override as StandardMaterial3D
		if near_material != null:
			near_material.emission_energy_multiplier = 0.68 + sin(_background_time * 0.21 + 0.4) * 0.05

	if background_starfield != null:
		background_starfield.rotation.y = _background_time * 0.0018


func _rebuild_nebula_layer(
	target_layer: MeshInstance3D,
	background_extent: float,
	seed: int,
	cloud_count: int,
	height: float,
	is_near_layer: bool
) -> void:
	if target_layer == null:
		return

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + int(round(background_extent))
	var field_radius := background_extent * (0.54 if is_near_layer else 0.64)
	var cluster_radius := field_radius * (0.42 if is_near_layer else 0.48)
	var cluster_count := 5
	var clusters: Array[Vector2] = []

	for cluster_index in range(cluster_count):
		var cluster_angle := float(cluster_index) * TAU / float(cluster_count) + rng.randf_range(-0.42, 0.42)
		var cluster_distance := field_radius * rng.randf_range(0.12, 0.62)
		clusters.append(Vector2(cos(cluster_angle), sin(cluster_angle)) * cluster_distance)

	for cloud_index in range(cloud_count):
		var cluster := clusters[cloud_index % clusters.size()]
		var center := _get_nebula_cloud_center(rng, cluster, cluster_radius, field_radius)
		var distance_ratio := clampf(center.length() / maxf(field_radius, 1.0), 0.0, 1.0)
		var base_radius := background_extent * rng.randf_range(
			0.06 if is_near_layer else 0.078,
			0.155 if is_near_layer else 0.205
		)
		var aspect := rng.randf_range(0.48, 1.42)
		var radius_x := base_radius * maxf(aspect, 0.74)
		var radius_z := base_radius / maxf(aspect, 0.74)
		var cloud_color := _get_nebula_cloud_color(rng, is_near_layer, distance_ratio)
		var cloud_height := height + rng.randf_range(-32.0, 32.0)
		_append_nebula_puff(
			surface_tool,
			center,
			cloud_height,
			radius_x,
			radius_z,
			rng.randf_range(0.0, TAU),
			cloud_color
		)

	target_layer.mesh = surface_tool.commit()
	target_layer.material_override = _build_background_nebula_material(0.68 if is_near_layer else 0.5)
	target_layer.position = Vector3.ZERO
	target_layer.rotation = Vector3.ZERO
	target_layer.scale = Vector3.ONE


func _rebuild_background_starfield(background_extent: float) -> void:
	if background_starfield == null:
		return

	var star_mesh := SphereMesh.new()
	var star_radius := maxf(background_extent * 0.00042, 2.0)
	star_mesh.radius = star_radius
	star_mesh.height = star_radius * 2.0
	star_mesh.radial_segments = 6
	star_mesh.rings = 4

	var star_material := _build_background_star_material()
	star_mesh.material = star_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = star_mesh
	multimesh.instance_count = BACKGROUND_STAR_COUNT

	var rng := RandomNumberGenerator.new()
	rng.seed = BACKGROUND_RANDOM_SEED + int(round(background_extent))
	var starfield_radius := background_extent * 0.56

	for star_index in range(BACKGROUND_STAR_COUNT):
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = starfield_radius * sqrt(rng.randf())
		if rng.randf() < 0.28:
			radius = starfield_radius * rng.randf_range(0.58, 1.0)

		var star_position := Vector3(
			cos(angle) * radius,
			BACKGROUND_STAR_HEIGHT + rng.randf_range(-150.0, 90.0),
			sin(angle) * radius
		)
		var size_scale: float = rng.randf_range(0.55, 1.55)
		if rng.randf() < 0.08:
			size_scale *= rng.randf_range(1.7, 2.45)

		var basis := Basis().scaled(Vector3.ONE * size_scale)
		multimesh.set_instance_transform(star_index, Transform3D(basis, star_position))
		multimesh.set_instance_color(star_index, _get_background_star_color(rng))

	background_starfield.multimesh = multimesh
	background_starfield.material_override = star_material


func _get_nebula_cloud_center(
	rng: RandomNumberGenerator,
	cluster: Vector2,
	cluster_radius: float,
	field_radius: float
) -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var radius := cluster_radius * sqrt(rng.randf())
	var center := cluster + Vector2(cos(angle), sin(angle)) * radius
	if center.length() > field_radius:
		center = center.normalized() * field_radius * rng.randf_range(0.72, 0.98)
	return center


func _append_nebula_puff(
	surface_tool: SurfaceTool,
	center: Vector2,
	height: float,
	radius_x: float,
	radius_z: float,
	rotation: float,
	color: Color
) -> void:
	var center_color := color
	center_color.a *= 0.94
	var middle_color := color
	middle_color.a *= 0.56
	var edge_color := color
	edge_color.a = 0.0

	for segment_index in range(BACKGROUND_NEBULA_SEGMENTS):
		var next_index := (segment_index + 1) % BACKGROUND_NEBULA_SEGMENTS
		var angle_a := float(segment_index) * TAU / float(BACKGROUND_NEBULA_SEGMENTS)
		var angle_b := float(next_index) * TAU / float(BACKGROUND_NEBULA_SEGMENTS)
		var center_point := Vector3(center.x, height, center.y)
		var mid_a_2d := _get_nebula_ellipse_point(center, radius_x * 0.42, radius_z * 0.42, angle_a, rotation)
		var mid_b_2d := _get_nebula_ellipse_point(center, radius_x * 0.42, radius_z * 0.42, angle_b, rotation)
		var edge_a_2d := _get_nebula_ellipse_point(center, radius_x, radius_z, angle_a, rotation)
		var edge_b_2d := _get_nebula_ellipse_point(center, radius_x, radius_z, angle_b, rotation)
		var mid_a := Vector3(mid_a_2d.x, height, mid_a_2d.y)
		var mid_b := Vector3(mid_b_2d.x, height, mid_b_2d.y)
		var edge_a := Vector3(edge_a_2d.x, height, edge_a_2d.y)
		var edge_b := Vector3(edge_b_2d.x, height, edge_b_2d.y)

		surface_tool.set_color(center_color)
		surface_tool.add_vertex(center_point)
		surface_tool.set_color(middle_color)
		surface_tool.add_vertex(mid_a)
		surface_tool.set_color(middle_color)
		surface_tool.add_vertex(mid_b)

		_append_background_gradient_quad(
			surface_tool,
			mid_a,
			edge_a,
			edge_b,
			mid_b,
			middle_color,
			edge_color,
			edge_color,
			middle_color
		)


func _get_nebula_ellipse_point(
	center: Vector2,
	radius_x: float,
	radius_z: float,
	angle: float,
	rotation: float
) -> Vector2:
	var local := Vector2(cos(angle) * radius_x, sin(angle) * radius_z)
	var cos_rotation := cos(rotation)
	var sin_rotation := sin(rotation)
	return center + Vector2(
		local.x * cos_rotation - local.y * sin_rotation,
		local.x * sin_rotation + local.y * cos_rotation
	)


func _get_nebula_cloud_color(rng: RandomNumberGenerator, is_near_layer: bool, distance_ratio: float) -> Color:
	var palette: Array[Color] = [
		Color(0.24, 0.58, 0.76, 1.0),
		Color(0.54, 0.28, 0.64, 1.0),
		Color(0.3, 0.62, 0.52, 1.0),
		Color(0.82, 0.48, 0.28, 1.0),
		Color(0.45, 0.54, 0.86, 1.0),
	]
	var base_color: Color = palette[rng.randi_range(0, palette.size() - 1)]
	var mix_color: Color = palette[rng.randi_range(0, palette.size() - 1)]
	var color := base_color.lerp(mix_color, rng.randf_range(0.0, 0.38))
	var alpha_base := 0.085 if is_near_layer else 0.063
	color.a = alpha_base * lerpf(1.05, 0.46, distance_ratio) * rng.randf_range(0.72, 1.18)
	return color


func _append_background_gradient_quad(
	surface_tool: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	color_a: Color,
	color_b: Color,
	color_c: Color,
	color_d: Color
) -> void:
	surface_tool.set_color(color_a)
	surface_tool.add_vertex(a)
	surface_tool.set_color(color_b)
	surface_tool.add_vertex(b)
	surface_tool.set_color(color_c)
	surface_tool.add_vertex(c)
	surface_tool.set_color(color_a)
	surface_tool.add_vertex(a)
	surface_tool.set_color(color_c)
	surface_tool.add_vertex(c)
	surface_tool.set_color(color_d)
	surface_tool.add_vertex(d)


func _get_background_star_color(rng: RandomNumberGenerator) -> Color:
	var color_roll := rng.randf()
	var color := Color(0.78, 0.9, 1.0, 1.0)
	if color_roll < 0.18:
		color = Color(1.0, 0.86, 0.58, 1.0)
	elif color_roll < 0.32:
		color = Color(1.0, 0.64, 0.7, 1.0)
	elif color_roll < 0.56:
		color = Color(0.58, 0.86, 1.0, 1.0)
	color.a = rng.randf_range(0.38, 0.86)
	return color


func _build_background_nebula_material(emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = emission_energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material


func _build_background_star_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.2
	return material


func _get_current_system_extent() -> float:
	var extent: float = 0.0
	for system_position in system_positions:
		extent = maxf(extent, Vector2(system_position.x, system_position.z).length())
	return extent
