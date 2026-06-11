extends RefCounted
class_name DefaultShipSet

## Procedural low-poly ship/station meshes for the default ship set.
## All meshes are built from a handful of boxes via SurfaceTool, use vertex
## colors in grayscale-plus-accent so MultiMesh instance colors tint them per
## owner, and face +X so a yaw of atan2(-v.z, v.x) points them along velocity.
## Visual fidelity is intentionally simple — these are MultiMesh-instanced for
## large fleets, one draw call per model type.

const SET_ID := "default"

const COLOR_HULL := Color(0.82, 0.86, 0.9, 1.0)
const COLOR_HULL_DARK := Color(0.55, 0.6, 0.66, 1.0)
const COLOR_ACCENT := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_ENGINE := Color(0.55, 0.85, 1.0, 1.0)
const COLOR_FRAME := Color(0.62, 0.66, 0.7, 1.0)


static func build_mesh(visual_key: String) -> Mesh:
	match visual_key:
		"corvette":
			return _build_corvette_mesh()
		"science":
			return _build_science_mesh()
		"builder":
			return _build_builder_mesh()
		"collector_station":
			return _build_collector_station_mesh()
		"stellar_station":
			return _build_stellar_station_mesh()
		"station":
			return _build_station_mesh()
		_:
			return _build_generic_ship_mesh()


static func _build_corvette_mesh() -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Hull spine with a narrower nose and swept wings.
	_append_box(surface_tool, Vector3(-0.1, 0.0, 0.0), Vector3(1.6, 0.36, 0.52), COLOR_HULL)
	_append_box(surface_tool, Vector3(0.95, 0.0, 0.0), Vector3(0.7, 0.26, 0.32), COLOR_ACCENT)
	_append_box(surface_tool, Vector3(-0.35, -0.02, 0.0), Vector3(0.72, 0.1, 1.9), COLOR_HULL_DARK)
	_append_box(surface_tool, Vector3(-0.2, 0.22, 0.0), Vector3(0.5, 0.18, 0.3), COLOR_HULL_DARK)
	_append_box(surface_tool, Vector3(-0.95, 0.0, 0.16), Vector3(0.3, 0.18, 0.18), COLOR_ENGINE)
	_append_box(surface_tool, Vector3(-0.95, 0.0, -0.16), Vector3(0.3, 0.18, 0.18), COLOR_ENGINE)
	return surface_tool.commit()


static func _build_science_mesh() -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Slim hull with a forward sensor dish and a long instrument boom.
	_append_box(surface_tool, Vector3(-0.15, 0.0, 0.0), Vector3(1.7, 0.3, 0.42), COLOR_HULL)
	_append_box(surface_tool, Vector3(0.95, 0.0, 0.0), Vector3(0.08, 1.05, 1.05), COLOR_ACCENT)
	_append_box(surface_tool, Vector3(0.55, 0.0, 0.0), Vector3(0.7, 0.14, 0.14), COLOR_FRAME)
	_append_box(surface_tool, Vector3(-0.4, 0.3, 0.0), Vector3(0.9, 0.08, 0.08), COLOR_FRAME)
	_append_box(surface_tool, Vector3(-1.05, 0.0, 0.0), Vector3(0.28, 0.2, 0.2), COLOR_ENGINE)
	return surface_tool.commit()


static func _build_builder_mesh() -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Boxy industrial hull with side cargo pods and a forward crane arm.
	_append_box(surface_tool, Vector3(-0.2, 0.0, 0.0), Vector3(1.3, 0.6, 0.8), COLOR_HULL)
	_append_box(surface_tool, Vector3(-0.25, 0.0, 0.62), Vector3(0.9, 0.42, 0.34), COLOR_HULL_DARK)
	_append_box(surface_tool, Vector3(-0.25, 0.0, -0.62), Vector3(0.9, 0.42, 0.34), COLOR_HULL_DARK)
	_append_box(surface_tool, Vector3(0.85, 0.12, 0.0), Vector3(1.0, 0.12, 0.12), COLOR_FRAME)
	_append_box(surface_tool, Vector3(1.3, 0.0, 0.0), Vector3(0.12, 0.36, 0.12), COLOR_ACCENT)
	_append_box(surface_tool, Vector3(-0.95, 0.0, 0.0), Vector3(0.3, 0.26, 0.26), COLOR_ENGINE)
	return surface_tool.commit()


static func _build_generic_ship_mesh() -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_box(surface_tool, Vector3(-0.1, 0.0, 0.0), Vector3(1.7, 0.3, 0.7), COLOR_HULL)
	_append_box(surface_tool, Vector3(0.85, 0.0, 0.0), Vector3(0.5, 0.22, 0.4), COLOR_ACCENT)
	_append_box(surface_tool, Vector3(-0.9, 0.0, 0.0), Vector3(0.26, 0.2, 0.34), COLOR_ENGINE)
	return surface_tool.commit()


static func _build_station_mesh() -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Central column with cross arms and habitat pads.
	_append_box(surface_tool, Vector3(0.0, 0.0, 0.0), Vector3(0.9, 1.5, 0.9), COLOR_HULL)
	_append_box(surface_tool, Vector3(0.0, 0.18, 0.0), Vector3(2.9, 0.3, 0.6), COLOR_HULL_DARK)
	_append_box(surface_tool, Vector3(0.0, 0.18, 0.0), Vector3(0.6, 0.3, 2.9), COLOR_HULL_DARK)
	_append_box(surface_tool, Vector3(1.45, 0.18, 0.0), Vector3(0.45, 0.55, 0.9), COLOR_FRAME)
	_append_box(surface_tool, Vector3(-1.45, 0.18, 0.0), Vector3(0.45, 0.55, 0.9), COLOR_FRAME)
	_append_box(surface_tool, Vector3(0.0, 0.86, 0.0), Vector3(1.3, 0.18, 1.3), COLOR_ACCENT)
	return surface_tool.commit()


static func _build_stellar_station_mesh() -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Larger double-deck variant of the station.
	_append_box(surface_tool, Vector3(0.0, 0.0, 0.0), Vector3(1.1, 1.9, 1.1), COLOR_HULL)
	_append_box(surface_tool, Vector3(0.0, -0.3, 0.0), Vector3(3.4, 0.28, 0.7), COLOR_HULL_DARK)
	_append_box(surface_tool, Vector3(0.0, -0.3, 0.0), Vector3(0.7, 0.28, 3.4), COLOR_HULL_DARK)
	_append_box(surface_tool, Vector3(0.0, 0.55, 0.0), Vector3(2.4, 0.24, 0.6), COLOR_FRAME)
	_append_box(surface_tool, Vector3(0.0, 0.55, 0.0), Vector3(0.6, 0.24, 2.4), COLOR_FRAME)
	_append_box(surface_tool, Vector3(0.0, 1.1, 0.0), Vector3(1.5, 0.2, 1.5), COLOR_ACCENT)
	return surface_tool.commit()


static func _build_collector_station_mesh() -> Mesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Compact core with three long collector booms and end pods.
	_append_box(surface_tool, Vector3(0.0, 0.0, 0.0), Vector3(0.9, 0.9, 0.9), COLOR_HULL)
	for boom_index in range(3):
		var angle := float(boom_index) * TAU / 3.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var boom_center := direction * 1.15
		_append_rotated_box(surface_tool, boom_center, Vector3(1.7, 0.14, 0.14), angle, COLOR_FRAME)
		_append_box(surface_tool, direction * 2.0, Vector3(0.4, 0.4, 0.4), COLOR_ACCENT)
	_append_box(surface_tool, Vector3(0.0, 0.62, 0.0), Vector3(0.5, 0.34, 0.5), COLOR_ENGINE)
	return surface_tool.commit()


static func _append_box(surface_tool: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	_append_rotated_box(surface_tool, center, size, 0.0, color)


static func _append_rotated_box(surface_tool: SurfaceTool, center: Vector3, size: Vector3, yaw: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var half := size * 0.5
	var corners: Array[Vector3] = []
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				corners.append(center + basis * Vector3(half.x * x_sign, half.y * y_sign, half.z * z_sign))
	# Corner order: index bit 2 = +x, bit 1 = +y, bit 0 = +z.
	var faces := [
		[0, 1, 3, 2], # -x
		[4, 6, 7, 5], # +x
		[0, 4, 5, 1], # -y
		[2, 3, 7, 6], # +y
		[0, 2, 6, 4], # -z
		[1, 5, 7, 3], # +z
	]
	for face in faces:
		for triangle_indices in [[0, 1, 2], [0, 2, 3]]:
			for triangle_index in triangle_indices:
				surface_tool.set_color(color)
				surface_tool.add_vertex(corners[face[triangle_index]])
