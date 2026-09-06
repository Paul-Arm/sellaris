extends Node3D
class_name StarSystemPreview

signal selection_changed(selection_data: Dictionary)
signal movement_order_requested(selection_data: Dictionary, target_local_position: Vector3)
signal build_menu_requested(builder_unit_id: String, body_context: Dictionary, options: Array[Dictionary], screen_position: Vector2)

const SYSTEM_SKY_SHADER: Shader = preload("res://scene/StarSystem/SystemSkyBackdrop.gdshader")
const CLEAN_SKY_SHADER: Shader = preload("res://scene/StarSystem/design/GalacticSky.gdshader")
const SYSTEM_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT: Script = preload("res://scene/StarSystem/SystemRuntimePlaceholderRenderer.gd")
const SYSTEM_COMBAT_EFFECTS_RENDERER_SCRIPT: Script = preload("res://scene/StarSystem/SystemCombatEffectsRenderer.gd")
const SYSTEM_SELECTABLE_COMPONENT_SCRIPT: Script = preload("res://scene/StarSystem/SystemSelectableComponent.gd")
const PROCEDURAL_PLANET_VISUAL_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralPlanetVisual.gd")
const PROCEDURAL_STAR_VISUAL_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralStarVisual.gd")
const PROCEDURAL_ASTEROID_BELT_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralAsteroidBelt.gd")
const ORBITAL_TYPE_PLANET := "planet"
const ORBITAL_TYPE_ASTEROID_BELT := "asteroid_belt"
const ORBITAL_TYPE_STRUCTURE := "structure"
const ORBITAL_TYPE_RUIN := "ruin"
const STAR_SYSTEM_STAR_SIZE_MULTIPLIER := 1.6
const ORBIT_SEGMENT_COUNT := 80
const SELECTION_RING_SEGMENT_COUNT := 48
const INVALID_COMMAND_TARGET := Vector3(INF, INF, INF)

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var pivot: Node3D = $Pivot
@onready var orbit_lines: Node3D = $Pivot/OrbitLines
@onready var bodies: Node3D = $Pivot/Bodies
@onready var effects: Node3D = $Pivot/Effects

var _right_press_position := Vector2.ZERO
var _right_dragged := false
var _right_down := false

var _has_content: bool = false
var _current_system_details: Dictionary = {}
var _runtime_placeholder_renderer: RefCounted = SYSTEM_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT.new()
var _combat_effects_renderer: SystemCombatEffectsRenderer = SYSTEM_COMBAT_EFFECTS_RENDERER_SCRIPT.new()
var _selectables: Array[SystemSelectableComponent] = []
var _runtime_selectables: Array[SystemSelectableComponent] = []
var _selected_selectable: SystemSelectableComponent = null
var _selection_indicator: MeshInstance3D = null
var _movement_route_indicator: MeshInstance3D = null
var _runtime_effects_root: Node3D = null
var _static_outer_radius: float = 22.0
var _external_selected_builder_unit_id: String = ""
var _primary_star_position := Vector3.ZERO
var _sky_material: ShaderMaterial = null
var _gravity_field: GravityFieldMap = null
var _clean_body_records: Array[Dictionary] = []


func _ready() -> void:
	_runtime_placeholder_renderer.bind(self)
	_combat_effects_renderer.bind(self)
	_setup_backdrop_sky()
	clear_preview()
	_set_camera_distance(92.0)
	SettingsManager.design_changed.connect(_on_design_changed)
	_apply_environment_design()


func _on_design_changed(_variant: String) -> void:
	_apply_environment_design()
	if not _has_content:
		return
	var focus := camera_rig.position
	var distance: float = camera_rig.get("_camera_distance")
	var tilt: float = camera_rig.get("_tilt_degrees")
	var yaw: float = camera_rig.get("_yaw_degrees")
	var details := _current_system_details.duplicate(true)
	set_system_details(details)
	camera_rig.configure_view(focus, distance, tilt, yaw)


func _apply_environment_design() -> void:
	var world := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var clean := DesignDirector.is_clean()
	world.environment.background_mode = Environment.BG_SKY
	world.environment.background_color = Color(0.003, 0.006, 0.010)
	world.environment.ambient_light_energy = 0.35 if clean else 0.55
	world.environment.glow_intensity = 0.65 if clean else 0.22
	world.environment.glow_bloom = 0.0 if clean else 0.08
	if _sky_material != null:
		_sky_material.shader = CLEAN_SKY_SHADER if clean else SYSTEM_SKY_SHADER


# Procedural starfield + nebula backdrop, seeded per system in
# set_system_details(). The environment is duplicated so other instances of
# this scene (tests, panels) are not affected.
func _setup_backdrop_sky() -> void:
	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment.duplicate()
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SYSTEM_SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	world_environment.environment = environment


func _exit_tree() -> void:
	if _runtime_placeholder_renderer != null:
		_runtime_placeholder_renderer.unbind()
	if _combat_effects_renderer != null:
		_combat_effects_renderer.unbind()


func _process(_delta: float) -> void:
	if not _has_content:
		return
	var space_renderables: Dictionary = _current_system_details.get("space_renderables", {})
	if space_renderables.is_empty():
		return
	var day_progress: float = SimClock.get_day_progress() if SimClock != null and SimClock.has_method("get_day_progress") else 1.0
	_runtime_placeholder_renderer.update_interpolated_runtime_positions(space_renderables, day_progress)
	_update_runtime_selectable_positions(space_renderables, day_progress)
	_update_movement_route_indicator(space_renderables, day_progress)


func _input(event: InputEvent) -> void:
	if not _has_content:
		return
	if _is_pointer_over_gui():
		return

	if event is InputEventMouseMotion and _right_down:
		_right_dragged = _right_dragged or event.position.distance_to(_right_press_position) > 5.0
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_right_press_position = event.position
			_right_dragged = false
			_right_down = true
			return # Camera receives the press in _unhandled_input.
		var was_down := _right_down
		_right_down = false
		_cancel_camera_gestures()
		if not was_down or _right_dragged:
			return
		var build_target := _pick_selectable_at_screen_position(event.position)
		if _try_emit_build_menu(build_target, event.position):
			get_viewport().set_input_as_handled()
			return
		var command_target: Vector3 = _get_command_target_at_screen_position(event.position)
		if command_target != INVALID_COMMAND_TARGET:
			movement_order_requested.emit(get_selected_command_entity(), command_target)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var picked_selectable: SystemSelectableComponent = _pick_selectable_at_screen_position(event.position)
		_select_selectable(picked_selectable)
		get_viewport().set_input_as_handled()


func set_system_details(system_details: Dictionary) -> void:
	var previous_system_id := str(_current_system_details.get("id", "")).strip_edges()
	var next_system_id := str(system_details.get("id", "")).strip_edges()
	var previous_selection_id: String = get_selected_selection_id() if previous_system_id == next_system_id else ""
	_current_system_details = system_details.duplicate(true)
	_clear_preview_nodes()
	_clear_selectables(false)
	if system_details.is_empty():
		_has_content = false
		_set_camera_distance(92.0)
		_emit_selection_changed()
		return

	if DesignDirector.is_clean():
		_clean_body_records = GravityFieldMap.collect_bodies(system_details)
	var stars: Array = system_details.get("stars", [])
	var orbitals: Array = system_details.get("orbitals", [])
	var max_radius := 22.0

	if _sky_material != null:
		var backdrop_seed: int = int(system_details.get("seed", str(system_details.get("id", "system")).hash()))
		_sky_material.set_shader_parameter("seed_offset", float(absi(backdrop_seed) % 4096) * 0.37)

	_primary_star_position = Vector3.ZERO
	var has_primary_star := false
	for star_variant in stars:
		var star: Dictionary = star_variant
		var star_position := _get_orbit_position(star)
		max_radius = maxf(max_radius, star_position.length() + float(star.get("scale", 1.0)) * 8.0 * STAR_SYSTEM_STAR_SIZE_MULTIPLIER)
		if not has_primary_star or bool(star.get("is_primary", false)):
			_primary_star_position = star_position
			has_primary_star = true
		_build_star_visual(star, star_position)
		_build_body_deposit_label(star, star_position)
		_register_star_selectable(star, star_position)

	for orbital_variant in orbitals:
		var orbital: Dictionary = orbital_variant
		var orbital_radius: float = float(orbital.get("orbit_radius", 0.0))
		var orbital_position := _get_orbit_position(orbital)
		max_radius = maxf(max_radius, orbital_radius + float(orbital.get("size", 1.0)) * 7.0 + float(orbital.get("orbit_width", 0.0)))
		if not DesignDirector.is_clean():
			_build_orbit_ring(orbital_radius, float(orbital.get("vertical_offset", 0.0)), _get_orbit_color(orbital))
		_build_orbital_visual(orbital, orbital_position)
		_build_body_deposit_label(orbital, orbital_position)
		_register_orbital_selectable(orbital, orbital_position)

	if DesignDirector.is_clean():
		_gravity_field = GravityFieldMap.new()
		bodies.add_child(_gravity_field)
		_gravity_field.configure(system_details, max_radius * 1.6)
	_static_outer_radius = max_radius
	var runtime_layouts: Dictionary = _render_runtime_layer(system_details.get("space_renderables", {}))
	max_radius = maxf(max_radius, float(runtime_layouts.get("outer_radius", max_radius)))
	_register_runtime_selectables(runtime_layouts)
	_set_camera_distance(max_radius + 24.0)
	_has_content = true
	_restore_selection(previous_selection_id)
	_emit_selection_changed()


func clear_preview() -> void:
	_right_down = false
	_cancel_camera_gestures()
	_current_system_details.clear()
	_clear_preview_nodes()
	_clear_selectables()
	_clear_runtime_selectables()
	_static_outer_radius = 22.0
	_has_content = false
	_set_camera_distance(92.0)


func refresh_runtime_placeholders(system_details: Dictionary) -> void:
	if not _has_content:
		set_system_details(system_details)
		return

	var previous_selection_id: String = get_selected_selection_id()
	_current_system_details["space_renderables"] = system_details.get("space_renderables", {})
	_clear_runtime_visuals()
	_clear_runtime_selectables(false)
	var runtime_layouts: Dictionary = _render_runtime_layer(system_details.get("space_renderables", {}))
	_register_runtime_selectables(runtime_layouts)
	_restore_selection(previous_selection_id)
	_emit_selection_changed()


func play_combat_events(events: Array) -> void:
	if not _has_content or _combat_effects_renderer == null:
		return
	var system_id := str(_current_system_details.get("id", "")).strip_edges()
	_combat_effects_renderer.play_events(events, system_id)


func forward_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.push_input(event, true)


func set_external_selected_builder_unit_id(unit_id: String) -> void:
	_external_selected_builder_unit_id = unit_id.strip_edges()


func set_camera_input_blocked(blocked: bool) -> void:
	if camera_rig != null and camera_rig.has_method("set_input_blocked"):
		camera_rig.call("set_input_blocked", blocked)


func has_selection() -> bool:
	return _selected_selectable != null


func get_selected_selection_id() -> String:
	if _selected_selectable == null:
		return ""
	return _selected_selectable.selection_id


func clear_selection() -> void:
	_select_selectable(null)


func select_runtime_entity(selection_kind: String, record_id: String) -> bool:
	var trimmed_record_id := record_id.strip_edges()
	if trimmed_record_id.is_empty():
		return false

	for selection_id in _build_runtime_selection_ids(selection_kind, trimmed_record_id):
		if _select_selectable_by_id(selection_id):
			return true

	return false


func get_selection_popup_state() -> Dictionary:
	if _selected_selectable == null:
		return {}
	return _selected_selectable.build_popup_state(camera, get_viewport().get_visible_rect())


func get_selected_command_entity() -> Dictionary:
	var selectable_entity := _get_selected_selectable_command_entity()
	if not selectable_entity.is_empty():
		return selectable_entity
	return _get_external_builder_command_entity()


func _get_selected_selectable_command_entity() -> Dictionary:
	if _selected_selectable == null:
		return {}
	if not _is_commandable_selection_kind(_selected_selectable.selection_kind):
		return {}
	var parts := _selected_selectable.selection_id.split(":", false, 1)
	if parts.size() < 2:
		return {}
	return {
		"selection_id": _selected_selectable.selection_id,
		"selection_kind": _selected_selectable.selection_kind,
		"record_id": str(parts[1]),
	}


func _get_external_builder_command_entity() -> Dictionary:
	if _external_selected_builder_unit_id.is_empty():
		return {}
	var unit := SpaceManager.get_unit(_external_selected_builder_unit_id)
	if unit == null or not unit.can_build_units():
		return {}
	if not _current_system_details.is_empty() and unit.current_system_id != str(_current_system_details.get("id", "")):
		return {}
	return {
		"selection_id": "unit:%s" % unit.unit_id,
		"selection_kind": SpaceUnitClass.UNIT_KIND_SHIP,
		"record_id": unit.unit_id,
	}


func _clear_preview_nodes() -> void:
	_gravity_field = null
	_clean_body_records.clear()
	for container in [orbit_lines, bodies, effects]:
		for child in container.get_children():
			child.free()
	pivot.rotation = Vector3(-0.28, 0.0, 0.0)
	_runtime_effects_root = null
	_ensure_runtime_effects_root()
	_ensure_selection_indicator()
	_update_selection_indicator()


func _clear_selectables(emit_change: bool = true) -> void:
	_selectables.clear()
	_runtime_selectables.clear()
	_selected_selectable = null
	_update_selection_indicator()
	if emit_change:
		_emit_selection_changed()


func _clear_runtime_selectables(emit_change: bool = true) -> void:
	for selectable in _runtime_selectables:
		_selectables.erase(selectable)
	_runtime_selectables.clear()
	if _selected_selectable != null and not _selectables.has(_selected_selectable):
		_selected_selectable = null
	_update_selection_indicator()
	if emit_change:
		_emit_selection_changed()


func _clear_runtime_visuals() -> void:
	_ensure_runtime_effects_root()
	if _runtime_effects_root == null:
		return
	for child in _runtime_effects_root.get_children():
		child.free()


func _render_runtime_layer(space_renderables: Dictionary) -> Dictionary:
	_ensure_runtime_effects_root()
	return _runtime_placeholder_renderer.render_runtime_placeholders(
		space_renderables,
		_static_outer_radius
	)


func _restore_selection(selection_id: String) -> void:
	if selection_id.is_empty():
		_selected_selectable = null
		_update_selection_indicator()
		return

	for selectable in _selectables:
		if selectable.selection_id != selection_id:
			continue
		_selected_selectable = selectable
		_update_selection_indicator()
		return

	_selected_selectable = null
	_update_selection_indicator()


func _emit_selection_changed() -> void:
	selection_changed.emit(get_selection_popup_state())


func _select_selectable(next_selectable: SystemSelectableComponent) -> void:
	_selected_selectable = next_selectable
	_update_selection_indicator()
	_emit_selection_changed()


func _select_selectable_by_id(selection_id: String) -> bool:
	for selectable in _selectables:
		if selectable.selection_id != selection_id:
			continue
		_select_selectable(selectable)
		return true
	return false


func _build_runtime_selection_ids(selection_kind: String, record_id: String) -> PackedStringArray:
	var normalized_kind := selection_kind.strip_edges()
	var selection_ids := PackedStringArray()
	match normalized_kind:
		"fleet":
			selection_ids.append("fleet:%s" % record_id)
		SpaceUnitClass.UNIT_KIND_STATION, "station":
			selection_ids.append("station:%s" % record_id)
		SpaceUnitClass.UNIT_KIND_SHIP:
			selection_ids.append("%s:%s" % [SpaceUnitClass.UNIT_KIND_SHIP, record_id])
			selection_ids.append("unit:%s" % record_id)
		SpaceUnitClass.UNIT_KIND_CREATURE:
			selection_ids.append("%s:%s" % [SpaceUnitClass.UNIT_KIND_CREATURE, record_id])
			selection_ids.append("unit:%s" % record_id)
		"unit":
			selection_ids.append("unit:%s" % record_id)
			selection_ids.append("%s:%s" % [SpaceUnitClass.UNIT_KIND_SHIP, record_id])
			selection_ids.append("%s:%s" % [SpaceUnitClass.UNIT_KIND_CREATURE, record_id])
			selection_ids.append("station:%s" % record_id)
		"construction":
			selection_ids.append("construction:%s" % record_id)
		_:
			selection_ids.append("%s:%s" % [normalized_kind, record_id])
			selection_ids.append("unit:%s" % record_id)
	return selection_ids


func _pick_selectable_at_screen_position(screen_position: Vector2) -> SystemSelectableComponent:
	var best_selectable: SystemSelectableComponent = null
	var best_score: float = INF
	var best_priority: int = -1000000
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()

	for selectable in _selectables:
		var pick_score: float = selectable.get_pick_score(camera, viewport_rect, screen_position)
		if pick_score == INF:
			continue
		if pick_score < best_score or (is_equal_approx(pick_score, best_score) and selectable.pick_priority > best_priority):
			best_selectable = selectable
			best_score = pick_score
			best_priority = selectable.pick_priority

	return best_selectable


func _try_emit_build_menu(target_selectable: SystemSelectableComponent, screen_position: Vector2) -> bool:
	if target_selectable == null:
		return false
	var body_context := target_selectable.context.duplicate(true)
	if body_context.is_empty() or not body_context.has("buildable_component"):
		return false
	var builder_unit_id := _get_active_builder_unit_id()
	if builder_unit_id.is_empty():
		return false
	var system_id := str(_current_system_details.get("id", ""))
	var options := SpaceManager.get_build_options_for_body(builder_unit_id, system_id, body_context)
	if options.is_empty():
		return false
	build_menu_requested.emit(builder_unit_id, body_context, options, screen_position)
	return true


func _get_active_builder_unit_id() -> String:
	var selected_entity := _get_selected_selectable_command_entity()
	var unit_id := str(selected_entity.get("record_id", ""))
	var unit := SpaceManager.get_unit(unit_id)
	if unit != null and unit.can_build_units():
		return unit.unit_id
	var external_entity := _get_external_builder_command_entity()
	unit_id = str(external_entity.get("record_id", ""))
	unit = SpaceManager.get_unit(unit_id)
	if unit != null and unit.can_build_units():
		return unit.unit_id
	return ""


func _cancel_camera_gestures() -> void:
	if camera_rig != null and camera_rig.has_method("cancel_camera_gestures"):
		camera_rig.call("cancel_camera_gestures")


func _register_selectable(selectable: SystemSelectableComponent) -> void:
	if selectable == null:
		return
	_selectables.append(selectable)


func _register_runtime_selectable(selectable: SystemSelectableComponent) -> void:
	if selectable == null:
		return
	_register_selectable(selectable)
	_runtime_selectables.append(selectable)


func _update_runtime_selectable_positions(space_renderables: Dictionary, day_progress: float) -> void:
	var records_by_key: Dictionary = {}
	for unit_variant in space_renderables.get("units", []):
		var unit_record: Dictionary = unit_variant
		var unit_id := str(unit_record.get("unit_id", ""))
		var unit_kind := str(unit_record.get("unit_kind", SpaceUnitClass.UNIT_KIND_SHIP))
		if not unit_id.is_empty():
			records_by_key["%s:%s" % [unit_kind, unit_id]] = unit_record
			records_by_key["unit:%s" % unit_id] = unit_record
	for fleet_variant in space_renderables.get("fleets", []):
		var fleet_record: Dictionary = fleet_variant
		var fleet_id := str(fleet_record.get("fleet_id", ""))
		if not fleet_id.is_empty():
			records_by_key["fleet:%s" % fleet_id] = fleet_record
	for project_variant in space_renderables.get("construction_projects", []):
		var project_record: Dictionary = project_variant
		var project_id := str(project_record.get("project_id", ""))
		if not project_id.is_empty():
			records_by_key["construction:%s" % project_id] = project_record

	var moved_selected := false
	for selectable in _runtime_selectables:
		if not records_by_key.has(selectable.selection_id):
			continue
		var record: Dictionary = records_by_key[selectable.selection_id]
		selectable.anchor_local_position = _get_visual_record_position(record, day_progress)
		if selectable == _selected_selectable:
			moved_selected = true
	if moved_selected:
		_update_selection_indicator()


func _register_star_selectable(star: Dictionary, star_position: Vector3) -> void:
	var star_name: String = str(star.get("name", star.get("id", "Star")))
	var star_class: String = str(star.get("star_class", "G"))
	var special_type: String = str(star.get("special_type", "none"))
	var subtitle: String = "Star / Class %s" % star_class
	if special_type != "none":
		subtitle = "Star / %s" % special_type

	var lines: Array[String] = []
	_append_labeled_line(lines, "Role", "Primary" if bool(star.get("is_primary", false)) else "Companion")
	_append_labeled_line(lines, "Class", star_class)
	_append_labeled_line(lines, "Color", _format_star_color_name(str(star.get("color_name", ""))))
	_append_labeled_line(lines, "Scale", "%sx" % _format_number(float(star.get("scale", 1.0)), 0.01))
	if special_type != "none":
		_append_labeled_line(lines, "Special", special_type)
	if float(star.get("orbit_radius", 0.0)) > 0.01:
		_append_labeled_line(lines, "Orbit Radius", _format_distance(float(star.get("orbit_radius", 0.0))))
	if absf(float(star.get("vertical_offset", 0.0))) > 0.01:
		_append_labeled_line(lines, "Vertical Offset", _format_distance(float(star.get("vertical_offset", 0.0))))
	_append_notes_and_metadata(lines, str(star.get("notes", "")), star.get("metadata", {}))

	var star_color: Color = star.get("color", Color(1.0, 0.9, 0.55, 1.0))
	_register_selectable(_create_selectable({
		"selection_id": "star:%s" % str(star.get("id", star_name)),
		"selection_kind": "star",
		"title": star_name,
		"subtitle": subtitle,
		"body_text": _join_lines(lines),
		"anchor_local_position": _design_anchor(str(star.get("id", "")), star_position),
		"screen_pick_radius": 24.0 + float(star.get("scale", 1.0)) * 5.0 * STAR_SYSTEM_STAR_SIZE_MULTIPLIER,
		"highlight_radius": 3.4 + float(star.get("scale", 1.0)) * 1.6 * STAR_SYSTEM_STAR_SIZE_MULTIPLIER,
		"highlight_color": Color(star_color.r, star_color.g, star_color.b, 0.95),
		"pick_priority": 10,
		"context": _build_body_context(star, "star", star_position),
	}))


func _register_orbital_selectable(orbital: Dictionary, orbital_position: Vector3) -> void:
	var orbital_type: String = str(orbital.get("type", ORBITAL_TYPE_PLANET))
	var type_label: String = _get_orbital_type_label(orbital_type)
	var lines: Array[String] = []
	_append_labeled_line(lines, "Type", type_label)
	_append_labeled_line(lines, "Orbit Radius", _format_distance(float(orbital.get("orbit_radius", 0.0))))
	if absf(float(orbital.get("vertical_offset", 0.0))) > 0.01:
		_append_labeled_line(lines, "Vertical Offset", _format_distance(float(orbital.get("vertical_offset", 0.0))))
	if orbital_type == ORBITAL_TYPE_ASTEROID_BELT:
		_append_labeled_line(lines, "Belt Width", _format_distance(float(orbital.get("orbit_width", 0.0))))
	else:
		_append_labeled_line(lines, "Size", _format_number(float(orbital.get("size", 1.0)), 0.01))
	if orbital_type == ORBITAL_TYPE_PLANET:
		var world_info: Dictionary = ProceduralPlanetVisual.describe_planet(_current_system_details, orbital)
		_append_labeled_line(lines, "Class", str(world_info.get("label", "Planet")))
		_append_labeled_line(lines, "Colonizable", _format_bool(bool(orbital.get("is_colonizable", false))))
		_append_labeled_line(lines, "Habitability", _format_percentage(float(orbital.get("habitability", 0.0))))
	_append_labeled_line(lines, "Resource Richness", _format_percentage(float(orbital.get("resource_richness", 0.0))))
	_append_notes_and_metadata(lines, str(orbital.get("notes", "")), orbital.get("metadata", {}))

	var orbital_color: Color = orbital.get("color", _get_orbit_color(orbital))
	var selection_config: Dictionary = {
		"selection_id": "%s:%s" % [orbital_type, str(orbital.get("id", orbital.get("name", orbital_type)))],
		"selection_kind": orbital_type,
		"title": str(orbital.get("name", orbital.get("id", type_label))),
		"subtitle": type_label,
		"body_text": _join_lines(lines),
		"anchor_local_position": _design_anchor(str(orbital.get("id", "")), orbital_position),
		"screen_pick_radius": 18.0 + float(orbital.get("size", 1.0)) * 4.0,
		"highlight_radius": 1.8 + float(orbital.get("size", 1.0)) * 0.9,
		"highlight_color": Color(orbital_color.r, orbital_color.g, orbital_color.b, 0.95),
		"pick_priority": 20,
		"context": _build_body_context(orbital, orbital_type, orbital_position),
	}

	if orbital_type == ORBITAL_TYPE_ASTEROID_BELT:
		selection_config["pick_mode"] = SystemSelectableComponent.PICK_MODE_ORBIT_RING
		selection_config["ring_center_local"] = Vector3(0.0, float(orbital.get("vertical_offset", 0.0)), 0.0)
		selection_config["ring_radius"] = float(orbital.get("orbit_radius", 0.0))
		selection_config["ring_pick_tolerance"] = 13.0 + float(orbital.get("orbit_width", 0.0)) * 0.35
		selection_config["highlight_radius"] = maxf(3.2, float(orbital.get("orbit_width", 0.0)) * 0.3)
		selection_config["pick_priority"] = 12

	_register_selectable(_create_selectable(selection_config))


func _register_runtime_selectables(runtime_layouts: Dictionary) -> void:
	for project_variant in runtime_layouts.get("construction_projects", []):
		var project_entry: Dictionary = project_variant
		_register_runtime_construction_selectable(project_entry.get("record", {}), project_entry.get("position", Vector3.ZERO))

	for station_variant in runtime_layouts.get("stations", []):
		var station_entry: Dictionary = station_variant
		_register_runtime_ship_selectable(station_entry.get("record", {}), station_entry.get("position", Vector3.ZERO), true)

	for fleet_variant in runtime_layouts.get("fleets", []):
		var fleet_entry: Dictionary = fleet_variant
		_register_runtime_fleet_selectable(fleet_entry.get("record", {}), fleet_entry.get("position", Vector3.ZERO))

	for unit_variant in runtime_layouts.get("units", []):
		var unit_entry: Dictionary = unit_variant
		_register_runtime_ship_selectable(unit_entry.get("record", {}), unit_entry.get("position", Vector3.ZERO), false)


func _register_runtime_ship_selectable(record: Dictionary, marker_position: Vector3, is_station: bool) -> void:
	var owner_name: String = str(record.get("owner_name", "Unclaimed"))
	var class_display_name: String = str(record.get("class_display_name", record.get("class_id", "Ship")))
	var entity_kind: String = "station" if is_station else str(record.get("unit_kind", "unit"))
	var subtitle: String = "%s / %s" % [_format_token_label(entity_kind), owner_name]
	if is_station:
		subtitle = "Station / %s" % owner_name
	var lines: Array[String] = []
	_append_labeled_line(lines, "Owner", owner_name)
	_append_labeled_line(lines, "Class", class_display_name)
	_append_labeled_line(lines, "Category", _format_token_label(str(record.get("class_category", ""))))
	_append_labeled_line(lines, "Hull", _format_hull_points(
		float(record.get("current_hull_points", 0.0)),
		float(record.get("max_hull_points", 1.0))
	))
	_append_labeled_line(lines, "Role", _format_token_label(str(record.get("ai_role", ""))))
	_append_labeled_line(lines, "Controller", _format_controller_kind(str(record.get("controller_kind", ""))))
	if int(record.get("controller_peer_id", 0)) > 0:
		_append_labeled_line(lines, "Controller Peer", str(int(record.get("controller_peer_id", 0))))
	_append_labeled_line(lines, "Fleet", str(record.get("fleet_name", "")))
	_append_labeled_line(lines, "Destination", str(record.get("destination_system_name", "")))
	if int(record.get("eta_days_remaining", 0)) > 0:
		_append_labeled_line(lines, "ETA", "%d days" % int(record.get("eta_days_remaining", 0)))
	if bool(record.get("is_exploring", false)):
		var exploration_order: Dictionary = record.get("exploration_order", {}) if record.get("exploration_order", {}) is Dictionary else {}
		_append_labeled_line(lines, "Exploration", "%s %d%%" % [
			str(exploration_order.get("state_label", "Active")),
			int(exploration_order.get("progress_percent", 0)),
		])
		_append_labeled_line(lines, "Scan Target", str(exploration_order.get("current_target_name", "")))
	if not is_station:
		_append_labeled_line(lines, "Orders", "Right-click empty space to move")
	_append_labeled_line(lines, "Tags", _format_string_list(record.get("command_tags", PackedStringArray()), 6))
	_append_notes_and_metadata(lines, str(record.get("notes", "")), record.get("metadata", {}))

	var owner_color: Color = record.get("owner_color", Color(0.82, 0.88, 1.0, 1.0))
	_register_runtime_selectable(_create_selectable({
		"selection_id": "%s:%s" % [entity_kind, str(record.get("unit_id", record.get("display_name", "")))],
		"selection_kind": entity_kind,
		"title": str(record.get("display_name", class_display_name)),
		"subtitle": subtitle,
		"body_text": _join_lines(lines),
		"anchor_local_position": marker_position,
		"screen_pick_radius": 19.0 if is_station else 17.0,
		"highlight_radius": 3.0 if is_station else 2.4,
		"highlight_color": Color(owner_color.r, owner_color.g, owner_color.b, 0.98),
		"pick_priority": 30 if is_station else 26,
		"context": _build_runtime_body_context(record, entity_kind, marker_position, is_station),
	}))


func _register_runtime_construction_selectable(record: Dictionary, marker_position: Vector3) -> void:
	var project_id := str(record.get("project_id", "")).strip_edges()
	if project_id.is_empty():
		return
	var owner_name: String = str(record.get("owner_name", "Unclaimed"))
	var class_display_name: String = str(record.get("class_display_name", record.get("build_class_id", "Station")))
	var progress_ratio := clampf(float(record.get("progress_ratio", 0.0)), 0.0, 1.0)
	var lines: Array[String] = []
	_append_labeled_line(lines, "Owner", owner_name)
	_append_labeled_line(lines, "Class", class_display_name)
	_append_labeled_line(lines, "Target", str(record.get("target_body_name", record.get("target_body_id", ""))))
	_append_labeled_line(lines, "Status", _format_construction_state(str(record.get("construction_state", ""))))
	_append_labeled_line(lines, "Progress", _format_percentage(progress_ratio))
	_append_labeled_line(lines, "Remaining", "%d days" % int(record.get("days_remaining", 0)))
	_append_labeled_line(lines, "Builder", str(record.get("builder_name", record.get("builder_unit_id", ""))))

	var owner_color: Color = record.get("owner_color", Color(0.82, 0.88, 1.0, 1.0))
	_register_runtime_selectable(_create_selectable({
		"selection_id": "construction:%s" % project_id,
		"selection_kind": "construction",
		"title": str(record.get("display_name", class_display_name)),
		"subtitle": "Bauprojekt / %s" % owner_name,
		"body_text": _join_lines(lines),
		"anchor_local_position": marker_position,
		"screen_pick_radius": 19.0,
		"highlight_radius": 3.2,
		"highlight_color": Color(owner_color.r, owner_color.g, owner_color.b, 0.98),
		"pick_priority": 28,
		"context": _build_runtime_body_context(record, "construction", marker_position, false),
	}))


func _register_runtime_fleet_selectable(record: Dictionary, marker_position: Vector3) -> void:
	var owner_name: String = str(record.get("owner_name", "Unclaimed"))
	var unit_count: int = maxi(int(record.get("unit_count", 0)), 1)
	var lines: Array[String] = []
	_append_labeled_line(lines, "Owner", owner_name)
	_append_labeled_line(lines, "Units", str(unit_count))
	_append_labeled_line(lines, "Role", _format_token_label(str(record.get("ai_role", ""))))
	_append_labeled_line(lines, "Controller", _format_controller_kind(str(record.get("controller_kind", ""))))
	if int(record.get("controller_peer_id", 0)) > 0:
		_append_labeled_line(lines, "Controller Peer", str(int(record.get("controller_peer_id", 0))))
	_append_labeled_line(lines, "Home", str(record.get("home_system_name", "")))
	_append_labeled_line(lines, "Destination", str(record.get("destination_system_name", "")))
	if int(record.get("eta_days_remaining", 0)) > 0:
		_append_labeled_line(lines, "ETA", "%d days" % int(record.get("eta_days_remaining", 0)))
	if int(record.get("command_queue_size", 0)) > 0:
		_append_labeled_line(lines, "Queued Commands", str(int(record.get("command_queue_size", 0))))
	_append_labeled_line(lines, "Orders", "Right-click empty space to move")
	_append_labeled_line(lines, "Members", _format_string_list(record.get("unit_display_names", PackedStringArray()), 4))
	_append_notes_and_metadata(lines, str(record.get("notes", "")), record.get("metadata", {}))

	var owner_color: Color = record.get("owner_color", Color(0.82, 0.88, 1.0, 1.0))
	_register_runtime_selectable(_create_selectable({
		"selection_id": "fleet:%s" % str(record.get("fleet_id", record.get("display_name", ""))),
		"selection_kind": "fleet",
		"title": str(record.get("display_name", "Fleet")),
		"subtitle": "Fleet / %s" % owner_name,
		"body_text": _join_lines(lines),
		"anchor_local_position": marker_position,
		"screen_pick_radius": 22.0 + minf(float(unit_count), 14.0) * 0.75,
		"highlight_radius": 3.6 + minf(float(unit_count), 18.0) * 0.14,
		"highlight_color": Color(owner_color.r, owner_color.g, owner_color.b, 0.98),
		"pick_priority": 34,
		"context": _build_runtime_body_context(record, "fleet", marker_position, false),
	}))


func _create_selectable(config: Dictionary) -> SystemSelectableComponent:
	var selectable := SYSTEM_SELECTABLE_COMPONENT_SCRIPT.new() as SystemSelectableComponent
	selectable.selection_id = str(config.get("selection_id", ""))
	selectable.selection_kind = str(config.get("selection_kind", ""))
	selectable.title = str(config.get("title", selectable.selection_id))
	selectable.subtitle = str(config.get("subtitle", ""))
	selectable.body_text = str(config.get("body_text", ""))
	selectable.pick_mode = str(config.get("pick_mode", SystemSelectableComponent.PICK_MODE_POINT))
	selectable.pick_priority = int(config.get("pick_priority", 0))
	selectable.space_transform = pivot.global_transform
	selectable.anchor_local_position = config.get("anchor_local_position", Vector3.ZERO)
	selectable.screen_pick_radius = float(config.get("screen_pick_radius", 18.0))
	selectable.highlight_radius = float(config.get("highlight_radius", 2.0))
	selectable.highlight_color = config.get("highlight_color", Color(0.92, 0.96, 1.0, 0.95))
	selectable.ring_center_local = config.get("ring_center_local", Vector3.ZERO)
	selectable.ring_radius = float(config.get("ring_radius", 0.0))
	selectable.ring_pick_tolerance = float(config.get("ring_pick_tolerance", 14.0))
	selectable.context = config.get("context", {}).duplicate(true) if config.get("context", {}) is Dictionary else {}
	return selectable


func _build_body_context(body_record: Dictionary, body_type: String, local_position: Vector3) -> Dictionary:
	var body_id := str(body_record.get("id", body_record.get("name", body_type))).strip_edges()
	return {
		"system_id": str(_current_system_details.get("id", "")),
		"system_name": str(_current_system_details.get("name", "")),
		"generated_seed": int(_current_system_details.get("generated_seed", _current_system_details.get("seed", 0))),
		"body_id": body_id,
		"body_type": body_type,
		"body_name": str(body_record.get("name", body_id)),
		"host_kind": ColonyRuntime.HOST_KIND_ORBITAL,
		"host_id": body_id,
		"local_position": local_position,
		"size": float(body_record.get("size", body_record.get("scale", 1.0))),
		"body_record": body_record.duplicate(true),
		"buildable_component": body_record.get("buildable_component", {}).duplicate(true) if body_record.get("buildable_component", {}) is Dictionary else {},
	}


func _build_runtime_body_context(record: Dictionary, body_type: String, local_position: Vector3, is_station: bool) -> Dictionary:
	var record_id := str(record.get("unit_id", record.get("fleet_id", record.get("project_id", record.get("display_name", ""))))).strip_edges()
	var host_kind := ColonyRuntime.HOST_KIND_SPACE_UNIT if is_station else ""
	return {
		"system_id": str(_current_system_details.get("id", "")),
		"system_name": str(_current_system_details.get("name", "")),
		"generated_seed": int(_current_system_details.get("generated_seed", _current_system_details.get("seed", 0))),
		"body_id": record_id,
		"body_type": body_type,
		"body_name": str(record.get("display_name", record.get("class_display_name", record_id))),
		"host_kind": host_kind,
		"host_id": record_id if is_station else "",
		"local_position": local_position,
		"size": 1.0,
		"body_record": record.duplicate(true),
		"buildable_component": {},
	}


func _ensure_selection_indicator() -> void:
	if is_instance_valid(_selection_indicator):
		return
	_selection_indicator = MeshInstance3D.new()
	_selection_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effects.add_child(_selection_indicator)


func _ensure_movement_route_indicator() -> void:
	if is_instance_valid(_movement_route_indicator):
		return
	_movement_route_indicator = MeshInstance3D.new()
	_movement_route_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effects.add_child(_movement_route_indicator)


func get_runtime_effects_root() -> Node3D:
	_ensure_runtime_effects_root()
	return _runtime_effects_root


func _ensure_runtime_effects_root() -> void:
	if is_instance_valid(_runtime_effects_root):
		return
	if effects == null:
		return
	_runtime_effects_root = Node3D.new()
	_runtime_effects_root.name = "RuntimeEffects"
	effects.add_child(_runtime_effects_root)


func _update_selection_indicator() -> void:
	_ensure_selection_indicator()
	if _selection_indicator == null:
		return
	if _selected_selectable == null:
		_selection_indicator.mesh = null
		return

	var indicator_radius: float = maxf(_selected_selectable.highlight_radius, 1.4)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)

	for point_index in range(SELECTION_RING_SEGMENT_COUNT):
		var from_angle: float = float(point_index) * TAU / float(SELECTION_RING_SEGMENT_COUNT)
		var to_angle: float = float(point_index + 1) * TAU / float(SELECTION_RING_SEGMENT_COUNT)
		surface_tool.set_color(_selected_selectable.highlight_color)
		surface_tool.add_vertex(_selected_selectable.anchor_local_position + Vector3(cos(from_angle) * indicator_radius, 0.28, sin(from_angle) * indicator_radius))
		surface_tool.set_color(_selected_selectable.highlight_color)
		surface_tool.add_vertex(_selected_selectable.anchor_local_position + Vector3(cos(to_angle) * indicator_radius, 0.28, sin(to_angle) * indicator_radius))

	_selection_indicator.mesh = surface_tool.commit()
	_selection_indicator.position = Vector3.ZERO
	_selection_indicator.material_override = _build_line_material(0.7)


func _update_movement_route_indicator(space_renderables: Dictionary, day_progress: float) -> void:
	_ensure_movement_route_indicator()
	if _movement_route_indicator == null:
		return
	var record: Dictionary = _get_selected_runtime_record(space_renderables)
	if record.is_empty() or str(record.get("movement_state", "")) != SpaceUnitRuntime.MOVEMENT_MOVING:
		_movement_route_indicator.mesh = null
		return

	var start_position := _get_visual_record_position(record, day_progress)
	var target_position := _variant_to_vector3(record.get("target_local_position", start_position))
	if start_position.distance_to(target_position) < 0.5:
		_movement_route_indicator.mesh = null
		return

	_movement_route_indicator.mesh = _build_dotted_line_mesh(start_position + Vector3.UP * 0.42, target_position + Vector3.UP * 0.42, 1.2, 0.9, Color(0.62, 0.9, 1.0, 0.82))
	_movement_route_indicator.position = Vector3.ZERO
	if _movement_route_indicator.material_override == null:
		_movement_route_indicator.material_override = _build_line_material(0.9)


func _get_selected_runtime_record(space_renderables: Dictionary) -> Dictionary:
	if _selected_selectable == null:
		return {}
	for unit_variant in space_renderables.get("units", []):
		var unit_record: Dictionary = unit_variant
		var unit_id := str(unit_record.get("unit_id", ""))
		var unit_kind := str(unit_record.get("unit_kind", SpaceUnitClass.UNIT_KIND_SHIP))
		if _selected_selectable.selection_id == "%s:%s" % [unit_kind, unit_id] or _selected_selectable.selection_id == "unit:%s" % unit_id:
			return unit_record
	for fleet_variant in space_renderables.get("fleets", []):
		var fleet_record: Dictionary = fleet_variant
		if _selected_selectable.selection_id == "fleet:%s" % str(fleet_record.get("fleet_id", "")):
			return fleet_record
	return {}


func _get_visual_record_position(record: Dictionary, day_progress: float) -> Vector3:
	if str(record.get("movement_state", SpaceUnitRuntime.MOVEMENT_IDLE)) != SpaceUnitRuntime.MOVEMENT_MOVING:
		return _variant_to_vector3(record.get("local_position", Vector3.ZERO))
	var previous := _variant_to_vector3(record.get("previous_local_position", record.get("local_position", Vector3.ZERO)))
	var current := _variant_to_vector3(record.get("local_position", previous))
	return previous.lerp(current, clampf(day_progress, 0.0, 1.0))


func _build_dotted_line_mesh(start_position: Vector3, end_position: Vector3, dash_length: float, gap_length: float, color: Color) -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)
	var offset := end_position - start_position
	var distance := offset.length()
	if distance <= 0.001:
		return surface_tool.commit()
	var direction := offset / distance
	var cursor := 0.0
	while cursor < distance:
		var segment_end := minf(cursor + dash_length, distance)
		surface_tool.set_color(color)
		surface_tool.add_vertex(start_position + direction * cursor)
		surface_tool.set_color(color)
		surface_tool.add_vertex(start_position + direction * segment_end)
		cursor += dash_length + gap_length
	return surface_tool.commit()


func _get_command_target_at_screen_position(screen_position: Vector2) -> Vector3:
	if get_selected_command_entity().is_empty():
		return INVALID_COMMAND_TARGET
	if camera == null or pivot == null:
		return INVALID_COMMAND_TARGET

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var plane_normal: Vector3 = pivot.global_transform.basis * Vector3.UP
	plane_normal = plane_normal.normalized()
	var denominator := plane_normal.dot(ray_direction)
	if absf(denominator) <= 0.0001:
		return INVALID_COMMAND_TARGET
	var distance := plane_normal.dot(pivot.global_transform.origin - ray_origin) / denominator
	if distance < 0.0:
		return INVALID_COMMAND_TARGET
	var intersection := ray_origin + ray_direction * distance

	var target_local: Vector3 = pivot.to_local(intersection)
	target_local.y = 0.0
	return target_local


func _is_commandable_selection_kind(selection_kind: String) -> bool:
	match selection_kind:
		"fleet", SpaceUnitClass.UNIT_KIND_SHIP, SpaceUnitClass.UNIT_KIND_CREATURE, "unit":
			return true
		_:
			return false


func _build_star_visual(star: Dictionary, star_position: Vector3) -> void:
	if DesignDirector.is_clean():
		return
	var star_visual: ProceduralStarVisual = PROCEDURAL_STAR_VISUAL_SCRIPT.new() as ProceduralStarVisual
	star_visual.position = star_position
	star_visual.configure(star)
	bodies.add_child(star_visual)


func _build_orbital_visual(orbital: Dictionary, orbital_position: Vector3) -> void:
	var orbital_type: String = str(orbital.get("type", ORBITAL_TYPE_PLANET))
	match orbital_type:
		ORBITAL_TYPE_ASTEROID_BELT:
			_build_asteroid_belt(orbital)
		ORBITAL_TYPE_STRUCTURE:
			_build_structure(orbital, orbital_position)
		ORBITAL_TYPE_RUIN:
			_build_ruin(orbital, orbital_position)
		_:
			_build_planet(orbital, orbital_position)


func _build_body_deposit_label(body_record: Dictionary, body_position: Vector3) -> void:
	if DesignDirector.is_clean():
		return
	if not _should_show_deposit_labels():
		return
	if EconomyManager == null or not EconomyManager.has_method("preview_body_deposit_income"):
		return

	var system_id := str(_current_system_details.get("id", "")).strip_edges()
	var galaxy_seed := int(_current_system_details.get("generated_seed", _current_system_details.get("seed", 0)))
	var deposits: Dictionary = EconomyManager.preview_body_deposit_income(galaxy_seed, system_id, body_record)
	if deposits.is_empty():
		return

	var label := Label3D.new()
	label.name = "DepositLabel_%s" % str(body_record.get("id", body_record.get("name", "body")))
	label.text = _format_deposit_label(deposits)
	label.position = body_position + Vector3(0.0, -_get_deposit_label_offset(body_record), 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 18
	label.pixel_size = 0.036
	label.outline_size = 8
	label.modulate = Color(0.76, 0.93, 0.98, 0.95)
	label.outline_modulate = Color(0.02, 0.04, 0.06, 0.92)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bodies.add_child(label)


func _should_show_deposit_labels() -> bool:
	if _current_system_details.has("has_full_intel"):
		return bool(_current_system_details.get("has_full_intel", false))
	return true


func _format_deposit_label(deposits: Dictionary) -> String:
	var resource_ids: Array[String] = []
	for resource_id_variant in deposits.keys():
		var resource_id := str(resource_id_variant).strip_edges()
		if resource_id.is_empty():
			continue
		resource_ids.append(resource_id)
	resource_ids.sort()

	var parts: Array[String] = []
	for resource_id in resource_ids:
		if parts.size() >= 3:
			break
		parts.append("%s %s" % [
			_format_token_label(resource_id),
			_format_milliunits(int(deposits.get(resource_id, 0))),
		])
	if resource_ids.size() > parts.size():
		parts.append("+%d" % (resource_ids.size() - parts.size()))
	return "  ".join(parts)


func _get_deposit_label_offset(body_record: Dictionary) -> float:
	var body_type := _resolve_deposit_body_type(body_record)
	match body_type:
		"star":
			return maxf(4.0, float(body_record.get("scale", 1.0)) * 8.0 * STAR_SYSTEM_STAR_SIZE_MULTIPLIER + 2.2)
		ORBITAL_TYPE_ASTEROID_BELT:
			return maxf(2.8, float(body_record.get("orbit_width", 1.0)) * 0.18 + 2.0)
		ORBITAL_TYPE_STRUCTURE, ORBITAL_TYPE_RUIN:
			return maxf(2.4, float(body_record.get("size", 1.0)) * 1.6 + 1.2)
		_:
			return maxf(2.4, float(body_record.get("size", 1.0)) * 1.75 + 1.15)


func _resolve_deposit_body_type(body_record: Dictionary) -> String:
	if body_record.has("type"):
		return str(body_record.get("type", ORBITAL_TYPE_PLANET))
	if body_record.has("kind"):
		var kind := str(body_record.get("kind", ORBITAL_TYPE_PLANET))
		if kind == "star" or kind == "black_hole":
			return "star"
		return kind
	if body_record.has("star_class") or body_record.has("color_name"):
		return "star"
	return ORBITAL_TYPE_PLANET


func _build_planet(orbital: Dictionary, orbital_position: Vector3) -> void:
	if DesignDirector.is_clean():
		return
	var planet: ProceduralPlanetVisual = PROCEDURAL_PLANET_VISUAL_SCRIPT.new() as ProceduralPlanetVisual
	planet.position = orbital_position
	planet.configure(_current_system_details, orbital)
	bodies.add_child(planet)
	planet.set_sun_world_position(_get_sun_world_position())


# Sun position for the planet shaders' point-light mode, in world space (the
# bodies container local positions pass through the tilted Pivot transform).
func _get_sun_world_position() -> Vector3:
	if bodies != null and bodies.is_inside_tree():
		return bodies.to_global(_primary_star_position)
	return _primary_star_position


func _build_structure(orbital: Dictionary, orbital_position: Vector3) -> void:
	var structure := MeshInstance3D.new()
	var box := BoxMesh.new()
	var size: float = float(orbital.get("size", 1.0))
	box.size = Vector3.ONE * size * 2.1
	structure.mesh = box
	structure.material_override = _build_lit_material(
		orbital.get("color", Color(0.42, 0.8, 1.0, 1.0)),
		Color(0.32, 0.78, 1.0, 1.0),
		0.7,
		0.25,
		0.1
	)
	structure.position = orbital_position
	structure.rotation = Vector3(0.3, 0.75, 0.2)
	bodies.add_child(structure)


func _build_ruin(orbital: Dictionary, orbital_position: Vector3) -> void:
	var ruin_root := Node3D.new()
	ruin_root.position = orbital_position
	bodies.add_child(ruin_root)

	for part_index in range(3):
		var fragment := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size: float = float(orbital.get("size", 1.0))
		box.size = Vector3.ONE * size * (1.0 - float(part_index) * 0.18)
		fragment.mesh = box
		fragment.material_override = _build_lit_material(
			orbital.get("color", Color(0.72, 0.73, 0.78, 1.0)),
			Color(0.18, 0.22, 0.28, 1.0),
			0.22,
			0.95,
			0.0
		)
		fragment.position = Vector3(
			0.35 * float(part_index),
			0.16 * float(part_index),
			-0.28 * float(part_index)
		)
		fragment.rotation = Vector3(0.2 * float(part_index), 0.55 * float(part_index), 0.16 * float(part_index))
		ruin_root.add_child(fragment)


func _build_asteroid_belt(orbital: Dictionary) -> void:
	var belt: ProceduralAsteroidBelt = PROCEDURAL_ASTEROID_BELT_SCRIPT.new() as ProceduralAsteroidBelt
	belt.configure(orbital)
	bodies.add_child(belt)
	belt.set_sun_world_position(_get_sun_world_position())


func _build_orbit_ring(radius: float, height: float, color: Color) -> void:
	if radius <= 0.1:
		return

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)
	var orbit_color := color
	orbit_color.a = 0.22

	for point_index in range(ORBIT_SEGMENT_COUNT):
		var from_angle: float = float(point_index) * TAU / float(ORBIT_SEGMENT_COUNT)
		var to_angle: float = float(point_index + 1) * TAU / float(ORBIT_SEGMENT_COUNT)
		surface_tool.set_color(orbit_color)
		surface_tool.add_vertex(Vector3(cos(from_angle) * radius, height, sin(from_angle) * radius))
		surface_tool.set_color(orbit_color)
		surface_tool.add_vertex(Vector3(cos(to_angle) * radius, height, sin(to_angle) * radius))

	var ring := MeshInstance3D.new()
	ring.mesh = surface_tool.commit()
	ring.material_override = _build_line_material()
	orbit_lines.add_child(ring)


func _get_orbit_position(body: Dictionary) -> Vector3:
	var radius: float = float(body.get("orbit_radius", 0.0))
	var angle: float = float(body.get("orbit_angle", 0.0))
	return Vector3(
		cos(angle) * radius,
		float(body.get("vertical_offset", 0.0)),
		sin(angle) * radius
	)


func _set_camera_distance(distance: float) -> void:
	if camera_rig.has_method("configure_view"):
		camera_rig.configure_view(Vector3.ZERO, distance * (1.5 if DesignDirector.is_clean() else 1.0), -44.0 if DesignDirector.is_clean() else -34.0, 0.0)
		return
	camera_rig.position = Vector3(0.0, distance * 0.42, distance)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _get_orbit_color(orbital: Dictionary) -> Color:
	if DesignDirector.is_clean():
		return Color(0.37, 0.55, 0.57, 0.20)
	var orbital_type: String = str(orbital.get("type", ORBITAL_TYPE_PLANET))
	match orbital_type:
		ORBITAL_TYPE_ASTEROID_BELT:
			return Color(0.62, 0.58, 0.52, 0.2)
		ORBITAL_TYPE_STRUCTURE:
			return Color(0.42, 0.8, 1.0, 0.22)
		ORBITAL_TYPE_RUIN:
			return Color(0.72, 0.73, 0.78, 0.2)
		_:
			return Color(0.72, 0.84, 1.0, 0.2)


func _build_lit_material(
	albedo: Color,
	emission: Color,
	emission_energy: float,
	roughness: float,
	metallic: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	if albedo.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = roughness
	material.metallic = metallic
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = emission_energy
	return material


func _build_unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.0
	return material


func _build_line_material(emission_energy: float = 0.18) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = emission_energy
	return material


func _append_labeled_line(lines: Array[String], label: String, value: String) -> void:
	var trimmed_value: String = value.strip_edges()
	if trimmed_value.is_empty():
		return
	lines.append("%s: %s" % [label, trimmed_value])


func _append_notes_and_metadata(lines: Array[String], notes: String, metadata_variant: Variant) -> void:
	var trimmed_notes: String = notes.strip_edges()
	if not trimmed_notes.is_empty():
		lines.append("Notes: %s" % trimmed_notes)
	if metadata_variant is Dictionary:
		_append_flattened_dictionary_lines(lines, metadata_variant, "Data")


func _append_flattened_dictionary_lines(lines: Array[String], source: Dictionary, prefix: String) -> void:
	if source.is_empty():
		return
	var keys: Array = source.keys()
	keys.sort()
	for key_variant in keys:
		var key: String = str(key_variant)
		var value: Variant = source[key_variant]
		if value is Dictionary:
			_append_flattened_dictionary_lines(lines, value, "%s %s" % [prefix, _format_key_label(key)])
			continue
		var formatted_value: String = _format_variant_value(value)
		if formatted_value.is_empty():
			continue
		lines.append("%s %s: %s" % [prefix, _format_key_label(key), formatted_value])


func _join_lines(lines: Array[String]) -> String:
	return "\n".join(lines)


func _get_orbital_type_label(orbital_type: String) -> String:
	match orbital_type:
		ORBITAL_TYPE_ASTEROID_BELT:
			return "Asteroid Belt"
		ORBITAL_TYPE_STRUCTURE:
			return "Structure"
		ORBITAL_TYPE_RUIN:
			return "Ruin"
		_:
			return "Planet"


func _format_key_label(value: String) -> String:
	var words: PackedStringArray = value.replace("-", "_").split("_", false)
	var formatted_words: Array[String] = []
	for word in words:
		var trimmed_word: String = word.strip_edges()
		if trimmed_word.is_empty():
			continue
		formatted_words.append(trimmed_word.capitalize())
	return " ".join(formatted_words)


func _format_token_label(value: String) -> String:
	var trimmed_value: String = value.strip_edges()
	if trimmed_value.is_empty():
		return ""
	return _format_key_label(trimmed_value)


func _format_star_color_name(value: String) -> String:
	var trimmed_value: String = value.strip_edges()
	if trimmed_value.is_empty() or trimmed_value == "Void":
		return trimmed_value
	return _format_token_label(trimmed_value)


func _format_controller_kind(controller_kind: String) -> String:
	match controller_kind:
		"player_local":
			return "Player"
		"player_remote":
			return "Remote Player"
		"ai":
			return "AI"
		"unassigned":
			return "Unassigned"
		_:
			return _format_token_label(controller_kind)


func _format_construction_state(construction_state: String) -> String:
	match construction_state:
		SpaceManager.CONSTRUCTION_STATE_MOVING_TO_SITE:
			return "Anflug zur Baustelle"
		SpaceManager.CONSTRUCTION_STATE_BUILDING:
			return "Im Bau"
		_:
			return _format_token_label(construction_state)


func _format_percentage(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))


func _format_distance(value: float) -> String:
	return "%s u" % _format_number(value, 0.1)


func _format_number(value: float, step: float = 0.1) -> String:
	var snapped_value: float = snappedf(value, step)
	if is_equal_approx(snapped_value, round(snapped_value)):
		return str(int(round(snapped_value)))
	return str(snapped_value)


func _format_milliunits(value: int) -> String:
	var sign := "+" if value >= 0 else "-"
	var absolute_value := absi(value)
	var whole_units := absolute_value / 1000
	var milli_units := absolute_value % 1000
	if milli_units == 0:
		return "%s%d" % [sign, whole_units]
	return "%s%d.%03d" % [sign, whole_units, milli_units]


func _format_hull_points(current_points: float, max_points: float) -> String:
	var safe_max_points: float = maxf(max_points, 1.0)
	var hull_ratio: float = current_points / safe_max_points
	return "%s / %s (%s)" % [
		_format_number(current_points, 1.0),
		_format_number(safe_max_points, 1.0),
		_format_percentage(hull_ratio),
	]


func _format_string_list(values_variant: Variant, max_items: int) -> String:
	var values := PackedStringArray()
	if values_variant is PackedStringArray:
		values = values_variant
	elif values_variant is Array:
		for value_variant in values_variant:
			var value_text: String = str(value_variant).strip_edges()
			if value_text.is_empty():
				continue
			values.append(value_text)
	else:
		return ""

	if values.is_empty():
		return ""

	var display_values: Array[String] = []
	for value_index in range(mini(values.size(), max_items)):
		display_values.append(values[value_index])
	var result: String = ", ".join(display_values)
	if values.size() > max_items:
		result += " +%d more" % (values.size() - max_items)
	return result


func _format_variant_value(value: Variant) -> String:
	if value is bool:
		return _format_bool(value)
	if value is int:
		return str(value)
	if value is float:
		return _format_number(value, 0.01)
	if value is PackedStringArray or value is Array:
		return _format_string_list(value, 6)
	if value is Color:
		return value.to_html()
	if value is String:
		return value.strip_edges()
	return str(value)


func _format_bool(value: bool) -> String:
	return "Yes" if value else "No"


static func _variant_to_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("z", 0.0))
		)
	if value is Array:
		var values: Array = value
		if values.size() >= 3:
			return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO


func _is_pointer_over_gui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _design_anchor(body_id: String, position: Vector3) -> Vector3:
	for record in _clean_body_records:
		if str(record["id"]) == body_id:
			return GravityFieldMap.visual_position(record, _clean_body_records)
	return position
