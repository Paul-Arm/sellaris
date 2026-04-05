extends RefCounted

var _host: Node = null


func bind(host: Node) -> void:
	_host = host


func unbind() -> void:
	_unbind_view_signals()
	_host = null


func handle_unhandled_input(event: InputEvent) -> void:
	if _host == null:
		return

	if event.is_action_pressed("ui_cancel"):
		if _host.galaxy_hud.is_settings_visible():
			_host._set_settings_overlay_visible(false)
			return
		if _host.empire_picker_overlay.visible and not _host._empire_picker_requires_selection:
			_host._set_empire_picker_visible(false, false)
			return
		if _host.is_system_view_open():
			var system_view: SystemView = _host.get_system_view()
			if system_view != null and system_view.handle_cancel_action():
				_host._close_system_view()
			return
		_host._set_settings_overlay_visible(true)
		return

	if _host._is_generating:
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

	_host._view_router.handle_active_view_input(event)


func bind_view_signals() -> void:
	if _host == null:
		return

	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view != null:
		if not galaxy_view.hovered_system_changed.is_connected(_on_galaxy_view_hovered_system_changed):
			galaxy_view.hovered_system_changed.connect(_on_galaxy_view_hovered_system_changed)
		if not galaxy_view.inspect_system_requested.is_connected(_on_galaxy_view_inspect_system_requested):
			galaxy_view.inspect_system_requested.connect(_on_galaxy_view_inspect_system_requested)
		if not galaxy_view.pinned_system_changed.is_connected(_on_galaxy_view_pinned_system_changed):
			galaxy_view.pinned_system_changed.connect(_on_galaxy_view_pinned_system_changed)

	if not _host._view_router.system_close_requested.is_connected(_host._close_system_view):
		_host._view_router.system_close_requested.connect(_host._close_system_view)


func _unbind_view_signals() -> void:
	if _host == null:
		return

	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view != null:
		if galaxy_view.hovered_system_changed.is_connected(_on_galaxy_view_hovered_system_changed):
			galaxy_view.hovered_system_changed.disconnect(_on_galaxy_view_hovered_system_changed)
		if galaxy_view.inspect_system_requested.is_connected(_on_galaxy_view_inspect_system_requested):
			galaxy_view.inspect_system_requested.disconnect(_on_galaxy_view_inspect_system_requested)
		if galaxy_view.pinned_system_changed.is_connected(_on_galaxy_view_pinned_system_changed):
			galaxy_view.pinned_system_changed.disconnect(_on_galaxy_view_pinned_system_changed)

	if _host._view_router != null and _host._view_router.system_close_requested.is_connected(_host._close_system_view):
		_host._view_router.system_close_requested.disconnect(_host._close_system_view)


func _on_galaxy_view_hovered_system_changed(system_id: String) -> void:
	_host.hovered_system_id = system_id
	_host._update_system_panel()
	_host._update_info_label()


func _on_galaxy_view_inspect_system_requested(system_id: String) -> void:
	if system_id.is_empty():
		return
	_host.hovered_system_id = system_id
	_host.selected_system_id = system_id
	_host._update_system_panel()
	_host._update_info_label()
	_host._open_system_view(system_id)


func _on_galaxy_view_pinned_system_changed(system_id: String) -> void:
	_host.pinned_system_id = system_id
	_host.hovered_system_id = system_id
	_host._render_stars()
	_host._update_system_panel()
	_host._update_info_label()
