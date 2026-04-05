extends Node3D
class_name StarSystemPreview

signal selection_changed(selection_data: Dictionary)

const SYSTEM_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT: Script = preload("res://scene/StarSystem/SystemRuntimePlaceholderRenderer.gd")
const SYSTEM_SELECTABLE_COMPONENT_SCRIPT: Script = preload("res://scene/StarSystem/SystemSelectableComponent.gd")
const PROCEDURAL_PLANET_VISUAL_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralPlanetVisual.gd")
const PROCEDURAL_STAR_VISUAL_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralStarVisual.gd")
const PROCEDURAL_ASTEROID_BELT_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralAsteroidBelt.gd")
const ORBITAL_TYPE_PLANET := "planet"
const ORBITAL_TYPE_ASTEROID_BELT := "asteroid_belt"
const ORBITAL_TYPE_STRUCTURE := "structure"
const ORBITAL_TYPE_RUIN := "ruin"
const SPECIAL_TYPE_BLACK_HOLE := "Black hole"
const SPECIAL_TYPE_NEUTRON := "Neutron star"
const SPECIAL_TYPE_O_CLASS := "O class star"
const ORBIT_SEGMENT_COUNT := 80
const SELECTION_RING_SEGMENT_COUNT := 48

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var pivot: Node3D = $Pivot
@onready var orbit_lines: Node3D = $Pivot/OrbitLines
@onready var bodies: Node3D = $Pivot/Bodies
@onready var effects: Node3D = $Pivot/Effects

var _has_content: bool = false
var _current_system_details: Dictionary = {}
var _runtime_placeholder_renderer: RefCounted = SYSTEM_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT.new()
var _selectables: Array[SystemSelectableComponent] = []
var _selected_selectable: SystemSelectableComponent = null
var _selection_indicator: MeshInstance3D = null


func _ready() -> void:
	_runtime_placeholder_renderer.bind(self)
	clear_preview()
	_set_camera_distance(92.0)


func _exit_tree() -> void:
	if _runtime_placeholder_renderer != null:
		_runtime_placeholder_renderer.unbind()


func _unhandled_input(event: InputEvent) -> void:
	if not _has_content:
		return
	if _is_pointer_over_gui():
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var picked_selectable: SystemSelectableComponent = _pick_selectable_at_screen_position(event.position)
		_select_selectable(picked_selectable)
		get_viewport().set_input_as_handled()


func set_system_details(system_details: Dictionary) -> void:
	var previous_selection_id: String = get_selected_selection_id()
	_current_system_details = system_details.duplicate(true)
	_clear_preview_nodes()
	_clear_selectables(false)
	if system_details.is_empty():
		_has_content = false
		_set_camera_distance(92.0)
		_emit_selection_changed()
		return

	var stars: Array = system_details.get("stars", [])
	var orbitals: Array = system_details.get("orbitals", [])
	var max_radius := 22.0

	for star_variant in stars:
		var star: Dictionary = star_variant
		var star_position := _get_orbit_position(star)
		max_radius = maxf(max_radius, star_position.length() + float(star.get("scale", 1.0)) * 8.0)
		_build_star_visual(star, star_position)
		_register_star_selectable(star, star_position)

	for orbital_variant in orbitals:
		var orbital: Dictionary = orbital_variant
		var orbital_radius: float = float(orbital.get("orbit_radius", 0.0))
		var orbital_position := _get_orbit_position(orbital)
		max_radius = maxf(max_radius, orbital_radius + float(orbital.get("size", 1.0)) * 7.0 + float(orbital.get("orbit_width", 0.0)))
		_build_orbit_ring(orbital_radius, float(orbital.get("vertical_offset", 0.0)), _get_orbit_color(orbital))
		_build_orbital_visual(orbital, orbital_position)
		_register_orbital_selectable(orbital, orbital_position)

	var runtime_layouts: Dictionary = _runtime_placeholder_renderer.render_runtime_placeholders(
		system_details.get("space_renderables", {}),
		max_radius
	)
	max_radius = maxf(max_radius, float(runtime_layouts.get("outer_radius", max_radius)))
	_register_runtime_selectables(runtime_layouts)
	_set_camera_distance(max_radius + 24.0)
	_has_content = true
	_restore_selection(previous_selection_id)
	_emit_selection_changed()


func clear_preview() -> void:
	_current_system_details.clear()
	_clear_preview_nodes()
	_clear_selectables()
	_has_content = false
	_set_camera_distance(92.0)


func forward_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.push_input(event, true)


func has_selection() -> bool:
	return _selected_selectable != null


func get_selected_selection_id() -> String:
	if _selected_selectable == null:
		return ""
	return _selected_selectable.selection_id


func clear_selection() -> void:
	_select_selectable(null)


func get_selection_popup_state() -> Dictionary:
	if _selected_selectable == null:
		return {}
	return _selected_selectable.build_popup_state(camera, get_viewport().get_visible_rect())


func _clear_preview_nodes() -> void:
	for container in [orbit_lines, bodies, effects]:
		for child in container.get_children():
			child.free()
	pivot.rotation = Vector3(-0.28, 0.0, 0.0)
	_ensure_selection_indicator()
	_update_selection_indicator()


func _clear_selectables(emit_change: bool = true) -> void:
	_selectables.clear()
	_selected_selectable = null
	_update_selection_indicator()
	if emit_change:
		_emit_selection_changed()


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


func _register_selectable(selectable: SystemSelectableComponent) -> void:
	if selectable == null:
		return
	_selectables.append(selectable)


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
		"anchor_local_position": star_position,
		"screen_pick_radius": 24.0 + float(star.get("scale", 1.0)) * 5.0,
		"highlight_radius": 3.4 + float(star.get("scale", 1.0)) * 1.6,
		"highlight_color": Color(star_color.r, star_color.g, star_color.b, 0.95),
		"pick_priority": 10,
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
		"anchor_local_position": orbital_position,
		"screen_pick_radius": 18.0 + float(orbital.get("size", 1.0)) * 4.0,
		"highlight_radius": 1.8 + float(orbital.get("size", 1.0)) * 0.9,
		"highlight_color": Color(orbital_color.r, orbital_color.g, orbital_color.b, 0.95),
		"pick_priority": 20,
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
	for station_variant in runtime_layouts.get("stations", []):
		var station_entry: Dictionary = station_variant
		_register_runtime_ship_selectable(station_entry.get("record", {}), station_entry.get("position", Vector3.ZERO), true)

	for fleet_variant in runtime_layouts.get("fleets", []):
		var fleet_entry: Dictionary = fleet_variant
		_register_runtime_fleet_selectable(fleet_entry.get("record", {}), fleet_entry.get("position", Vector3.ZERO))

	for ship_variant in runtime_layouts.get("ships", []):
		var ship_entry: Dictionary = ship_variant
		_register_runtime_ship_selectable(ship_entry.get("record", {}), ship_entry.get("position", Vector3.ZERO), false)


func _register_runtime_ship_selectable(record: Dictionary, marker_position: Vector3, is_station: bool) -> void:
	var owner_name: String = str(record.get("owner_name", "Unclaimed"))
	var class_display_name: String = str(record.get("class_display_name", record.get("class_id", "Ship")))
	var entity_kind: String = "station" if is_station else "ship"
	var subtitle: String = "Ship / %s" % owner_name
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
	_append_labeled_line(lines, "Tags", _format_string_list(record.get("command_tags", PackedStringArray()), 6))
	_append_notes_and_metadata(lines, str(record.get("notes", "")), record.get("metadata", {}))

	var owner_color: Color = record.get("owner_color", Color(0.82, 0.88, 1.0, 1.0))
	_register_selectable(_create_selectable({
		"selection_id": "%s:%s" % [entity_kind, str(record.get("ship_id", record.get("display_name", "")))],
		"selection_kind": entity_kind,
		"title": str(record.get("display_name", class_display_name)),
		"subtitle": subtitle,
		"body_text": _join_lines(lines),
		"anchor_local_position": marker_position,
		"screen_pick_radius": 19.0 if is_station else 17.0,
		"highlight_radius": 3.0 if is_station else 2.4,
		"highlight_color": Color(owner_color.r, owner_color.g, owner_color.b, 0.98),
		"pick_priority": 30 if is_station else 26,
	}))


func _register_runtime_fleet_selectable(record: Dictionary, marker_position: Vector3) -> void:
	var owner_name: String = str(record.get("owner_name", "Unclaimed"))
	var ship_count: int = maxi(int(record.get("ship_count", 0)), 1)
	var lines: Array[String] = []
	_append_labeled_line(lines, "Owner", owner_name)
	_append_labeled_line(lines, "Ships", str(ship_count))
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
	_append_labeled_line(lines, "Members", _format_string_list(record.get("ship_display_names", PackedStringArray()), 4))
	_append_notes_and_metadata(lines, str(record.get("notes", "")), record.get("metadata", {}))

	var owner_color: Color = record.get("owner_color", Color(0.82, 0.88, 1.0, 1.0))
	_register_selectable(_create_selectable({
		"selection_id": "fleet:%s" % str(record.get("fleet_id", record.get("display_name", ""))),
		"selection_kind": "fleet",
		"title": str(record.get("display_name", "Fleet")),
		"subtitle": "Fleet / %s" % owner_name,
		"body_text": _join_lines(lines),
		"anchor_local_position": marker_position,
		"screen_pick_radius": 22.0 + minf(float(ship_count), 14.0) * 0.75,
		"highlight_radius": 3.6 + minf(float(ship_count), 18.0) * 0.14,
		"highlight_color": Color(owner_color.r, owner_color.g, owner_color.b, 0.98),
		"pick_priority": 34,
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
	return selectable


func _ensure_selection_indicator() -> void:
	if is_instance_valid(_selection_indicator):
		return
	_selection_indicator = MeshInstance3D.new()
	_selection_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effects.add_child(_selection_indicator)


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


func _build_star_visual(star: Dictionary, star_position: Vector3) -> void:
	var star_visual: ProceduralStarVisual = PROCEDURAL_STAR_VISUAL_SCRIPT.new() as ProceduralStarVisual
	star_visual.position = star_position
	star_visual.configure(star)
	bodies.add_child(star_visual)


func _build_black_hole_disk(star_position: Vector3, star_scale: float) -> void:
	var disk := MultiMeshInstance3D.new()
	var disk_mesh := SphereMesh.new()
	disk_mesh.radius = 0.32
	disk_mesh.height = 0.64
	disk_mesh.radial_segments = 8
	disk_mesh.rings = 4
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = disk_mesh
	multimesh.instance_count = 44

	var rng := RandomNumberGenerator.new()
	rng.seed = int(star_position.length() * 1000.0) + 17
	for instance_index in range(multimesh.instance_count):
		var angle: float = float(instance_index) * TAU / float(multimesh.instance_count) + rng.randf_range(-0.09, 0.09)
		var radius: float = 4.8 * star_scale + rng.randf_range(-0.9, 1.1)
		var local_position := Vector3(cos(angle) * radius, rng.randf_range(-0.18, 0.18), sin(angle) * radius)
		var basis := Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.25))
		multimesh.set_instance_transform(instance_index, Transform3D(basis, local_position))

	disk.multimesh = multimesh
	disk.material_override = _build_lit_material(Color(0.38, 0.52, 0.98, 0.85), Color(0.3, 0.44, 1.0, 1.0), 1.5, 0.45, 0.1)
	var disk_root := Node3D.new()
	disk_root.position = star_position
	disk_root.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	disk_root.add_child(disk)
	effects.add_child(disk_root)


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


func _build_planet(orbital: Dictionary, orbital_position: Vector3) -> void:
	var planet: ProceduralPlanetVisual = PROCEDURAL_PLANET_VISUAL_SCRIPT.new() as ProceduralPlanetVisual
	planet.position = orbital_position
	planet.configure(_current_system_details, orbital)
	bodies.add_child(planet)


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
		camera_rig.configure_view(Vector3.ZERO, distance, -34.0, 0.0)
		return
	camera_rig.position = Vector3(0.0, distance * 0.42, distance)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _get_orbit_color(orbital: Dictionary) -> Color:
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


func _get_star_glow_color(base_color: Color, special_type: String) -> Color:
	match special_type:
		SPECIAL_TYPE_BLACK_HOLE:
			return Color(0.22, 0.36, 0.98, 0.32)
		SPECIAL_TYPE_NEUTRON:
			return Color(0.76, 0.92, 1.0, 0.28)
		SPECIAL_TYPE_O_CLASS:
			return Color(0.62, 0.86, 1.0, 0.3)
		_:
			var glow_color := base_color
			glow_color.a = 0.24
			return glow_color


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


func _format_percentage(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))


func _format_distance(value: float) -> String:
	return "%s u" % _format_number(value, 0.1)


func _format_number(value: float, step: float = 0.1) -> String:
	var snapped_value: float = snappedf(value, step)
	if is_equal_approx(snapped_value, round(snapped_value)):
		return str(int(round(snapped_value)))
	return str(snapped_value)


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


func _is_pointer_over_gui() -> bool:
	return get_viewport().gui_get_hovered_control() != null
