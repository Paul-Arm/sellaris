extends RefCounted

const BLACK_HOLE_TYPE := "Black hole"
const NEUTRON_TYPE := "Neutron star"
const O_CLASS_TYPE := "O class star"
const OWNERSHIP_BLOB_RADIUS_FACTOR := 2.05
const OWNERSHIP_EXCLUSION_RADIUS_FACTOR := 1.18
const OWNERSHIP_CONNECTOR_RADIUS_FACTOR := 0.8
const OWNERSHIP_CONNECTION_DISTANCE_FACTOR := 5.75
const OWNERSHIP_BORDER_WIDTH_FACTOR := 0.24
const OWNERSHIP_CIRCLE_SEGMENTS := 40
const OWNERSHIP_ISLAND_BRIDGE_DISTANCE_FACTOR := 1.15
const OWNERSHIP_ISLAND_BRIDGE_RADIUS_FACTOR := 1.12
const HYPERLANE_OUTER_WIDTH_FACTOR := 0.16
const HYPERLANE_CORE_WIDTH_FACTOR := 0.055
const HYPERLANE_OUTER_MIN_WIDTH := 7.5
const HYPERLANE_CORE_MIN_WIDTH := 2.6
const HYPERLANE_HEIGHT_OFFSET := 2.2

var _host: Node
var _star_core_shader: Shader
var _star_glow_shader: Shader


func bind(host: Node, star_core_shader: Shader, star_glow_shader: Shader) -> void:
	_host = host
	_star_core_shader = star_core_shader
	_star_glow_shader = star_glow_shader


func unbind() -> void:
	_host = null
	_star_core_shader = null
	_star_glow_shader = null


func render_stars() -> void:
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 4.5
	core_mesh.height = 9.0
	core_mesh.radial_segments = 18
	core_mesh.rings = 12

	var core_material := ShaderMaterial.new()
	core_material.shader = _star_core_shader
	core_material.set_shader_parameter("emission_strength", 1.2)
	core_material.set_shader_parameter("rim_strength", 0.18)
	core_material.set_shader_parameter("rim_power", 2.6)
	core_material.set_shader_parameter("saturation_boost", 1.45)
	core_mesh.material = core_material

	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 11.0
	glow_mesh.height = 22.0
	glow_mesh.radial_segments = 18
	glow_mesh.rings = 12

	var star_instances: Array[Dictionary] = []
	for system_record in _host.system_records:
		var star_profile: Dictionary = system_record.get("star_profile", {})
		var profile_stars: Array = star_profile.get("stars", [])
		if profile_stars.is_empty():
			profile_stars = [{
				"index": 0,
				"color": Color(1.0, 0.93, 0.46, 1.0),
				"scale": 1.0,
				"special_type": "none",
			}]

		var orbit_radius := 12.0
		if profile_stars.size() == 2:
			orbit_radius = 9.5
		elif profile_stars.size() >= 3:
			orbit_radius = 13.0

		for star_data_variant in profile_stars:
			var star_data: Dictionary = star_data_variant
			var offset := _get_star_offset(int(star_data.get("index", 0)), profile_stars.size(), orbit_radius)
			star_instances.append({
				"position": system_record["position"] + offset,
				"color": star_data.get("color", star_profile.get("display_color", Color.WHITE)),
				"scale": float(star_data.get("scale", 1.0)),
				"special_type": str(star_data.get("special_type", "none")),
				"is_pinned": str(system_record.get("id", "")) == _host.pinned_system_id,
			})

	var core_multimesh := MultiMesh.new()
	core_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	core_multimesh.use_colors = true
	core_multimesh.mesh = core_mesh
	core_multimesh.instance_count = star_instances.size()

	var glow_multimesh := MultiMesh.new()
	glow_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	glow_multimesh.use_colors = true
	glow_multimesh.mesh = glow_mesh
	glow_multimesh.instance_count = star_instances.size()

	for i in range(star_instances.size()):
		var instance: Dictionary = star_instances[i]
		var star_scale: float = float(instance["scale"])
		var color: Color = instance["color"]
		var special_type: String = str(instance["special_type"])
		var is_pinned: bool = bool(instance.get("is_pinned", false))
		var star_position: Vector3 = instance["position"]
		var core_scale := star_scale * 1.05
		var glow_scale := star_scale * 2.0

		if special_type == BLACK_HOLE_TYPE:
			core_scale *= 0.72
			glow_scale *= 1.25
			color = color.darkened(0.55)
		elif special_type == NEUTRON_TYPE:
			core_scale *= 0.68
			glow_scale *= 0.95
		elif special_type == O_CLASS_TYPE:
			core_scale *= 1.18
			glow_scale *= 1.15

		if is_pinned:
			core_scale *= 1.18
			glow_scale *= 1.55
			color = color.lightened(0.18)

		core_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * core_scale), star_position))
		core_multimesh.set_instance_color(i, color)

		var glow_color := _get_glow_color(color, special_type)
		if is_pinned:
			glow_color = glow_color.lerp(Color(1.0, 0.95, 0.62, 0.82), 0.62)
			glow_color.a = maxf(glow_color.a, 0.78)
		glow_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * glow_scale), star_position))
		glow_multimesh.set_instance_color(i, glow_color)

	_host.core_stars.multimesh = core_multimesh
	_host.glow_stars.multimesh = glow_multimesh
	_host.glow_stars.material_override = _build_glow_material()


func render_hyperlanes() -> void:
	if _host.hyperlane_links.is_empty():
		_host.hyperlanes.mesh = null
		_host.hyperlanes.material_override = null
		return

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var outer_width := maxf(_host.min_system_distance * HYPERLANE_OUTER_WIDTH_FACTOR, HYPERLANE_OUTER_MIN_WIDTH)
	var core_width := maxf(_host.min_system_distance * HYPERLANE_CORE_WIDTH_FACTOR, HYPERLANE_CORE_MIN_WIDTH)
	var outer_color := Color(0.28, 0.96, 0.96, 0.16)
	var core_color := Color(0.66, 1.0, 1.0, 0.76)

	for link in _host.hyperlane_links:
		var start_point: Vector3 = _host.system_positions[link.x]
		var end_point: Vector3 = _host.system_positions[link.y]
		_append_hyperlane_band(surface_tool, start_point, end_point, outer_width, outer_color, HYPERLANE_HEIGHT_OFFSET)
		_append_hyperlane_band(surface_tool, start_point, end_point, core_width, core_color, HYPERLANE_HEIGHT_OFFSET + 0.55)

	_host.hyperlanes.mesh = surface_tool.commit()
	_host.hyperlanes.material_override = _build_hyperlane_material()


func render_ownership_markers() -> void:
	var empire_owned_systems: Dictionary = {}
	for system_record in _host.system_records:
		var owner_empire_id: String = str(system_record.get("owner_empire_id", ""))
		if owner_empire_id.is_empty() or not _host.empires_by_id.has(owner_empire_id):
			continue
		var aura_record: Dictionary = {
			"system_id": str(system_record.get("id", "")),
			"position": system_record["position"],
			"color": _host.empires_by_id[owner_empire_id].get("color", Color.WHITE),
		}
		var owned_by_empire: Array = empire_owned_systems.get(owner_empire_id, [])
		owned_by_empire.append(aura_record)
		empire_owned_systems[owner_empire_id] = owned_by_empire

	if empire_owned_systems.is_empty():
		_host.ownership_markers.mesh = null
		_host.ownership_connectors.mesh = null
		_host.ownership_markers.material_override = null
		_host.ownership_connectors.material_override = null
		return

	var fill_tool := SurfaceTool.new()
	fill_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var border_tool := SurfaceTool.new()
	border_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for owner_empire_id_variant in empire_owned_systems.keys():
		var owner_empire_id: String = str(owner_empire_id_variant)
		var systems_for_empire: Array = empire_owned_systems.get(owner_empire_id, [])
		var region_color: Color = _host.empires_by_id[owner_empire_id].get("color", Color.WHITE)
		var clustered_regions: Array[Dictionary] = _build_empire_blob_regions(owner_empire_id, systems_for_empire)

		for region_data_variant in clustered_regions:
			var region_data: Dictionary = region_data_variant
			var region_polygon: PackedVector2Array = region_data["polygon"]
			var region_height: float = float(region_data["height"])
			if region_polygon.size() < 3:
				continue
			_append_region_fill(fill_tool, region_polygon, region_height + 1.2, region_color)
			_append_region_border(border_tool, region_polygon, region_height + 2.4, region_color)

	_host.ownership_markers.mesh = fill_tool.commit()
	_host.ownership_connectors.mesh = border_tool.commit()
	_host.ownership_markers.material_override = _build_ownership_fill_material()
	_host.ownership_connectors.material_override = _build_ownership_border_material()


func _build_empire_blob_regions(owner_empire_id: String, systems_for_empire: Array) -> Array[Dictionary]:
	var clustered_regions: Array[Dictionary] = []
	var blob_radius: float = _get_ownership_blob_radius()
	var clusters: Array = _build_owned_system_clusters(systems_for_empire)

	for cluster_variant in clusters:
		var cluster_systems: Array = cluster_variant
		var primitive_regions: Array[PackedVector2Array] = []
		for system_variant in cluster_systems:
			var system_record: Dictionary = system_variant
			var system_position: Vector3 = system_record["position"]
			primitive_regions.append(_build_circle_polygon(Vector2(system_position.x, system_position.z), blob_radius, OWNERSHIP_CIRCLE_SEGMENTS))

		for connector_variant in _build_cluster_connector_polygons(cluster_systems):
			var connector_polygon: PackedVector2Array = connector_variant
			if connector_polygon.size() >= 3:
				primitive_regions.append(connector_polygon)

		var merged_polygons: Array[PackedVector2Array] = _merge_overlapping_polygons(primitive_regions)
		merged_polygons = _subtract_non_owned_systems(owner_empire_id, merged_polygons)
		merged_polygons = _bridge_region_islands(owner_empire_id, cluster_systems, merged_polygons)

		for merged_polygon in merged_polygons:
			var styled_polygon := _smooth_polygon(_sanitize_polygon(merged_polygon), 1)
			if styled_polygon.size() < 3:
				continue
			clustered_regions.append({
				"polygon": styled_polygon,
				"height": _get_region_height(cluster_systems),
			})

	return clustered_regions


func _build_circle_polygon(center: Vector2, radius: float, segment_count: int) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point_index in range(segment_count):
		var angle: float = float(point_index) * TAU / float(segment_count)
		polygon.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return polygon


func _build_owned_system_clusters(systems_for_empire: Array) -> Array:
	var clusters: Array = []
	var visited: Dictionary = {}
	var max_distance_sq: float = _get_ownership_connection_distance()
	max_distance_sq *= max_distance_sq

	for system_index in range(systems_for_empire.size()):
		if visited.has(system_index):
			continue

		var cluster: Array = []
		var queue: Array[int] = [system_index]
		visited[system_index] = true

		while not queue.is_empty():
			var current_index: int = int(queue.pop_front())
			var current_system: Dictionary = systems_for_empire[current_index]
			cluster.append(current_system)
			var current_position: Vector3 = current_system["position"]

			for candidate_index in range(systems_for_empire.size()):
				if visited.has(candidate_index):
					continue
				var candidate_system: Dictionary = systems_for_empire[candidate_index]
				var candidate_position: Vector3 = candidate_system["position"]
				if current_position.distance_squared_to(candidate_position) > max_distance_sq:
					continue
				visited[candidate_index] = true
				queue.append(candidate_index)

		clusters.append(cluster)

	return clusters


func _build_cluster_connector_polygons(cluster_systems: Array) -> Array[PackedVector2Array]:
	var connector_polygons: Array[PackedVector2Array] = []
	if cluster_systems.size() <= 1:
		return connector_polygons

	var dedupe: Dictionary = {}
	var max_distance_sq: float = _get_ownership_connection_distance()
	max_distance_sq *= max_distance_sq
	var connector_radius: float = _get_ownership_connector_radius()
	var system_index_by_id: Dictionary = {}

	for system_index in range(cluster_systems.size()):
		var system_record: Dictionary = cluster_systems[system_index]
		system_index_by_id[str(system_record.get("system_id", system_record.get("id", "")))] = system_index

	for link in _host.hyperlane_links:
		var system_a: int = int(link.x)
		var system_b: int = int(link.y)
		if system_a < 0 or system_b < 0 or system_a >= _host.system_records.size() or system_b >= _host.system_records.size():
			continue

		var system_a_id: String = str(_host.system_records[system_a].get("id", ""))
		var system_b_id: String = str(_host.system_records[system_b].get("id", ""))
		if not system_index_by_id.has(system_a_id) or not system_index_by_id.has(system_b_id):
			continue

		var local_a: int = int(system_index_by_id[system_a_id])
		var local_b: int = int(system_index_by_id[system_b_id])
		_append_cluster_connector_polygon(
			connector_polygons,
			dedupe,
			cluster_systems,
			local_a,
			local_b,
			max_distance_sq,
			connector_radius
		)

	for system_index in range(cluster_systems.size()):
		var origin: Dictionary = cluster_systems[system_index]
		var origin_position: Vector3 = origin["position"]
		var nearest_index: int = -1
		var nearest_distance_sq: float = INF

		for candidate_index in range(cluster_systems.size()):
			if candidate_index == system_index:
				continue
			var candidate: Dictionary = cluster_systems[candidate_index]
			var distance_sq: float = origin_position.distance_squared_to(candidate["position"])
			if distance_sq > max_distance_sq or distance_sq >= nearest_distance_sq:
				continue
			nearest_index = candidate_index
			nearest_distance_sq = distance_sq

		if nearest_index == -1:
			continue

		_append_cluster_connector_polygon(
			connector_polygons,
			dedupe,
			cluster_systems,
			system_index,
			nearest_index,
			max_distance_sq,
			connector_radius
		)

	return connector_polygons


func _append_cluster_connector_polygon(
	connector_polygons: Array[PackedVector2Array],
	dedupe: Dictionary,
	cluster_systems: Array,
	system_index: int,
	target_index: int,
	max_distance_sq: float,
	connector_radius: float
) -> void:
	if system_index == target_index:
		return

	var edge_a: int = mini(system_index, target_index)
	var edge_b: int = maxi(system_index, target_index)
	var edge_key: String = "%s:%s" % [edge_a, edge_b]
	if dedupe.has(edge_key):
		return

	var origin: Dictionary = cluster_systems[system_index]
	var target: Dictionary = cluster_systems[target_index]
	var origin_position: Vector3 = origin["position"]
	var target_position: Vector3 = target["position"]
	if origin_position.distance_squared_to(target_position) > max_distance_sq:
		return

	dedupe[edge_key] = true
	connector_polygons.append(_build_capsule_polygon(
		Vector2(origin_position.x, origin_position.z),
		Vector2(target_position.x, target_position.z),
		connector_radius
	))


func _build_capsule_polygon(start_point: Vector2, end_point: Vector2, radius: float) -> PackedVector2Array:
	var direction: Vector2 = end_point - start_point
	if direction.length_squared() <= 0.001:
		return _build_circle_polygon(start_point, radius, OWNERSHIP_CIRCLE_SEGMENTS)

	var polygon := PackedVector2Array()
	var axis: Vector2 = direction.normalized()
	var normal := Vector2(-axis.y, axis.x)
	var start_angle: float = normal.angle()
	var end_angle: float = start_angle + PI
	var arc_steps: int = maxi(6, OWNERSHIP_CIRCLE_SEGMENTS / 2)

	for step in range(arc_steps + 1):
		var t: float = float(step) / float(arc_steps)
		var angle: float = start_angle + PI * t
		polygon.append(start_point + Vector2(cos(angle), sin(angle)) * radius)

	for step in range(arc_steps + 1):
		var t: float = float(step) / float(arc_steps)
		var angle: float = end_angle + PI * t
		polygon.append(end_point + Vector2(cos(angle), sin(angle)) * radius)

	return polygon


func _merge_overlapping_polygons(polygons: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var merged_regions: Array[PackedVector2Array] = polygons.duplicate()
	var did_merge: bool = true

	while did_merge:
		did_merge = false
		for first_index in range(merged_regions.size()):
			for second_index in range(first_index + 1, merged_regions.size()):
				var merge_result: Array = Geometry2D.merge_polygons(merged_regions[first_index], merged_regions[second_index])
				if merge_result.size() != 1:
					continue

				var merged_polygon: PackedVector2Array = merge_result[0]
				if merged_polygon.size() >= 2 and merged_polygon[0].is_equal_approx(merged_polygon[merged_polygon.size() - 1]):
					merged_polygon.remove_at(merged_polygon.size() - 1)
				merged_regions.remove_at(second_index)
				merged_regions.remove_at(first_index)
				merged_regions.append(merged_polygon)
				did_merge = true
				break
			if did_merge:
				break

	return merged_regions


func _subtract_non_owned_systems(owner_empire_id: String, polygons: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var exclusion_records: Array[Dictionary] = []
	var exclusion_radius: float = _get_ownership_exclusion_radius()

	for system_record in _host.system_records:
		var system_owner_id: String = str(system_record.get("owner_empire_id", ""))
		if system_owner_id == owner_empire_id:
			continue
		var system_position: Vector3 = system_record["position"]
		exclusion_records.append({
			"center": Vector2(system_position.x, system_position.z),
			"polygon": _build_circle_polygon(Vector2(system_position.x, system_position.z), exclusion_radius, 16),
		})

	var result_polygons: Array[PackedVector2Array] = polygons.duplicate()
	for exclusion_record_variant in exclusion_records:
		var exclusion_record: Dictionary = exclusion_record_variant
		var exclusion_center: Vector2 = exclusion_record["center"]
		var exclusion_polygon: PackedVector2Array = exclusion_record["polygon"]
		var next_result: Array[PackedVector2Array] = []
		for region_polygon in result_polygons:
			if not _is_point_near_polygon_bounds(exclusion_center, region_polygon, exclusion_radius * 1.5):
				next_result.append(region_polygon)
				continue

			var overlap_regions: Array = Geometry2D.intersect_polygons(region_polygon, exclusion_polygon)
			if overlap_regions.is_empty():
				next_result.append(region_polygon)
				continue

			var clipped_regions: Array = Geometry2D.clip_polygons(region_polygon, exclusion_polygon)
			for clipped_region_variant in clipped_regions:
				var clipped_region: PackedVector2Array = clipped_region_variant
				if clipped_region.size() >= 3:
					if clipped_region[0].is_equal_approx(clipped_region[clipped_region.size() - 1]):
						clipped_region.remove_at(clipped_region.size() - 1)
					next_result.append(clipped_region)
		result_polygons = next_result

	return result_polygons


func _bridge_region_islands(
	owner_empire_id: String,
	cluster_systems: Array,
	polygons: Array[PackedVector2Array]
) -> Array[PackedVector2Array]:
	var sanitized_polygons: Array[PackedVector2Array] = []
	for polygon_variant in polygons:
		var polygon: PackedVector2Array = _sanitize_polygon(polygon_variant)
		if polygon.size() >= 3:
			sanitized_polygons.append(polygon)

	if sanitized_polygons.size() <= 1:
		return sanitized_polygons

	var bridge_distance_sq := _get_ownership_island_bridge_distance()
	bridge_distance_sq *= bridge_distance_sq
	var bridge_radius := _get_ownership_connector_radius() * OWNERSHIP_ISLAND_BRIDGE_RADIUS_FACTOR
	var primitive_regions: Array[PackedVector2Array] = sanitized_polygons.duplicate()

	for _iteration in range(cluster_systems.size()):
		var island_groups: Array = _build_polygon_system_groups(cluster_systems, primitive_regions)
		if island_groups.size() <= 1:
			break

		var best_group_a := -1
		var best_group_b := -1
		var best_distance_sq := INF
		var best_start := Vector2.ZERO
		var best_end := Vector2.ZERO

		for first_index in range(island_groups.size()):
			var first_group: Dictionary = island_groups[first_index]
			var first_systems: Array = first_group.get("systems", [])
			if first_systems.is_empty():
				continue

			for second_index in range(first_index + 1, island_groups.size()):
				var second_group: Dictionary = island_groups[second_index]
				var second_systems: Array = second_group.get("systems", [])
				if second_systems.is_empty():
					continue

				for first_system_variant in first_systems:
					var first_system: Dictionary = first_system_variant
					var first_point := Vector2(first_system["position"].x, first_system["position"].z)
					for second_system_variant in second_systems:
						var second_system: Dictionary = second_system_variant
						var second_point := Vector2(second_system["position"].x, second_system["position"].z)
						var distance_sq := first_point.distance_squared_to(second_point)
						if distance_sq >= best_distance_sq or distance_sq > bridge_distance_sq:
							continue
						best_distance_sq = distance_sq
						best_group_a = first_index
						best_group_b = second_index
						best_start = first_point
						best_end = second_point

		if best_group_a == -1 or best_group_b == -1:
			break

		primitive_regions.append(_build_capsule_polygon(best_start, best_end, bridge_radius))
		primitive_regions = _merge_overlapping_polygons(primitive_regions)
		primitive_regions = _subtract_non_owned_systems(owner_empire_id, primitive_regions)

	var result_polygons: Array[PackedVector2Array] = []
	for polygon_variant in primitive_regions:
		var polygon: PackedVector2Array = _sanitize_polygon(polygon_variant)
		if polygon.size() >= 3:
			result_polygons.append(polygon)
	return result_polygons


func _build_polygon_system_groups(cluster_systems: Array, polygons: Array[PackedVector2Array]) -> Array:
	var groups: Array = []
	for polygon_variant in polygons:
		var polygon: PackedVector2Array = _sanitize_polygon(polygon_variant)
		if polygon.size() < 3:
			continue
		groups.append({
			"polygon": polygon,
			"systems": [],
		})

	var capture_margin := _get_ownership_connector_radius() * 0.85
	for system_variant in cluster_systems:
		var system_record: Dictionary = system_variant
		var system_point := Vector2(system_record["position"].x, system_record["position"].z)
		var best_group_index := -1
		var best_distance_sq := INF

		for group_index in range(groups.size()):
			var group: Dictionary = groups[group_index]
			var polygon: PackedVector2Array = group["polygon"]
			if Geometry2D.is_point_in_polygon(system_point, polygon):
				best_group_index = group_index
				best_distance_sq = 0.0
				break
			if not _is_point_near_polygon_bounds(system_point, polygon, capture_margin):
				continue
			var distance_sq := _distance_sq_to_polygon_edges(system_point, polygon)
			if distance_sq < best_distance_sq:
				best_distance_sq = distance_sq
				best_group_index = group_index

		if best_group_index == -1:
			continue

		var systems_for_group: Array = groups[best_group_index].get("systems", [])
		systems_for_group.append(system_record)
		groups[best_group_index]["systems"] = systems_for_group

	var filtered_groups: Array = []
	for group_variant in groups:
		var group: Dictionary = group_variant
		var systems_for_group: Array = group.get("systems", [])
		if systems_for_group.is_empty():
			continue
		filtered_groups.append(group)
	return filtered_groups


func _is_point_near_polygon_bounds(point: Vector2, polygon: PackedVector2Array, margin: float) -> bool:
	if polygon.is_empty():
		return false

	var min_x: float = polygon[0].x
	var max_x: float = polygon[0].x
	var min_y: float = polygon[0].y
	var max_y: float = polygon[0].y

	for polygon_point in polygon:
		min_x = minf(min_x, polygon_point.x)
		max_x = maxf(max_x, polygon_point.x)
		min_y = minf(min_y, polygon_point.y)
		max_y = maxf(max_y, polygon_point.y)

	return point.x >= min_x - margin and point.x <= max_x + margin and point.y >= min_y - margin and point.y <= max_y + margin


func _distance_sq_to_polygon_edges(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.size() < 2:
		return INF

	var best_distance_sq := INF
	for point_index in range(polygon.size()):
		var segment_start: Vector2 = polygon[point_index]
		var segment_end: Vector2 = polygon[(point_index + 1) % polygon.size()]
		var distance_sq := _distance_sq_to_segment(point, segment_start, segment_end)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
	return best_distance_sq


func _distance_sq_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var segment_length_sq := segment.length_squared()
	if segment_length_sq <= 0.001:
		return point.distance_squared_to(segment_start)

	var t := clampf((point - segment_start).dot(segment) / segment_length_sq, 0.0, 1.0)
	var closest_point := segment_start + segment * t
	return point.distance_squared_to(closest_point)


func _append_region_fill(surface_tool: SurfaceTool, region_polygon: PackedVector2Array, region_height: float, region_color: Color) -> void:
	var haze_color := region_color
	haze_color.a = 0.08
	_append_region_band(
		surface_tool,
		region_polygon,
		_get_ownership_border_half_width() * 3.0,
		-_get_ownership_border_half_width() * 0.18,
		region_height - 0.6,
		haze_color
	)

	var fill_color := region_color
	fill_color.a = 0.15
	_append_triangulated_polygon(surface_tool, region_polygon, region_height, fill_color)


func _append_region_border(surface_tool: SurfaceTool, region_polygon: PackedVector2Array, region_height: float, region_color: Color) -> void:
	var half_width: float = _get_ownership_border_half_width()
	var shadow_color := Color(0.02, 0.03, 0.05, 0.48)
	var halo_color := region_color.darkened(0.08)
	halo_color.a = 0.22
	var border_color := region_color
	border_color.a = 0.86
	var highlight_color := region_color.lightened(0.32)
	highlight_color.a = 0.56

	_append_region_band(surface_tool, region_polygon, half_width * 1.9, -half_width * 0.95, region_height, shadow_color)
	_append_region_band(surface_tool, region_polygon, half_width * 1.3, -half_width * 0.12, region_height + 0.25, halo_color)
	_append_region_band(surface_tool, region_polygon, half_width * 0.64, -half_width * 0.38, region_height + 0.48, border_color)
	_append_region_band(surface_tool, region_polygon, half_width * 0.24, 0.0, region_height + 0.7, highlight_color)


func _append_triangle(surface_tool: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, height: float, color: Color) -> void:
	surface_tool.set_color(color)
	surface_tool.add_vertex(Vector3(a.x, height, a.y))
	surface_tool.set_color(color)
	surface_tool.add_vertex(Vector3(b.x, height, b.y))
	surface_tool.set_color(color)
	surface_tool.add_vertex(Vector3(c.x, height, c.y))


func _append_hyperlane_band(
	surface_tool: SurfaceTool,
	start_point: Vector3,
	end_point: Vector3,
	width: float,
	color: Color,
	height_offset: float
) -> void:
	var start_2d := Vector2(start_point.x, start_point.z)
	var end_2d := Vector2(end_point.x, end_point.z)
	var direction := end_2d - start_2d
	if direction.length_squared() <= 0.001:
		return

	var normal := Vector2(-direction.y, direction.x).normalized() * width * 0.5
	var start_left := Vector3(start_point.x + normal.x, start_point.y + height_offset, start_point.z + normal.y)
	var end_left := Vector3(end_point.x + normal.x, end_point.y + height_offset, end_point.z + normal.y)
	var end_right := Vector3(end_point.x - normal.x, end_point.y + height_offset, end_point.z - normal.y)
	var start_right := Vector3(start_point.x - normal.x, start_point.y + height_offset, start_point.z - normal.y)
	_append_quad(surface_tool, start_left, end_left, end_right, start_right, color)


func _append_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	surface_tool.set_color(color)
	surface_tool.add_vertex(a)
	surface_tool.set_color(color)
	surface_tool.add_vertex(b)
	surface_tool.set_color(color)
	surface_tool.add_vertex(c)
	surface_tool.set_color(color)
	surface_tool.add_vertex(a)
	surface_tool.set_color(color)
	surface_tool.add_vertex(c)
	surface_tool.set_color(color)
	surface_tool.add_vertex(d)


func _append_triangulated_polygon(surface_tool: SurfaceTool, polygon: PackedVector2Array, height: float, color: Color) -> void:
	var triangulated_indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	for triangle_index in range(0, triangulated_indices.size(), 3):
		for point_offset in range(3):
			var polygon_index: int = triangulated_indices[triangle_index + point_offset]
			var region_point: Vector2 = polygon[polygon_index]
			surface_tool.set_color(color)
			surface_tool.add_vertex(Vector3(region_point.x, height, region_point.y))


func _append_region_band(
	surface_tool: SurfaceTool,
	region_polygon: PackedVector2Array,
	outer_offset: float,
	inner_offset: float,
	region_height: float,
	color: Color
) -> void:
	var outer_polygon := _resolve_offset_polygon(region_polygon, outer_offset)
	if outer_polygon.size() < 3:
		return

	var inner_polygon := region_polygon if absf(inner_offset) <= 0.001 else _resolve_offset_polygon(region_polygon, inner_offset)
	if inner_polygon.size() < 3:
		_append_triangulated_polygon(surface_tool, outer_polygon, region_height, color)
		return

	var band_polygons: Array = Geometry2D.clip_polygons(outer_polygon, inner_polygon)
	if band_polygons.is_empty():
		_append_triangulated_polygon(surface_tool, outer_polygon, region_height, color)
		return

	for band_polygon_variant in band_polygons:
		var band_polygon: PackedVector2Array = _sanitize_polygon(band_polygon_variant)
		if band_polygon.size() < 3:
			continue
		_append_triangulated_polygon(surface_tool, band_polygon, region_height, color)


func _resolve_offset_polygon(region_polygon: PackedVector2Array, offset: float) -> PackedVector2Array:
	if absf(offset) <= 0.001:
		return _sanitize_polygon(region_polygon)

	var offset_results: Array = Geometry2D.offset_polygon(region_polygon, offset)
	if offset_results.is_empty():
		return PackedVector2Array()
	return _largest_polygon(offset_results)


func _largest_polygon(polygons: Array) -> PackedVector2Array:
	var largest_polygon := PackedVector2Array()
	var largest_area := -1.0
	for polygon_variant in polygons:
		var polygon: PackedVector2Array = _sanitize_polygon(polygon_variant)
		var polygon_area := absf(_polygon_area(polygon))
		if polygon_area <= largest_area:
			continue
		largest_area = polygon_area
		largest_polygon = polygon
	return largest_polygon


func _sanitize_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var sanitized := polygon
	if sanitized.size() >= 2 and sanitized[0].is_equal_approx(sanitized[sanitized.size() - 1]):
		sanitized.remove_at(sanitized.size() - 1)
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


func _build_glow_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _star_glow_shader
	material.set_shader_parameter("fresnel_power", 2.4)
	material.set_shader_parameter("glow_strength", 1.5)
	material.set_shader_parameter("pulse_strength", 0.06)
	material.set_shader_parameter("pulse_speed", 0.95)
	material.set_shader_parameter("center_fill", 0.22)
	return material


func _build_hyperlane_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.45
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_ownership_fill_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.38
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_ownership_border_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _get_ownership_blob_radius() -> float:
	return maxf(_host.min_system_distance * OWNERSHIP_BLOB_RADIUS_FACTOR, 42.0)


func _get_ownership_exclusion_radius() -> float:
	return maxf(_host.min_system_distance * OWNERSHIP_EXCLUSION_RADIUS_FACTOR, 28.0)


func _get_ownership_connector_radius() -> float:
	return maxf(_host.min_system_distance * OWNERSHIP_CONNECTOR_RADIUS_FACTOR, 18.0)


func _get_ownership_connection_distance() -> float:
	return maxf(_host.min_system_distance * OWNERSHIP_CONNECTION_DISTANCE_FACTOR, 180.0)


func _get_ownership_island_bridge_distance() -> float:
	return maxf(_get_ownership_connection_distance() * OWNERSHIP_ISLAND_BRIDGE_DISTANCE_FACTOR, _get_ownership_blob_radius() * 2.4)


func _get_ownership_border_half_width() -> float:
	return maxf(_host.min_system_distance * OWNERSHIP_BORDER_WIDTH_FACTOR, 9.0)


func _get_region_height(systems_for_empire: Array) -> float:
	if systems_for_empire.is_empty():
		return 0.0

	var total_height: float = 0.0
	for system_variant in systems_for_empire:
		var system_record: Dictionary = system_variant
		total_height += float(system_record["position"].y)
	return total_height / float(systems_for_empire.size())


func _get_star_offset(star_index: int, system_star_count: int, orbit_radius: float) -> Vector3:
	if system_star_count <= 1:
		return Vector3.ZERO

	if system_star_count == 2:
		var direction := -1.0 if star_index == 0 else 1.0
		return Vector3(direction * orbit_radius, 0.0, 0.0)

	var angle := float(star_index) * TAU / float(system_star_count)
	return Vector3(cos(angle) * orbit_radius, 0.0, sin(angle) * orbit_radius)


func _get_glow_color(base_color: Color, special_type: String) -> Color:
	if special_type == BLACK_HOLE_TYPE:
		return Color(0.28, 0.46, 1.0, 0.46)
	if special_type == NEUTRON_TYPE:
		return Color(0.72, 0.9, 1.0, 0.52)
	if special_type == O_CLASS_TYPE:
		return Color(0.7, 0.88, 1.0, 0.6)

	var glow_color := base_color
	glow_color.a = 0.34
	return glow_color
