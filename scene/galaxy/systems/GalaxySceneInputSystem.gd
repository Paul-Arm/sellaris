extends RefCounted

const SYSTEM_PICK_RADIUS := 26.0

var _host: Node3D = null


func bind(host: Node3D) -> void:
	_host = host


func unbind() -> void:
	_host = null


func handle_unhandled_input(event: InputEvent) -> void:
	if _host == null:
		return

	if event.is_action_pressed("ui_cancel"):
		if _host.system_view.is_open():
			if _host.system_view.handle_cancel_action():
				_host._close_system_view()
			return
		if _host.galaxy_hud.is_settings_visible():
			_host._set_settings_overlay_visible(false)
			return
		if _host.empire_picker_overlay.visible and not _host._empire_picker_requires_selection:
			_host._set_empire_picker_visible(false, false)
			return
		_host._set_settings_overlay_visible(true)
		return

	if _host._is_generating:
		return

	if _host.system_view.is_open():
		_host.system_view.handle_view_input(event)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_host.call_deferred("_generate_galaxy_async")
			return
		if event.keycode == KEY_E:
			_host._open_empire_picker(false)
			return
		if event.keycode == KEY_F9:
			_host._debug_spawner.toggle()
			return

	if _host.empire_picker_overlay.visible:
		return

	if _host.galaxy_hud.is_settings_visible():
		return

	if _host.bottom_category_bar.consume_hotkey_event(event):
		_host.get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		Callable(_host, "_update_system_panel").call_deferred()

	if event is InputEventMouseMotion:
		if is_pointer_over_gui():
			return
		if _host.pinned_system_id.is_empty():
			_host.hovered_system_id = pick_system_at_screen_position(event.position)
			_host._update_system_panel()
			_host._update_info_label()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_pointer_over_gui():
			return

		var clicked_system_id: String = pick_system_at_screen_position(event.position)
		if clicked_system_id.is_empty():
			return
		_host.hovered_system_id = clicked_system_id
		_host.selected_system_id = clicked_system_id
		_host._update_system_panel()
		_host._update_info_label()
		_host._open_system_view(clicked_system_id)
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if is_pointer_over_gui():
			return

		var pinned_system_id: String = pick_system_at_screen_position(event.position)
		_host.pinned_system_id = pinned_system_id
		_host.hovered_system_id = pinned_system_id
		_host._render_stars()
		_host._update_system_panel()
		_host._update_info_label()


func pick_system_at_screen_position(screen_position: Vector2) -> String:
	if _host == null:
		return ""

	var viewport_rect: Rect2 = _host.get_viewport().get_visible_rect()
	var best_system_id: String = ""
	var best_distance_sq: float = SYSTEM_PICK_RADIUS * SYSTEM_PICK_RADIUS
	var best_camera_distance_sq: float = INF

	for system_record in _host.system_records:
		var system_position: Vector3 = system_record.get("position", Vector3.ZERO)
		if _host.camera.is_position_behind(system_position):
			continue

		var projected_position: Vector2 = _host.camera.unproject_position(system_position)
		if not viewport_rect.has_point(projected_position):
			continue

		var screen_distance_sq: float = projected_position.distance_squared_to(screen_position)
		if screen_distance_sq > best_distance_sq:
			continue

		var camera_distance_sq: float = _host.camera.global_position.distance_squared_to(system_position)
		if screen_distance_sq < best_distance_sq or (is_equal_approx(screen_distance_sq, best_distance_sq) and camera_distance_sq < best_camera_distance_sq):
			best_distance_sq = screen_distance_sq
			best_camera_distance_sq = camera_distance_sq
			best_system_id = str(system_record.get("id", ""))

	return best_system_id


func is_pointer_over_gui() -> bool:
	if _host == null:
		return false
	return _host.get_viewport().gui_get_hovered_control() != null
