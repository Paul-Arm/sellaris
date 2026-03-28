extends Node3D

@export var min_distance: float = 420.0
@export var max_distance: float = 6200.0
@export var min_tilt_degrees: float = -72.0
@export var max_tilt_degrees: float = -20.0
@export var pan_speed: float = 900.0
@export var zoom_step: float = 0.9
@export var edge_pan_margin: float = 28.0
@export var edge_pan_speed_multiplier: float = 1.15
@export var drag_pan_sensitivity: float = 1.0
@export var orbit_sensitivity: float = 0.35
@export_range(0.0, 0.95, 0.05) var max_outside_screen_ratio: float = 0.8

@onready var camera: Camera3D = $Camera3D

var _is_middle_dragging: bool = false
var _is_right_dragging: bool = false
var _camera_distance: float = 1400.0
var _tilt_degrees: float = -34.0
var _yaw_degrees: float = 0.0
var _input_blocked: bool = false
var _window_focused: bool = true
var _galaxy_radius: float = 3000.0


func _ready() -> void:
	_window_focused = DisplayServer.window_is_focused()


func set_input_blocked(blocked: bool) -> void:
	_input_blocked = blocked
	if blocked:
		_stop_camera_gestures()


func set_galaxy_radius(radius: float) -> void:
	_galaxy_radius = maxf(radius, 0.0)
	_enforce_camera_limits()


func reset_view(galaxy_radius: float) -> void:
	_galaxy_radius = maxf(galaxy_radius, 0.0)
	configure_view(Vector3.ZERO, _galaxy_radius * 0.7)


func configure_view(focus_position: Vector3, distance: float, tilt_degrees: float = -34.0, yaw_degrees: float = 0.0) -> void:
	position = focus_position
	_camera_distance = clampf(distance, min_distance, max_distance)
	_tilt_degrees = clamp(tilt_degrees, min_tilt_degrees, max_tilt_degrees)
	_yaw_degrees = yaw_degrees
	_enforce_camera_limits()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_process_camera_input():
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_middle_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_is_right_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = clampf(_camera_distance * zoom_step, min_distance, max_distance)
			_enforce_camera_limits()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = clampf(_camera_distance / zoom_step, min_distance, max_distance)
			_enforce_camera_limits()
	elif event is InputEventMouseMotion and _is_middle_dragging:
		_pan_from_mouse_drag(event.relative)
	elif event is InputEventMouseMotion and _is_right_dragging:
		_orbit_camera(event.relative)


func _process(delta: float) -> void:
	if not _can_process_camera_input():
		return

	var move_input := _get_keyboard_input()
	move_input += _get_edge_pan_input()

	if move_input != Vector2.ZERO:
		move_input = move_input.normalized()
		_translate_on_galaxy_plane(move_input.x * pan_speed * delta, -move_input.y * pan_speed * delta)


func _pan_from_mouse_drag(relative: Vector2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return

	var world_units_per_pixel := (_camera_distance * 1.25) / viewport_size.y
	_translate_on_galaxy_plane(
		-relative.x * world_units_per_pixel * drag_pan_sensitivity,
		relative.y * world_units_per_pixel * drag_pan_sensitivity
	)


func _get_keyboard_input() -> Vector2:
	var move_input := Vector2.ZERO

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_input.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_input.y += 1.0

	return move_input


func _get_edge_pan_input() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	if viewport.gui_get_hovered_control() != null:
		return Vector2.ZERO

	var visible_rect := viewport.get_visible_rect()
	var viewport_size := visible_rect.size
	if viewport_size.x <= edge_pan_margin * 2.0 or viewport_size.y <= edge_pan_margin * 2.0:
		return Vector2.ZERO

	var mouse_position := viewport.get_mouse_position()
	if not visible_rect.has_point(mouse_position):
		return Vector2.ZERO

	var move_input := Vector2.ZERO

	if mouse_position.x <= edge_pan_margin:
		move_input.x -= inverse_lerp(edge_pan_margin, 0.0, mouse_position.x)
	elif mouse_position.x >= viewport_size.x - edge_pan_margin:
		move_input.x += inverse_lerp(viewport_size.x - edge_pan_margin, viewport_size.x, mouse_position.x)

	if mouse_position.y <= edge_pan_margin:
		move_input.y -= inverse_lerp(edge_pan_margin, 0.0, mouse_position.y)
	elif mouse_position.y >= viewport_size.y - edge_pan_margin:
		move_input.y += inverse_lerp(viewport_size.y - edge_pan_margin, viewport_size.y, mouse_position.y)

	return move_input * edge_pan_speed_multiplier


func _orbit_camera(relative: Vector2) -> void:
	_yaw_degrees -= relative.x * orbit_sensitivity
	_tilt_degrees = clamp(_tilt_degrees - relative.y * orbit_sensitivity * 0.65, min_tilt_degrees, max_tilt_degrees)
	_enforce_camera_limits()


func _apply_camera_transform() -> void:
	var yaw_basis := Basis(Vector3.UP, deg_to_rad(_yaw_degrees))
	var tilt_basis := Basis(Vector3.RIGHT, deg_to_rad(_tilt_degrees))
	var camera_basis := yaw_basis * tilt_basis
	camera.transform = Transform3D(camera_basis, camera_basis * Vector3(0.0, 0.0, _camera_distance))


func _translate_on_galaxy_plane(right_amount: float, forward_amount: float) -> void:
	var right_dir := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z)
	var forward_dir := Vector3(-camera.global_basis.z.x, 0.0, -camera.global_basis.z.z)

	if right_dir.length_squared() > 0.0:
		right_dir = right_dir.normalized()
	if forward_dir.length_squared() > 0.0:
		forward_dir = forward_dir.normalized()

	position += right_dir * right_amount
	position += forward_dir * forward_amount
	_clamp_focus_position()


func _can_process_camera_input() -> bool:
	_refresh_window_focus_state()
	return not _input_blocked and _window_focused


func _refresh_window_focus_state() -> void:
	var is_focused := DisplayServer.window_is_focused()
	if is_focused == _window_focused:
		return

	_window_focused = is_focused
	if not _window_focused:
		_stop_camera_gestures()


func _stop_camera_gestures() -> void:
	_is_middle_dragging = false
	_is_right_dragging = false


func _enforce_camera_limits() -> void:
	_camera_distance = clampf(_camera_distance, min_distance, max_distance)
	_apply_camera_transform()
	_clamp_focus_position()


func _clamp_focus_position() -> void:
	var planar_position := Vector3(position.x, 0.0, position.z)
	if _galaxy_radius <= 0.0 or planar_position.length_squared() <= 0.0001:
		position = Vector3(planar_position.x, 0.0, planar_position.z)
		return

	var visible_plane_points := _get_visible_plane_points()
	if visible_plane_points.is_empty():
		position = Vector3(planar_position.x, 0.0, planar_position.z)
		return

	var outward_direction := planar_position.normalized()
	var inward_extent := 0.0
	var outward_extent := 0.0

	for plane_point in visible_plane_points:
		var projection := (plane_point - planar_position).dot(outward_direction)
		if projection < 0.0:
			inward_extent = maxf(inward_extent, -projection)
		else:
			outward_extent = maxf(outward_extent, projection)

	var visible_span := inward_extent + outward_extent
	if visible_span <= 0.0:
		position = Vector3(planar_position.x, 0.0, planar_position.z)
		return

	var required_inside_span := visible_span * (1.0 - max_outside_screen_ratio)
	var max_center_distance := maxf(0.0, _galaxy_radius + inward_extent - required_inside_span)
	if planar_position.length() > max_center_distance:
		planar_position = planar_position.normalized() * max_center_distance

	position = Vector3(planar_position.x, 0.0, planar_position.z)


func _get_visible_plane_points() -> Array[Vector3]:
	var viewport := get_viewport()
	if viewport == null:
		return []

	var visible_rect := viewport.get_visible_rect()
	var viewport_size := visible_rect.size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return []

	var sample_margin_ratio := (1.0 - max_outside_screen_ratio) * 0.5
	var margin_x := viewport_size.x * sample_margin_ratio
	var margin_y := viewport_size.y * sample_margin_ratio
	var sample_points: Array[Vector2] = [
		Vector2(margin_x, margin_y),
		Vector2(viewport_size.x - margin_x, margin_y),
		Vector2(viewport_size.x - margin_x, viewport_size.y - margin_y),
		Vector2(margin_x, viewport_size.y - margin_y),
	]
	var plane_points: Array[Vector3] = []

	for screen_point in sample_points:
		var ray_origin := camera.project_ray_origin(screen_point)
		var ray_direction := camera.project_ray_normal(screen_point)
		if is_zero_approx(ray_direction.y):
			return []

		var distance_to_plane := -ray_origin.y / ray_direction.y
		if distance_to_plane <= 0.0:
			return []

		plane_points.append(ray_origin + ray_direction * distance_to_plane)

	return plane_points
