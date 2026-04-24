extends RefCounted

const TERRITORY_FILL_SHADER: Shader = preload("res://scene/galaxy/TerritoryFill.gdshader")
const TERRITORY_BORDER_SHADER: Shader = preload("res://scene/galaxy/TerritoryBorder.gdshader")

const OWNERSHIP_THRESHOLD := 1.05
const OWNERSHIP_BLOB_RADIUS_FACTOR := 1.55
const OWNERSHIP_BLOB_RADIUS_MIN := 30.0
const OWNERSHIP_FALLOFF_RADIUS_FACTOR := 1.85
const OWNERSHIP_FIELD_MARGIN_FACTOR := 0.85
const OWNERSHIP_FIELD_MARGIN_MIN := 42.0
const OWNERSHIP_TEXEL_TARGET_FACTOR := 0.08
const OWNERSHIP_TEXEL_TARGET_MIN := 3.75
const OWNERSHIP_RESOLUTION_MIN := 192
const OWNERSHIP_RESOLUTION_MAX := 1280
const OWNERSHIP_BRIDGE_SAMPLE_SPACING_FACTOR := 0.78
const OWNERSHIP_BRIDGE_WEIGHT := 0.12
const OWNERSHIP_BRIDGE_RADIUS_FACTOR := 0.38
const OWNERSHIP_BRIDGE_MAX_LENGTH_FACTOR := 2.5
const OWNERSHIP_BLOCKER_WEIGHT := 1.16
const OWNERSHIP_BLOCKER_RADIUS_FACTOR := 1.05
const OWNERSHIP_COMPETITOR_WEIGHT := 0.72
const OWNERSHIP_CONTOUR_POINT_SNAP := 0.05
const OWNERSHIP_LOOP_SMOOTHING_PASSES := 6
const OWNERSHIP_LOOP_MITER_LIMIT := 2.6
const OWNERSHIP_BORDER_HEIGHT := -6.0
const OWNERSHIP_FILL_HEIGHT := -5.65
const OWNERSHIP_BORDER_OUTER_FACTOR := 0.08
const OWNERSHIP_BORDER_OUTER_MIN := 4.0
const OWNERSHIP_BORDER_INNER_FACTOR := 0.24
const OWNERSHIP_BORDER_INNER_MIN := 10.0

var _host: Node = null
var _topology_signature: String = ""
var _territory_cache: Dictionary = {}


func bind(host: Node) -> void:
	_host = host


func unbind() -> void:
	_host = null
	_topology_signature = ""
	_territory_cache.clear()


func render() -> void:
	if _host == null:
		return

	var empire_systems: Dictionary = _collect_owned_systems()
	if empire_systems.is_empty():
		clear()
		return

	var topology_signature: String = _build_topology_signature(empire_systems)
	if topology_signature != _topology_signature:
		_territory_cache = _build_territory_cache(empire_systems)
		_topology_signature = topology_signature

	if _territory_cache.is_empty():
		clear()
		return

	_apply_territory_cache()


func clear() -> void:
	if _host == null:
		return

	_host.ownership_markers.mesh = null
	_host.ownership_markers.material_override = null
	_host.ownership_connectors.mesh = null
	_host.ownership_connectors.material_override = null


func _collect_owned_systems() -> Dictionary:
	var empire_systems: Dictionary = {}

	for system_record_variant in _host.system_records:
		var system_record: Dictionary = system_record_variant
		var system_id: String = str(system_record.get("id", ""))
		if not _is_system_visible(system_id):
			continue
		var owner_empire_id: String = str(system_record.get("owner_empire_id", ""))
		if owner_empire_id.is_empty() or not _host.empires_by_id.has(owner_empire_id):
			continue

		var owned_systems: Array = empire_systems.get(owner_empire_id, [])
		owned_systems.append({
			"system_id": system_id,
			"position": system_record.get("position", Vector3.ZERO),
		})
		empire_systems[owner_empire_id] = owned_systems

	return empire_systems


func _build_topology_signature(empire_systems: Dictionary) -> String:
	var signature_parts := PackedStringArray()
	signature_parts.append("distance:%0.3f" % float(_host.min_system_distance))

	for system_record_variant in _host.system_records:
		var system_record: Dictionary = system_record_variant
		if not _is_system_visible(str(system_record.get("id", ""))):
			continue
		var owner_empire_id: String = str(system_record.get("owner_empire_id", ""))
		if owner_empire_id.is_empty() or not empire_systems.has(owner_empire_id):
			continue

		var position: Vector3 = system_record.get("position", Vector3.ZERO)
		signature_parts.append(
			"%s|%s|%0.2f|%0.2f" % [
				owner_empire_id,
				str(system_record.get("id", "")),
				position.x,
				position.z,
			]
		)

	for link_variant in _host.hyperlane_links:
		var link: Vector2i = link_variant
		if link.x < 0 or link.y < 0 or link.x >= _host.system_records.size() or link.y >= _host.system_records.size():
			continue

		var system_a: Dictionary = _host.system_records[link.x]
		var system_b: Dictionary = _host.system_records[link.y]
		if not _is_system_visible(str(system_a.get("id", ""))) or not _is_system_visible(str(system_b.get("id", ""))):
			continue
		var owner_a: String = str(system_a.get("owner_empire_id", ""))
		var owner_b: String = str(system_b.get("owner_empire_id", ""))
		if owner_a.is_empty() or owner_a != owner_b:
			continue

		signature_parts.append(
			"link|%s|%s|%s" % [
				owner_a,
				str(system_a.get("id", "")),
				str(system_b.get("id", "")),
			]
		)

	return "|".join(signature_parts)


func _build_territory_cache(empire_systems: Dictionary) -> Dictionary:
	var empire_ids := PackedStringArray()
	for empire_id_variant in empire_systems.keys():
		empire_ids.append(str(empire_id_variant))
	empire_ids.sort()

	if empire_ids.is_empty():
		return {}

	var empire_index_by_id: Dictionary = {}
	for empire_index in range(empire_ids.size()):
		empire_index_by_id[empire_ids[empire_index]] = empire_index

	var bounds: Dictionary = _build_field_bounds(empire_systems)
	var field_data: Dictionary = _build_influence_data(empire_systems, empire_ids, empire_index_by_id, bounds)
	if field_data.is_empty():
		return {}

	var fill_mesh: Mesh = _build_fill_mesh(bounds)
	var border_mesh: Mesh = _build_border_mesh(field_data)
	var influence_texture: Texture2D = _build_influence_texture(field_data)

	return {
		"empire_ids": empire_ids,
		"fill_mesh": fill_mesh,
		"border_mesh": border_mesh,
		"influence_texture": influence_texture,
	}


func _build_field_bounds(empire_systems: Dictionary) -> Dictionary:
	var min_point := Vector2.ZERO
	var max_point := Vector2.ZERO
	var has_points: bool = false

	for systems_variant in empire_systems.values():
		var systems: Array = systems_variant
		for system_variant in systems:
			var system_record: Dictionary = system_variant
			var position: Vector3 = system_record.get("position", Vector3.ZERO)
			var point := Vector2(position.x, position.z)
			if not has_points:
				min_point = point
				max_point = point
				has_points = true
				continue
			min_point.x = minf(min_point.x, point.x)
			min_point.y = minf(min_point.y, point.y)
			max_point.x = maxf(max_point.x, point.x)
			max_point.y = maxf(max_point.y, point.y)

	if not has_points:
		return {}

	var blob_radius: float = _get_blob_radius()
	var falloff_radius: float = _get_falloff_radius(blob_radius)
	var margin: float = maxf(falloff_radius * OWNERSHIP_FIELD_MARGIN_FACTOR, OWNERSHIP_FIELD_MARGIN_MIN)
	var minimum_span: float = falloff_radius * 2.2
	var current_size: Vector2 = max_point - min_point
	if current_size.x < minimum_span:
		var expand_x := (minimum_span - current_size.x) * 0.5
		min_point.x -= expand_x
		max_point.x += expand_x
	if current_size.y < minimum_span:
		var expand_y := (minimum_span - current_size.y) * 0.5
		min_point.y -= expand_y
		max_point.y += expand_y

	min_point -= Vector2.ONE * margin
	max_point += Vector2.ONE * margin

	return {
		"min": min_point,
		"max": max_point,
		"size": max_point - min_point,
	}


func _build_influence_data(
	empire_systems: Dictionary,
	empire_ids: PackedStringArray,
	empire_index_by_id: Dictionary,
	bounds: Dictionary
) -> Dictionary:
	var map_min: Vector2 = bounds.get("min", Vector2.ZERO)
	var map_size: Vector2 = bounds.get("size", Vector2.ZERO)
	if map_size.x <= 0.001 or map_size.y <= 0.001:
		return {}

	var target_texel_world: float = maxf(_host.min_system_distance * OWNERSHIP_TEXEL_TARGET_FACTOR, OWNERSHIP_TEXEL_TARGET_MIN)
	var width: int = clampi(int(ceil(map_size.x / target_texel_world)) + 1, OWNERSHIP_RESOLUTION_MIN, OWNERSHIP_RESOLUTION_MAX)
	var height: int = clampi(int(ceil(map_size.y / target_texel_world)) + 1, OWNERSHIP_RESOLUTION_MIN, OWNERSHIP_RESOLUTION_MAX)
	var texel_size := Vector2(
		map_size.x / maxf(float(width - 1), 1.0),
		map_size.y / maxf(float(height - 1), 1.0)
	)
	var pixel_count: int = width * height

	var influence_fields: Array[PackedFloat32Array] = []
	for _empire_id in empire_ids:
		var empire_field := PackedFloat32Array()
		empire_field.resize(pixel_count)
		influence_fields.append(empire_field)

	var blob_radius: float = _get_blob_radius()
	var falloff_radius: float = _get_falloff_radius(blob_radius)
	var system_weight: float = blob_radius * blob_radius

	for empire_index in range(empire_ids.size()):
		var empire_id: String = empire_ids[empire_index]
		var empire_field: PackedFloat32Array = influence_fields[empire_index]
		var systems_for_empire: Array = empire_systems.get(empire_id, [])
		for system_variant in systems_for_empire:
			var system_record: Dictionary = system_variant
			var position: Vector3 = system_record.get("position", Vector3.ZERO)
			_splat_influence_point(
				empire_field,
				Vector2(position.x, position.z),
				system_weight,
				falloff_radius,
				map_min,
				texel_size,
				width,
				height
			)
		influence_fields[empire_index] = empire_field

	_splat_bridge_influences(
		influence_fields,
		empire_index_by_id,
		system_weight * OWNERSHIP_BRIDGE_WEIGHT,
		falloff_radius * OWNERSHIP_BRIDGE_RADIUS_FACTOR,
		map_min,
		texel_size,
		width,
		height
	)

	var blocker_fields: Array[PackedFloat32Array] = _build_blocker_fields(
		empire_ids,
		system_weight * OWNERSHIP_BLOCKER_WEIGHT,
		blob_radius * OWNERSHIP_BLOCKER_RADIUS_FACTOR,
		map_min,
		texel_size,
		width,
		height
	)

	var dominant_indices := PackedInt32Array()
	dominant_indices.resize(pixel_count)
	var top_influence := PackedFloat32Array()
	top_influence.resize(pixel_count)
	var second_influence := PackedFloat32Array()
	second_influence.resize(pixel_count)

	for pixel_index in range(pixel_count):
		var best_empire_index: int = -1
		var best_influence: float = 0.0
		var second_best_influence: float = 0.0

		for empire_index in range(empire_ids.size()):
			var influence: float = influence_fields[empire_index][pixel_index]
			if influence > best_influence:
				second_best_influence = best_influence
				best_influence = influence
				best_empire_index = empire_index
			elif influence > second_best_influence:
				second_best_influence = influence

		dominant_indices[pixel_index] = best_empire_index
		top_influence[pixel_index] = best_influence
		second_influence[pixel_index] = second_best_influence

	var ownership_indices := PackedInt32Array()
	ownership_indices.resize(pixel_count)
	var ownership_scores := PackedFloat32Array()
	ownership_scores.resize(pixel_count)
	var score_fields: Array[PackedFloat32Array] = []
	for _empire_id in empire_ids:
		var score_field := PackedFloat32Array()
		score_field.resize(pixel_count)
		score_fields.append(score_field)

	for pixel_index in range(pixel_count):
		var best_score: float = -INF
		var best_score_empire_index: int = -1

		for empire_index in range(empire_ids.size()):
			var own_influence: float = influence_fields[empire_index][pixel_index]
			var competitor_influence: float = top_influence[pixel_index]
			if dominant_indices[pixel_index] == empire_index:
				competitor_influence = second_influence[pixel_index]
			var blocker_value: float = blocker_fields[empire_index][pixel_index]
			var ownership_score: float = own_influence - OWNERSHIP_THRESHOLD - competitor_influence * OWNERSHIP_COMPETITOR_WEIGHT - blocker_value
			score_fields[empire_index][pixel_index] = ownership_score
			if ownership_score > best_score:
				best_score = ownership_score
				best_score_empire_index = empire_index

		if best_score > 0.0:
			ownership_indices[pixel_index] = best_score_empire_index
			ownership_scores[pixel_index] = best_score
		else:
			ownership_indices[pixel_index] = -1
			ownership_scores[pixel_index] = 0.0

	return {
		"width": width,
		"height": height,
		"map_min": map_min,
		"map_size": map_size,
		"texel_size": texel_size,
		"empire_ids": empire_ids,
		"influence_fields": influence_fields,
		"blocker_fields": blocker_fields,
		"dominant_indices": dominant_indices,
		"top_influence": top_influence,
		"second_influence": second_influence,
		"score_fields": score_fields,
		"ownership_indices": ownership_indices,
		"ownership_scores": ownership_scores,
	}


func _build_blocker_fields(
	empire_ids: PackedStringArray,
	blocker_weight: float,
	blocker_radius: float,
	map_min: Vector2,
	texel_size: Vector2,
	width: int,
	height: int
) -> Array[PackedFloat32Array]:
	var blocker_fields: Array[PackedFloat32Array] = []
	for _empire_id in empire_ids:
		var blocker_field := PackedFloat32Array()
		blocker_field.resize(width * height)
		blocker_fields.append(blocker_field)

	for system_record_variant in _host.system_records:
		var system_record: Dictionary = system_record_variant
		if not _is_system_hint_visible(str(system_record.get("id", ""))):
			continue
		var system_owner_id: String = str(system_record.get("owner_empire_id", ""))
		var position: Vector3 = system_record.get("position", Vector3.ZERO)
		var point := Vector2(position.x, position.z)
		for empire_index in range(empire_ids.size()):
			if empire_ids[empire_index] == system_owner_id:
				continue
			var blocker_field: PackedFloat32Array = blocker_fields[empire_index]
			_splat_influence_point(
				blocker_field,
				point,
				blocker_weight,
				blocker_radius,
				map_min,
				texel_size,
				width,
				height
			)
			blocker_fields[empire_index] = blocker_field

	return blocker_fields


func _splat_bridge_influences(
	influence_fields: Array[PackedFloat32Array],
	empire_index_by_id: Dictionary,
	bridge_weight: float,
	bridge_radius: float,
	map_min: Vector2,
	texel_size: Vector2,
	width: int,
	height: int
) -> void:
	var blob_radius: float = _get_blob_radius()
	var max_bridge_length: float = _get_falloff_radius(blob_radius) * OWNERSHIP_BRIDGE_MAX_LENGTH_FACTOR

	for link_variant in _host.hyperlane_links:
		var link: Vector2i = link_variant
		if link.x < 0 or link.y < 0 or link.x >= _host.system_records.size() or link.y >= _host.system_records.size():
			continue

		var system_a: Dictionary = _host.system_records[link.x]
		var system_b: Dictionary = _host.system_records[link.y]
		if not _is_system_visible(str(system_a.get("id", ""))) or not _is_system_visible(str(system_b.get("id", ""))):
			continue
		var owner_a: String = str(system_a.get("owner_empire_id", ""))
		var owner_b: String = str(system_b.get("owner_empire_id", ""))
		if owner_a.is_empty() or owner_a != owner_b or not empire_index_by_id.has(owner_a):
			continue

		var start := Vector2(system_a.get("position", Vector3.ZERO).x, system_a.get("position", Vector3.ZERO).z)
		var end := Vector2(system_b.get("position", Vector3.ZERO).x, system_b.get("position", Vector3.ZERO).z)
		var bridge_length: float = start.distance_to(end)
		if bridge_length <= blob_radius * 1.2 or bridge_length > max_bridge_length:
			continue

		var empire_index: int = int(empire_index_by_id[owner_a])
		var spacing: float = maxf(blob_radius * OWNERSHIP_BRIDGE_SAMPLE_SPACING_FACTOR, 1.0)
		var intermediate_samples: int = maxi(0, int(ceil(bridge_length / spacing)) - 1)
		if intermediate_samples <= 0:
			continue

		var empire_field: PackedFloat32Array = influence_fields[empire_index]
		for sample_index in range(intermediate_samples):
			var t: float = float(sample_index + 1) / float(intermediate_samples + 1)
			_splat_influence_point(
				empire_field,
				start.lerp(end, t),
				bridge_weight,
				bridge_radius,
				map_min,
				texel_size,
				width,
				height
			)
		influence_fields[empire_index] = empire_field


func _splat_influence_point(
	field: PackedFloat32Array,
	center: Vector2,
	weight: float,
	falloff_radius: float,
	map_min: Vector2,
	texel_size: Vector2,
	width: int,
	height: int
) -> void:
	var center_x: int = int(round((center.x - map_min.x) / maxf(texel_size.x, 0.001)))
	var center_y: int = int(round((center.y - map_min.y) / maxf(texel_size.y, 0.001)))
	var radius_x: int = int(ceil(falloff_radius / maxf(texel_size.x, 0.001)))
	var radius_y: int = int(ceil(falloff_radius / maxf(texel_size.y, 0.001)))
	var min_distance_sq: float = maxf(minf(texel_size.x, texel_size.y) * minf(texel_size.x, texel_size.y) * 0.18, 9.0)
	var falloff_sq: float = falloff_radius * falloff_radius

	for y in range(maxi(0, center_y - radius_y), mini(height - 1, center_y + radius_y) + 1):
		var world_y: float = map_min.y + float(y) * texel_size.y
		var dy: float = world_y - center.y
		var dy_sq: float = dy * dy
		if dy_sq > falloff_sq:
			continue

		for x in range(maxi(0, center_x - radius_x), mini(width - 1, center_x + radius_x) + 1):
			var world_x: float = map_min.x + float(x) * texel_size.x
			var dx: float = world_x - center.x
			var distance_sq: float = dx * dx + dy_sq
			if distance_sq > falloff_sq:
				continue

			var influence: float = weight / maxf(distance_sq, min_distance_sq)
			field[y * width + x] += influence


func _build_fill_mesh(bounds: Dictionary) -> Mesh:
	var map_min: Vector2 = bounds.get("min", Vector2.ZERO)
	var map_max: Vector2 = bounds.get("max", Vector2.ZERO)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bottom_left := Vector3(map_min.x, OWNERSHIP_FILL_HEIGHT, map_min.y)
	var bottom_right := Vector3(map_max.x, OWNERSHIP_FILL_HEIGHT, map_min.y)
	var top_right := Vector3(map_max.x, OWNERSHIP_FILL_HEIGHT, map_max.y)
	var top_left := Vector3(map_min.x, OWNERSHIP_FILL_HEIGHT, map_max.y)

	_append_fill_vertex(surface_tool, bottom_left, Vector2(0.0, 1.0))
	_append_fill_vertex(surface_tool, bottom_right, Vector2(1.0, 1.0))
	_append_fill_vertex(surface_tool, top_right, Vector2(1.0, 0.0))
	_append_fill_vertex(surface_tool, bottom_left, Vector2(0.0, 1.0))
	_append_fill_vertex(surface_tool, top_right, Vector2(1.0, 0.0))
	_append_fill_vertex(surface_tool, top_left, Vector2(0.0, 0.0))

	return surface_tool.commit()


func _append_fill_vertex(surface_tool: SurfaceTool, vertex: Vector3, uv: Vector2) -> void:
	surface_tool.set_normal(Vector3.UP)
	surface_tool.set_uv(uv)
	surface_tool.add_vertex(vertex)


func _build_border_mesh(field_data: Dictionary) -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_ribbon: bool = false
	var empire_ids: PackedStringArray = field_data.get("empire_ids", PackedStringArray())
	var score_fields: Array[PackedFloat32Array] = field_data.get("score_fields", [])

	for empire_index in range(empire_ids.size()):
		if empire_index >= score_fields.size():
			continue
		var loops: Array[PackedVector2Array] = _extract_contour_loops(field_data, score_fields[empire_index])
		for loop_variant in loops:
			var loop: PackedVector2Array = _smooth_polygon(_sanitize_polygon(loop_variant), OWNERSHIP_LOOP_SMOOTHING_PASSES)
			loop = _sanitize_polygon(loop)
			if loop.size() < 3:
				continue
			_append_loop_ribbon(surface_tool, field_data, score_fields[empire_index], loop, empire_index + 1)
			has_ribbon = true

	if not has_ribbon:
		return null

	return surface_tool.commit()


func _extract_contour_loops(field_data: Dictionary, score_field: PackedFloat32Array) -> Array[PackedVector2Array]:
	var width: int = int(field_data.get("width", 0))
	var height: int = int(field_data.get("height", 0))
	var texel_size: Vector2 = field_data.get("texel_size", Vector2.ONE)
	var map_min: Vector2 = field_data.get("map_min", Vector2.ZERO)
	var segments: Array[Dictionary] = []

	for y in range(height - 1):
		for x in range(width - 1):
			var bottom_left_index: int = y * width + x
			var bottom_right_index: int = bottom_left_index + 1
			var top_left_index: int = (y + 1) * width + x
			var top_right_index: int = top_left_index + 1

			var bottom_left_value: float = score_field[bottom_left_index]
			var bottom_right_value: float = score_field[bottom_right_index]
			var top_right_value: float = score_field[top_right_index]
			var top_left_value: float = score_field[top_left_index]

			var case_index: int = 0
			if bottom_left_value > 0.0:
				case_index |= 1
			if bottom_right_value > 0.0:
				case_index |= 2
			if top_right_value > 0.0:
				case_index |= 4
			if top_left_value > 0.0:
				case_index |= 8

			if case_index == 0 or case_index == 15:
				continue

			var edge_pairs: Array[Vector2i] = _resolve_edge_pairs(
				case_index,
				bottom_left_value,
				bottom_right_value,
				top_right_value,
				top_left_value
			)
			if edge_pairs.is_empty():
				continue

			var cell_origin := Vector2(
				map_min.x + float(x) * texel_size.x,
				map_min.y + float(y) * texel_size.y
			)
			for edge_pair_variant in edge_pairs:
				var edge_pair: Vector2i = edge_pair_variant
				var start_point: Vector2 = _edge_to_world_position(
					edge_pair.x,
					cell_origin,
					texel_size,
					bottom_left_value,
					bottom_right_value,
					top_right_value,
					top_left_value
				)
				var end_point: Vector2 = _edge_to_world_position(
					edge_pair.y,
					cell_origin,
					texel_size,
					bottom_left_value,
					bottom_right_value,
					top_right_value,
					top_left_value
				)
				if start_point.distance_squared_to(end_point) <= 0.001:
					continue
				segments.append({
					"start": start_point,
					"end": end_point,
				})

	return _build_contour_loops_from_segments(segments)


func _resolve_edge_pairs(
	case_index: int,
	bottom_left_value: float,
	bottom_right_value: float,
	top_right_value: float,
	top_left_value: float
) -> Array[Vector2i]:
	match case_index:
		1:
			return [Vector2i(3, 0)]
		2:
			return [Vector2i(0, 1)]
		3:
			return [Vector2i(3, 1)]
		4:
			return [Vector2i(1, 2)]
		5:
			var center_5: float = (bottom_left_value + bottom_right_value + top_right_value + top_left_value) * 0.25
			if center_5 > 0.0:
				return [Vector2i(0, 1), Vector2i(2, 3)]
			return [Vector2i(3, 0), Vector2i(1, 2)]
		6:
			return [Vector2i(0, 2)]
		7:
			return [Vector2i(3, 2)]
		8:
			return [Vector2i(2, 3)]
		9:
			return [Vector2i(0, 2)]
		10:
			var center_10: float = (bottom_left_value + bottom_right_value + top_right_value + top_left_value) * 0.25
			if center_10 > 0.0:
				return [Vector2i(3, 0), Vector2i(1, 2)]
			return [Vector2i(0, 1), Vector2i(2, 3)]
		11:
			return [Vector2i(1, 2)]
		12:
			return [Vector2i(1, 3)]
		13:
			return [Vector2i(0, 1)]
		14:
			return [Vector2i(3, 0)]
		_:
			return []


func _edge_to_world_position(
	edge_index: int,
	cell_origin: Vector2,
	texel_size: Vector2,
	bottom_left_value: float,
	bottom_right_value: float,
	top_right_value: float,
	top_left_value: float
) -> Vector2:
	match edge_index:
		0:
			return Vector2(
				cell_origin.x + texel_size.x * _inverse_lerp(bottom_left_value, bottom_right_value, 0.0),
				cell_origin.y
			)
		1:
			return Vector2(
				cell_origin.x + texel_size.x,
				cell_origin.y + texel_size.y * _inverse_lerp(bottom_right_value, top_right_value, 0.0)
			)
		2:
			return Vector2(
				cell_origin.x + texel_size.x * (1.0 - _inverse_lerp(top_right_value, top_left_value, 0.0)),
				cell_origin.y + texel_size.y
			)
		3:
			return Vector2(
				cell_origin.x,
				cell_origin.y + texel_size.y * (1.0 - _inverse_lerp(top_left_value, bottom_left_value, 0.0))
			)
		_:
			return cell_origin


func _inverse_lerp(from_value: float, to_value: float, target_value: float) -> float:
	var delta: float = to_value - from_value
	if absf(delta) <= 0.0001:
		return 0.5
	return clampf((target_value - from_value) / delta, 0.0, 1.0)


func _build_contour_loops_from_segments(segments: Array[Dictionary]) -> Array[PackedVector2Array]:
	var adjacency: Dictionary = {}
	for segment_index in range(segments.size()):
		var segment: Dictionary = segments[segment_index]
		var start_key: String = _point_key(segment.get("start", Vector2.ZERO))
		var end_key: String = _point_key(segment.get("end", Vector2.ZERO))
		var start_indices: Array = adjacency.get(start_key, [])
		start_indices.append(segment_index)
		adjacency[start_key] = start_indices
		var end_indices: Array = adjacency.get(end_key, [])
		end_indices.append(segment_index)
		adjacency[end_key] = end_indices

	var used: Dictionary = {}
	var loops: Array[PackedVector2Array] = []
	for segment_index in range(segments.size()):
		if used.has(segment_index):
			continue

		var seed_segment: Dictionary = segments[segment_index]
		var points: Array[Vector2] = [
			seed_segment.get("start", Vector2.ZERO),
			seed_segment.get("end", Vector2.ZERO),
		]
		used[segment_index] = true
		_extend_contour(points, segments, adjacency, used, true)
		_extend_contour(points, segments, adjacency, used, false)

		var packed := PackedVector2Array(points)
		packed = _dedupe_consecutive_points(packed)
		if packed.size() >= 2 and packed[0].distance_to(packed[packed.size() - 1]) <= OWNERSHIP_CONTOUR_POINT_SNAP * 2.0:
			packed.remove_at(packed.size() - 1)
		if packed.size() >= 3:
			loops.append(packed)

	return loops


func _extend_contour(
	points: Array[Vector2],
	segments: Array[Dictionary],
	adjacency: Dictionary,
	used: Dictionary,
	forward: bool
) -> void:
	while true:
		var current_index: int = points.size() - 1 if forward else 0
		var previous_index: int = points.size() - 2 if forward else 1
		if previous_index < 0 or previous_index >= points.size():
			return
		var current_point: Vector2 = points[current_index]
		var previous_point: Vector2 = points[previous_index]
		var next_segment_index: int = _pick_next_contour_segment(current_point, previous_point, segments, adjacency, used)
		if next_segment_index == -1:
			return
		used[next_segment_index] = true
		var next_segment: Dictionary = segments[next_segment_index]
		var segment_start: Vector2 = next_segment.get("start", Vector2.ZERO)
		var segment_end: Vector2 = next_segment.get("end", Vector2.ZERO)
		var next_point: Vector2 = segment_end if _point_key(segment_start) == _point_key(current_point) else segment_start
		if forward:
			points.append(next_point)
		else:
			points.insert(0, next_point)


func _pick_next_contour_segment(
	current_point: Vector2,
	previous_point: Vector2,
	segments: Array[Dictionary],
	adjacency: Dictionary,
	used: Dictionary
) -> int:
	var candidates: Array = adjacency.get(_point_key(current_point), [])
	if candidates.is_empty():
		return -1

	var incoming_direction: Vector2 = (current_point - previous_point).normalized()
	var best_segment_index: int = -1
	var best_turn_dot: float = -INF

	for candidate_index_variant in candidates:
		var candidate_index: int = int(candidate_index_variant)
		if used.has(candidate_index):
			continue
		var segment: Dictionary = segments[candidate_index]
		var segment_start: Vector2 = segment.get("start", Vector2.ZERO)
		var segment_end: Vector2 = segment.get("end", Vector2.ZERO)
		var next_point: Vector2 = segment_end if _point_key(segment_start) == _point_key(current_point) else segment_start
		var outgoing_direction: Vector2 = (next_point - current_point).normalized()
		if outgoing_direction.length_squared() <= 0.0001:
			continue
		var turn_dot: float = incoming_direction.dot(outgoing_direction)
		if turn_dot > best_turn_dot:
			best_turn_dot = turn_dot
			best_segment_index = candidate_index

	return best_segment_index


func _append_loop_ribbon(
	surface_tool: SurfaceTool,
	field_data: Dictionary,
	score_field: PackedFloat32Array,
	loop: PackedVector2Array,
	palette_index: int
) -> void:
	if loop.size() < 3:
		return

	var sample_point: Vector2 = _get_polygon_sample_point(loop)
	var occupied_inside: bool = _sample_score_at_world(field_data, score_field, sample_point) > 0.0
	var empire_width: float = _get_border_inner_width()
	var space_width: float = _get_border_outer_width()
	var empire_vertices := PackedVector2Array()
	var space_vertices := PackedVector2Array()
	var cumulative_lengths := PackedFloat32Array()
	cumulative_lengths.resize(loop.size())
	var total_length: float = 0.0

	for point_index in range(loop.size()):
		var previous_point: Vector2 = loop[(point_index - 1 + loop.size()) % loop.size()]
		var current_point: Vector2 = loop[point_index]
		var next_point: Vector2 = loop[(point_index + 1) % loop.size()]
		var previous_edge: Vector2 = (current_point - previous_point).normalized()
		var next_edge: Vector2 = (next_point - current_point).normalized()
		if previous_edge.length_squared() <= 0.0001:
			previous_edge = next_edge
		if next_edge.length_squared() <= 0.0001:
			next_edge = previous_edge

		var polygon_inside_prev := Vector2(-previous_edge.y, previous_edge.x)
		var polygon_inside_next := Vector2(-next_edge.y, next_edge.x)
		var empire_normal_prev := polygon_inside_prev if occupied_inside else -polygon_inside_prev
		var empire_normal_next := polygon_inside_next if occupied_inside else -polygon_inside_next
		var space_normal_prev := -empire_normal_prev
		var space_normal_next := -empire_normal_next

		empire_vertices.append(_compute_miter_offset_vertex(current_point, empire_normal_prev, empire_normal_next, empire_width))
		space_vertices.append(_compute_miter_offset_vertex(current_point, space_normal_prev, space_normal_next, space_width))
		cumulative_lengths[point_index] = total_length
		total_length += current_point.distance_to(next_point)

	if total_length <= 0.001:
		return

	for point_index in range(loop.size()):
		var next_index: int = (point_index + 1) % loop.size()
		var from_u: float = cumulative_lengths[point_index] / total_length
		var to_u: float = (cumulative_lengths[point_index] + loop[point_index].distance_to(loop[next_index])) / total_length

		_append_border_vertex(surface_tool, space_vertices[point_index], Vector2(from_u, 0.0), palette_index)
		_append_border_vertex(surface_tool, space_vertices[next_index], Vector2(to_u, 0.0), palette_index)
		_append_border_vertex(surface_tool, empire_vertices[next_index], Vector2(to_u, 1.0), palette_index)
		_append_border_vertex(surface_tool, space_vertices[point_index], Vector2(from_u, 0.0), palette_index)
		_append_border_vertex(surface_tool, empire_vertices[next_index], Vector2(to_u, 1.0), palette_index)
		_append_border_vertex(surface_tool, empire_vertices[point_index], Vector2(from_u, 1.0), palette_index)


func _compute_miter_offset_vertex(
	current_point: Vector2,
	normal_prev: Vector2,
	normal_next: Vector2,
	width: float
) -> Vector2:
	var miter: Vector2 = normal_prev + normal_next
	if miter.length_squared() <= 0.0001:
		return current_point + normal_next * width
	miter = miter.normalized()
	var denominator: float = maxf(miter.dot(normal_next), 0.35)
	var miter_length: float = minf(width / denominator, width * OWNERSHIP_LOOP_MITER_LIMIT)
	return current_point + miter * miter_length


func _point_key(point: Vector2) -> String:
	return "%0.2f|%0.2f" % [
		snappedf(point.x, OWNERSHIP_CONTOUR_POINT_SNAP),
		snappedf(point.y, OWNERSHIP_CONTOUR_POINT_SNAP),
	]


func _dedupe_consecutive_points(points: PackedVector2Array) -> PackedVector2Array:
	var deduped := PackedVector2Array()
	for point in points:
		if deduped.is_empty() or deduped[deduped.size() - 1].distance_to(point) > OWNERSHIP_CONTOUR_POINT_SNAP:
			deduped.append(point)
	return deduped


func _sanitize_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var sanitized := polygon
	if sanitized.size() >= 2 and sanitized[0].distance_to(sanitized[sanitized.size() - 1]) <= OWNERSHIP_CONTOUR_POINT_SNAP:
		sanitized.remove_at(sanitized.size() - 1)
	if sanitized.size() >= 3 and _polygon_area(sanitized) < 0.0:
		sanitized.reverse()
	return sanitized


func _smooth_polygon(polygon: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var result := _sanitize_polygon(polygon)
	for _iteration in range(iterations):
		if result.size() < 3:
			return result
		var smoothed := PackedVector2Array()
		for point_index in range(result.size()):
			var current: Vector2 = result[point_index]
			var next_point: Vector2 = result[(point_index + 1) % result.size()]
			smoothed.append(current.lerp(next_point, 0.25))
			smoothed.append(current.lerp(next_point, 0.75))
		result = smoothed
	return result


func _polygon_area(polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0

	var area := 0.0
	for point_index in range(polygon.size()):
		var current: Vector2 = polygon[point_index]
		var next_point: Vector2 = polygon[(point_index + 1) % polygon.size()]
		area += current.x * next_point.y - next_point.x * current.y
	return area * 0.5


func _get_polygon_sample_point(polygon: PackedVector2Array) -> Vector2:
	var triangulated_indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	if triangulated_indices.size() >= 3:
		return (
			polygon[triangulated_indices[0]]
			+ polygon[triangulated_indices[1]]
			+ polygon[triangulated_indices[2]]
		) / 3.0

	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point
	return centroid / maxf(float(polygon.size()), 1.0)


func _append_border_vertex(surface_tool: SurfaceTool, point: Vector2, uv: Vector2, palette_index: int) -> void:
	surface_tool.set_normal(Vector3.UP)
	surface_tool.set_uv(uv)
	surface_tool.set_uv2(Vector2(float(palette_index), 0.0))
	surface_tool.add_vertex(Vector3(point.x, OWNERSHIP_BORDER_HEIGHT, point.y))


func _sample_score_at_world(field_data: Dictionary, score_field: PackedFloat32Array, world_point: Vector2) -> float:
	var map_min: Vector2 = field_data.get("map_min", Vector2.ZERO)
	var texel_size: Vector2 = field_data.get("texel_size", Vector2.ONE)
	var width: int = int(field_data.get("width", 0))
	var height: int = int(field_data.get("height", 0))
	if width <= 0 or height <= 0:
		return -OWNERSHIP_THRESHOLD

	var fx: float = (world_point.x - map_min.x) / maxf(texel_size.x, 0.001)
	var fy: float = (world_point.y - map_min.y) / maxf(texel_size.y, 0.001)
	var x0: int = clampi(int(floor(fx)), 0, width - 1)
	var y0: int = clampi(int(floor(fy)), 0, height - 1)
	var x1: int = clampi(x0 + 1, 0, width - 1)
	var y1: int = clampi(y0 + 1, 0, height - 1)
	var tx: float = clampf(fx - float(x0), 0.0, 1.0)
	var ty: float = clampf(fy - float(y0), 0.0, 1.0)

	var bottom_left: float = score_field[y0 * width + x0]
	var bottom_right: float = score_field[y0 * width + x1]
	var top_left: float = score_field[y1 * width + x0]
	var top_right: float = score_field[y1 * width + x1]
	var bottom: float = lerpf(bottom_left, bottom_right, tx)
	var top: float = lerpf(top_left, top_right, tx)
	return lerpf(bottom, top, ty)


func _build_influence_texture(field_data: Dictionary) -> Texture2D:
	var width: int = int(field_data.get("width", 0))
	var height: int = int(field_data.get("height", 0))
	var ownership_scores: PackedFloat32Array = field_data.get("ownership_scores", PackedFloat32Array())
	var ownership_indices: PackedInt32Array = field_data.get("ownership_indices", PackedInt32Array())

	var image := Image.create(width, height, false, Image.FORMAT_RGBAF)
	for y in range(height):
		var image_y: int = height - 1 - y
		for x in range(width):
			var pixel_index: int = y * width + x
			var palette_index: float = 0.0
			if ownership_indices[pixel_index] >= 0 and ownership_scores[pixel_index] > 0.0:
				palette_index = float(ownership_indices[pixel_index] + 1)
			image.set_pixel(
				x,
				image_y,
				Color(
					ownership_scores[pixel_index],
					palette_index,
					0.0,
					1.0
				)
			)

	return ImageTexture.create_from_image(image)


func _apply_territory_cache() -> void:
	var empire_ids: PackedStringArray = _territory_cache.get("empire_ids", PackedStringArray())
	var palette_texture: Texture2D = _build_palette_texture(empire_ids)
	var palette_size: int = empire_ids.size() + 1

	var fill_material := ShaderMaterial.new()
	fill_material.shader = TERRITORY_FILL_SHADER
	fill_material.set_shader_parameter("influence_map", _territory_cache.get("influence_texture"))
	fill_material.set_shader_parameter("palette_texture", palette_texture)
	fill_material.set_shader_parameter("palette_size", palette_size)
	fill_material.set_shader_parameter("threshold", 0.0)
	fill_material.set_shader_parameter("fill_overlap", 0.06)
	fill_material.set_shader_parameter("fill_softness", 0.16)
	fill_material.set_shader_parameter("fill_opacity", float(_host.ownership_core_opacity))

	var border_material := ShaderMaterial.new()
	border_material.shader = TERRITORY_BORDER_SHADER
	border_material.set_shader_parameter("palette_texture", palette_texture)
	border_material.set_shader_parameter("palette_size", palette_size)
	border_material.set_shader_parameter("bright_rim_strength", 1.0 if bool(_host.ownership_bright_rim_enabled) else 0.0)
	border_material.set_shader_parameter("inner_alpha_floor", 0.18)

	_host.ownership_markers.mesh = _territory_cache.get("fill_mesh", null)
	_host.ownership_markers.material_override = fill_material
	_host.ownership_connectors.mesh = _territory_cache.get("border_mesh", null)
	_host.ownership_connectors.material_override = border_material


func _build_palette_texture(empire_ids: PackedStringArray) -> Texture2D:
	var image := Image.create(empire_ids.size() + 1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 0.0))
	for empire_index in range(empire_ids.size()):
		var empire_id: String = empire_ids[empire_index]
		var empire_record: Dictionary = _host.empires_by_id.get(empire_id, {})
		var base_color: Color = empire_record.get("color", Color.WHITE)
		image.set_pixel(empire_index + 1, 0, Color(base_color.r, base_color.g, base_color.b, 1.0))
	return ImageTexture.create_from_image(image)


func _get_blob_radius() -> float:
	return maxf(float(_host.min_system_distance) * OWNERSHIP_BLOB_RADIUS_FACTOR, OWNERSHIP_BLOB_RADIUS_MIN)


func _get_falloff_radius(blob_radius: float) -> float:
	return blob_radius * OWNERSHIP_FALLOFF_RADIUS_FACTOR


func _get_border_outer_width() -> float:
	return maxf(float(_host.min_system_distance) * OWNERSHIP_BORDER_OUTER_FACTOR, OWNERSHIP_BORDER_OUTER_MIN)


func _get_border_inner_width() -> float:
	return maxf(float(_host.min_system_distance) * OWNERSHIP_BORDER_INNER_FACTOR, OWNERSHIP_BORDER_INNER_MIN)


func _is_system_visible(system_id: String) -> bool:
	if system_id.is_empty():
		return false
	if _host != null and _host.has_method("is_system_visible_on_map"):
		return bool(_host.is_system_visible_on_map(system_id))
	return true


func _is_system_hint_visible(system_id: String) -> bool:
	if system_id.is_empty():
		return false
	if _host != null and _host.has_method("is_system_hint_visible_on_map"):
		return bool(_host.is_system_hint_visible_on_map(system_id))
	return _is_system_visible(system_id)
