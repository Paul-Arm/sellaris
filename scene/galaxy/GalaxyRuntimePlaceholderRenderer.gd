extends RefCounted
class_name GalaxyRuntimePlaceholderRenderer

const STATION_BASE_RADIUS: float = 18.0
const RING_STEP: float = 6.0
const STATION_HEIGHT: float = 9.0
const FLEET_ICON_HEIGHT: float = 13.0
const SLOTS_PER_RING: int = 6
const SHIPS_PER_BAR: int = 100
const BAR_COLUMNS: int = 6
const BAR_SPACING_X: float = 6.0
const BAR_ROW_STEP: float = 2.2
const BAR_BASE_Y_OFFSET: float = 4.3
const FLEET_CIRCLE_RADIUS: float = 2.2
const FLEET_BAR_LENGTH: float = 4.4
const FLEET_BAR_THICKNESS: float = 0.5

var _host: Node = null


func bind(host: Node) -> void:
	_host = host
	_apply_materials()


func unbind() -> void:
	_host = null


func render_runtime_placeholders() -> void:
	if _host == null:
		return

	var station_instances: Array[Dictionary] = []
	var fleet_icon_instances: Array[Dictionary] = []
	var fleet_bar_instances: Array[Dictionary] = []

	for system_record in _host.system_records:
		var system_id: String = str(system_record.get("id", ""))
		if system_id.is_empty():
			continue
		if not _is_system_visible(system_id):
			continue
		var system_position: Vector3 = system_record.get("position", Vector3.ZERO)
		var station_index: int = 0
		var mobile_ship_summary: Dictionary = _summarize_mobile_ships_in_system(system_id)
		if not mobile_ship_summary.is_empty():
			var icon_center := system_position + Vector3(0.0, FLEET_ICON_HEIGHT, 0.0)
			var ship_count: int = int(mobile_ship_summary.get("ship_count", 0))
			var underscore_count: int = int(floor(float(ship_count) / float(SHIPS_PER_BAR)))
			var color := _get_owner_color(str(mobile_ship_summary.get("owner_empire_id", "")))
			fleet_icon_instances.append({
				"position": icon_center,
				"yaw": 0.0,
				"scale": 1.0,
				"color": color,
			})
			for bar_position in _build_bar_positions(icon_center, underscore_count):
				fleet_bar_instances.append({
					"position": bar_position,
					"yaw": 0.0,
					"scale": 1.0,
					"color": color,
				})

		for ship_id in SpaceManager.get_ship_ids_in_system(system_id):
			var ship: ShipRuntime = SpaceManager.get_ship(ship_id)
			if ship == null:
				continue
			if ship.is_stationary():
				var station_layout: Dictionary = _resolve_marker_layout(
					STATION_BASE_RADIUS,
					station_index,
					system_position,
					ship.ship_id.hash(),
					STATION_HEIGHT
				)
				station_instances.append({
					"position": station_layout.get("position", system_position),
					"yaw": float(station_layout.get("yaw", 0.0)),
					"scale": 1.0 + clampf(1.0 - ship.get_hull_ratio(), 0.0, 0.5),
					"color": _get_owner_color(ship.owner_empire_id),
				})
				station_index += 1

	_render_multimesh(_host.station_markers, _build_station_mesh(), station_instances)
	_render_multimesh(_host.fleet_markers, _build_fleet_mesh(), fleet_icon_instances)
	if _host.get("ship_markers") != null:
		_render_multimesh(_host.ship_markers, _build_bar_mesh(), fleet_bar_instances)


func clear_runtime_placeholders() -> void:
	if _host == null:
		return
	_host.station_markers.multimesh = null
	_host.fleet_markers.multimesh = null
	if _host.get("ship_markers") != null:
		_host.ship_markers.multimesh = null


func _render_multimesh(target: MultiMeshInstance3D, mesh: Mesh, instances: Array[Dictionary]) -> void:
	if target == null:
		return
	if instances.is_empty():
		target.multimesh = null
		return

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = instances.size()

	for instance_index in range(instances.size()):
		var instance: Dictionary = instances[instance_index]
		var scale_value: float = float(instance.get("scale", 1.0))
		var yaw: float = float(instance.get("yaw", 0.0))
		var position: Vector3 = instance.get("position", Vector3.ZERO)
		var instance_basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value)
		multimesh.set_instance_transform(instance_index, Transform3D(instance_basis, position))
		multimesh.set_instance_color(instance_index, instance.get("color", Color.WHITE))

	target.multimesh = multimesh


func _resolve_marker_layout(base_radius: float, index: int, origin: Vector3, seed_value: int, height: float) -> Dictionary:
	var ring_index: int = int(floor(float(index) / float(SLOTS_PER_RING)))
	var slot_index: int = index % SLOTS_PER_RING
	var ring_slot_count: int = SLOTS_PER_RING + ring_index * 2
	var seed_angle: float = float(abs(seed_value) % 3600) / 3600.0 * TAU
	var angle: float = seed_angle + float(slot_index) * TAU / float(maxi(ring_slot_count, 1))
	var radius: float = base_radius + float(ring_index) * RING_STEP
	var position: Vector3 = origin + Vector3(cos(angle) * radius, height + float(ring_index) * 0.6, sin(angle) * radius)
	return {
		"position": position,
		"yaw": -angle + PI * 0.5,
	}


func _get_owner_color(owner_empire_id: String) -> Color:
	if _host != null and _host.empires_by_id.has(owner_empire_id):
		return _host.empires_by_id[owner_empire_id].get("color", Color.WHITE)
	return Color(0.82, 0.88, 1.0, 1.0)


func _is_system_visible(system_id: String) -> bool:
	if system_id.is_empty():
		return false
	if _host != null and _host.has_method("is_system_visible_on_map"):
		return bool(_host.is_system_visible_on_map(system_id))
	return true


func _apply_materials() -> void:
	if _host == null:
		return
	var station_material: StandardMaterial3D = _build_material(0.52, 1.35)
	var fleet_material: StandardMaterial3D = _build_material(0.95, 1.25)
	var bar_material: StandardMaterial3D = _build_material(0.92, 0.95)
	_host.station_markers.material_override = station_material
	_host.fleet_markers.material_override = fleet_material
	_host.fleet_markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _host.get("ship_markers") != null:
		_host.ship_markers.material_override = bar_material
		_host.ship_markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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


func _build_station_mesh() -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_extent := 3.1
	var column_height := 1.6
	var wing_span := 5.0
	var wing_height := 0.55
	var color := Color.WHITE
	_append_box(surface_tool, Vector3(0.0, 0.0, 0.0), Vector3(1.5, column_height, 1.5), color)
	_append_box(surface_tool, Vector3(0.0, 0.0, 0.0), Vector3(wing_span, wing_height, 1.2), color)
	_append_box(surface_tool, Vector3(0.0, 0.0, 0.0), Vector3(1.2, wing_height, wing_span), color)
	_append_box(surface_tool, Vector3(0.0, column_height * 0.75, 0.0), Vector3(half_extent, 0.35, half_extent), color)
	return surface_tool.commit()


func _build_fleet_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = FLEET_CIRCLE_RADIUS
	mesh.height = FLEET_CIRCLE_RADIUS * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


func _build_bar_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(FLEET_BAR_LENGTH, FLEET_BAR_THICKNESS, FLEET_BAR_THICKNESS)
	return mesh


func _summarize_mobile_ships_in_system(system_id: String) -> Dictionary:
	var ship_count: int = 0
	var owner_ship_counts: Dictionary = {}

	for ship_id in SpaceManager.get_ship_ids_in_system(system_id):
		var ship: ShipRuntime = SpaceManager.get_ship(ship_id)
		if ship == null or ship.is_stationary():
			continue
		ship_count += 1
		owner_ship_counts[ship.owner_empire_id] = int(owner_ship_counts.get(ship.owner_empire_id, 0)) + 1

	if ship_count <= 0:
		return {}

	var dominant_owner_id: String = ""
	var dominant_count: int = -1
	var is_tied: bool = false
	for owner_id_variant in owner_ship_counts.keys():
		var owner_id: String = str(owner_id_variant)
		var owner_count: int = int(owner_ship_counts.get(owner_id_variant, 0))
		if owner_count > dominant_count:
			dominant_owner_id = owner_id
			dominant_count = owner_count
			is_tied = false
		elif owner_count == dominant_count:
			is_tied = true

	return {
		"ship_count": ship_count,
		"owner_empire_id": "" if is_tied else dominant_owner_id,
	}


func _build_bar_positions(icon_center: Vector3, underscore_count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for bar_index in range(underscore_count):
		var row_index: int = int(floor(float(bar_index) / float(BAR_COLUMNS)))
		var column_index: int = bar_index % BAR_COLUMNS
		var row_count: int = mini(BAR_COLUMNS, underscore_count - row_index * BAR_COLUMNS)
		var x_offset: float = (float(column_index) - float(row_count - 1) * 0.5) * BAR_SPACING_X
		positions.append(icon_center + Vector3(
			x_offset,
			-BAR_BASE_Y_OFFSET - float(row_index) * BAR_ROW_STEP,
			0.0
		))
	return positions


func _append_box(surface_tool: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var half := size * 0.5
	var vertices := [
		center + Vector3(-half.x, -half.y, -half.z),
		center + Vector3(half.x, -half.y, -half.z),
		center + Vector3(half.x, half.y, -half.z),
		center + Vector3(-half.x, half.y, -half.z),
		center + Vector3(-half.x, -half.y, half.z),
		center + Vector3(half.x, -half.y, half.z),
		center + Vector3(half.x, half.y, half.z),
		center + Vector3(-half.x, half.y, half.z),
	]
	var faces := [
		[0, 1, 2, 3],
		[5, 4, 7, 6],
		[4, 0, 3, 7],
		[1, 5, 6, 2],
		[3, 2, 6, 7],
		[4, 5, 1, 0],
	]
	for face in faces:
		_append_quad(
			surface_tool,
			vertices[face[0]],
			vertices[face[1]],
			vertices[face[2]],
			vertices[face[3]],
			color
		)


func _append_triangle_prism(
	surface_tool: SurfaceTool,
	base_points: Array[Vector3],
	height: float,
	color: Color
) -> void:
	if base_points.size() != 3:
		return
	var top_points: Array[Vector3] = []
	for point_variant in base_points:
		var point: Vector3 = point_variant
		top_points.append(point + Vector3(0.0, height, 0.0))
	_append_triangle(surface_tool, top_points[0], top_points[1], top_points[2], color)
	_append_triangle(surface_tool, base_points[2], base_points[1], base_points[0], color)
	for edge_index in range(3):
		var next_index: int = (edge_index + 1) % 3
		_append_quad(
			surface_tool,
			base_points[edge_index],
			base_points[next_index],
			top_points[next_index],
			top_points[edge_index],
			color
		)


func _append_triangle(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface_tool.set_color(color)
	surface_tool.add_vertex(a)
	surface_tool.set_color(color)
	surface_tool.add_vertex(b)
	surface_tool.set_color(color)
	surface_tool.add_vertex(c)


func _append_quad(surface_tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_append_triangle(surface_tool, a, b, c, color)
	_append_triangle(surface_tool, a, c, d, color)
