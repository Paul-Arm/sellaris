extends RefCounted
class_name ObservatoryShipSet

## Faceted expedition fleet. Ships face +X, matching movement yaw. Two cached
## surfaces per model: lit alloy hulls and unshaded engine/window illumination.
const SET_ID := "observatory"
const HULL := Color(0.64, 0.73, 0.77)
const FRAME := Color(0.13, 0.21, 0.26)
const TRIM := Color(0.83, 0.72, 0.47)
const LIGHT := Color(0.42, 0.95, 0.88)

static func build_mesh(key: String) -> Mesh:
	var hull := SurfaceTool.new()
	var lights := SurfaceTool.new()
	hull.begin(Mesh.PRIMITIVE_TRIANGLES)
	lights.begin(Mesh.PRIMITIVE_TRIANGLES)
	if key in ["station", "stellar_station", "collector_station"]:
		_station(hull, lights, key)
	else:
		_ship(hull, lights, key)
	hull.generate_normals()
	var alloy := StandardMaterial3D.new()
	alloy.vertex_color_use_as_albedo = true
	alloy.metallic = 0.65
	alloy.roughness = 0.36
	hull.set_material(alloy)
	var mesh := hull.commit()
	lights.generate_normals()
	var emission := StandardMaterial3D.new()
	emission.vertex_color_use_as_albedo = true
	emission.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emission.albedo_color = Color(1.5, 1.5, 1.5)
	lights.set_material(emission)
	lights.commit(mesh)
	return mesh

static func _ship(h: SurfaceTool, e: SurfaceTool, key: String) -> void:
	var length_factor := 1.0
	var width_factor := 1.0
	match key:
		"destroyer": length_factor = 1.3; width_factor = 1.2
		"cruiser": length_factor = 1.65; width_factor = 1.5
		"battleship": length_factor = 2.0; width_factor = 1.8
		"science": length_factor = 1.15; width_factor = 0.7
		"builder": length_factor = 0.9; width_factor = 1.35
	# Diamond keel with a sharp prow and layered upper armor.
	_hull(h, Vector3.ZERO, length_factor * 2.6, width_factor * 0.72, 0.40, HULL)
	_hull(h, Vector3(-0.22, 0.27, 0), length_factor * 1.3, width_factor * 0.46, 0.20, FRAME)
	_box(e, Vector3(0.06, 0.38, 0), Vector3(0.32, 0.035, 0.22), LIGHT)
	for sign_value in [-1.0, 1.0]:
		var z: float = sign_value * width_factor * 0.64
		_hull(h, Vector3(-0.44, -0.03, z), length_factor * 1.22, 0.28, 0.26, FRAME)
		_box(h, Vector3(-0.34, 0.01, z * 0.55), Vector3(0.35, 0.09, absf(z)), TRIM)
		_box(e, Vector3(-0.44 - length_factor * 0.61, -0.025, z), Vector3(0.045, 0.13, 0.14), LIGHT)
		_box(h, Vector3(-0.5, 0.10, z), Vector3(0.28, 0.04, 0.20), HULL)
	if key == "science":
		_ring(h, Vector3(0.55, 0.50, 0), 0.42, 0.06, 0.045, TRIM)
		_box(h, Vector3(0.55, 0.3, 0), Vector3(0.06, 0.4, 0.06), FRAME)
		_box(e, Vector3(0.55, 0.53, 0), Vector3(0.08, 0.06, 0.08), LIGHT)
	elif key == "builder":
		for sign_value in [-1.0, 1.0]:
			_box(h, Vector3(0.9, 0.04, sign_value * 0.5), Vector3(1.0, 0.09, 0.09), TRIM)
			for i in range(3):
				_box(h, Vector3(-0.65 + i * 0.33, 0.30, sign_value * 0.54), Vector3(0.27, 0.32, 0.28), HULL)
	else:
		var batteries := 1 if key in ["corvette", "ship"] else 2 if key == "destroyer" else 3
		for i in range(batteries):
			for sign_value in [-1.0, 1.0]:
				var mount := Vector3(0.5 - i * 0.52, 0.28, sign_value * width_factor * 0.23)
				_box(h, mount, Vector3(0.22, 0.16, 0.20), FRAME)
				_box(h, mount + Vector3(0.2, 0.06, 0), Vector3(0.36, 0.04, 0.045), TRIM)

static func _station(h: SurfaceTool, e: SurfaceTool, key: String) -> void:
	var radius := 1.8 if key == "stellar_station" else 1.25
	_hull(h, Vector3.ZERO, 1.2, 0.8, 1.4, HULL)
	_ring(h, Vector3.ZERO, radius, 0.18, 0.16, FRAME)
	_ring(e, Vector3(0, 0.10, 0), radius, 0.025, 0.025, LIGHT)
	var count := 3 if key == "collector_station" else 6
	for i in range(count):
		var angle := TAU * i / float(count)
		var direction := Vector3(cos(angle), 0, sin(angle))
		DefaultShipSet._append_rotated_box(h, direction * radius * 0.5, Vector3(radius, 0.13, 0.15), -angle, TRIM)
		_box(h, direction * radius, Vector3(0.40, 0.48, 0.40), HULL)
		_box(e, direction * radius + Vector3(0, 0.26, 0), Vector3(0.18, 0.035, 0.18), LIGHT)
	if key == "stellar_station":
		_ring(h, Vector3(0, 0.65, 0), 1.0, 0.14, 0.12, TRIM)
	elif key == "collector_station":
		for i in range(3):
			var a := TAU * i / 3.0
			var tip := Vector3(cos(a), 0, sin(a)) * 2.0
			DefaultShipSet._append_rotated_box(h, tip, Vector3(0.8, 0.08, 0.65), -a, FRAME)

static func _box(st: SurfaceTool, center: Vector3, dimensions: Vector3, color: Color) -> void:
	DefaultShipSet._append_box(st, center, dimensions, color)

static func _hull(st: SurfaceTool, center: Vector3, length: float, width: float, height: float, color: Color) -> void:
	var outline := [Vector2(length * 0.5, 0), Vector2(length * 0.12, -width * 0.5), Vector2(-length * 0.5, -width * 0.36), Vector2(-length * 0.5, width * 0.36), Vector2(length * 0.12, width * 0.5)]
	var top := center + Vector3(0, height * 0.5, 0)
	var bottom := center - Vector3(0, height * 0.5, 0)
	for i in range(outline.size()):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var va := center + Vector3(a.x, 0, a.y)
		var vb := center + Vector3(b.x, 0, b.y)
		_triangle(st, top, va, vb, color)
		_triangle(st, bottom, vb, va, color.darkened(0.18))

static func _ring(st: SurfaceTool, center: Vector3, radius: float, width: float, height: float, color: Color) -> void:
	# Segmented architecture deliberately reads as individual structural modules.
	for i in range(32):
		var angle := TAU * i / 32.0
		var pos := center + Vector3(cos(angle), 0, sin(angle)) * radius
		DefaultShipSet._append_rotated_box(st, pos, Vector3(radius * TAU / 32.0 * 0.94, height, width), -angle + PI * 0.5, color)

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex: Vector3 in [a, b, c]:
		st.set_color(color)
		st.add_vertex(vertex)
