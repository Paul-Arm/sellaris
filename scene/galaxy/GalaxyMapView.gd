extends Node3D
class_name GalaxyMapView

signal hovered_system_changed(system_id: String)
signal inspect_system_requested(system_id: String)
signal pinned_system_changed(system_id: String)

const GALAXY_MAP_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyMapRenderer.gd")
const GALAXY_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyRuntimePlaceholderRenderer.gd")
const STAR_CORE_SHADER: Shader = preload("res://scene/galaxy/StarCore.gdshader")
const STAR_GLOW_SHADER: Shader = preload("res://scene/galaxy/StarGlow.gdshader")
const SYSTEM_PICK_RADIUS: float = 26.0
const BACKGROUND_MIN_EXTENT: float = 9000.0
const BACKGROUND_RADIUS_FACTOR: float = 3.8

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var galaxy_fog_volume: Node = get_node_or_null("WorldEnvironment/FogVolume")
@onready var stars: Node3D = $Stars
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
var _map_renderer: RefCounted = GALAXY_MAP_RENDERER_SCRIPT.new()
var _runtime_placeholder_renderer: RefCounted = GALAXY_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT.new()
var _nebula_extent: float = 0.0


func _ready() -> void:
	_map_renderer.bind(self, STAR_CORE_SHADER, STAR_GLOW_SHADER)
	_runtime_placeholder_renderer.bind(self)
	_resize_background(0.0)


func _exit_tree() -> void:
	if _map_renderer != null:
		_map_renderer.unbind()
	if _runtime_placeholder_renderer != null:
		_runtime_placeholder_renderer.unbind()


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

		var clicked_system_id: String = _pick_system_at_screen_position(event.position)
		if clicked_system_id.is_empty():
			return
		_hovered_system_id = clicked_system_id
		hovered_system_changed.emit(clicked_system_id)
		inspect_system_requested.emit(clicked_system_id)
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _is_pointer_over_gui():
			return

		var clicked_system_id: String = _pick_system_at_screen_position(event.position)
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
	core_stars.multimesh = null
	glow_stars.multimesh = null
	ownership_markers.mesh = null
	ownership_connectors.mesh = null
	hyperlanes.mesh = null
	clear_runtime_placeholders()


func render_runtime_placeholders() -> void:
	_runtime_placeholder_renderer.render_runtime_placeholders()


func clear_runtime_placeholders() -> void:
	_runtime_placeholder_renderer.clear_runtime_placeholders()


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


func _pick_system_at_screen_position(screen_position: Vector2) -> String:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var best_system_id: String = ""
	var best_distance_sq: float = SYSTEM_PICK_RADIUS * SYSTEM_PICK_RADIUS
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


func _is_pointer_over_gui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _resize_background(radius: float) -> void:
	var target_radius: float = maxf(radius, _get_current_system_extent())
	var background_extent: float = maxf(target_radius * BACKGROUND_RADIUS_FACTOR, BACKGROUND_MIN_EXTENT)
	if is_equal_approx(background_extent, _nebula_extent):
		return
	_nebula_extent = background_extent
	_configure_environment_fog()
	_configure_galaxy_fog_volume(background_extent)


func _configure_environment_fog() -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.0
	environment.volumetric_fog_length = maxf(_nebula_extent * 1.35, 12000.0)
	environment.volumetric_fog_albedo = Color(0.18, 0.24, 0.38, 1.0)
	environment.volumetric_fog_emission = Color(0.015, 0.035, 0.07, 1.0)
	environment.volumetric_fog_emission_energy = 0.32


func _configure_galaxy_fog_volume(background_extent: float) -> void:
	if galaxy_fog_volume == null or not ClassDB.class_exists("FogMaterial"):
		return

	var fog_material: Resource = galaxy_fog_volume.get("material") as Resource
	if fog_material == null:
		fog_material = ClassDB.instantiate("FogMaterial") as Resource
		galaxy_fog_volume.set("material", fog_material)
	if fog_material == null:
		return

	galaxy_fog_volume.set("shape", 4)
	galaxy_fog_volume.set("size", Vector3.ONE * background_extent)
	fog_material.set("albedo", Color(0.16, 0.24, 0.42, 1.0))
	fog_material.set("emission", Color(0.025, 0.055, 0.12, 1.0))
	fog_material.set("density", 0.0018)
	fog_material.set("height_falloff", 0.0)
	fog_material.set("edge_fade", 0.0)


func _get_current_system_extent() -> float:
	var extent: float = 0.0
	for system_position in system_positions:
		extent = maxf(extent, Vector2(system_position.x, system_position.z).length())
	return extent
