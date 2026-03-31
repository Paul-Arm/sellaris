extends Node3D
class_name GalaxyMapView

signal hovered_system_changed(system_id: String)
signal inspect_system_requested(system_id: String)
signal pinned_system_changed(system_id: String)

const GALAXY_MAP_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyMapRenderer.gd")
const STAR_CORE_SHADER: Shader = preload("res://scene/galaxy/StarCore.gdshader")
const STAR_GLOW_SHADER: Shader = preload("res://scene/galaxy/StarGlow.gdshader")
const SYSTEM_PICK_RADIUS: float = 26.0

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var stars: Node3D = $Stars
@onready var core_stars: MultiMeshInstance3D = $Stars/CoreStars
@onready var glow_stars: MultiMeshInstance3D = $Stars/GlowStars
@onready var ownership_markers: MeshInstance3D = $Stars/OwnershipMarkers
@onready var ownership_connectors: MeshInstance3D = $Stars/OwnershipConnectors
@onready var hyperlanes: MeshInstance3D = $Hyperlanes

var system_positions: Array[Vector3] = []
var system_records: Array[Dictionary] = []
var hyperlane_links: Array[Vector2i] = []
var empires_by_id: Dictionary = {}
var min_system_distance: float = 48.0
var ownership_bright_rim_enabled: bool = true
var ownership_core_opacity: float = 0.0
var pinned_system_id: String = ""
var _hovered_system_id: String = ""
var _map_renderer: RefCounted = GALAXY_MAP_RENDERER_SCRIPT.new()


func _ready() -> void:
	_map_renderer.bind(self, STAR_CORE_SHADER, STAR_GLOW_SHADER)


func _exit_tree() -> void:
	if _map_renderer != null:
		_map_renderer.unbind()


func sync_state(
	next_system_positions: Array[Vector3],
	next_system_records: Array[Dictionary],
	next_hyperlane_links: Array[Vector2i],
	next_empires_by_id: Dictionary,
	next_min_system_distance: float,
	next_ownership_bright_rim_enabled: bool,
	next_ownership_core_opacity: float,
	next_pinned_system_id: String
) -> void:
	system_positions = next_system_positions
	system_records = next_system_records
	hyperlane_links = next_hyperlane_links
	empires_by_id = next_empires_by_id
	min_system_distance = next_min_system_distance
	ownership_bright_rim_enabled = next_ownership_bright_rim_enabled
	ownership_core_opacity = next_ownership_core_opacity
	pinned_system_id = next_pinned_system_id


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


func set_camera_input_blocked(blocked: bool) -> void:
	if camera_rig != null and camera_rig.has_method("set_input_blocked"):
		camera_rig.set_input_blocked(blocked)


func set_galaxy_radius(radius: float) -> void:
	if camera_rig != null and camera_rig.has_method("set_galaxy_radius"):
		camera_rig.set_galaxy_radius(radius)


func reset_camera_view(galaxy_radius: float) -> void:
	if camera_rig != null and camera_rig.has_method("reset_view"):
		camera_rig.reset_view(galaxy_radius)


func _pick_system_at_screen_position(screen_position: Vector2) -> String:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var best_system_id: String = ""
	var best_distance_sq: float = SYSTEM_PICK_RADIUS * SYSTEM_PICK_RADIUS
	var best_camera_distance_sq: float = INF

	for system_record in system_records:
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
			best_system_id = str(system_record.get("id", ""))

	return best_system_id


func _is_pointer_over_gui() -> bool:
	return get_viewport().gui_get_hovered_control() != null
