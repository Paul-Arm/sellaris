extends Node

const GALAXY_GENERATOR_SCRIPT: Script = preload("res://scene/galaxy/GalaxyGenerator.gd")
const GALAXY_STATE_SCRIPT: Script = preload("res://scene/galaxy/GalaxyState.gd")
const EMPIRE_FACTORY_SCRIPT: Script = preload("res://scene/galaxy/EmpireFactory.gd")
const GAME_SCENE_UI_CONTROLLER_SCRIPT: Script = preload("res://scene/game/GameSceneUiController.gd")
const GAME_VIEW_ROUTER_SCRIPT: Script = preload("res://scene/game/GameViewRouter.gd")
const GALAXY_DEBUG_SPAWNER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyDebugSpawner.gd")
const GALAXY_HUD_MUSIC_CONTROLLER_SCRIPT: Script = preload("res://scene/UI/GalaxyHudMusicController.gd")
const DEFAULT_EMPIRE_COUNT: int = 6

@export var star_count: int = 900
@export var galaxy_radius: float = 3000.0
@export var min_system_distance: float = 48.0
@export_range(1, 6, 1) var spiral_arms: int = 4
@export_enum("spiral", "ring", "elliptical", "clustered") var galaxy_shape: String = "spiral"
@export_range(1, 8, 1) var hyperlane_density: int = 2
@export var ownership_bright_rim_enabled: bool = true
@export_range(0.0, 0.35, 0.01) var ownership_core_opacity: float = 0.0
@export var custom_systems: Array[Resource] = []

@onready var view_root: Node = $ViewRoot
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
var _sim_speed_display_steps: Array[float] = [0.5, 1.0, 2.0, 4.0]
var _sim_speed_actual_steps: Array[float] = [0.25, 0.5, 1.0, 2.0]
var _sim_speed_index: int = 0
var _sim_paused: bool = false
var _scene_ui_controller: GameSceneUiController = GAME_SCENE_UI_CONTROLLER_SCRIPT.new()
var _view_router: GameViewRouter = GAME_VIEW_ROUTER_SCRIPT.new()
var _debug_spawner: GalaxyDebugSpawner = GALAXY_DEBUG_SPAWNER_SCRIPT.new()
var _music_ui_controller: RefCounted = GALAXY_HUD_MUSIC_CONTROLLER_SCRIPT.new()


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
	SimClock.day_tick.connect(_on_sim_day_tick)
	SimClock.month_tick.connect(_on_sim_month_tick)
	SimClock.year_tick.connect(_on_sim_year_tick)

	ownership_bright_rim_enabled = SettingsManager.get_territory_bright_rim()
	ownership_core_opacity = SettingsManager.get_territory_core_opacity()

	_scene_ui_controller.bind(self)
	_view_router.bind(view_root)
	_bind_view_signals()
	_debug_spawner.bind(self, debug_spawn_panel, debug_spawn_toggle_button)
	_music_ui_controller.bind(galaxy_hud)

	_sync_sim_clock_ui()
	_sync_territory_settings_ui()
	_update_system_panel()
	_connect_space_runtime_signals()
	call_deferred("_generate_galaxy_async")


func _exit_tree() -> void:
	_unbind_view_signals()
	_disconnect_space_runtime_signals()
	if _scene_ui_controller != null:
		_scene_ui_controller.unbind()
	if _view_router != null:
		_view_router.unbind()
	if _debug_spawner != null:
		_debug_spawner.unbind()
	if _music_ui_controller != null:
		_music_ui_controller.unbind()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if galaxy_hud.is_settings_visible():
			_set_settings_overlay_visible(false)
			return
		if empire_picker_overlay.visible and not _empire_picker_requires_selection:
			_set_empire_picker_visible(false, false)
			return
		if is_system_view_open():
			var system_view: SystemView = get_system_view()
			if system_view != null and system_view.handle_cancel_action():
				_close_system_view()
			return
		_set_settings_overlay_visible(true)
		return

	if _is_generating:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			call_deferred("_generate_galaxy_async")
			return
		if event.keycode == KEY_E:
			_open_empire_picker(false)
			return
		if event.keycode == KEY_F9:
			_debug_spawner.toggle()
			return

	if empire_picker_overlay.visible:
		return

	if galaxy_hud.is_settings_visible():
		return

	if bottom_category_bar.consume_hotkey_event(event):
		get_viewport().set_input_as_handled()
		return

	_view_router.handle_active_view_input(event)


func _generate_galaxy_async() -> void:
	if _is_generating:
		return

	_is_generating = true
	SpaceManager.reset_runtime_state()
	_debug_spawner.register_debug_ship_classes()
	selected_system_id = ""
	hovered_system_id = ""
	pinned_system_id = ""
	active_empire_id = ""
	_invalidate_system_panel_snapshot()
	_set_empire_picker_visible(false, false)
	_set_settings_overlay_visible(false)
	_set_loading_state(true, "Preparing generator...", 0.0)
	show_galaxy_view()
	await get_tree().process_frame

	system_positions.clear()
	system_records.clear()
	hyperlane_links.clear()
	hyperlane_graph.clear()
	empire_records.clear()
	systems_by_id.clear()
	system_indices_by_id.clear()
	empires_by_id.clear()
	galaxy_state.reset()
	_set_galaxy_presentation_visible(true)
	system_preview_image.texture = null
	_clear_galaxy_view()
	var galaxy_view: GalaxyMapView = get_galaxy_view()
	if galaxy_view != null:
		galaxy_view.sync_interaction_state("", "")
		galaxy_view.reset_camera_view(galaxy_radius)

	_set_loading_state(true, "Resolving settings...", 0.1)
	await get_tree().process_frame

	var resolved_settings: Dictionary = {
		"seed_text": seed_text,
		"star_count": star_count,
		"galaxy_radius": galaxy_radius,
		"min_system_distance": min_system_distance,
		"spiral_arms": spiral_arms,
		"shape": galaxy_shape,
		"hyperlane_density": hyperlane_density,
	}
	for key_variant in generation_settings.keys():
		var key: Variant = key_variant
		resolved_settings[key] = generation_settings[key]

	_set_loading_state(true, "Placing systems and hyperlanes...", 0.45)
	await get_tree().process_frame

	var layout: Dictionary = generator.build_layout(resolved_settings, custom_systems)
	galaxy_state.load_from_layout(layout)
	generated_seed = int(layout.get("seed", 0))
	galaxy_radius = float(layout.get("galaxy_radius", galaxy_radius))
	min_system_distance = float(layout.get("min_system_distance", min_system_distance))
	galaxy_shape = str(layout.get("shape", galaxy_shape))
	hyperlane_density = int(layout.get("hyperlane_density", hyperlane_density))
	_sync_cached_state()
	_sync_galaxy_view_state()
	if galaxy_view != null:
		galaxy_view.set_galaxy_radius(galaxy_radius)
		galaxy_view.reset_camera_view(galaxy_radius)

	_set_loading_state(true, "Preparing empire shells...", 0.6)
	await get_tree().process_frame
	_initialize_empires()
	_sync_debug_spawner()

	_set_loading_state(true, "Preparing scene data...", 0.72)
	await get_tree().process_frame

	_set_loading_state(true, "Rendering stars...", 0.84)
	await get_tree().process_frame
	_render_stars()

	_set_loading_state(true, "Rendering hyperlanes...", 0.92)
	await get_tree().process_frame
	_render_hyperlanes()
	_render_ownership_markers()
	_update_system_panel()
	_update_info_label()

	_set_loading_state(true, "Finalizing...", 1.0)
	await get_tree().process_frame
	_set_loading_state(false)
	_is_generating = false
	_open_empire_picker(true)


func get_system_details(system_id: String) -> Dictionary:
	var details: Dictionary = _resolve_system_details(system_id)
	if details.is_empty():
		return {}

	var owner_id: String = galaxy_state.get_system_owner_id(system_id)
	var owner_name: String = "Unclaimed"
	if empires_by_id.has(owner_id):
		owner_name = str(empires_by_id[owner_id].get("name", owner_name))

	details["owner_empire_id"] = owner_id
	details["owner_name"] = owner_name
	details["space_presence"] = get_system_space_presence(system_id)
	return details


func _resolve_system_details(system_id: String) -> Dictionary:
	if not systems_by_id.has(system_id):
		return {}

	var detail_override: Dictionary = galaxy_state.get_system_detail_override(system_id)
	return generator.generate_system_details(
		generated_seed,
		systems_by_id[system_id],
		custom_systems,
		detail_override
	)


func get_galaxy_state_snapshot() -> Dictionary:
	return galaxy_state.build_snapshot()


func get_runtime_snapshot() -> Dictionary:
	return {
		"galaxy": get_galaxy_state_snapshot(),
		"space": SpaceManager.build_snapshot(),
	}


func get_system_space_presence(system_id: String) -> Dictionary:
	if system_id.is_empty():
		return {}
	return SpaceManager.build_system_presence(system_id)


func spawn_runtime_ship(class_id: String, owner_empire_id: String, system_id: String, spawn_data: Dictionary = {}) -> ShipRuntime:
	if system_id.is_empty() or not systems_by_id.has(system_id):
		return null
	return SpaceManager.spawn_ship(class_id, owner_empire_id, system_id, spawn_data)


func create_runtime_fleet(owner_empire_id: String, system_id: String, ship_ids_variant: Variant = PackedStringArray(), fleet_data: Dictionary = {}) -> FleetRuntime:
	if system_id.is_empty() or not systems_by_id.has(system_id):
		return null
	return SpaceManager.create_fleet(owner_empire_id, system_id, ship_ids_variant, fleet_data)


func assign_active_empire(empire_id: String) -> bool:
	if not galaxy_state.set_local_player_empire(empire_id):
		return false

	active_empire_id = empire_id
	_sync_cached_state()
	_populate_empire_picker()
	_sync_debug_spawner()
	_update_system_panel()
	_update_info_label()
	return true


func set_system_owner(system_id: String, empire_id: String) -> bool:
	if not galaxy_state.set_system_owner(system_id, empire_id):
		return false

	_sync_cached_state()
	_render_ownership_markers()
	_update_system_panel()
	_update_info_label()
	return true


func clear_system_owner(system_id: String) -> bool:
	return set_system_owner(system_id, "")


func set_runtime_system_details(system_id: String, detail_patch: Dictionary) -> bool:
	if not systems_by_id.has(system_id):
		return false

	var resolved_details: Dictionary = generator.generate_system_details(
		generated_seed,
		systems_by_id[system_id],
		custom_systems,
		detail_patch
	)
	return _apply_system_detail_state(system_id, resolved_details, true)


func patch_runtime_system_details(system_id: String, detail_patch: Dictionary) -> bool:
	if not systems_by_id.has(system_id):
		return false

	var resolved_details: Dictionary = generator.apply_system_detail_patch(
		_resolve_system_details(system_id),
		detail_patch
	)
	return _apply_system_detail_state(system_id, resolved_details, true)


func clear_runtime_system_details(system_id: String) -> bool:
	if not systems_by_id.has(system_id):
		return false
	if not galaxy_state.clear_system_detail_override(system_id):
		return false

	var resolved_details: Dictionary = generator.generate_system_details(
		generated_seed,
		systems_by_id[system_id],
		custom_systems
	)
	return _apply_system_detail_state(system_id, resolved_details, false)


func add_runtime_system(system_record: Dictionary, detail_patch: Dictionary = {}) -> bool:
	if not galaxy_state.add_system(system_record):
		return false

	_sync_cached_state()
	if not detail_patch.is_empty() and not system_records.is_empty():
		var created_record: Dictionary = system_records[system_records.size() - 1]
		var created_system_id: String = str(created_record.get("id", ""))
		if not created_system_id.is_empty():
			var resolved_details: Dictionary = generator.generate_system_details(
				generated_seed,
				created_record,
				custom_systems,
				detail_patch
			)
			if not _apply_system_detail_state(created_system_id, resolved_details, true):
				return false
			_render_hyperlanes()
			_render_ownership_markers()
			return true

	_render_stars()
	_render_hyperlanes()
	_render_ownership_markers()
	_update_system_panel()
	_update_info_label()
	return true


func add_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if not galaxy_state.add_hyperlane(system_a_id, system_b_id):
		return false

	_sync_cached_state()
	_render_hyperlanes()
	_update_system_panel()
	_update_info_label()
	return true


func remove_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if not galaxy_state.remove_hyperlane(system_a_id, system_b_id):
		return false

	_sync_cached_state()
	_render_hyperlanes()
	_update_system_panel()
	_update_info_label()
	return true


func _apply_system_detail_state(system_id: String, resolved_details: Dictionary, store_override: bool) -> bool:
	if store_override:
		if not galaxy_state.set_system_detail_override(system_id, resolved_details):
			return false

	if not galaxy_state.update_system_record(system_id, {
		"star_profile": resolved_details.get("star_profile", {}),
		"system_summary": resolved_details.get("system_summary", {}),
	}):
		return false

	_invalidate_system_panel_snapshot(system_id)
	_sync_cached_state()
	_render_stars()
	_update_system_panel()
	_update_info_label()
	return true


func _initialize_empires() -> void:
	var preset_empires: Array[Dictionary] = EmpirePresetManager.build_galaxy_empire_records()
	var desired_empire_count: int = maxi(DEFAULT_EMPIRE_COUNT, preset_empires.size())
	var generated_empires: Array[Dictionary] = empire_factory.build_default_empires(
		generated_seed,
		system_records.size(),
		desired_empire_count
	)
	var merged_empires: Array[Dictionary] = []

	for preset_index in range(preset_empires.size()):
		var preset_record: Dictionary = preset_empires[preset_index].duplicate(true)
		preset_record["player_slot"] = preset_index
		merged_empires.append(preset_record)

	for generated_index in range(generated_empires.size()):
		if merged_empires.size() >= desired_empire_count:
			break

		var generated_record: Dictionary = generated_empires[generated_index].duplicate(true)
		generated_record["id"] = "generated_empire_%02d" % generated_index
		generated_record["player_slot"] = merged_empires.size()
		merged_empires.append(generated_record)

	galaxy_state.set_empires(merged_empires)
	_sync_cached_state()
	_populate_empire_picker()
	_sync_debug_spawner()


func _sync_cached_state() -> void:
	generated_seed = int(galaxy_state.generated_seed)
	system_positions = galaxy_state.system_positions
	system_records = galaxy_state.system_records
	hyperlane_links = galaxy_state.hyperlane_links
	hyperlane_graph = galaxy_state.hyperlane_graph
	systems_by_id = galaxy_state.systems_by_id
	system_indices_by_id = galaxy_state.system_indices_by_id
	empire_records = galaxy_state.empires
	empires_by_id = galaxy_state.empires_by_id


func _connect_space_runtime_signals() -> void:
	var runtime_signals: Array[Signal] = [
		SpaceManager.ship_spawned,
		SpaceManager.ship_removed,
		SpaceManager.ship_updated,
		SpaceManager.fleet_created,
		SpaceManager.fleet_removed,
		SpaceManager.fleet_updated,
	]
	for runtime_signal in runtime_signals:
		if not runtime_signal.is_connected(_on_space_runtime_changed):
			runtime_signal.connect(_on_space_runtime_changed)


func _disconnect_space_runtime_signals() -> void:
	var runtime_signals: Array[Signal] = [
		SpaceManager.ship_spawned,
		SpaceManager.ship_removed,
		SpaceManager.ship_updated,
		SpaceManager.fleet_created,
		SpaceManager.fleet_removed,
		SpaceManager.fleet_updated,
	]
	for runtime_signal in runtime_signals:
		if runtime_signal.is_connected(_on_space_runtime_changed):
			runtime_signal.disconnect(_on_space_runtime_changed)


func _on_space_runtime_changed(_record_id: String) -> void:
	_update_system_panel()


func _sync_debug_spawner() -> void:
	var inspected_system_id: String = _get_inspected_system_id()
	_debug_spawner.populate_panel(empire_records, system_records, active_empire_id, inspected_system_id)


func _sync_galaxy_view_state() -> void:
	var galaxy_view: GalaxyMapView = get_galaxy_view()
	if galaxy_view == null:
		return
	galaxy_view.sync_state(
		system_positions,
		system_records,
		hyperlane_links,
		empires_by_id,
		min_system_distance,
		ownership_bright_rim_enabled,
		ownership_core_opacity,
		pinned_system_id
	)
	galaxy_view.sync_interaction_state(hovered_system_id, pinned_system_id)


func _clear_galaxy_view() -> void:
	var galaxy_view: GalaxyMapView = get_galaxy_view()
	if galaxy_view != null:
		galaxy_view.clear_rendered_map()


func _render_stars() -> void:
	var galaxy_view: GalaxyMapView = get_galaxy_view()
	if galaxy_view == null:
		return
	_sync_galaxy_view_state()
	galaxy_view.render_stars()


func _render_hyperlanes() -> void:
	var galaxy_view: GalaxyMapView = get_galaxy_view()
	if galaxy_view == null:
		return
	_sync_galaxy_view_state()
	galaxy_view.render_hyperlanes()


func _render_ownership_markers() -> void:
	var galaxy_view: GalaxyMapView = get_galaxy_view()
	if galaxy_view == null:
		return
	_sync_galaxy_view_state()
	galaxy_view.render_ownership_markers()


func _sync_territory_settings_ui() -> void:
	if galaxy_hud != null:
		galaxy_hud.set_territory_ui(ownership_bright_rim_enabled, ownership_core_opacity)


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


func get_galaxy_view() -> GalaxyMapView:
	return _view_router.get_galaxy_view()


func get_system_view() -> SystemView:
	return _view_router.get_system_view()


func is_system_view_open() -> bool:
	return _view_router.is_system_view_open()


func get_current_system_view_id() -> String:
	var system_view: SystemView = get_system_view()
	if system_view == null:
		return ""
	return system_view.get_current_system_id()


func show_system_view(system_details: Dictionary, neighbor_count: int) -> void:
	_view_router.show_system_view(system_details, neighbor_count)


func show_galaxy_view() -> void:
	_view_router.show_galaxy_view()


func refresh_system_view(system_details: Dictionary, neighbor_count: int) -> void:
	_view_router.refresh_system_view(system_details, neighbor_count)


func set_galaxy_camera_input_blocked(blocked: bool) -> void:
	var galaxy_view: GalaxyMapView = get_galaxy_view()
	if galaxy_view != null:
		galaxy_view.set_camera_input_blocked(blocked)


func _bind_view_signals() -> void:
	var galaxy_view: GalaxyMapView = get_galaxy_view()
	if galaxy_view != null:
		if not galaxy_view.hovered_system_changed.is_connected(_on_galaxy_view_hovered_system_changed):
			galaxy_view.hovered_system_changed.connect(_on_galaxy_view_hovered_system_changed)
		if not galaxy_view.inspect_system_requested.is_connected(_on_galaxy_view_inspect_system_requested):
			galaxy_view.inspect_system_requested.connect(_on_galaxy_view_inspect_system_requested)
		if not galaxy_view.pinned_system_changed.is_connected(_on_galaxy_view_pinned_system_changed):
			galaxy_view.pinned_system_changed.connect(_on_galaxy_view_pinned_system_changed)

	if not _view_router.system_close_requested.is_connected(_close_system_view):
		_view_router.system_close_requested.connect(_close_system_view)


func _unbind_view_signals() -> void:
	var galaxy_view: GalaxyMapView = get_galaxy_view()
	if galaxy_view != null:
		if galaxy_view.hovered_system_changed.is_connected(_on_galaxy_view_hovered_system_changed):
			galaxy_view.hovered_system_changed.disconnect(_on_galaxy_view_hovered_system_changed)
		if galaxy_view.inspect_system_requested.is_connected(_on_galaxy_view_inspect_system_requested):
			galaxy_view.inspect_system_requested.disconnect(_on_galaxy_view_inspect_system_requested)
		if galaxy_view.pinned_system_changed.is_connected(_on_galaxy_view_pinned_system_changed):
			galaxy_view.pinned_system_changed.disconnect(_on_galaxy_view_pinned_system_changed)

	if _view_router != null and _view_router.system_close_requested.is_connected(_close_system_view):
		_view_router.system_close_requested.disconnect(_close_system_view)


func _on_galaxy_view_hovered_system_changed(system_id: String) -> void:
	hovered_system_id = system_id
	_update_system_panel()
	_update_info_label()


func _on_galaxy_view_inspect_system_requested(system_id: String) -> void:
	if system_id.is_empty():
		return
	hovered_system_id = system_id
	selected_system_id = system_id
	_update_system_panel()
	_update_info_label()
	_open_system_view(system_id)


func _on_galaxy_view_pinned_system_changed(system_id: String) -> void:
	pinned_system_id = system_id
	hovered_system_id = system_id
	_render_stars()
	_update_system_panel()
	_update_info_label()


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
	var empire_id: String = _get_selected_empire_id_from_picker()
	if empire_id.is_empty():
		return
	assign_active_empire(empire_id)
	_set_empire_picker_visible(false, false)


func _on_cancel_empire_picker_pressed() -> void:
	if _empire_picker_requires_selection:
		return
	_set_empire_picker_visible(false, false)


func _sync_sim_clock_ui() -> void:
	var current_speed: float = SimClock.sim_speed
	_sim_paused = current_speed <= 0.0
	if not _sim_paused:
		var best_index: int = 0
		var best_distance: float = INF
		for speed_index in range(_sim_speed_actual_steps.size()):
			var distance: float = absf(_sim_speed_actual_steps[speed_index] - current_speed)
			if distance < best_distance:
				best_distance = distance
				best_index = speed_index
		_sim_speed_index = best_index
	var current_date: Dictionary = SimClock.get_current_date()
	var date_text: String = "%04d-%02d-%02d" % [
		int(current_date.get("year", 0)),
		int(current_date.get("month", 0)),
		int(current_date.get("day", 0)),
	]
	var speed_value: float = _sim_speed_display_steps[_sim_speed_index]
	var speed_text: String = "Paused" if _sim_paused else "x%s" % _format_speed_factor(speed_value)
	galaxy_hud.set_sim_ui(date_text, speed_text, _sim_paused)


func _format_speed_factor(speed_value: float) -> String:
	if is_equal_approx(speed_value, round(speed_value)):
		return str(int(round(speed_value)))
	return str(snappedf(speed_value, 0.1))


func _on_close_settings_pressed() -> void:
	_set_settings_overlay_visible(false)


func _on_territory_bright_rim_toggled(enabled: bool) -> void:
	ownership_bright_rim_enabled = enabled
	SettingsManager.set_territory_bright_rim(enabled)
	_sync_territory_settings_ui()
	_render_ownership_markers()


func _on_territory_core_opacity_changed(value: float) -> void:
	ownership_core_opacity = value
	SettingsManager.set_territory_core_opacity(value)
	_sync_territory_settings_ui()
	_render_ownership_markers()


func _on_sim_pause_pressed() -> void:
	if _sim_paused:
		SimClock.set_sim_speed(_sim_speed_actual_steps[_sim_speed_index])
	else:
		SimClock.pause_sim()
	_sync_sim_clock_ui()


func _on_sim_speed_pressed() -> void:
	_sim_speed_index = (_sim_speed_index + 1) % _sim_speed_actual_steps.size()
	SimClock.set_sim_speed(_sim_speed_actual_steps[_sim_speed_index])
	_sync_sim_clock_ui()


func _on_sim_day_tick(_date: Dictionary) -> void:
	_sync_sim_clock_ui()


func _on_sim_month_tick(_year: int, _month: int) -> void:
	_sync_sim_clock_ui()


func _on_sim_year_tick(_year: int) -> void:
	_sync_sim_clock_ui()


func _on_bottom_category_selected(_category: Dictionary, _index: int) -> void:
	pass
