extends Node3D
class_name GravityFieldMap

## Visual potential and 2D radiance transport share the existing system's XZ
## coordinates. No physics body is added, so command targets stay on y = 0.
const CASCADE_SHADER: Shader = preload("res://scene/StarSystem/design/RadianceCascade.gdshader")
const SURFACE_SHADER: Shader = preload("res://scene/StarSystem/design/GravitySurface.gdshader")
const BODY_SHADER: Shader = preload("res://scene/StarSystem/design/CleanBody.gdshader")
const AURA_SHADER: Shader = preload("res://scene/StarSystem/design/StellarAura.gdshader")
const MAX_BODIES := 32
const ATLAS_SIZE := 256
const MAX_EXITS := 32
var cascade_views: Array[SubViewport] = []
var surface: MeshInstance3D
var _bake_index := -1
var bake_complete := false
var _frame_pending := false
var body_records: Array[Dictionary] = []
var exit_records: Array[Dictionary] = []

static func body_position(body: Dictionary) -> Vector3:
	var radius := float(body.get("orbit_radius", 0.0))
	var angle := float(body.get("orbit_angle", 0.0))
	return Vector3(cos(angle) * radius, float(body.get("vertical_offset", 0.0)), sin(angle) * radius)

static func collect_bodies(details: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in details.get("stars", []):
		var black_hole := str(record.get("special_type", "")).to_lower() == "black hole" or str(record.get("kind", "")) == "black_hole" or str(record.get("star_class", "")) == "BH"
		result.append({"id": str(record.get("id", "")), "name": str(record.get("name", "Star")), "position": body_position(record), "radius": maxf(1.8, float(record.get("scale", 1.0)) * 3.7), "star": true, "black_hole": black_hole, "color": _star_color(record) if not black_hole else Color(0.80, 0.39, 0.68), "source": record})
	for record: Dictionary in details.get("orbitals", []):
		if str(record.get("type", "planet")) != "planet":
			continue
		result.append({"id": str(record.get("id", "")), "name": str(record.get("name", "World")), "position": body_position(record), "radius": maxf(0.55, float(record.get("size", 1.0)) * 0.8), "star": false, "black_hole": false, "color": _planet_color(record), "source": record})
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

func configure(details: Dictionary, extent: float, bake_cascade_reference: bool = false) -> void:
	name = "GravityFieldMap"
	body_records = collect_bodies(details)
	exit_records = collect_exits(details, extent)
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
	# Retain the old cascade only for comparison/transport diagnostics.
	if bake_cascade_reference:
		for level in range(4):
			var viewport := SubViewport.new()
			viewport.name = "RadianceCascade%d" % level
			viewport.size = Vector2i(ATLAS_SIZE, ATLAS_SIZE)
			viewport.disable_3d = true
			viewport.transparent_bg = true
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
			add_child(viewport)
			var rect := ColorRect.new()
			rect.size = Vector2(ATLAS_SIZE, ATLAS_SIZE)
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
	plane.subdivide_width = 255
	plane.subdivide_depth = 255
	surface.mesh = plane
	surface.custom_aabb = AABB(Vector3(-extent, -extent, -extent), Vector3(extent * 2.0, extent * 2.0, extent * 2.0))
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	var exits := PackedVector4Array()
	for index in range(MAX_EXITS):
		if index < exit_records.size():
			var exit_record: Dictionary = exit_records[index]
			var point: Vector2 = exit_record["position"]
			exits.append(Vector4(point.x, point.y, exit_record["width"], exit_record["depth"]))
		else: exits.append(Vector4.ZERO)
	material.set_shader_parameter("exit_count", exit_records.size())
	material.set_shader_parameter("exits", exits)
	material.set_shader_parameter("wells", wells)
	material.set_shader_parameter("well_count", count)
	material.set_shader_parameter("map_extent", extent)
	material.set_shader_parameter("body_count", count)
	material.set_shader_parameter("bodies", emitters)
	material.set_shader_parameter("body_colors", colors)
	surface.material_override = material
	add_child(surface)
	for exit_record in exit_records: _add_exit_label(exit_record)
	_bake_index = 3
	# Far-to-near, one completed render per cascade. No work while idle.
	if not bake_cascade_reference or DisplayServer.get_name() == "headless":
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
	var source: Dictionary = body.get("source", {})
	material.set_shader_parameter("pattern_seed", float(absi(str(source.get("seed", body["id"])).hash()) % 10000) / 137.0)
	material.set_shader_parameter("body_kind", _planet_kind(source))
	var light_position := Vector3(0, 12, 0)
	var nearest := INF
	for star in body_records:
		if not star["star"] or star["black_hole"]:
			continue
		var position := visual_position(star, body_records)
		var distance := mesh.position.distance_squared_to(position)
		if distance < nearest and star["id"] != body["id"]:
			nearest = distance
			light_position = position
	material.set_shader_parameter("sun_position", to_global(light_position))
	mesh.material_override = material
	add_child(mesh)
	if body["star"]:
		_add_aura(mesh.position, float(body["radius"]) * 12.0, _aura_color(body["color"]), 1.0, str(body["id"]))
	else:
		_add_aura(mesh.position, float(body["radius"]) * 5.0, body["color"], 0.16, str(body["id"]))
	if body["black_hole"]:
		_add_ring(mesh, body)

	var label := Label3D.new()
	label.text = str(body["name"]).to_upper()
	label.position = mesh.position + Vector3(0, float(body["radius"]) + 1.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.pixel_size = 0.0175
	label.modulate = Color(0.65, 0.79, 0.80)
	label.outline_size = 4
	add_child(label)


static func _star_color(record: Dictionary) -> Color:
	match str(record.get("star_class", "G")):
		"O", "B", "Neutron": return Color(0.48, 0.73, 1.0)
		"A", "F": return Color(0.83, 0.89, 1.0)
		"M": return Color(1.0, 0.30, 0.12)
		"K": return Color(1.0, 0.56, 0.22)
		_: return Color(1.0, 0.83, 0.49)


static func _planet_kind(record: Dictionary) -> int:
	var source: Dictionary = record.get("metadata", {}) if record.get("metadata", {}) is Dictionary else {}
	var metadata: Dictionary = source.get("planet_visual", {}) if source.get("planet_visual", {}) is Dictionary else {}
	var kind := str(metadata.get("kind", record.get("planet_type", ""))).to_lower()
	if kind.is_empty():
		if float(record.get("size", 1.0)) >= 2.7: return 2
		if float(record.get("habitability", 0.0)) >= 0.45 or bool(record.get("is_colonizable", false)): return 0
		var color: Color = record.get("color", Color(0.6, 0.5, 0.4))
		return 3 if color.b > color.r * 1.2 else 1
	if kind in ["gas", "gas_giant", "gas_planet", "jovian"]: return 2
	if kind in ["ice", "frozen", "ice_world", "tundra"]: return 3
	if kind in ["lava", "molten", "lava_world", "volcanic"]: return 4
	if kind in ["desert", "barren", "dry_terran", "no_atmosphere", "rocky", "arid"]: return 1
	return 0


static func _planet_color(record: Dictionary) -> Color:
	var palette := [Color("83dfda"), Color("aebff4"), Color("b7a0ef"), Color("9edcff"), Color("e2a0e9")]
	var color: Color = palette[_planet_kind(record)]
	var seed_value := absi(str(record.get("seed", record.get("id", ""))).hash())
	return Color.from_hsv(fposmod(color.h + float(seed_value % 101 - 50) * 0.00035, 1.0), color.s, color.v)


static func collect_exits(details: Dictionary, extent: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in details.get("hyperlane_exits", []):
		if result.size() >= MAX_EXITS: break
		var direction: Vector2 = record.get("direction", Vector2.ZERO)
		if direction.length_squared() < 0.0001: continue
		direction = direction.normalized()
		# Compact support starts beyond the body area (extent / 1.6). Thus
		# lane wells never displace the existing body / selection anchors.
		result.append({"system_id": record["system_id"], "name": record.get("name", "Uncharted system"), "direction": direction, "position": direction * extent * 0.71, "width": extent * 0.065, "depth": extent * 0.065 * 0.85})
	return result


func exit_position(record: Dictionary) -> Vector3:
	var point: Vector2 = record["position"]
	var probe := {"position": Vector3(point.x, 0, point.y), "radius": 0.0}
	var height := visual_position(probe, body_records).y
	for other in exit_records:
		var q: Vector2 = (point - other["position"]) / float(other["width"])
		height -= float(other["depth"]) * pow(maxf(0, 1.0 - q.length_squared()), 3)
	return Vector3(point.x, height, point.y)


func _add_exit_label(record: Dictionary) -> void:
	_add_aura(exit_position(record), float(record["width"]) * 3.0, Color("62cfff"), 0.25, str(record["system_id"]))
	var label := Label3D.new()
	label.name = "Hyperlane_%s" % record["system_id"]
	label.text = "TO " + str(record["name"]).to_upper()
	label.position = exit_position(record) + Vector3(0, float(record["depth"]) + 2.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 44
	label.pixel_size = 0.020
	label.modulate = Color("9fe9ff")
	label.outline_size = 5
	add_child(label)


func _add_ring(marker: MeshInstance3D, body: Dictionary) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "AccretionRing" if body["black_hole"] else "PlanetRing"
	var torus := TorusMesh.new()
	var radius: float = body["radius"]
	torus.inner_radius = radius * 1.5
	torus.outer_radius = radius * 2.15
	torus.rings = 96
	torus.ring_segments = 12
	ring.mesh = torus
	ring.scale.y = 0.10
	ring.rotation_degrees.z = 24.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = body["color"] * (1.2 if body["black_hole"] else 0.45)
	ring.material_override = material
	marker.add_child(ring)


static func _aura_color(stellar_color: Color) -> Color:
	return stellar_color.lerp(Color(0.9, 0.28, 0.68), 0.65)


func _add_aura(point: Vector3, diameter: float, color: Color, strength: float, identity: String) -> void:
	var aura := MeshInstance3D.new()
	aura.name = "Aura_" + identity
	aura.position = point
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * diameter
	aura.mesh = quad
	# Billboarding can rotate the quad out of its untransformed bounds.
	aura.custom_aabb = AABB(Vector3.ONE * -diameter * 0.5, Vector3.ONE * diameter)
	var material := ShaderMaterial.new()
	material.shader = AURA_SHADER
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("phase", float(absi(identity.hash()) % 1000))
	aura.material_override = material
	add_child(aura)
