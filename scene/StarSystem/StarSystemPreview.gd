extends Node3D
class_name StarSystemPreview

const ORBITAL_TYPE_PLANET := "planet"
const ORBITAL_TYPE_ASTEROID_BELT := "asteroid_belt"
const ORBITAL_TYPE_STRUCTURE := "structure"
const ORBITAL_TYPE_RUIN := "ruin"
const SPECIAL_TYPE_BLACK_HOLE := "Black hole"
const SPECIAL_TYPE_NEUTRON := "Neutron star"
const SPECIAL_TYPE_O_CLASS := "O class star"
const ORBIT_SEGMENT_COUNT := 80

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var pivot: Node3D = $Pivot
@onready var orbit_lines: Node3D = $Pivot/OrbitLines
@onready var bodies: Node3D = $Pivot/Bodies
@onready var effects: Node3D = $Pivot/Effects

var _has_content: bool = false


func _ready() -> void:
	clear_preview()
	_set_camera_distance(92.0)


func set_system_details(system_details: Dictionary) -> void:
	_clear_preview_nodes()
	if system_details.is_empty():
		_has_content = false
		_set_camera_distance(92.0)
		return

	var stars: Array = system_details.get("stars", [])
	var orbitals: Array = system_details.get("orbitals", [])
	var max_radius := 22.0

	for star_variant in stars:
		var star: Dictionary = star_variant
		var star_position := _get_orbit_position(star)
		max_radius = maxf(max_radius, star_position.length() + float(star.get("scale", 1.0)) * 8.0)
		_build_star_visual(star, star_position)

	for orbital_variant in orbitals:
		var orbital: Dictionary = orbital_variant
		var orbital_radius: float = float(orbital.get("orbit_radius", 0.0))
		var orbital_position := _get_orbit_position(orbital)
		max_radius = maxf(max_radius, orbital_radius + float(orbital.get("size", 1.0)) * 7.0 + float(orbital.get("orbit_width", 0.0)))
		_build_orbit_ring(orbital_radius, float(orbital.get("vertical_offset", 0.0)), _get_orbit_color(orbital))
		_build_orbital_visual(orbital, orbital_position)

	_set_camera_distance(max_radius + 24.0)
	_has_content = true


func clear_preview() -> void:
	_clear_preview_nodes()
	_has_content = false
	_set_camera_distance(92.0)


func forward_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.push_input(event, true)


func _clear_preview_nodes() -> void:
	for container in [orbit_lines, bodies, effects]:
		for child in container.get_children():
			child.free()
	pivot.rotation = Vector3(-0.28, 0.0, 0.0)


func _build_star_visual(star: Dictionary, star_position: Vector3) -> void:
	var star_scale: float = float(star.get("scale", 1.0))
	var star_color: Color = star.get("color", Color(1.0, 0.9, 0.55, 1.0))
	var special_type: String = str(star.get("special_type", "none"))

	var star_root := Node3D.new()
	star_root.position = star_position
	bodies.add_child(star_root)

	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 2.2 * star_scale
	core_mesh.height = core_mesh.radius * 2.0
	core_mesh.radial_segments = 22
	core_mesh.rings = 12
	core.mesh = core_mesh
	core.material_override = _build_lit_material(star_color, star_color, 1.8, 0.2, 0.0)
	star_root.add_child(core)

	var glow := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 3.6 * star_scale
	glow_mesh.height = glow_mesh.radius * 2.0
	glow_mesh.radial_segments = 18
	glow_mesh.rings = 10
	glow.mesh = glow_mesh
	glow.material_override = _build_unshaded_material(_get_star_glow_color(star_color, special_type))
	effects.add_child(glow)
	glow.position = star_position

	if special_type == SPECIAL_TYPE_BLACK_HOLE:
		core.material_override = _build_lit_material(Color(0.08, 0.09, 0.12, 1.0), Color(0.06, 0.1, 0.18, 1.0), 0.65, 0.3, 0.9)
		_build_black_hole_disk(star_position, star_scale)


func _build_black_hole_disk(star_position: Vector3, star_scale: float) -> void:
	var disk := MultiMeshInstance3D.new()
	var disk_mesh := SphereMesh.new()
	disk_mesh.radius = 0.32
	disk_mesh.height = 0.64
	disk_mesh.radial_segments = 8
	disk_mesh.rings = 4
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = disk_mesh
	multimesh.instance_count = 44

	var rng := RandomNumberGenerator.new()
	rng.seed = int(star_position.length() * 1000.0) + 17
	for instance_index in range(multimesh.instance_count):
		var angle: float = float(instance_index) * TAU / float(multimesh.instance_count) + rng.randf_range(-0.09, 0.09)
		var radius: float = 4.8 * star_scale + rng.randf_range(-0.9, 1.1)
		var local_position := Vector3(cos(angle) * radius, rng.randf_range(-0.18, 0.18), sin(angle) * radius)
		var basis := Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.25))
		multimesh.set_instance_transform(instance_index, Transform3D(basis, local_position))

	disk.multimesh = multimesh
	disk.material_override = _build_lit_material(Color(0.38, 0.52, 0.98, 0.85), Color(0.3, 0.44, 1.0, 1.0), 1.5, 0.45, 0.1)
	var disk_root := Node3D.new()
	disk_root.position = star_position
	disk_root.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	disk_root.add_child(disk)
	effects.add_child(disk_root)


func _build_orbital_visual(orbital: Dictionary, orbital_position: Vector3) -> void:
	var orbital_type: String = str(orbital.get("type", ORBITAL_TYPE_PLANET))
	match orbital_type:
		ORBITAL_TYPE_ASTEROID_BELT:
			_build_asteroid_belt(orbital)
		ORBITAL_TYPE_STRUCTURE:
			_build_structure(orbital, orbital_position)
		ORBITAL_TYPE_RUIN:
			_build_ruin(orbital, orbital_position)
		_:
			_build_planet(orbital, orbital_position)


func _build_planet(orbital: Dictionary, orbital_position: Vector3) -> void:
	var planet := MeshInstance3D.new()
	var planet_mesh := SphereMesh.new()
	var size: float = float(orbital.get("size", 1.0))
	planet_mesh.radius = size
	planet_mesh.height = size * 2.0
	planet_mesh.radial_segments = 18
	planet_mesh.rings = 10
	planet.mesh = planet_mesh

	var base_color: Color = orbital.get("color", Color(0.58, 0.68, 0.94, 1.0))
	var emission_color := base_color.darkened(0.18)
	if bool(orbital.get("is_colonizable", false)):
		emission_color = emission_color.lerp(Color(0.3, 0.72, 0.36, 1.0), 0.4)
	planet.material_override = _build_lit_material(base_color, emission_color, 0.45, 0.85, 0.0)
	planet.position = orbital_position
	bodies.add_child(planet)


func _build_structure(orbital: Dictionary, orbital_position: Vector3) -> void:
	var structure := MeshInstance3D.new()
	var box := BoxMesh.new()
	var size: float = float(orbital.get("size", 1.0))
	box.size = Vector3.ONE * size * 2.1
	structure.mesh = box
	structure.material_override = _build_lit_material(
		orbital.get("color", Color(0.42, 0.8, 1.0, 1.0)),
		Color(0.32, 0.78, 1.0, 1.0),
		0.7,
		0.25,
		0.1
	)
	structure.position = orbital_position
	structure.rotation = Vector3(0.3, 0.75, 0.2)
	bodies.add_child(structure)


func _build_ruin(orbital: Dictionary, orbital_position: Vector3) -> void:
	var ruin_root := Node3D.new()
	ruin_root.position = orbital_position
	bodies.add_child(ruin_root)

	for part_index in range(3):
		var fragment := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size: float = float(orbital.get("size", 1.0))
		box.size = Vector3.ONE * size * (1.0 - float(part_index) * 0.18)
		fragment.mesh = box
		fragment.material_override = _build_lit_material(
			orbital.get("color", Color(0.72, 0.73, 0.78, 1.0)),
			Color(0.18, 0.22, 0.28, 1.0),
			0.22,
			0.95,
			0.0
		)
		fragment.position = Vector3(
			0.35 * float(part_index),
			0.16 * float(part_index),
			-0.28 * float(part_index)
		)
		fragment.rotation = Vector3(0.2 * float(part_index), 0.55 * float(part_index), 0.16 * float(part_index))
		ruin_root.add_child(fragment)


func _build_asteroid_belt(orbital: Dictionary) -> void:
	var belt := MultiMeshInstance3D.new()
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = maxf(float(orbital.get("size", 1.0)) * 0.22, 0.18)
	rock_mesh.height = rock_mesh.radius * 2.0
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 4

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rock_mesh
	multimesh.instance_count = 56

	var rng := RandomNumberGenerator.new()
	rng.seed = str(orbital.get("id", "belt")).hash()
	var belt_radius: float = float(orbital.get("orbit_radius", 0.0))
	var belt_width: float = maxf(float(orbital.get("orbit_width", 8.0)), 6.0)
	var belt_height: float = float(orbital.get("vertical_offset", 0.0))

	for instance_index in range(multimesh.instance_count):
		var angle: float = float(instance_index) * TAU / float(multimesh.instance_count) + rng.randf_range(-0.09, 0.09)
		var radius: float = belt_radius + rng.randf_range(-belt_width * 0.5, belt_width * 0.5)
		var position := Vector3(cos(angle) * radius, belt_height + rng.randf_range(-0.25, 0.25), sin(angle) * radius)
		var basis := Basis().rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3.ONE * rng.randf_range(0.45, 1.35))
		multimesh.set_instance_transform(instance_index, Transform3D(basis, position))

	belt.multimesh = multimesh
	belt.material_override = _build_lit_material(
		orbital.get("color", Color(0.6, 0.58, 0.54, 1.0)),
		Color(0.12, 0.12, 0.12, 1.0),
		0.08,
		1.0,
		0.0
	)
	bodies.add_child(belt)


func _build_orbit_ring(radius: float, height: float, color: Color) -> void:
	if radius <= 0.1:
		return

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)
	var orbit_color := color
	orbit_color.a = 0.22

	for point_index in range(ORBIT_SEGMENT_COUNT):
		var from_angle: float = float(point_index) * TAU / float(ORBIT_SEGMENT_COUNT)
		var to_angle: float = float(point_index + 1) * TAU / float(ORBIT_SEGMENT_COUNT)
		surface_tool.set_color(orbit_color)
		surface_tool.add_vertex(Vector3(cos(from_angle) * radius, height, sin(from_angle) * radius))
		surface_tool.set_color(orbit_color)
		surface_tool.add_vertex(Vector3(cos(to_angle) * radius, height, sin(to_angle) * radius))

	var ring := MeshInstance3D.new()
	ring.mesh = surface_tool.commit()
	ring.material_override = _build_line_material()
	orbit_lines.add_child(ring)


func _get_orbit_position(body: Dictionary) -> Vector3:
	var radius: float = float(body.get("orbit_radius", 0.0))
	var angle: float = float(body.get("orbit_angle", 0.0))
	return Vector3(
		cos(angle) * radius,
		float(body.get("vertical_offset", 0.0)),
		sin(angle) * radius
	)


func _set_camera_distance(distance: float) -> void:
	if camera_rig.has_method("configure_view"):
		camera_rig.configure_view(Vector3.ZERO, distance, -34.0, 0.0)
		return
	camera_rig.position = Vector3(0.0, distance * 0.42, distance)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _get_orbit_color(orbital: Dictionary) -> Color:
	var orbital_type: String = str(orbital.get("type", ORBITAL_TYPE_PLANET))
	match orbital_type:
		ORBITAL_TYPE_ASTEROID_BELT:
			return Color(0.62, 0.58, 0.52, 0.2)
		ORBITAL_TYPE_STRUCTURE:
			return Color(0.42, 0.8, 1.0, 0.22)
		ORBITAL_TYPE_RUIN:
			return Color(0.72, 0.73, 0.78, 0.2)
		_:
			return Color(0.72, 0.84, 1.0, 0.2)


func _get_star_glow_color(base_color: Color, special_type: String) -> Color:
	match special_type:
		SPECIAL_TYPE_BLACK_HOLE:
			return Color(0.22, 0.36, 0.98, 0.32)
		SPECIAL_TYPE_NEUTRON:
			return Color(0.76, 0.92, 1.0, 0.28)
		SPECIAL_TYPE_O_CLASS:
			return Color(0.62, 0.86, 1.0, 0.3)
		_:
			var glow_color := base_color
			glow_color.a = 0.24
			return glow_color


func _build_lit_material(
	albedo: Color,
	emission: Color,
	emission_energy: float,
	roughness: float,
	metallic: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	if albedo.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = roughness
	material.metallic = metallic
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = emission_energy
	return material


func _build_unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.0
	return material


func _build_line_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.18
	return material
