extends Node3D

const GALAXY_GENERATOR_SCRIPT: Script = preload("res://scene/galaxy/GalaxyGenerator.gd")
const GALAXY_STATE_SCRIPT: Script = preload("res://scene/galaxy/GalaxyState.gd")
const EMPIRE_FACTORY_SCRIPT: Script = preload("res://scene/galaxy/EmpireFactory.gd")
const GALAXY_MAP_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyMapRenderer.gd")
const GALAXY_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyRuntimePlaceholderRenderer.gd")
const GALAXY_SCENE_UI_CONTROLLER_SCRIPT: Script = preload("res://scene/galaxy/GalaxySceneUiController.gd")
const GALAXY_DEBUG_SPAWNER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyDebugSpawner.gd")
const GALAXY_HUD_MUSIC_CONTROLLER_SCRIPT: Script = preload("res://scene/UI/GalaxyHudMusicController.gd")
const GALAXY_SCENE_RUNTIME_SYSTEM_SCRIPT: Script = preload("res://scene/galaxy/systems/GalaxySceneRuntimeSystem.gd")
const GALAXY_SCENE_INPUT_SYSTEM_SCRIPT: Script = preload("res://scene/galaxy/systems/GalaxySceneInputSystem.gd")
const GALAXY_SCENE_SIMULATION_SYSTEM_SCRIPT: Script = preload("res://scene/galaxy/systems/GalaxySceneSimulationSystem.gd")
const STAR_CORE_SHADER := preload("res://scene/galaxy/StarCore.gdshader")
const STAR_GLOW_SHADER := preload("res://scene/galaxy/StarGlow.gdshader")
const DEFAULT_EMPIRE_COUNT := 6

@export var star_count: int = 900
@export var galaxy_radius: float = 3000.0
@export var min_system_distance: float = 48.0
@export_range(1, 6, 1) var spiral_arms: int = 4
@export_enum("spiral", "ring", "elliptical", "clustered") var galaxy_shape: String = "spiral"
@export_range(1, 8, 1) var hyperlane_density: int = 2
@export var ownership_bright_rim_enabled: bool = true
@export_range(0.0, 0.35, 0.01) var ownership_core_opacity: float = 0.0
@export var custom_systems: Array[Resource] = []

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var stars: Node3D = $Stars
@onready var core_stars: MultiMeshInstance3D = $Stars/CoreStars
@onready var glow_stars: MultiMeshInstance3D = $Stars/GlowStars
@onready var ownership_markers: MeshInstance3D = $Stars/OwnershipMarkers
@onready var ownership_connectors: MeshInstance3D = $Stars/OwnershipConnectors
@onready var hyperlanes: MeshInstance3D = $Hyperlanes
@onready var runtime_placeholders: Node3D = $RuntimePlaceholders
@onready var station_markers: MultiMeshInstance3D = $RuntimePlaceholders/StationMarkers
@onready var fleet_markers: MultiMeshInstance3D = $RuntimePlaceholders/FleetMarkers
@onready var ship_markers: MultiMeshInstance3D = $RuntimePlaceholders/ShipMarkers
@onready var info_label: Label = $CanvasLayer/InfoLabel
@onready var loading_overlay: Control = $CanvasLayer/LoadingOverlay
@onready var loading_status: Label = $CanvasLayer/LoadingOverlay/Panel/MarginContainer/VBoxContainer/LoadingStatus
@onready var loading_progress: ProgressBar = $CanvasLayer/LoadingOverlay/Panel/MarginContainer/VBoxContainer/LoadingProgress
@onready var bottom_category_bar: BottomCategoryBar = $CanvasLayer/BottomCategoryBar
@onready var system_panel: PanelContainer = $CanvasLayer/SystemPanel
@onready var empire_status_label: Label = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/EmpireStatusLabel
@onready var change_empire_button: Button = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/ChangeEmpireButton
@onready var system_preview_image: TextureRect = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/SystemPreviewImage
@onready var system_snapshot_viewport: SubViewport = $CanvasLayer/SystemPreviewSnapshotViewport
@onready var system_snapshot_preview: StarSystemPreview = $CanvasLayer/SystemPreviewSnapshotViewport/StarSystemPreview
@onready var selected_system_title: Label = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/SelectedSystemTitle
@onready var selected_system_meta: Label = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/SelectedSystemMeta
@onready var claim_system_button: Button = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/ClaimSystemButton
@onready var clear_owner_button: Button = $CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/ClearOwnerButton
@onready var empire_picker_overlay: Control = $CanvasLayer/EmpirePickerOverlay
@onready var empire_picker_list: ItemList = $CanvasLayer/EmpirePickerOverlay/Panel/MarginContainer/VBoxContainer/EmpirePickerList
@onready var select_empire_button: Button = $CanvasLayer/EmpirePickerOverlay/Panel/MarginContainer/VBoxContainer/ButtonRow/SelectEmpireButton
@onready var cancel_empire_picker_button: Button = $CanvasLayer/EmpirePickerOverlay/Panel/MarginContainer/VBoxContainer/ButtonRow/CancelEmpirePickerButton
@onready var debug_spawn_toggle_button: Button = $CanvasLayer/DebugSpawnToggleButton
@onready var debug_spawn_panel: PanelContainer = $CanvasLayer/DebugSpawnPanel
@onready var galaxy_hud: Control = $CanvasLayer/GalaxyHud
@onready var system_view = $CanvasLayer/SystemView

var seed_text: String = ""
var generated_seed: int = 0
var system_positions: Array[Vector3] = []
var system_records: Array[Dictionary] = []
var hyperlane_links: Array[Vector2i] = []
var hyperlane_graph: Dictionary = {}
var generation_settings: Dictionary = {}
var generator: RefCounted = GALAXY_GENERATOR_SCRIPT.new()
var galaxy_state: RefCounted = GALAXY_STATE_SCRIPT.new()
var empire_factory: RefCounted = EMPIRE_FACTORY_SCRIPT.new()
var systems_by_id: Dictionary = {}
var system_indices_by_id: Dictionary = {}
var empire_records: Array[Dictionary] = []
var empires_by_id: Dictionary = {}
var active_empire_id: String = ""
var selected_system_id: String = ""
var hovered_system_id: String = ""
var pinned_system_id: String = ""
var _is_generating: bool = false
var _empire_picker_requires_selection: bool = true
var _galaxy_presentation_visibility: Dictionary = {}
var _system_panel_snapshot_cache: Dictionary = {}
var _system_panel_snapshot_token: int = 0
var _sim_speed_display_steps := [0.5, 1.0, 2.0, 4.0]
var _sim_speed_actual_steps := [0.25, 0.5, 1.0, 2.0]
var _sim_speed_index: int = 0
var _sim_paused: bool = false
var _map_renderer = GALAXY_MAP_RENDERER_SCRIPT.new()
var _runtime_placeholder_renderer = GALAXY_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT.new()
var _scene_ui_controller = GALAXY_SCENE_UI_CONTROLLER_SCRIPT.new()
var _debug_spawner = GALAXY_DEBUG_SPAWNER_SCRIPT.new()
var _music_ui_controller = GALAXY_HUD_MUSIC_CONTROLLER_SCRIPT.new()
var _runtime_system = GALAXY_SCENE_RUNTIME_SYSTEM_SCRIPT.new()
var _input_system = GALAXY_SCENE_INPUT_SYSTEM_SCRIPT.new()
var _simulation_system = GALAXY_SCENE_SIMULATION_SYSTEM_SCRIPT.new()


func set_seed_text(value: String) -> void:
	seed_text = value


func configure(settings: Dictionary) -> void:
	generation_settings = settings.duplicate(true)
	if generation_settings.has("seed_text"):
		seed_text = str(generation_settings["seed_text"])
	if generation_settings.has("star_count"):
		star_count = int(generation_settings["star_count"])
	if generation_settings.has("min_system_distance"):
		min_system_distance = float(generation_settings["min_system_distance"])
	if generation_settings.has("shape"):
		galaxy_shape = str(generation_settings["shape"])
	if generation_settings.has("hyperlane_density"):
		hyperlane_density = int(generation_settings["hyperlane_density"])


func _ready() -> void:
	change_empire_button.pressed.connect(_on_change_empire_pressed)
	claim_system_button.pressed.connect(_on_claim_selected_system_pressed)
	clear_owner_button.pressed.connect(_on_clear_owner_pressed)
	select_empire_button.pressed.connect(_on_select_empire_pressed)
	cancel_empire_picker_button.pressed.connect(_on_cancel_empire_picker_pressed)
	galaxy_hud.close_settings_requested.connect(_on_close_settings_pressed)
	galaxy_hud.sim_pause_requested.connect(_on_sim_pause_pressed)
	galaxy_hud.sim_speed_requested.connect(_on_sim_speed_pressed)
	galaxy_hud.territory_bright_rim_toggled.connect(_on_territory_bright_rim_toggled)
	galaxy_hud.territory_core_opacity_changed.connect(_on_territory_core_opacity_changed)
	empire_picker_list.item_selected.connect(_on_empire_picker_item_selected)
	empire_picker_list.item_activated.connect(_on_empire_picker_item_activated)
	bottom_category_bar.category_selected.connect(_on_bottom_category_selected)
	system_view.close_requested.connect(_close_system_view)
	SimClock.day_tick.connect(_on_sim_day_tick)
	SimClock.month_tick.connect(_on_sim_month_tick)
	SimClock.year_tick.connect(_on_sim_year_tick)

	ownership_bright_rim_enabled = SettingsManager.get_territory_bright_rim()
	ownership_core_opacity = SettingsManager.get_territory_core_opacity()

	_map_renderer.bind(self, STAR_CORE_SHADER, STAR_GLOW_SHADER)
	_runtime_placeholder_renderer.bind(self)
	_scene_ui_controller.bind(self)
	_debug_spawner.bind(self, debug_spawn_panel, debug_spawn_toggle_button)
	_music_ui_controller.bind(galaxy_hud)
	_runtime_system.bind(self)
	_input_system.bind(self)
	_simulation_system.bind(self)

	_sync_sim_clock_ui()
	_sync_territory_settings_ui()
	_update_system_panel()
	_runtime_system.connect_space_runtime_signals()
	call_deferred("_generate_galaxy_async")


func _exit_tree() -> void:
	if _runtime_system != null:
		_runtime_system.unbind()
	if _input_system != null:
		_input_system.unbind()
	if _simulation_system != null:
		_simulation_system.unbind()
	if _map_renderer != null:
		_map_renderer.unbind()
	if _runtime_placeholder_renderer != null:
		_runtime_placeholder_renderer.unbind()
	if _scene_ui_controller != null:
		_scene_ui_controller.unbind()
	if _debug_spawner != null:
		_debug_spawner.unbind()
	if _music_ui_controller != null:
		_music_ui_controller.unbind()


func _unhandled_input(event: InputEvent) -> void:
	_input_system.handle_unhandled_input(event)


func _generate_galaxy_async() -> void:
	await _runtime_system.generate_async()


func get_system_details(system_id: String) -> Dictionary:
	return _runtime_system.get_system_details(system_id)


func get_galaxy_state_snapshot() -> Dictionary:
	return _runtime_system.get_galaxy_state_snapshot()


func get_runtime_snapshot() -> Dictionary:
	return _runtime_system.get_runtime_snapshot()


func get_system_space_presence(system_id: String) -> Dictionary:
	return _runtime_system.get_system_space_presence(system_id)


func spawn_runtime_ship(class_id: String, owner_empire_id: String, system_id: String, spawn_data: Dictionary = {}) -> ShipRuntime:
	return _runtime_system.spawn_runtime_ship(class_id, owner_empire_id, system_id, spawn_data)


func create_runtime_fleet(owner_empire_id: String, system_id: String, ship_ids_variant: Variant = PackedStringArray(), fleet_data: Dictionary = {}) -> FleetRuntime:
	return _runtime_system.create_runtime_fleet(owner_empire_id, system_id, ship_ids_variant, fleet_data)


func assign_active_empire(empire_id: String) -> bool:
	return _runtime_system.assign_active_empire(empire_id)


func set_system_owner(system_id: String, empire_id: String) -> bool:
	return _runtime_system.set_system_owner(system_id, empire_id)


func clear_system_owner(system_id: String) -> bool:
	return _runtime_system.clear_system_owner(system_id)


func set_runtime_system_details(system_id: String, detail_patch: Dictionary) -> bool:
	return _runtime_system.set_runtime_system_details(system_id, detail_patch)


func patch_runtime_system_details(system_id: String, detail_patch: Dictionary) -> bool:
	return _runtime_system.patch_runtime_system_details(system_id, detail_patch)


func clear_runtime_system_details(system_id: String) -> bool:
	return _runtime_system.clear_runtime_system_details(system_id)


func add_runtime_system(system_record: Dictionary, detail_patch: Dictionary = {}) -> bool:
	return _runtime_system.add_runtime_system(system_record, detail_patch)


func add_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	return _runtime_system.add_runtime_hyperlane(system_a_id, system_b_id)


func remove_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	return _runtime_system.remove_runtime_hyperlane(system_a_id, system_b_id)


func _sync_debug_spawner() -> void:
	var inspected_system_id: String = _get_inspected_system_id()
	_debug_spawner.populate_panel(empire_records, system_records, active_empire_id, inspected_system_id)


func _render_stars() -> void:
	_map_renderer.render_stars()


func _render_hyperlanes() -> void:
	_map_renderer.render_hyperlanes()


func _render_ownership_markers() -> void:
	_map_renderer.render_ownership_markers()


func _render_runtime_placeholders() -> void:
	_runtime_placeholder_renderer.render_runtime_placeholders()


func _sync_territory_settings_ui() -> void:
	_simulation_system.sync_territory_settings_ui()


func _update_info_label() -> void:
	_scene_ui_controller.update_info_label()


func _update_system_panel() -> void:
	_scene_ui_controller.update_system_panel()
	_sync_debug_spawner()


func _get_inspected_system_id() -> String:
	return _scene_ui_controller.get_inspected_system_id()


func _invalidate_system_panel_snapshot(system_id: String = "") -> void:
	_scene_ui_controller.invalidate_system_panel_snapshot(system_id)


func _update_system_panel_preview(system_id: String, system_details: Dictionary) -> void:
	_scene_ui_controller.update_system_panel_preview(system_id, system_details)


func _capture_system_panel_snapshot(system_id: String, system_details: Dictionary, request_token: int) -> void:
	await _scene_ui_controller._capture_system_panel_snapshot(system_id, system_details, request_token)


func _populate_empire_picker() -> void:
	_scene_ui_controller.populate_empire_picker()


func _open_empire_picker(requires_selection: bool) -> void:
	_scene_ui_controller.open_empire_picker(requires_selection)


func _set_empire_picker_visible(visible_state: bool, requires_selection: bool = false) -> void:
	_scene_ui_controller.set_empire_picker_visible(visible_state, requires_selection)


func _set_settings_overlay_visible(visible_state: bool) -> void:
	_scene_ui_controller.set_settings_overlay_visible(visible_state)


func _set_loading_state(visible_state: bool, status_text: String = "", progress_ratio: float = 0.0) -> void:
	_scene_ui_controller.set_loading_state(visible_state, status_text, progress_ratio)


func _refresh_camera_input_block() -> void:
	_scene_ui_controller.refresh_camera_input_block()


func _set_galaxy_presentation_visible(visible_state: bool) -> void:
	_scene_ui_controller.set_galaxy_presentation_visible(visible_state)


func _open_system_view(system_id: String) -> void:
	_scene_ui_controller.open_system_view(system_id)


func _close_system_view() -> void:
	_scene_ui_controller.close_system_view()


func _update_bottom_category_bar_context(active_empire_name: String, selected_system_name: String, selected_owner_name: String) -> void:
	_scene_ui_controller.update_bottom_category_bar_context(active_empire_name, selected_system_name, selected_owner_name)


func _get_selected_empire_id_from_picker() -> String:
	return _scene_ui_controller.get_selected_empire_id_from_picker()


func _format_controller_kind(controller_kind: String) -> String:
	return _scene_ui_controller.format_controller_kind(controller_kind)


func _sync_sim_clock_ui() -> void:
	_simulation_system.sync_sim_clock_ui()


func _format_speed_factor(speed_value: float) -> String:
	return _simulation_system.format_speed_factor(speed_value)


func _on_change_empire_pressed() -> void:
	_open_empire_picker(false)


func _on_claim_selected_system_pressed() -> void:
	if selected_system_id.is_empty() or active_empire_id.is_empty():
		return
	set_system_owner(selected_system_id, active_empire_id)


func _on_clear_owner_pressed() -> void:
	if selected_system_id.is_empty():
		return
	clear_system_owner(selected_system_id)


func _on_empire_picker_item_selected(_index: int) -> void:
	select_empire_button.disabled = _get_selected_empire_id_from_picker().is_empty()


func _on_empire_picker_item_activated(_index: int) -> void:
	_on_select_empire_pressed()


func _on_select_empire_pressed() -> void:
	var empire_id := _get_selected_empire_id_from_picker()
	if empire_id.is_empty():
		return
	assign_active_empire(empire_id)
	_set_empire_picker_visible(false, false)


func _on_cancel_empire_picker_pressed() -> void:
	if _empire_picker_requires_selection:
		return
	_set_empire_picker_visible(false, false)


func _on_close_settings_pressed() -> void:
	_simulation_system.on_close_settings_pressed()


func _on_territory_bright_rim_toggled(enabled: bool) -> void:
	_simulation_system.on_territory_bright_rim_toggled(enabled)


func _on_territory_core_opacity_changed(value: float) -> void:
	_simulation_system.on_territory_core_opacity_changed(value)


func _on_sim_pause_pressed() -> void:
	_simulation_system.on_sim_pause_pressed()


func _on_sim_speed_pressed() -> void:
	_simulation_system.on_sim_speed_pressed()


func _on_sim_day_tick(date: Dictionary) -> void:
	_simulation_system.on_sim_day_tick(date)


func _on_sim_month_tick(year: int, month: int) -> void:
	_simulation_system.on_sim_month_tick(year, month)


func _on_sim_year_tick(year: int) -> void:
	_simulation_system.on_sim_year_tick(year)


func _on_bottom_category_selected(_category: Dictionary, _index: int) -> void:
	# The bar handles its own visual state today; this hook keeps future category panels easy to add.
	pass
