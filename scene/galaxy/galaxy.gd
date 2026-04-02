extends Node3D

const GALAXY_GENERATOR_SCRIPT: Script = preload("res://scene/galaxy/GalaxyGenerator.gd")
const GALAXY_STATE_SCRIPT: Script = preload("res://scene/galaxy/GalaxyState.gd")
const EMPIRE_FACTORY_SCRIPT: Script = preload("res://scene/galaxy/EmpireFactory.gd")
const GALAXY_MAP_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyMapRenderer.gd")
const GALAXY_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyRuntimePlaceholderRenderer.gd")
const GALAXY_SCENE_UI_CONTROLLER_SCRIPT: Script = preload("res://scene/galaxy/GalaxySceneUiController.gd")
const GALAXY_DEBUG_SPAWNER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyDebugSpawner.gd")
const GALAXY_HUD_MUSIC_CONTROLLER_SCRIPT: Script = preload("res://scene/UI/GalaxyHudMusicController.gd")
const STAR_CORE_SHADER := preload("res://scene/galaxy/StarCore.gdshader")
const STAR_GLOW_SHADER := preload("res://scene/galaxy/StarGlow.gdshader")
const DEFAULT_EMPIRE_COUNT := 6
const SYSTEM_PICK_RADIUS := 26.0

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
	_sync_sim_clock_ui()
	_sync_territory_settings_ui()
	_update_system_panel()
	_connect_space_runtime_signals()
	call_deferred("_generate_galaxy_async")


func _exit_tree() -> void:
	_disconnect_space_runtime_signals()
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
	if event.is_action_pressed("ui_cancel"):
		if system_view.is_open():
			if system_view.handle_cancel_action():
				_close_system_view()
			return
		if galaxy_hud.is_settings_visible():
			_set_settings_overlay_visible(false)
			return
		if empire_picker_overlay.visible and not _empire_picker_requires_selection:
			_set_empire_picker_visible(false, false)
			return
		_set_settings_overlay_visible(true)
		return

	if _is_generating:
		return

	if system_view.is_open():
		system_view.handle_view_input(event)
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

	if system_view.is_open():
		return

	if bottom_category_bar.consume_hotkey_event(event):
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if _is_pointer_over_gui():
			return
		if pinned_system_id.is_empty():
			hovered_system_id = _pick_system_at_screen_position(event.position)
			_update_system_panel()
			_update_info_label()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_pointer_over_gui():
			return

		var clicked_system_id: String = _pick_system_at_screen_position(event.position)
		if clicked_system_id.is_empty():
			return
		hovered_system_id = clicked_system_id
		selected_system_id = clicked_system_id
		_update_system_panel()
		_update_info_label()
		_open_system_view(clicked_system_id)
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _is_pointer_over_gui():
			return

		var clicked_system_id: String = _pick_system_at_screen_position(event.position)
		pinned_system_id = clicked_system_id
		hovered_system_id = clicked_system_id
		_render_stars()
		_update_system_panel()
		_update_info_label()


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
	system_view.hide_view()
	_set_galaxy_presentation_visible(true)
	core_stars.multimesh = null
	glow_stars.multimesh = null
	ownership_markers.mesh = null
	ownership_connectors.mesh = null
	hyperlanes.mesh = null
	_runtime_placeholder_renderer.clear_runtime_placeholders()
	system_preview_image.texture = null
	if camera_rig.has_method("reset_view"):
		camera_rig.reset_view(galaxy_radius)

	_set_loading_state(true, "Resolving settings...", 0.1)
	await get_tree().process_frame

	var resolved_settings := {
		"seed_text": seed_text,
		"star_count": star_count,
		"galaxy_radius": galaxy_radius,
		"min_system_distance": min_system_distance,
		"spiral_arms": spiral_arms,
		"shape": galaxy_shape,
		"hyperlane_density": hyperlane_density,
	}
	for key in generation_settings.keys():
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
	if camera_rig.has_method("set_galaxy_radius"):
		camera_rig.set_galaxy_radius(galaxy_radius)
	if camera_rig.has_method("reset_view"):
		camera_rig.reset_view(galaxy_radius)

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
	_render_runtime_placeholders()
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
	var owner_name := "Unclaimed"
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


func _apply_system_detail_state(
	system_id: String,
	resolved_details: Dictionary,
	store_override: bool
) -> bool:
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
	var desired_empire_count := maxi(DEFAULT_EMPIRE_COUNT, preset_empires.size())
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
	var runtime_signals := [
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
	var runtime_signals := [
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
	_render_runtime_placeholders()
	_update_system_panel()


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


func _pick_system_at_screen_position(screen_position: Vector2) -> String:
	var viewport_rect := get_viewport().get_visible_rect()
	var best_system_id := ""
	var best_distance_sq := SYSTEM_PICK_RADIUS * SYSTEM_PICK_RADIUS
	var best_camera_distance_sq := INF

	for system_record in system_records:
		var system_position: Vector3 = system_record.get("position", Vector3.ZERO)
		if camera.is_position_behind(system_position):
			continue

		var projected_position := camera.unproject_position(system_position)
		if not viewport_rect.has_point(projected_position):
			continue

		var screen_distance_sq := projected_position.distance_squared_to(screen_position)
		if screen_distance_sq > best_distance_sq:
			continue

		var camera_distance_sq := camera.global_position.distance_squared_to(system_position)
		if screen_distance_sq < best_distance_sq or (is_equal_approx(screen_distance_sq, best_distance_sq) and camera_distance_sq < best_camera_distance_sq):
			best_distance_sq = screen_distance_sq
			best_camera_distance_sq = camera_distance_sq
			best_system_id = str(system_record.get("id", ""))

	return best_system_id


func _is_pointer_over_gui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _get_selected_empire_id_from_picker() -> String:
	return _scene_ui_controller.get_selected_empire_id_from_picker()


func _format_controller_kind(controller_kind: String) -> String:
	return _scene_ui_controller.format_controller_kind(controller_kind)


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


func _sync_sim_clock_ui() -> void:
	var current_speed: float = SimClock.sim_speed
	_sim_paused = current_speed <= 0.0
	if not _sim_paused:
		var best_index := 0
		var best_distance := INF
		for speed_index in range(_sim_speed_actual_steps.size()):
			var distance: float = absf(_sim_speed_actual_steps[speed_index] - current_speed)
			if distance < best_distance:
				best_distance = distance
				best_index = speed_index
		_sim_speed_index = best_index
	var current_date: Dictionary = SimClock.get_current_date()
	var date_text := "%04d-%02d-%02d" % [
		int(current_date.get("year", 0)),
		int(current_date.get("month", 0)),
		int(current_date.get("day", 0)),
	]
	var speed_value: float = _sim_speed_display_steps[_sim_speed_index]
	var speed_text := "Paused" if _sim_paused else "x%s" % _format_speed_factor(speed_value)
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
	# The bar handles its own visual state today; this hook keeps future category panels easy to add.
	pass
