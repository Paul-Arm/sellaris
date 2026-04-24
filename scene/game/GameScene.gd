extends Node

const GALAXY_DEBUG_SPAWNER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyDebugSpawner.gd")
const GALAXY_HUD_MUSIC_CONTROLLER_SCRIPT: Script = preload("res://scene/UI/GalaxyHudMusicController.gd")

@export var star_count: int = 900
@export var galaxy_radius: float = 3000.0
@export var min_system_distance: float = 48.0
@export_range(1, 6, 1) var spiral_arms: int = 4
@export_enum("spiral", "ring", "elliptical", "clustered") var galaxy_shape: String = "spiral"
@export_range(1, 8, 1) var hyperlane_density: int = 2
@export var ownership_bright_rim_enabled: bool = true
@export_range(0.0, 0.35, 0.01) var ownership_core_opacity: float = 0.0
@export var custom_systems: Array[Resource] = []

@onready var _view_router: GameViewRouter = $SceneSystems/ViewRouter
@onready var _scene_ui_controller: GameSceneUiController = $SceneSystems/UiController
@onready var _runtime_system: GameSceneRuntimeSystem = $SceneSystems/RuntimeSystem
@onready var _view_system: GameSceneViewSystem = $SceneSystems/ViewSystem
@onready var _simulation_system: GameSceneSimulationSystem = $SceneSystems/SimulationSystem

var _state: GameSceneState = GameSceneState.new()
var _ui: GameSceneRefs = null
var _debug_spawner: GalaxyDebugSpawner = GALAXY_DEBUG_SPAWNER_SCRIPT.new()
var _music_ui_controller: RefCounted = GALAXY_HUD_MUSIC_CONTROLLER_SCRIPT.new()


func set_seed_text(value: String) -> void:
	_state.seed_text = value


func configure(settings: Dictionary) -> void:
	_state.generation_settings = settings.duplicate(true)
	if _state.generation_settings.has("seed_text"):
		_state.seed_text = str(_state.generation_settings["seed_text"])
	if _state.generation_settings.has("star_count"):
		star_count = int(_state.generation_settings["star_count"])
	if _state.generation_settings.has("min_system_distance"):
		min_system_distance = float(_state.generation_settings["min_system_distance"])
	if _state.generation_settings.has("shape"):
		galaxy_shape = str(_state.generation_settings["shape"])
	if _state.generation_settings.has("hyperlane_density"):
		hyperlane_density = int(_state.generation_settings["hyperlane_density"])
	if _state.generation_settings.has("selected_starting_empire_id"):
		_state.selected_starting_empire_id = str(_state.generation_settings["selected_starting_empire_id"])
	if _state.generation_settings.has("selected_starting_empire_preset_name"):
		_state.selected_starting_empire_preset_name = str(_state.generation_settings["selected_starting_empire_preset_name"])
	_apply_export_settings_to_state()


func _ready() -> void:
	_ui = GameSceneRefs.from_root(self)
	_apply_export_settings_to_state()
	_load_persisted_settings()
	_setup_scene_components()
	_connect_scene_signals()
	_simulation_system.sync_sim_clock_ui()
	_simulation_system.sync_territory_settings_ui()
	_scene_ui_controller.update_system_panel()
	Callable(_runtime_system, "generate_async").call_deferred()


func _exit_tree() -> void:
	if _view_system != null:
		_view_system.teardown()
	if _runtime_system != null:
		_runtime_system.teardown()
	if _simulation_system != null:
		_simulation_system.teardown()
	if _scene_ui_controller != null:
		_scene_ui_controller.teardown()
	if _view_router != null:
		_view_router.teardown()
	if _debug_spawner != null:
		_debug_spawner.unbind()
	if _music_ui_controller != null:
		_music_ui_controller.unbind()


func _unhandled_input(event: InputEvent) -> void:
	_view_system.handle_unhandled_input(event)


func _on_claim_selected_system_pressed() -> void:
	if _state.selected_system_id.is_empty() or _state.active_empire_id.is_empty():
		return
	_runtime_system.set_system_owner(_state.selected_system_id, _state.active_empire_id)


func _on_clear_owner_pressed() -> void:
	if _state.selected_system_id.is_empty():
		return
	_runtime_system.clear_system_owner(_state.selected_system_id)


func _on_survey_system_pressed() -> void:
	if _state.selected_system_id.is_empty():
		return
	_runtime_system.survey_system_for_active_empire(_state.selected_system_id)


func _on_debug_reveal_toggled() -> void:
	_runtime_system.set_debug_reveal_galaxy(not _state.debug_reveal_galaxy)


func _on_empire_picker_item_selected(_index: int) -> void:
	_ui.select_empire_button.disabled = _scene_ui_controller.get_selected_empire_id_from_picker().is_empty()


func _on_empire_picker_item_activated(_index: int) -> void:
	_on_select_empire_pressed()


func _on_select_empire_pressed() -> void:
	var empire_id: String = _scene_ui_controller.get_selected_empire_id_from_picker()
	if empire_id.is_empty():
		return
	_runtime_system.assign_active_empire(empire_id)
	_scene_ui_controller.set_empire_picker_visible(false, false)


func _on_cancel_empire_picker_pressed() -> void:
	if _state.empire_picker_requires_selection:
		return
	_scene_ui_controller.set_empire_picker_visible(false, false)


func _apply_export_settings_to_state() -> void:
	_state.star_count = star_count
	_state.galaxy_radius = galaxy_radius
	_state.min_system_distance = min_system_distance
	_state.spiral_arms = spiral_arms
	_state.galaxy_shape = galaxy_shape
	_state.hyperlane_density = hyperlane_density
	_state.ownership_bright_rim_enabled = ownership_bright_rim_enabled
	_state.ownership_core_opacity = ownership_core_opacity
	_state.custom_systems = custom_systems.duplicate()


func _load_persisted_settings() -> void:
	_state.ownership_bright_rim_enabled = SettingsManager.get_territory_bright_rim()
	_state.ownership_core_opacity = SettingsManager.get_territory_core_opacity()


func _setup_scene_components() -> void:
	_view_router.setup(_ui.view_root)
	_scene_ui_controller.setup(_state, _ui, _runtime_system, _view_router, _debug_spawner)
	_runtime_system.setup(_state, _ui, _view_router, _scene_ui_controller, _debug_spawner)
	_view_system.setup(_state, _ui, _view_router, _scene_ui_controller, _runtime_system, _debug_spawner)
	_simulation_system.setup(_state, _ui, _runtime_system, _scene_ui_controller)
	_debug_spawner.bind(
		_ui.debug_spawn_panel,
		_ui.debug_spawn_toggle_button,
		Callable(self, "_get_active_empire_id"),
		Callable(_scene_ui_controller, "get_inspected_system_id"),
		Callable(self, "_get_systems_by_id"),
		Callable(_runtime_system, "spawn_runtime_ship"),
		Callable(_runtime_system, "create_runtime_fleet")
	)
	_music_ui_controller.bind(_ui.galaxy_hud)
	_view_system.bind_view_signals()
	_runtime_system.connect_space_runtime_signals()


func _connect_scene_signals() -> void:
	_ui.change_empire_button.pressed.connect(_scene_ui_controller.open_empire_picker.bind(false))
	_ui.claim_system_button.pressed.connect(_on_claim_selected_system_pressed)
	_ui.clear_owner_button.pressed.connect(_on_clear_owner_pressed)
	_ui.survey_system_button.pressed.connect(_on_survey_system_pressed)
	_ui.debug_reveal_toggle_button.pressed.connect(_on_debug_reveal_toggled)
	_ui.select_empire_button.pressed.connect(_on_select_empire_pressed)
	_ui.cancel_empire_picker_button.pressed.connect(_on_cancel_empire_picker_pressed)
	_ui.galaxy_hud.close_settings_requested.connect(_simulation_system.on_close_settings_pressed)
	_ui.galaxy_hud.sim_pause_requested.connect(_simulation_system.on_sim_pause_pressed)
	_ui.galaxy_hud.sim_speed_requested.connect(_simulation_system.on_sim_speed_pressed)
	_ui.galaxy_hud.territory_bright_rim_toggled.connect(_simulation_system.on_territory_bright_rim_toggled)
	_ui.galaxy_hud.territory_core_opacity_changed.connect(_simulation_system.on_territory_core_opacity_changed)
	_ui.empire_picker_list.item_selected.connect(_on_empire_picker_item_selected)
	_ui.empire_picker_list.item_activated.connect(_on_empire_picker_item_activated)
	SimClock.day_tick.connect(_simulation_system.on_sim_day_tick)
	SimClock.month_tick.connect(_simulation_system.on_sim_month_tick)
	SimClock.year_tick.connect(_simulation_system.on_sim_year_tick)


func _get_active_empire_id() -> String:
	return _state.active_empire_id


func _get_systems_by_id() -> Dictionary:
	return _state.systems_by_id
