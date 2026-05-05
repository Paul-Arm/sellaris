extends Node
class_name GameSceneViewSystem

var _state: GameSceneState = null
var _ui: GameSceneRefs = null
var _view_router: GameViewRouter = null
var _scene_ui_controller: GameSceneUiController = null
var _runtime_system: GameSceneRuntimeSystem = null
var _debug_spawner: GalaxyDebugSpawner = null


func setup(
	state: GameSceneState,
	ui: GameSceneRefs,
	view_router: GameViewRouter,
	scene_ui_controller: GameSceneUiController,
	runtime_system: GameSceneRuntimeSystem,
	debug_spawner: GalaxyDebugSpawner
) -> void:
	_state = state
	_ui = ui
	_view_router = view_router
	_scene_ui_controller = scene_ui_controller
	_runtime_system = runtime_system
	_debug_spawner = debug_spawner


func teardown() -> void:
	_unbind_view_signals()
	_state = null
	_ui = null
	_view_router = null
	_scene_ui_controller = null
	_runtime_system = null
	_debug_spawner = null


func handle_unhandled_input(event: InputEvent) -> void:
	if _state == null or _ui == null:
		return

	if event.is_action_pressed("ui_cancel"):
		if _scene_ui_controller.is_colony_modal_visible():
			_scene_ui_controller.close_colony_modal()
			return
		if _ui.galaxy_hud.is_settings_visible():
			_scene_ui_controller.set_settings_overlay_visible(false)
			return
		if _ui.empire_picker_overlay.visible and not _state.empire_picker_requires_selection:
			_scene_ui_controller.set_empire_picker_visible(false, false)
			return
		if _view_router.is_system_view_open():
			var system_view: SystemView = _view_router.get_system_view()
			if system_view != null:
				system_view.handle_cancel_action()
			return
		if clear_current_selection():
			return
		_scene_ui_controller.set_settings_overlay_visible(true)
		return

	if _state.is_generating:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			Callable(_runtime_system, "generate_async").call_deferred()
			return
		if event.keycode == KEY_E:
			_scene_ui_controller.open_empire_picker(false)
			return
		if event.keycode == KEY_F9:
			_debug_spawner.toggle()
			return

	if _ui.empire_picker_overlay.visible:
		return

	if _scene_ui_controller.is_colony_modal_visible():
		return

	if _ui.galaxy_hud.is_settings_visible():
		return

	if _ui.bottom_category_bar.consume_hotkey_event(event):
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		Callable(_scene_ui_controller, "update_system_panel").call_deferred()

	_view_router.handle_active_view_input(event)


func bind_view_signals() -> void:
	if _view_router == null:
		return

	var galaxy_view: GalaxyMapView = _view_router.get_galaxy_view()
	if galaxy_view != null:
		if not galaxy_view.hovered_system_changed.is_connected(_on_galaxy_view_hovered_system_changed):
			galaxy_view.hovered_system_changed.connect(_on_galaxy_view_hovered_system_changed)
		if not galaxy_view.inspect_system_requested.is_connected(_on_galaxy_view_inspect_system_requested):
			galaxy_view.inspect_system_requested.connect(_on_galaxy_view_inspect_system_requested)
		if not galaxy_view.open_system_requested.is_connected(_on_galaxy_view_open_system_requested):
			galaxy_view.open_system_requested.connect(_on_galaxy_view_open_system_requested)
		if not galaxy_view.pinned_system_changed.is_connected(_on_galaxy_view_pinned_system_changed):
			galaxy_view.pinned_system_changed.connect(_on_galaxy_view_pinned_system_changed)
		if not galaxy_view.space_entity_selected.is_connected(_on_galaxy_view_space_entity_selected):
			galaxy_view.space_entity_selected.connect(_on_galaxy_view_space_entity_selected)
		if not galaxy_view.space_entity_move_requested.is_connected(_on_galaxy_view_space_entity_move_requested):
			galaxy_view.space_entity_move_requested.connect(_on_galaxy_view_space_entity_move_requested)

	if not _view_router.system_close_requested.is_connected(_scene_ui_controller.close_system_view):
		_view_router.system_close_requested.connect(_scene_ui_controller.close_system_view)


func _unbind_view_signals() -> void:
	if _view_router == null:
		return

	var galaxy_view: GalaxyMapView = _view_router.get_galaxy_view()
	if galaxy_view != null:
		if galaxy_view.hovered_system_changed.is_connected(_on_galaxy_view_hovered_system_changed):
			galaxy_view.hovered_system_changed.disconnect(_on_galaxy_view_hovered_system_changed)
		if galaxy_view.inspect_system_requested.is_connected(_on_galaxy_view_inspect_system_requested):
			galaxy_view.inspect_system_requested.disconnect(_on_galaxy_view_inspect_system_requested)
		if galaxy_view.open_system_requested.is_connected(_on_galaxy_view_open_system_requested):
			galaxy_view.open_system_requested.disconnect(_on_galaxy_view_open_system_requested)
		if galaxy_view.pinned_system_changed.is_connected(_on_galaxy_view_pinned_system_changed):
			galaxy_view.pinned_system_changed.disconnect(_on_galaxy_view_pinned_system_changed)
		if galaxy_view.space_entity_selected.is_connected(_on_galaxy_view_space_entity_selected):
			galaxy_view.space_entity_selected.disconnect(_on_galaxy_view_space_entity_selected)
		if galaxy_view.space_entity_move_requested.is_connected(_on_galaxy_view_space_entity_move_requested):
			galaxy_view.space_entity_move_requested.disconnect(_on_galaxy_view_space_entity_move_requested)

	if _view_router.system_close_requested.is_connected(_scene_ui_controller.close_system_view):
		_view_router.system_close_requested.disconnect(_scene_ui_controller.close_system_view)


func _on_galaxy_view_hovered_system_changed(system_id: String) -> void:
	_state.hovered_system_id = system_id
	_scene_ui_controller.update_info_label()


func _on_galaxy_view_inspect_system_requested(system_id: String) -> void:
	if system_id.is_empty():
		return
	_state.hovered_system_id = system_id
	_state.selected_system_id = system_id
	_state.selected_system_panel_id = system_id
	_clear_selected_space_entity()
	_scene_ui_controller.update_system_panel()
	_scene_ui_controller.update_info_label()


func _on_galaxy_view_open_system_requested(system_id: String) -> void:
	if system_id.is_empty():
		return
	_state.hovered_system_id = system_id
	_state.selected_system_id = system_id
	_state.selected_system_panel_id = system_id
	_clear_selected_space_entity()
	_scene_ui_controller.update_system_panel()
	_scene_ui_controller.update_info_label()
	if not _runtime_system.can_open_system_view(system_id):
		return
	_scene_ui_controller.open_system_view(system_id)


func _on_galaxy_view_pinned_system_changed(system_id: String) -> void:
	_state.pinned_system_id = system_id
	_state.hovered_system_id = system_id
	_runtime_system.render_stars()
	_scene_ui_controller.update_system_panel()
	_scene_ui_controller.update_info_label()


func _on_galaxy_view_space_entity_selected(selection_data: Dictionary) -> void:
	_state.selected_space_entity_kind = str(selection_data.get("selection_kind", ""))
	_state.selected_space_entity_id = str(selection_data.get("record_id", ""))
	_state.selected_space_entity_title = str(selection_data.get("title", ""))
	if not _state.selected_space_entity_id.is_empty():
		_state.selected_system_panel_id = ""
	_scene_ui_controller.update_selection_panel()
	_scene_ui_controller.update_system_panel()
	_scene_ui_controller.update_info_label()


func _on_galaxy_view_space_entity_move_requested(selection_data: Dictionary, destination_system_id: String) -> void:
	if _runtime_system.issue_space_entity_hyperlane_move(
		str(selection_data.get("selection_kind", "")),
		str(selection_data.get("record_id", "")),
		destination_system_id
	):
		_scene_ui_controller.update_system_panel()
		_scene_ui_controller.update_selection_panel()
		_scene_ui_controller.update_info_label()


func clear_current_selection() -> bool:
	if _state == null:
		return false
	var had_selection := not _state.selected_system_panel_id.is_empty() or not _state.selected_space_entity_id.is_empty()
	_state.selected_system_panel_id = ""
	_clear_selected_space_entity()
	var galaxy_view: GalaxyMapView = _view_router.get_galaxy_view()
	if galaxy_view != null:
		galaxy_view.set_selected_space_entity("", "")
	_scene_ui_controller.update_system_panel()
	_scene_ui_controller.update_selection_panel()
	_scene_ui_controller.update_info_label()
	return had_selection


func _clear_selected_space_entity() -> void:
	_state.selected_space_entity_kind = ""
	_state.selected_space_entity_id = ""
	_state.selected_space_entity_title = ""
