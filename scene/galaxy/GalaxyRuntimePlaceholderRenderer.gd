extends RefCounted
class_name GalaxyRuntimePlaceholderRenderer

const STATION_BASE_RADIUS: float = 18.0
const FLEET_BASE_RADIUS: float = 28.0
const SHIP_BASE_RADIUS: float = 22.0
const RING_STEP: float = 6.0
const STATION_HEIGHT: float = 9.0
const FLEET_HEIGHT: float = 13.0
const SHIP_HEIGHT: float = 7.0
const SLOTS_PER_RING: int = 6

var _host: GalaxyMapView = null


func bind(host: GalaxyMapView) -> void:
	_host = host
	_apply_materials()


func unbind() -> void:
	_host = null


func render_runtime_placeholders() -> void:
	if _host == null:
		return

	var station_instances: Array[Dictionary] = []
	var fleet_instances: Array[Dictionary] = []
	var ship_instances: Array[Dictionary] = []

	for system_record in _host.system_records:
		var system_id: String = str(system_record.get("id", ""))
		if system_id.is_empty():
			continue
		var system_position: Vector3 = system_record.get("position", Vector3.ZERO)
		var fleet_ship_ids: Dictionary = {}
		var fleet_index: int = 0
		var station_index: int = 0
		var loose_ship_index: int = 0

		for fleet_id in SpaceManager.get_fleet_ids_in_system(system_id):
			var fleet: FleetRuntime = SpaceManager.get_fleet(fleet_id)
			if fleet == null:
				continue
			for ship_id in fleet.ship_ids:
				fleet_ship_ids[ship_id] = true

			var fleet_layout: Dictionary = _resolve_marker_layout(
				FLEET_BASE_RADIUS,
				fleet_index,
				system_position,
				fleet.fleet_id.hash(),
				FLEET_HEIGHT
			)
			fleet_instances.append({
				"position": fleet_layout.get("position", system_position),
				"yaw": float(fleet_layout.get("yaw", 0.0)),
				"scale": 1.0 + min(float(fleet.ship_ids.size()), 20.0) * 0.05,
				"color": _get_owner_color(fleet.owner_empire_id),
			})
			fleet_index += 1

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
				continue

			if not ship.fleet_id.is_empty() and fleet_ship_ids.has(ship.ship_id):
				continue

			var ship_layout: Dictionary = _resolve_marker_layout(
				SHIP_BASE_RADIUS,
				loose_ship_index,
				system_position,
				ship.ship_id.hash(),
				SHIP_HEIGHT
			)
			ship_instances.append({
				"position": ship_layout.get("position", system_position),
				"yaw": float(ship_layout.get("yaw", 0.0)),
				"scale": 1.0,
				"color": _get_owner_color(ship.owner_empire_id),
			})
			loose_ship_index += 1

	_render_multimesh(_host.station_markers, _build_station_mesh(), station_instances)
	_render_multimesh(_host.fleet_markers, _build_fleet_mesh(), fleet_instances)
	_render_multimesh(_host.ship_markers, _build_ship_mesh(), ship_instances)


func clear_runtime_placeholders() -> void:
	if _host == null:
		return
	_host.station_markers.multimesh = null
	_host.fleet_markers.multimesh = null
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
		var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value)
		multimesh.set_instance_transform(instance_index, Transform3D(basis, position))
		multimesh.set_instance_color(instance_index, instance.get("color", Color.WHITE))

	target.multimesh = multimesh


func _resolve_marker_layout(base_radius: float, index: int, origin: Vector3, seed_value: int, height: float) -> Dictionary:
	var ring_index: int = index / SLOTS_PER_RING
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


func _apply_materials() -> void:
	if _host == null:
		return
	var station_material: StandardMaterial3D = _build_material(0.52, 1.35)
	var fleet_material: StandardMaterial3D = _build_material(0.4, 1.6)
	var ship_material: StandardMaterial3D = _build_material(0.58, 1.0)
	_host.station_markers.material_override = station_material
	_host.fleet_markers.material_override = fleet_material
	_host.ship_markers.material_override = ship_material


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
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(5.8, 1.35, 5.8)
	return mesh


func _build_fleet_mesh() -> Mesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(3.2, 1.4, 8.4)
	return mesh


func _build_ship_mesh() -> Mesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(1.6, 0.7, 3.8)
	return mesh
