extends Node3D
class_name GravityFieldMap

## Visual potential and 2D radiance transport share the existing system's XZ
## coordinates. No physics body is added, so command targets stay on y = 0.
const CASCADE_SHADER: Shader = preload("res://scene/StarSystem/design/RadianceCascade.gdshader")
const SURFACE_SHADER: Shader = preload("res://scene/StarSystem/design/GravitySurface.gdshader")
const BODY_SHADER: Shader = preload("res://scene/StarSystem/design/CleanBody.gdshader")
const MAX_BODIES := 32
var cascade_views: Array[SubViewport] = []
var surface: MeshInstance3D
var _bake_index := -1
var bake_complete := false
var _frame_pending := false
var body_records: Array[Dictionary] = []

static func body_position(body: Dictionary) -> Vector3:
	var radius := float(body.get("orbit_radius", 0.0))
	var angle := float(body.get("orbit_angle", 0.0))
	return Vector3(cos(angle) * radius, float(body.get("vertical_offset", 0.0)), sin(angle) * radius)

static func collect_bodies(details: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in details.get("stars", []):
		var black_hole := str(record.get("special_type", "")).to_lower() == "black hole" or str(record.get("kind", "")) == "black_hole" or str(record.get("star_class", "")) == "BH"
		result.append({"id": str(record.get("id", "")), "name": str(record.get("name", "Star")), "position": body_position(record), "radius": maxf(1.5, float(record.get("scale", 1.0)) * 2.7), "star": true, "black_hole": black_hole, "color": Color(0.98, 0.57, 0.25) if not black_hole else Color(0.80, 0.39, 0.68)})
	for record: Dictionary in details.get("orbitals", []):
		if str(record.get("type", "planet")) != "planet":
			continue
		result.append({"id": str(record.get("id", "")), "name": str(record.get("name", "World")), "position": body_position(record), "radius": maxf(0.55, float(record.get("size", 1.0)) * 0.8), "star": false, "black_hole": false, "color": Color(0.52, 0.82, 0.77)})
	return result

static func visual_position(body: Dictionary, records: Array[Dictionary]) -> Vector3:
	var position: Vector3 = body["position"]
	var h := -1.2
	for index in range(mini(records.size(), MAX_BODIES)):
		var well: Dictionary = records[index]
		var source: Vector3 = well["position"]
		var radius: float = well["radius"]
		var star: bool = well["star"]
		var soft := radius * (2.5 if star else 2.0)
		var depth := radius * (3.8 if star else 1.8)
		var distance_sq := Vector2(position.x - source.x, position.z - source.z).length_squared()
		h -= depth * soft / sqrt(distance_sq + soft * soft)
	# The visible marker nestles in its well. Real command coordinates remain
	# in the selectable context; only its projected selection anchor changes.
	return Vector3(position.x, h + float(body["radius"]) * 0.85, position.z)

func configure(details: Dictionary, extent: float) -> void:
	name = "GravityFieldMap"
	body_records = collect_bodies(details)
	var wells := PackedVector4Array()
	var emitters := PackedVector4Array()
	var colors := PackedVector4Array()
	for index in range(MAX_BODIES):
		if index < body_records.size():
			var body: Dictionary = body_records[index]
			var p: Vector3 = body["position"]
			var r: float = body["radius"]
			var star: bool = body["star"]
			var color: Color = body["color"]
			wells.append(Vector4(p.x, p.z, r * (2.5 if star else 2.0), r * (3.8 if star else 1.8)))
			emitters.append(Vector4(p.x, p.z, r, 1.0 if star else 0.0))
			colors.append(Vector4(color.r, color.g, color.b, 1.0))
		else:
			wells.append(Vector4.ZERO)
			emitters.append(Vector4.ZERO)
			colors.append(Vector4.ZERO)
	var count := mini(body_records.size(), MAX_BODIES)
	# Every body remains represented; the transport budget covers the first 32
	# (stars first). Unusual larger systems retain their selectable body markers.
	for body in body_records:
		_add_body(body)
	for level in range(4):
		var viewport := SubViewport.new()
		viewport.name = "RadianceCascade%d" % level
		viewport.size = Vector2i(128, 128)
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		add_child(viewport)
		var rect := ColorRect.new()
		rect.size = Vector2(128, 128)
		var material := ShaderMaterial.new()
		material.shader = CASCADE_SHADER
		material.set_shader_parameter("cascade_index", level)
		material.set_shader_parameter("body_count", count)
		material.set_shader_parameter("bodies", emitters)
		material.set_shader_parameter("body_colors", colors)
		material.set_shader_parameter("map_extent", extent)
		rect.material = material
		viewport.add_child(rect)
		cascade_views.append(viewport)
	for level in range(3):
		var material := cascade_views[level].get_child(0).material as ShaderMaterial
		material.set_shader_parameter("upper_cascade", cascade_views[level + 1].get_texture())
	surface = MeshInstance3D.new()
	surface.name = "PotentialSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * extent * 2.0
	plane.subdivide_width = 191
	plane.subdivide_depth = 191
	surface.mesh = plane
	surface.custom_aabb = AABB(Vector3(-extent, -extent, -extent), Vector3(extent * 2.0, extent * 2.0, extent * 2.0))
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("wells", wells)
	material.set_shader_parameter("well_count", count)
	material.set_shader_parameter("map_extent", extent)
	material.set_shader_parameter("radiance_cascade", cascade_views[0].get_texture())
	surface.material_override = material
	add_child(surface)
	_bake_index = 3
	# Far-to-near, one completed render per cascade. No work while idle.
	if DisplayServer.get_name() == "headless":
		bake_complete = true
		set_process(false)
	else:
		RenderingServer.frame_post_draw.connect(_after_draw)

func _process(_delta: float) -> void:
	if _bake_index >= 0 and not _frame_pending:
		cascade_views[_bake_index].render_target_update_mode = SubViewport.UPDATE_ONCE
		_frame_pending = true

func _after_draw() -> void:
	if not _frame_pending:
		return
	_frame_pending = false
	_bake_index -= 1
	if _bake_index < 0:
		bake_complete = true
		set_process(false)
		RenderingServer.frame_post_draw.disconnect(_after_draw)

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)

func _add_body(body: Dictionary) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Marker_%s" % str(body["id"])
	mesh.position = visual_position(body, body_records)
	var sphere := SphereMesh.new()
	sphere.radius = body["radius"]
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mesh.mesh = sphere
	var material := ShaderMaterial.new()
	material.shader = BODY_SHADER
	material.set_shader_parameter("tint", Color(0.005, 0.008, 0.014) if body["black_hole"] else body["color"])
	material.set_shader_parameter("emitter", body["star"] and not body["black_hole"])
	mesh.material_override = material
	add_child(mesh)
	var label := Label3D.new()
	label.text = str(body["name"]).to_upper()
	label.position = mesh.position + Vector3(0, float(body["radius"]) + 1.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 24
	label.pixel_size = 0.035
	label.modulate = Color(0.65, 0.79, 0.80)
	label.outline_size = 4
	add_child(label)
