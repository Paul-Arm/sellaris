extends Node
class_name GameViewRouter

signal system_close_requested

const GALAXY_MAP_VIEW_SCENE: PackedScene = preload("res://scene/galaxy/GalaxyMapView.tscn")
const SYSTEM_VIEW_SCENE: PackedScene = preload("res://scene/StarSystem/SystemView.tscn")

var _view_root: Node = null
var _galaxy_view: GalaxyMapView = null
var _system_view: SystemView = null


func setup(view_root: Node) -> void:
	_view_root = view_root
	_ensure_views()
	show_galaxy_view()


func teardown() -> void:
	if _system_view != null and _system_view.close_requested.is_connected(_on_system_close_requested):
		_system_view.close_requested.disconnect(_on_system_close_requested)
	_view_root = null
	_galaxy_view = null
	_system_view = null


func get_galaxy_view() -> GalaxyMapView:
	return _galaxy_view


func get_system_view() -> SystemView:
	return _system_view


func is_system_view_open() -> bool:
	return _system_view != null and _system_view.is_open()


func get_current_system_view_id() -> String:
	if _system_view == null:
		return ""
	return _system_view.get_current_system_id()


func show_galaxy_view() -> void:
	_ensure_views()
	if _galaxy_view != null:
		_galaxy_view.visible = true
	if _system_view != null:
		_system_view.hide_view()


func show_system_view(system_details: Dictionary, neighbor_count: int) -> void:
	_ensure_views()
	if _galaxy_view != null:
		_galaxy_view.visible = false
	if _system_view != null:
		_system_view.show_system(system_details, neighbor_count)


func refresh_system_view(system_details: Dictionary, neighbor_count: int) -> void:
	if _system_view == null or not _system_view.is_open():
		return
	_system_view.show_system(system_details, neighbor_count)


func set_galaxy_camera_input_blocked(blocked: bool) -> void:
	if _galaxy_view != null:
		_galaxy_view.set_camera_input_blocked(blocked)


func handle_active_view_input(event: InputEvent) -> void:
	if is_system_view_open():
		_system_view.handle_view_input(event)
		return
	if _galaxy_view != null and _galaxy_view.visible:
		_galaxy_view.handle_view_input(event)


func _ensure_views() -> void:
	if _view_root == null:
		return

	if _galaxy_view == null:
		_galaxy_view = GALAXY_MAP_VIEW_SCENE.instantiate() as GalaxyMapView
		_view_root.add_child(_galaxy_view)

	if _system_view == null:
		_system_view = SYSTEM_VIEW_SCENE.instantiate() as SystemView
		_view_root.add_child(_system_view)
		_system_view.hide_view()
		if not _system_view.close_requested.is_connected(_on_system_close_requested):
			_system_view.close_requested.connect(_on_system_close_requested)


func _on_system_close_requested() -> void:
	system_close_requested.emit()
