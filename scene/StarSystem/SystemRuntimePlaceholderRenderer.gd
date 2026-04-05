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

var _host: StarSystemPreview = null


func bind(host: StarSystemPreview) -> void:
	_host = host


func unbind() -> void:
	_host = null


func render_runtime_placeholders(space_renderables: Dictionary, outer_radius: float) -> Dictionary:
	var result := {
		"outer_radius": outer_radius,
		"stations": [],
		"fleets": [],
		"ships": [],
	}

	if _host == null:
		return result

	var ships_variant: Variant = space_renderables.get("ships", [])
	if ships_variant is not Array:
		return result
	var fleets_variant: Variant = space_renderables.get("fleets", [])

	var mobile_ships: Array[Dictionary] = []
	var stations: Array[Dictionary] = []
	var fleets: Array[Dictionary] = []
	var fleet_ship_ids: Dictionary = {}
	var ships_by_id: Dictionary = {}

	if fleets_variant is Array:
		for fleet_variant in fleets_variant:
			var fleet_record: Dictionary = fleet_variant
			fleets.append(fleet_record)
			for ship_id in _variant_to_packed_string_array(fleet_record.get("ship_ids", PackedStringArray())):
				fleet_ship_ids[ship_id] = true

	for ship_variant in ships_variant:
		var ship_record: Dictionary = ship_variant
		var ship_id: String = str(ship_record.get("ship_id", ""))
		if not ship_id.is_empty():
			ships_by_id[ship_id] = ship_record
		if bool(ship_record.get("is_stationary", false)):
			stations.append(ship_record)
		elif not str(ship_record.get("fleet_id", "")).is_empty() and fleet_ship_ids.has(ship_id):
			continue
		else:
			mobile_ships.append(ship_record)

	var resolved_outer_radius: float = outer_radius
	if not stations.is_empty():
		var station_radius: float = outer_radius + STATION_RING_OFFSET
		result["stations"] = _build_group(
			stations,
			"ship_id",
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
			ships_by_id,
			fleet_radius,
			0.98,
			0.42,
			FLEET_MEMBER_MARKER_SIZE,
			FLEET_MARKER_TINT_STRENGTH
		)
		var largest_fleet_size: int = 1
		for fleet_record in fleets:
			largest_fleet_size = maxi(largest_fleet_size, _variant_to_packed_string_array(fleet_record.get("ship_ids", PackedStringArray())).size())
		resolved_outer_radius = maxf(resolved_outer_radius, fleet_radius + _get_fleet_cluster_radius(largest_fleet_size) + 8.0)

	if not mobile_ships.is_empty():
		var ship_radius: float = outer_radius + SHIP_RING_OFFSET
		result["ships"] = _build_sprite_group(
			mobile_ships,
			"ship_id",
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

	for record_index in range(records.size()):
		var record: Dictionary = records[record_index]
		var entity_id: String = str(record.get(id_key, "%s_%02d" % [id_key, record_index]))
		var layout: Dictionary = _resolve_layout(base_radius, record_index, entity_id.hash())
		var hull_ratio: float = clampf(float(record.get("hull_ratio", 1.0)), 0.2, 1.0)
		var scale_blend: Vector3 = damaged_scale.lerp(base_scale, hull_ratio)
		var basis: Basis = Basis(Vector3.UP, float(layout.get("yaw", 0.0))).scaled(scale_blend)
		var position: Vector3 = layout.get("position", Vector3.ZERO)
		multimesh.set_instance_transform(record_index, Transform3D(basis, position))
		multimesh.set_instance_color(record_index, _get_owner_color(record, alpha))
		instance_layouts.append({
			"record": record.duplicate(true),
			"position": position,
			"yaw": float(layout.get("yaw", 0.0)),
			"ring_radius": float(layout.get("radius", base_radius)),
		})

	marker.multimesh = multimesh
	marker.material_override = _build_material(alpha, emission_energy)
	_host.effects.add_child(marker)
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

	for record_index in range(records.size()):
		var record: Dictionary = records[record_index]
		var entity_id: String = str(record.get(id_key, "%s_%02d" % [id_key, record_index]))
		var layout: Dictionary = _resolve_layout(base_radius, record_index, entity_id.hash())
		var hull_ratio: float = clampf(float(record.get("hull_ratio", 1.0)), 0.2, 1.0)
		var size_multiplier: float = lerpf(0.84, 1.0, hull_ratio)

		var basis: Basis = Basis.IDENTITY.scaled(Vector3.ONE * size_multiplier)
		var position: Vector3 = layout.get("position", Vector3.ZERO)
		multimesh.set_instance_transform(record_index, Transform3D(basis, position))
		multimesh.set_instance_color(record_index, _get_marker_tint(record, alpha, tint_strength))
		instance_layouts.append({
			"record": record.duplicate(true),
			"position": position,
			"yaw": 0.0,
			"ring_radius": float(layout.get("radius", base_radius)),
		})

	marker.multimesh = multimesh
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.material_override = _build_ship_material(alpha, emission_energy)
	_host.effects.add_child(marker)
	return instance_layouts


func _build_fleet_group(
	fleet_records: Array[Dictionary],
	ships_by_id: Dictionary,
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
	multimesh.instance_count = _count_fleet_visual_instances(fleet_records, ships_by_id)
	var instance_layouts: Array[Dictionary] = []
	var instance_index: int = 0

	for fleet_index in range(fleet_records.size()):
		var fleet_record: Dictionary = fleet_records[fleet_index]
		var fleet_id: String = str(fleet_record.get("fleet_id", "fleet_%02d" % fleet_index))
		var fleet_layout: Dictionary = _resolve_layout(base_radius, fleet_index, fleet_id.hash())
		var fleet_center: Vector3 = fleet_layout.get("position", Vector3.ZERO)
		var member_records: Array[Dictionary] = _get_fleet_member_records(fleet_record, ships_by_id)
		if member_records.is_empty():
			member_records.append(fleet_record)

		for member_index in range(member_records.size()):
			var member_record: Dictionary = member_records[member_index]
			var hull_ratio: float = clampf(float(member_record.get("hull_ratio", 1.0)), 0.2, 1.0)
			var size_multiplier: float = lerpf(0.82, 1.0, hull_ratio)
			var member_position: Vector3 = fleet_center + _resolve_fleet_member_offset(member_index, member_records.size(), fleet_id.hash())
			var basis: Basis = Basis.IDENTITY.scaled(Vector3.ONE * size_multiplier)
			multimesh.set_instance_transform(instance_index, Transform3D(basis, member_position))
			multimesh.set_instance_color(instance_index, _get_marker_tint(member_record, alpha, tint_strength))
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
	_host.effects.add_child(marker)
	return instance_layouts


func _resolve_layout(base_radius: float, index: int, seed_value: int) -> Dictionary:
	var ring_index: int = index / SLOTS_PER_RING
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


func _get_fleet_member_records(fleet_record: Dictionary, ships_by_id: Dictionary) -> Array[Dictionary]:
	var member_records: Array[Dictionary] = []
	for ship_id in _variant_to_packed_string_array(fleet_record.get("ship_ids", PackedStringArray())):
		if ships_by_id.has(ship_id):
			member_records.append((ships_by_id[ship_id] as Dictionary).duplicate(true))
	return member_records


func _count_fleet_visual_instances(fleet_records: Array[Dictionary], ships_by_id: Dictionary) -> int:
	var total_instances: int = 0
	for fleet_record in fleet_records:
		var member_count: int = _get_fleet_member_records(fleet_record, ships_by_id).size()
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


func _get_fleet_cluster_radius(ship_count: int) -> float:
	if ship_count <= 1:
		return 0.0

	var remaining_ships: int = ship_count - 1
	var ring_index: int = 0
	var ring_capacity: int = FLEET_MEMBER_SLOTS_PER_RING
	while remaining_ships > ring_capacity:
		remaining_ships -= ring_capacity
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
