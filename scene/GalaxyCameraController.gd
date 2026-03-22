extends Node3D

const MIN_ZOOM := 220.0
const MAX_ZOOM := 5200.0

@export var pan_speed: float = 900.0
@export var zoom_step: float = 0.9
@export var edge_pan_margin: float = 28.0
@export var edge_pan_speed_multiplier: float = 1.15
@export var drag_pan_sensitivity: float = 1.0

@onready var camera: Camera3D = $Camera3D

var _is_middle_dragging: bool = false


func reset_view(galaxy_radius: float) -> void:
	position = Vector3.ZERO
	camera.size = clamp(galaxy_radius * 0.65, MIN_ZOOM, MAX_ZOOM)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_middle_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = max(MIN_ZOOM, camera.size * zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = min(MAX_ZOOM, camera.size / zoom_step)
	elif event is InputEventMouseMotion and _is_middle_dragging:
		_pan_from_mouse_drag(event.relative)


func _process(delta: float) -> void:
	var move_input := _get_keyboard_input()
	move_input += _get_edge_pan_input()

	if move_input != Vector2.ZERO:
		move_input = move_input.normalized()
		position.x += move_input.x * pan_speed * delta
		position.z += move_input.y * pan_speed * delta


func _pan_from_mouse_drag(relative: Vector2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return

	var world_units_per_pixel := (camera.size * 2.0) / viewport_size.y
	position.x -= relative.x * world_units_per_pixel * drag_pan_sensitivity
	position.z -= relative.y * world_units_per_pixel * drag_pan_sensitivity


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
