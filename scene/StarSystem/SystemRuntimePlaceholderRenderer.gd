extends RefCounted
class_name SystemRuntimePlaceholderRenderer

const STATION_RING_OFFSET: float = 12.0
const FLEET_RING_OFFSET: float = 22.0
const SHIP_RING_OFFSET: float = 31.0
const RING_STEP: float = 5.5
const SLOTS_PER_RING: int = 8
const SHIP_MARKER_TEXTURE: Texture2D = preload("res://assets/ships/spaceship.png")
const FLEET_MEMBER_MARKER_SIZE: float = 2.35
const SHIP_MARKER_SIZE: float = 2.8
const FLEET_MARKER_TINT_STRENGTH: float = 0.18
const SHIP_MARKER_TINT_STRENGTH: float = 0.1
const FLEET_MEMBER_SLOTS_PER_RING: int = 6
const FLEET_MEMBER_RING_STEP: float = 1.9
const FLEET_MEMBER_BASE_RADIUS: float = 1.4
const CONSTRUCTION_SITE_RADIUS: float = 2.35
const CONSTRUCTION_RING_SEGMENTS: int = 52
const CONSTRUCTION_PARTICLES_PER_PROJECT: int = 14
const CONSTRUCTION_PARTICLE_SIZE: float = 0.18

var _host: StarSystemPreview = null
var _station_marker: MultiMeshInstance3D = null
var _fleet_marker: MultiMeshInstance3D = null
var _unit_marker: MultiMeshInstance3D = null
var _construction_particle_marker: MultiMeshInstance3D = null
var _station_instance_specs: Array[Dictionary] = []
var _fleet_instance_specs: Array[Dictionary] = []
var _unit_instance_specs: Array[Dictionary] = []
var _construction_particle_specs: Array[Dictionary] = []


func bind(host: StarSystemPreview) -> void:
	_host = host


func unbind() -> void:
	_host = null


func render_runtime_placeholders(space_renderables: Dictionary, outer_radius: float) -> Dictionary:
	_reset_interpolation_state()
	var result := {
		"outer_radius": outer_radius,
		"stations": [],
		"fleets": [],
		"units": [],
		"construction_projects": [],
	}

	if _host == null:
		return result

	var units_variant: Variant = space_renderables.get("units", [])
	if units_variant is not Array:
		return result
	var fleets_variant: Variant = space_renderables.get("fleets", [])
	var construction_variant: Variant = space_renderables.get("construction_projects", [])

	var mobile_units: Array[Dictionary] = []
	var stations: Array[Dictionary] = []
	var fleets: Array[Dictionary] = []
	var construction_projects: Array[Dictionary] = []
	var fleet_unit_ids: Dictionary = {}
	var units_by_id: Dictionary = {}

	if fleets_variant is Array:
		for fleet_variant in fleets_variant:
			var fleet_record: Dictionary = fleet_variant
			fleets.append(fleet_record)
			for unit_id in _variant_to_packed_string_array(fleet_record.get("unit_ids", PackedStringArray())):
				fleet_unit_ids[unit_id] = true

	for unit_variant in units_variant:
		var unit_record: Dictionary = unit_variant
		var unit_id: String = str(unit_record.get("unit_id", ""))
		if not unit_id.is_empty():
			units_by_id[unit_id] = unit_record
		if bool(unit_record.get("is_stationary", false)):
			stations.append(unit_record)
		elif not str(unit_record.get("fleet_id", "")).is_empty() and fleet_unit_ids.has(unit_id):
			continue
		else:
			mobile_units.append(unit_record)

	if construction_variant is Array:
		for project_variant in construction_variant:
			if project_variant is Dictionary:
				construction_projects.append(project_variant)

	var resolved_outer_radius: float = outer_radius
	if not construction_projects.is_empty():
		result["construction_projects"] = _build_construction_group(construction_projects, units_by_id)
		_build_construction_particle_group(construction_projects, units_by_id)
		for project_layout_variant in result.get("construction_projects", []):
			var project_layout: Dictionary = project_layout_variant
			var project_position: Vector3 = project_layout.get("position", Vector3.ZERO)
			resolved_outer_radius = maxf(resolved_outer_radius, project_position.length() + 8.0)

	if not stations.is_empty():
		var station_radius: float = outer_radius + STATION_RING_OFFSET
		result["stations"] = _build_group(
			stations,
			"unit_id",
			station_radius,
			Vector3(1.0, 1.0, 1.0),
			Vector3(2.6, 2.0, 2.6),
			0.95,
			1.4
		)
		resolved_outer_radius = maxf(resolved_outer_radius, station_radius + 8.0)

	if not fleets.is_empty():
		var fleet_radius: float = outer_radius + FLEET_RING_OFFSET
		result["fleets"] = _build_fleet_group(
			fleets,
			units_by_id,
			fleet_radius,
			0.98,
			0.42,
			FLEET_MEMBER_MARKER_SIZE,
			FLEET_MARKER_TINT_STRENGTH
		)
		var largest_fleet_size: int = 1
		for fleet_record in fleets:
			largest_fleet_size = maxi(largest_fleet_size, _variant_to_packed_string_array(fleet_record.get("unit_ids", PackedStringArray())).size())
		resolved_outer_radius = maxf(resolved_outer_radius, fleet_radius + _get_fleet_cluster_radius(largest_fleet_size) + 8.0)

	if not mobile_units.is_empty():
		var ship_radius: float = outer_radius + SHIP_RING_OFFSET
		result["units"] = _build_sprite_group(
			mobile_units,
			"unit_id",
			ship_radius,
			0.92,
			0.28,
			SHIP_MARKER_SIZE,
			SHIP_MARKER_TINT_STRENGTH
		)
		resolved_outer_radius = maxf(resolved_outer_radius, ship_radius + 10.0)

	result["outer_radius"] = resolved_outer_radius
	return result


func _build_group(
	records: Array[Dictionary],
	id_key: String,
	base_radius: float,
	base_scale: Vector3,
	damaged_scale: Vector3,
	alpha: float,
	emission_energy: float
) -> Array[Dictionary]:
	var marker: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = base_scale

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = records.size()
	var instance_layouts: Array[Dictionary] = []
	var instance_specs: Array[Dictionary] = []

	for record_index in range(records.size()):
		var record: Dictionary = records[record_index]
		var entity_id: String = str(record.get(id_key, "%s_%02d" % [id_key, record_index]))
		var seed_value := entity_id.hash()
		var layout: Dictionary = _resolve_record_layout(record, base_radius, record_index, seed_value)
		var hull_ratio: float = clampf(float(record.get("hull_ratio", 1.0)), 0.2, 1.0)
		var scale_blend: Vector3 = damaged_scale.lerp(base_scale, hull_ratio)
		var instance_basis: Basis = Basis(Vector3.UP, float(layout.get("yaw", 0.0))).scaled(scale_blend)
		var position: Vector3 = layout.get("position", Vector3.ZERO)
		multimesh.set_instance_transform(record_index, Transform3D(instance_basis, position))
		multimesh.set_instance_color(record_index, _get_owner_color(record, alpha))
		instance_layouts.append({
			"record": record.duplicate(true),
			"position": position,
			"yaw": float(layout.get("yaw", 0.0)),
			"ring_radius": float(layout.get("radius", base_radius)),
		})
		instance_specs.append({
			"id": entity_id,
			"index": record_index,
			"base_scale": base_scale,
			"damaged_scale": damaged_scale,
			"seed": seed_value,
			"fallback_index": record_index,
			"fallback_radius": base_radius,
		})

	marker.multimesh = multimesh
	marker.material_override = _build_material(alpha, emission_energy)
	_host.get_runtime_effects_root().add_child(marker)
	_station_marker = marker
	_station_instance_specs = instance_specs
	return instance_layouts


func _build_sprite_group(
	records: Array[Dictionary],
	id_key: String,
	base_radius: float,
	alpha: float,
	emission_energy: float,
	base_size: float,
	tint_strength: float
) -> Array[Dictionary]:
	var marker := MultiMeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * base_size

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = records.size()
	var instance_layouts: Array[Dictionary] = []
	var instance_specs: Array[Dictionary] = []

	for record_index in range(records.size()):
		var record: Dictionary = records[record_index]
		var entity_id: String = str(record.get(id_key, "%s_%02d" % [id_key, record_index]))
		var seed_value := entity_id.hash()
		var layout: Dictionary = _resolve_record_layout(record, base_radius, record_index, seed_value)
		var hull_ratio: float = clampf(float(record.get("hull_ratio", 1.0)), 0.2, 1.0)
		var size_multiplier: float = lerpf(0.84, 1.0, hull_ratio)

		var instance_basis: Basis = Basis.IDENTITY.scaled(Vector3.ONE * size_multiplier)
		var position: Vector3 = layout.get("position", Vector3.ZERO)
		multimesh.set_instance_transform(record_index, Transform3D(instance_basis, position))
		multimesh.set_instance_color(record_index, _get_marker_tint(record, alpha, tint_strength))
		instance_layouts.append({
			"record": record.duplicate(true),
			"position": position,
			"yaw": 0.0,
			"ring_radius": float(layout.get("radius", base_radius)),
		})
		instance_specs.append({
			"id": entity_id,
			"index": record_index,
			"base_size": base_size,
			"seed": seed_value,
			"fallback_index": record_index,
			"fallback_radius": base_radius,
		})

	marker.multimesh = multimesh
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.material_override = _build_ship_material(alpha, emission_energy)
	_host.get_runtime_effects_root().add_child(marker)
	_unit_marker = marker
	_unit_instance_specs = instance_specs
	return instance_layouts


func _build_fleet_group(
	fleet_records: Array[Dictionary],
	units_by_id: Dictionary,
	base_radius: float,
	alpha: float,
	emission_energy: float,
	base_size: float,
	tint_strength: float
) -> Array[Dictionary]:
	var marker := MultiMeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * base_size

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = _count_fleet_visual_instances(fleet_records, units_by_id)
	var instance_layouts: Array[Dictionary] = []
	var instance_specs: Array[Dictionary] = []
	var instance_index: int = 0

	for fleet_index in range(fleet_records.size()):
		var fleet_record: Dictionary = fleet_records[fleet_index]
		var fleet_id: String = str(fleet_record.get("fleet_id", "fleet_%02d" % fleet_index))
		var fleet_layout: Dictionary = _resolve_record_layout(fleet_record, base_radius, fleet_index, fleet_id.hash())
		var fleet_center: Vector3 = fleet_layout.get("position", Vector3.ZERO)
		var member_records: Array[Dictionary] = _get_fleet_member_records(fleet_record, units_by_id)
		if member_records.is_empty():
			member_records.append(fleet_record)

		for member_index in range(member_records.size()):
			var member_record: Dictionary = member_records[member_index]
			var hull_ratio: float = clampf(float(member_record.get("hull_ratio", 1.0)), 0.2, 1.0)
			var size_multiplier: float = lerpf(0.82, 1.0, hull_ratio)
			var member_position: Vector3 = _get_record_position(member_record, fleet_center + _resolve_fleet_member_offset(member_index, member_records.size(), fleet_id.hash()))
			var instance_basis: Basis = Basis.IDENTITY.scaled(Vector3.ONE * size_multiplier)
			multimesh.set_instance_transform(instance_index, Transform3D(instance_basis, member_position))
			multimesh.set_instance_color(instance_index, _get_marker_tint(member_record, alpha, tint_strength))
			instance_specs.append({
				"index": instance_index,
				"fleet_id": fleet_id,
				"unit_id": str(member_record.get("unit_id", "")),
				"member_index": member_index,
				"member_count": member_records.size(),
				"base_size": base_size,
				"seed": fleet_id.hash(),
			})
			instance_index += 1

		instance_layouts.append({
			"record": fleet_record.duplicate(true),
			"position": fleet_center,
			"yaw": 0.0,
			"ring_radius": float(fleet_layout.get("radius", base_radius)),
		})

	marker.multimesh = multimesh
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.material_override = _build_ship_material(alpha, emission_energy)
	_host.get_runtime_effects_root().add_child(marker)
	_fleet_marker = marker
	_fleet_instance_specs = instance_specs
	return instance_layouts


func _build_construction_group(records: Array[Dictionary], _units_by_id: Dictionary) -> Array[Dictionary]:
	var instance_layouts: Array[Dictionary] = []
	for record_index in range(records.size()):
		var record: Dictionary = records[record_index]
		var project_id := str(record.get("project_id", "construction_%02d" % record_index)).strip_edges()
		if project_id.is_empty():
			project_id = "construction_%02d" % record_index
		var position := _variant_to_vector3(record.get("local_position", Vector3.ZERO))
		var progress_ratio := clampf(float(record.get("progress_ratio", 0.0)), 0.0, 1.0)
		var owner_color := _get_owner_color(record, 1.0)

		var site_root := Node3D.new()
		site_root.name = "ConstructionSite_%s" % project_id
		site_root.position = position
		_host.get_runtime_effects_root().add_child(site_root)

		_add_construction_ring(site_root, progress_ratio, owner_color)
		_add_construction_scaffold(site_root, progress_ratio, owner_color, project_id.hash())
		_add_construction_progress_bar(site_root, progress_ratio, owner_color)
		site_root.add_child(_build_construction_label(record, progress_ratio))

		instance_layouts.append({
			"record": record.duplicate(true),
			"position": position,
			"yaw": 0.0,
			"ring_radius": CONSTRUCTION_SITE_RADIUS,
		})
	return instance_layouts


func _add_construction_ring(site_root: Node3D, progress_ratio: float, owner_color: Color) -> void:
	var base_ring := MeshInstance3D.new()
	base_ring.name = "ConstructionBaseRing"
	base_ring.mesh = _build_construction_arc_mesh(CONSTRUCTION_SITE_RADIUS, 1.0, Color(0.48, 0.72, 0.78, 0.28))
	base_ring.material_override = _build_material(0.32, 0.8)
	base_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site_root.add_child(base_ring)

	var progress_ring := MeshInstance3D.new()
	progress_ring.name = "ConstructionProgressRing"
	progress_ring.mesh = _build_construction_arc_mesh(CONSTRUCTION_SITE_RADIUS + 0.08, progress_ratio, Color(owner_color.r, owner_color.g, owner_color.b, 0.95))
	progress_ring.material_override = _build_material(0.95, 1.65)
	progress_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site_root.add_child(progress_ring)


func _add_construction_scaffold(site_root: Node3D, progress_ratio: float, owner_color: Color, seed_value: int) -> void:
	var scaffold := MeshInstance3D.new()
	scaffold.name = "ConstructionScaffold"
	var box := BoxMesh.new()
	var scaffold_width := lerpf(0.85, 1.9, progress_ratio)
	var scaffold_height := lerpf(0.35, 2.2, progress_ratio)
	box.size = Vector3(scaffold_width, scaffold_height, scaffold_width)
	scaffold.mesh = box
	scaffold.position = Vector3(0.0, 0.36 + scaffold_height * 0.5, 0.0)
	scaffold.rotation = Vector3(0.0, float(abs(seed_value) % 628) / 100.0, 0.0)
	scaffold.material_override = _build_plain_material(Color(owner_color.r, owner_color.g, owner_color.b, 1.0), 0.28, 0.95)
	scaffold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site_root.add_child(scaffold)

	var core := MeshInstance3D.new()
	core.name = "ConstructionCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = lerpf(0.16, 0.42, progress_ratio)
	core_mesh.height = core_mesh.radius * 2.0
	core.mesh = core_mesh
	core.position = Vector3(0.0, 0.72 + progress_ratio * 1.15, 0.0)
	core.material_override = _build_plain_material(Color(0.76, 0.96, 1.0, 1.0), 0.78, 1.6)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site_root.add_child(core)


func _add_construction_progress_bar(site_root: Node3D, progress_ratio: float, owner_color: Color) -> void:
	var frame := MeshInstance3D.new()
	frame.name = "ConstructionProgressBarFrame"
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(2.2, 0.05, 0.18)
	frame.mesh = frame_mesh
	frame.position = Vector3(0.0, 2.7, 0.0)
	frame.material_override = _build_plain_material(Color(0.18, 0.26, 0.3, 1.0), 0.72, 0.55)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site_root.add_child(frame)

	var fill := MeshInstance3D.new()
	fill.name = "ConstructionProgressBarFill"
	var fill_mesh := BoxMesh.new()
	var fill_width := maxf(0.06, 2.2 * progress_ratio)
	fill_mesh.size = Vector3(fill_width, 0.08, 0.22)
	fill.mesh = fill_mesh
	fill.position = Vector3(-1.1 + fill_width * 0.5, 2.71, 0.0)
	fill.material_override = _build_plain_material(Color(owner_color.r, owner_color.g, owner_color.b, 1.0), 0.86, 1.35)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site_root.add_child(fill)


func _build_construction_label(record: Dictionary, progress_ratio: float) -> Label3D:
	var project_id := str(record.get("project_id", "construction")).strip_edges()
	var label := Label3D.new()
	label.name = "ConstructionLabel_%s" % project_id
	var percent := int(round(progress_ratio * 100.0))
	var state := str(record.get("construction_state", "building"))
	var prefix := "Bau"
	if state == "moving_to_site":
		prefix = "Anflug"
	label.text = "%s %d%%" % [prefix, percent]
	label.position = Vector3(0.0, 3.12, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 18
	label.pixel_size = 0.036
	label.outline_size = 8
	label.modulate = Color(0.78, 0.96, 1.0, 0.96)
	label.outline_modulate = Color(0.02, 0.04, 0.06, 0.94)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _build_construction_particle_group(records: Array[Dictionary], units_by_id: Dictionary) -> void:
	var instance_count := records.size() * CONSTRUCTION_PARTICLES_PER_PROJECT
	if instance_count <= 0:
		return

	var marker := MultiMeshInstance3D.new()
	marker.name = "ConstructionParticles"
	var mesh := SphereMesh.new()
	mesh.radius = CONSTRUCTION_PARTICLE_SIZE
	mesh.height = CONSTRUCTION_PARTICLE_SIZE * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = instance_count

	var specs: Array[Dictionary] = []
	var instance_index := 0
	for record_index in range(records.size()):
		var record: Dictionary = records[record_index]
		var project_id := str(record.get("project_id", "construction_%02d" % record_index))
		var seed_value := project_id.hash()
		for particle_index in range(CONSTRUCTION_PARTICLES_PER_PROJECT):
			var spec := _build_construction_particle_spec(instance_index, project_id, particle_index, seed_value)
			specs.append(spec)
			multimesh.set_instance_transform(instance_index, _build_construction_particle_transform(record, units_by_id, spec, 1.0))
			multimesh.set_instance_color(instance_index, _get_construction_particle_color(record, particle_index))
			instance_index += 1

	marker.multimesh = multimesh
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.material_override = _build_material(0.9, 1.9)
	_host.get_runtime_effects_root().add_child(marker)
	_construction_particle_marker = marker
	_construction_particle_specs = specs


func _build_construction_particle_spec(instance_index: int, project_id: String, particle_index: int, seed_value: int) -> Dictionary:
	var seed: int = absi(seed_value + particle_index * 7919)
	var angle := float(seed % 3600) / 3600.0 * TAU
	var radius := 2.8 + float(int(seed / 17) % 90) / 100.0
	var side_angle := angle + PI * 0.5
	return {
		"index": instance_index,
		"project_id": project_id,
		"phase_offset": float(particle_index) / float(CONSTRUCTION_PARTICLES_PER_PROJECT),
		"source_offset": Vector3(cos(angle) * radius, 0.45 + float(seed % 5) * 0.08, sin(angle) * radius),
		"side_offset": Vector3(cos(side_angle), 0.0, sin(side_angle)) * (0.18 + float(seed % 7) * 0.025),
		"arc_height": 0.7 + float(seed % 80) / 100.0,
	}


func _build_construction_particle_transform(record: Dictionary, units_by_id: Dictionary, spec: Dictionary, day_progress: float) -> Transform3D:
	var position := _resolve_construction_particle_position(record, units_by_id, spec, day_progress)
	var time_seconds := float(Time.get_ticks_msec()) / 1000.0
	var pulse := 0.76 + sin((time_seconds + float(spec.get("phase_offset", 0.0))) * TAU) * 0.18
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(pulse, 0.35)), position)


func _resolve_construction_particle_position(record: Dictionary, units_by_id: Dictionary, spec: Dictionary, day_progress: float) -> Vector3:
	var site_position := _variant_to_vector3(record.get("local_position", Vector3.ZERO))
	var builder_id := str(record.get("builder_unit_id", "")).strip_edges()
	var start_position := site_position + _variant_to_vector3(spec.get("source_offset", Vector3.ZERO))
	if not builder_id.is_empty() and units_by_id.has(builder_id):
		var builder_record: Dictionary = units_by_id.get(builder_id, {})
		start_position = _get_interpolated_record_position(builder_record, day_progress)
	if start_position.distance_to(site_position) < 1.25:
		start_position = site_position + _variant_to_vector3(spec.get("source_offset", Vector3.ZERO))

	var time_seconds := float(Time.get_ticks_msec()) / 1000.0
	var phase := fmod(time_seconds * 0.44 + float(spec.get("phase_offset", 0.0)), 1.0)
	if phase < 0.0:
		phase += 1.0
	var eased := phase * phase * (3.0 - 2.0 * phase)
	var position := start_position.lerp(site_position, eased)
	position += _variant_to_vector3(spec.get("side_offset", Vector3.ZERO)) * sin(phase * TAU) * (1.0 - eased)
	position.y += sin(phase * PI) * float(spec.get("arc_height", 0.8))
	return position


func _get_construction_particle_color(record: Dictionary, particle_index: int) -> Color:
	var owner_color := _get_owner_color(record, 1.0)
	var tint := Color(0.76, 0.96, 1.0, 1.0).lerp(Color(owner_color.r, owner_color.g, owner_color.b, 1.0), 0.42)
	tint.a = 0.82 if particle_index % 3 != 0 else 0.96
	return tint


func _build_construction_arc_mesh(radius: float, progress_ratio: float, color: Color) -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)
	var segment_count := maxi(1, int(ceil(float(CONSTRUCTION_RING_SEGMENTS) * clampf(progress_ratio, 0.0, 1.0))))
	for point_index in range(segment_count):
		var from_angle: float = float(point_index) * TAU / float(CONSTRUCTION_RING_SEGMENTS)
		var to_angle: float = float(point_index + 1) * TAU / float(CONSTRUCTION_RING_SEGMENTS)
		surface_tool.set_color(color)
		surface_tool.add_vertex(Vector3(cos(from_angle) * radius, 0.18, sin(from_angle) * radius))
		surface_tool.set_color(color)
		surface_tool.add_vertex(Vector3(cos(to_angle) * radius, 0.18, sin(to_angle) * radius))
	return surface_tool.commit()


func update_interpolated_runtime_positions(space_renderables: Dictionary, day_progress: float) -> void:
	var records_by_unit_id: Dictionary = {}
	var records_by_fleet_id: Dictionary = {}
	var records_by_project_id: Dictionary = {}

	for unit_variant in space_renderables.get("units", []):
		var unit_record: Dictionary = unit_variant
		var unit_id := str(unit_record.get("unit_id", ""))
		if not unit_id.is_empty():
			records_by_unit_id[unit_id] = unit_record

	for fleet_variant in space_renderables.get("fleets", []):
		var fleet_record: Dictionary = fleet_variant
		var fleet_id := str(fleet_record.get("fleet_id", ""))
		if not fleet_id.is_empty():
			records_by_fleet_id[fleet_id] = fleet_record

	for project_variant in space_renderables.get("construction_projects", []):
		var project_record: Dictionary = project_variant
		var project_id := str(project_record.get("project_id", ""))
		if not project_id.is_empty():
			records_by_project_id[project_id] = project_record

	_update_station_marker(records_by_unit_id, day_progress)
	_update_unit_marker(records_by_unit_id, day_progress)
	_update_fleet_marker(records_by_fleet_id, records_by_unit_id, day_progress)
	_update_construction_particles(records_by_project_id, records_by_unit_id, day_progress)


func _reset_interpolation_state() -> void:
	_station_marker = null
	_fleet_marker = null
	_unit_marker = null
	_construction_particle_marker = null
	_station_instance_specs.clear()
	_fleet_instance_specs.clear()
	_unit_instance_specs.clear()
	_construction_particle_specs.clear()


func _update_station_marker(records_by_unit_id: Dictionary, day_progress: float) -> void:
	if _station_marker == null or _station_marker.multimesh == null:
		return
	for spec in _station_instance_specs:
		var record: Dictionary = records_by_unit_id.get(str(spec.get("id", "")), {})
		if record.is_empty():
			continue
		var position := _get_interpolated_record_position(record, day_progress)
		var velocity := _variant_to_vector3(record.get("velocity", Vector3.ZERO))
		var yaw := atan2(-position.z, position.x)
		if velocity.length_squared() > 0.0001:
			yaw = atan2(-velocity.z, velocity.x)
		var hull_ratio: float = clampf(float(record.get("hull_ratio", 1.0)), 0.2, 1.0)
		var base_scale: Vector3 = spec.get("base_scale", Vector3.ONE)
		var damaged_scale: Vector3 = spec.get("damaged_scale", base_scale)
		var scale_blend: Vector3 = damaged_scale.lerp(base_scale, hull_ratio)
		_station_marker.multimesh.set_instance_transform(int(spec.get("index", 0)), Transform3D(Basis(Vector3.UP, yaw).scaled(scale_blend), position))


func _update_unit_marker(records_by_unit_id: Dictionary, day_progress: float) -> void:
	if _unit_marker == null or _unit_marker.multimesh == null:
		return
	for spec in _unit_instance_specs:
		var record: Dictionary = records_by_unit_id.get(str(spec.get("id", "")), {})
		if record.is_empty():
			continue
		var hull_ratio: float = clampf(float(record.get("hull_ratio", 1.0)), 0.2, 1.0)
		var size_multiplier: float = lerpf(0.84, 1.0, hull_ratio)
		var position := _get_interpolated_record_position(record, day_progress)
		_unit_marker.multimesh.set_instance_transform(int(spec.get("index", 0)), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size_multiplier), position))


func _update_fleet_marker(records_by_fleet_id: Dictionary, records_by_unit_id: Dictionary, day_progress: float) -> void:
	if _fleet_marker == null or _fleet_marker.multimesh == null:
		return
	for spec in _fleet_instance_specs:
		var fleet_id := str(spec.get("fleet_id", ""))
		var fleet_record: Dictionary = records_by_fleet_id.get(fleet_id, {})
		if fleet_record.is_empty():
			continue
		var fleet_center := _get_interpolated_record_position(fleet_record, day_progress)
		var unit_id := str(spec.get("unit_id", ""))
		var member_record: Dictionary = records_by_unit_id.get(unit_id, {})
		var member_position := fleet_center + _resolve_fleet_member_offset(
			int(spec.get("member_index", 0)),
			int(spec.get("member_count", 1)),
			int(spec.get("seed", 0))
		)
		var hull_ratio := 1.0
		if not member_record.is_empty():
			member_position = _get_interpolated_record_position(member_record, day_progress)
			hull_ratio = clampf(float(member_record.get("hull_ratio", 1.0)), 0.2, 1.0)
		var size_multiplier: float = lerpf(0.82, 1.0, hull_ratio)
		_fleet_marker.multimesh.set_instance_transform(int(spec.get("index", 0)), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size_multiplier), member_position))


func _update_construction_particles(records_by_project_id: Dictionary, records_by_unit_id: Dictionary, day_progress: float) -> void:
	if _construction_particle_marker == null or _construction_particle_marker.multimesh == null:
		return
	for spec in _construction_particle_specs:
		var project_id := str(spec.get("project_id", ""))
		var record: Dictionary = records_by_project_id.get(project_id, {})
		if record.is_empty():
			continue
		_construction_particle_marker.multimesh.set_instance_transform(
			int(spec.get("index", 0)),
			_build_construction_particle_transform(record, records_by_unit_id, spec, day_progress)
		)


func _get_interpolated_record_position(record: Dictionary, day_progress: float) -> Vector3:
	if str(record.get("movement_state", SpaceUnitRuntime.MOVEMENT_IDLE)) != SpaceUnitRuntime.MOVEMENT_MOVING:
		return _variant_to_vector3(record.get("local_position", Vector3.ZERO))
	var previous := _variant_to_vector3(record.get("previous_local_position", record.get("local_position", Vector3.ZERO)))
	var current := _variant_to_vector3(record.get("local_position", previous))
	return previous.lerp(current, clampf(day_progress, 0.0, 1.0))


func _resolve_layout(base_radius: float, index: int, seed_value: int) -> Dictionary:
	var ring_index: int = int(floor(float(index) / float(SLOTS_PER_RING)))
	var slot_index: int = index % SLOTS_PER_RING
	var slot_count: int = SLOTS_PER_RING + ring_index * 2
	var seed_angle: float = float(abs(seed_value) % 3600) / 3600.0 * TAU
	var angle: float = seed_angle + float(slot_index) * TAU / float(maxi(slot_count, 1))
	var radius: float = base_radius + float(ring_index) * RING_STEP
	return {
		"position": Vector3(cos(angle) * radius, 0.35 + float(ring_index) * 0.4, sin(angle) * radius),
		"yaw": -angle + PI * 0.5,
		"radius": radius,
	}


func _resolve_record_layout(record: Dictionary, base_radius: float, index: int, seed_value: int) -> Dictionary:
	if record.has("interpolated_local_position") or record.has("local_position"):
		var position := _get_record_position(record, Vector3.ZERO)
		var yaw := 0.0
		var velocity := _variant_to_vector3(record.get("velocity", Vector3.ZERO))
		if velocity.length_squared() > 0.0001:
			yaw = atan2(-velocity.z, velocity.x)
		elif position.length_squared() > 0.0001:
			yaw = atan2(-position.z, position.x)
		return {
			"position": position,
			"yaw": yaw,
			"radius": position.length(),
		}
	return _resolve_layout(base_radius, index, seed_value)


func _get_record_position(record: Dictionary, fallback: Vector3) -> Vector3:
	if record.has("interpolated_local_position"):
		return _variant_to_vector3(record.get("interpolated_local_position", fallback))
	if record.has("local_position"):
		return _variant_to_vector3(record.get("local_position", fallback))
	return fallback


func _get_fleet_member_records(fleet_record: Dictionary, units_by_id: Dictionary) -> Array[Dictionary]:
	var member_records: Array[Dictionary] = []
	for unit_id in _variant_to_packed_string_array(fleet_record.get("unit_ids", PackedStringArray())):
		if units_by_id.has(unit_id):
			member_records.append((units_by_id[unit_id] as Dictionary).duplicate(true))
	return member_records


func _count_fleet_visual_instances(fleet_records: Array[Dictionary], units_by_id: Dictionary) -> int:
	var total_instances: int = 0
	for fleet_record in fleet_records:
		var member_count: int = _get_fleet_member_records(fleet_record, units_by_id).size()
		total_instances += maxi(member_count, 1)
	return total_instances


func _resolve_fleet_member_offset(index: int, total_count: int, seed_value: int) -> Vector3:
	if total_count <= 1:
		return Vector3.ZERO

	var local_index: int = index
	var ring_index: int = 0
	var ring_capacity: int = FLEET_MEMBER_SLOTS_PER_RING
	while local_index >= ring_capacity:
		local_index -= ring_capacity
		ring_index += 1
		ring_capacity = FLEET_MEMBER_SLOTS_PER_RING + ring_index * 2

	var seed_angle: float = float(abs(seed_value) % 3600) / 3600.0 * TAU
	var angle: float = seed_angle + float(local_index) * TAU / float(maxi(ring_capacity, 1))
	var radius: float = FLEET_MEMBER_BASE_RADIUS + float(ring_index) * FLEET_MEMBER_RING_STEP
	var vertical_offset: float = 0.04 + float((index + abs(seed_value)) % 3) * 0.08
	return Vector3(cos(angle) * radius, vertical_offset, sin(angle) * radius)


func _get_fleet_cluster_radius(unit_count: int) -> float:
	if unit_count <= 1:
		return 0.0

	var remaining_units: int = unit_count - 1
	var ring_index: int = 0
	var ring_capacity: int = FLEET_MEMBER_SLOTS_PER_RING
	while remaining_units > ring_capacity:
		remaining_units -= ring_capacity
		ring_index += 1
		ring_capacity = FLEET_MEMBER_SLOTS_PER_RING + ring_index * 2
	return FLEET_MEMBER_BASE_RADIUS + float(ring_index) * FLEET_MEMBER_RING_STEP + FLEET_MEMBER_MARKER_SIZE * 0.5


func _get_owner_color(record: Dictionary, alpha: float) -> Color:
	var color_variant: Variant = record.get("owner_color", Color(0.82, 0.88, 1.0, alpha))
	var color: Color = color_variant
	color.a = alpha
	return color


func _get_marker_tint(record: Dictionary, alpha: float, tint_strength: float) -> Color:
	var owner_color: Color = _get_owner_color(record, 1.0)
	var tint: Color = Color.WHITE.lerp(Color(owner_color.r, owner_color.g, owner_color.b, 1.0), tint_strength)
	tint.a = alpha
	return tint


func _build_material(alpha: float, emission_energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = emission_energy
	return material


func _build_ship_material(alpha: float, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	material.albedo_texture = SHIP_MARKER_TEXTURE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = emission_energy
	material.render_priority = 1
	return material


func _build_plain_material(color: Color, alpha: float, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var resolved_color := color
	resolved_color.a = alpha
	material.albedo_color = resolved_color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = emission_energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 2
	return material


static func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is PackedStringArray:
		return values
	if values is not Array:
		return result
	for value_variant in values:
		var value: String = str(value_variant).strip_edges()
		if value.is_empty():
			continue
		result.append(value)
	return result


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
