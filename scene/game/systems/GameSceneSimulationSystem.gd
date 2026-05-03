extends Node
class_name GameSceneSimulationSystem

var _state: GameSceneState = null
var _ui: GameSceneRefs = null
var _runtime_system: GameSceneRuntimeSystem = null
var _scene_ui_controller: GameSceneUiController = null


func setup(
	state: GameSceneState,
	ui: GameSceneRefs,
	runtime_system: GameSceneRuntimeSystem,
	scene_ui_controller: GameSceneUiController
) -> void:
	_state = state
	_ui = ui
	_runtime_system = runtime_system
	_scene_ui_controller = scene_ui_controller


func teardown() -> void:
	_state = null
	_ui = null
	_runtime_system = null
	_scene_ui_controller = null


func sync_territory_settings_ui() -> void:
	if _ui != null and _ui.galaxy_hud != null:
		_ui.galaxy_hud.set_territory_ui(_state.ownership_bright_rim_enabled, _state.ownership_core_opacity)


func sync_sim_clock_ui() -> void:
	if _state == null or _ui == null:
		return

	var current_speed: float = SimClock.sim_speed
	_state.sim_paused = current_speed <= 0.0
	if not _state.sim_paused:
		var best_index: int = 0
		var best_distance: float = INF
		for speed_index in range(_state.sim_speed_actual_steps.size()):
			var distance: float = absf(_state.sim_speed_actual_steps[speed_index] - current_speed)
			if distance < best_distance:
				best_distance = distance
				best_index = speed_index
		_state.sim_speed_index = best_index

	var current_date: Dictionary = SimClock.get_current_date()
	var date_text: String = "%04d-%02d-%02d" % [
		int(current_date.get("year", 0)),
		int(current_date.get("month", 0)),
		int(current_date.get("day", 0)),
	]
	var speed_value: float = _state.sim_speed_display_steps[_state.sim_speed_index]
	var speed_text: String = "Paused" if _state.sim_paused else "x%s" % format_speed_factor(speed_value)
	_ui.galaxy_hud.set_sim_ui(date_text, speed_text, _state.sim_paused)
	if _ui.galaxy_hud.has_method("set_active_empire"):
		_ui.galaxy_hud.set_active_empire(_state.active_empire_id)


func format_speed_factor(speed_value: float) -> String:
	if is_equal_approx(speed_value, round(speed_value)):
		return str(int(round(speed_value)))
	return str(snappedf(speed_value, 0.1))


func on_close_settings_pressed() -> void:
	if _scene_ui_controller != null:
		_scene_ui_controller.set_settings_overlay_visible(false)


func on_territory_bright_rim_toggled(enabled: bool) -> void:
	if _state == null:
		return
	_state.ownership_bright_rim_enabled = enabled
	SettingsManager.set_territory_bright_rim(enabled)
	sync_territory_settings_ui()
	_runtime_system.render_ownership_markers()


func on_territory_core_opacity_changed(value: float) -> void:
	if _state == null:
		return
	_state.ownership_core_opacity = value
	SettingsManager.set_territory_core_opacity(value)
	sync_territory_settings_ui()
	_runtime_system.render_ownership_markers()


func on_sim_pause_pressed() -> void:
	if _state == null:
		return
	if _state.sim_paused:
		SimClock.set_sim_speed(_state.sim_speed_actual_steps[_state.sim_speed_index])
	else:
		SimClock.pause_sim()
	sync_sim_clock_ui()


func on_sim_speed_pressed() -> void:
	if _state == null:
		return
	_state.sim_speed_index = (_state.sim_speed_index + 1) % _state.sim_speed_actual_steps.size()
	SimClock.set_sim_speed(_state.sim_speed_actual_steps[_state.sim_speed_index])
	sync_sim_clock_ui()


func on_sim_day_tick(_date: Dictionary) -> void:
	sync_sim_clock_ui()


func on_sim_month_tick(_year: int, _month: int) -> void:
	sync_sim_clock_ui()


func on_sim_year_tick(_year: int) -> void:
	sync_sim_clock_ui()
