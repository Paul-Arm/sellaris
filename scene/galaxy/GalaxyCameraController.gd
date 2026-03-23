extends Node3D

const MIN_DISTANCE := 420.0
const MAX_DISTANCE := 6200.0
const MIN_TILT_DEGREES := -72.0
const MAX_TILT_DEGREES := -20.0

@export var pan_speed: float = 900.0
@export var zoom_step: float = 0.9
@export var edge_pan_margin: float = 28.0
@export var edge_pan_speed_multiplier: float = 1.15
@export var drag_pan_sensitivity: float = 1.0
@export var orbit_sensitivity: float = 0.35

@onready var camera: Camera3D = $Camera3D

var _is_middle_dragging: bool = false
var _is_right_dragging: bool = false
var _camera_distance: float = 1400.0
var _tilt_degrees: float = -34.0
var _yaw_degrees: float = 0.0


func reset_view(galaxy_radius: float) -> void:
	position = Vector3.ZERO
	_camera_distance = clamp(galaxy_radius * 0.7, MIN_DISTANCE, MAX_DISTANCE)
	_tilt_degrees = -34.0
	_yaw_degrees = 0.0
	_apply_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_middle_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_is_right_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = max(MIN_DISTANCE, _camera_distance * zoom_step)
			_apply_camera_transform()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = min(MAX_DISTANCE, _camera_distance / zoom_step)
			_apply_camera_transform()
	elif event is InputEventMouseMotion and _is_middle_dragging:
		_pan_from_mouse_drag(event.relative)
	elif event is InputEventMouseMotion and _is_right_dragging:
		_orbit_camera(event.relative)


func _process(delta: float) -> void:
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

	var visible_rect := viewport.get_visible_rect()
	var viewport_size := visible_rect.size
	if viewport_size.x <= edge_pan_margin * 2.0 or viewport_size.y <= edge_pan_margin * 2.0:
		return Vector2.ZERO

	var mouse_position := viewport.get_mouse_position()
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
	_tilt_degrees = clamp(_tilt_degrees - relative.y * orbit_sensitivity * 0.65, MIN_TILT_DEGREES, MAX_TILT_DEGREES)
	_apply_camera_transform()


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
