extends RefCounted

var _host: Node3D = null


func bind(host: Node3D) -> void:
	_host = host


func unbind() -> void:
	_host = null


func sync_territory_settings_ui() -> void:
	if _host != null and _host.galaxy_hud != null:
		_host.galaxy_hud.set_territory_ui(_host.ownership_bright_rim_enabled, _host.ownership_core_opacity)


func sync_sim_clock_ui() -> void:
	if _host == null:
		return

	var current_speed: float = SimClock.sim_speed
	_host._sim_paused = current_speed <= 0.0
	if not _host._sim_paused:
		var best_index := 0
		var best_distance := INF
		for speed_index in range(_host._sim_speed_actual_steps.size()):
			var distance: float = absf(_host._sim_speed_actual_steps[speed_index] - current_speed)
			if distance < best_distance:
				best_distance = distance
				best_index = speed_index
		_host._sim_speed_index = best_index

	var current_date: Dictionary = SimClock.get_current_date()
	var date_text := "%04d-%02d-%02d" % [
		int(current_date.get("year", 0)),
		int(current_date.get("month", 0)),
		int(current_date.get("day", 0)),
	]
	var speed_value: float = _host._sim_speed_display_steps[_host._sim_speed_index]
	var speed_text := "Paused" if _host._sim_paused else "x%s" % format_speed_factor(speed_value)
	_host.galaxy_hud.set_sim_ui(date_text, speed_text, _host._sim_paused)
	if _host.galaxy_hud.has_method("set_active_empire"):
		_host.galaxy_hud.set_active_empire(_host.active_empire_id)


func format_speed_factor(speed_value: float) -> String:
	if is_equal_approx(speed_value, round(speed_value)):
		return str(int(round(speed_value)))
	return str(snappedf(speed_value, 0.1))


func on_close_settings_pressed() -> void:
	if _host != null:
		_host._set_settings_overlay_visible(false)


func on_territory_bright_rim_toggled(enabled: bool) -> void:
	if _host == null:
		return
	_host.ownership_bright_rim_enabled = enabled
	SettingsManager.set_territory_bright_rim(enabled)
	sync_territory_settings_ui()
	_host._render_ownership_markers()


func on_territory_core_opacity_changed(value: float) -> void:
	if _host == null:
		return
	_host.ownership_core_opacity = value
	SettingsManager.set_territory_core_opacity(value)
	sync_territory_settings_ui()
	_host._render_ownership_markers()


func on_sim_pause_pressed() -> void:
	if _host == null:
		return
	if _host._sim_paused:
		SimClock.set_sim_speed(_host._sim_speed_actual_steps[_host._sim_speed_index])
	else:
		SimClock.pause_sim()
	sync_sim_clock_ui()


func on_sim_speed_pressed() -> void:
	if _host == null:
		return
	_host._sim_speed_index = (_host._sim_speed_index + 1) % _host._sim_speed_actual_steps.size()
	SimClock.set_sim_speed(_host._sim_speed_actual_steps[_host._sim_speed_index])
	sync_sim_clock_ui()


func on_sim_day_tick(_date: Dictionary) -> void:
	sync_sim_clock_ui()


func on_sim_month_tick(_year: int, _month: int) -> void:
	sync_sim_clock_ui()


func on_sim_year_tick(_year: int) -> void:
	sync_sim_clock_ui()
