extends Node3D
class_name ProceduralStarVisual

## Real 3D procedural star: emissive sphere with live granulation shader plus
## an additive corona billboard (billboarded shader-side). Special types:
## neutron star (small pulsing core + sweeping lighthouse beam cones) and
## black hole (dark core with photon ring + doppler accretion disk).
## Deterministic via _get_star_seed; entry points (configure /
## build_visual_config) are stable API.

const STAR_SURFACE_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/StarSurface.gdshader")
const STAR_CORONA_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/StarCorona.gdshader")
const STAR_PLASMA_ARMS_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/StarPlasmaArms.gdshader")
const BLACK_HOLE_CORE_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/BlackHoleCore.gdshader")
const ACCRETION_DISK_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/AccretionDisk.gdshader")
const NEUTRON_BEAMS_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/NeutronBeams.gdshader")

const STAR_SCALE_MULTIPLIER := 2.1
const STAR_KIND_NORMAL := "star"
const STAR_KIND_NEUTRON := "neutron"
const STAR_KIND_BLACK_HOLE := "black_hole"

# Per-class look table M -> O. The generator currently emits M/K/G/B plus
# specials; the full table keeps custom systems working.
const STAR_CLASS_PARAMS := {
	"M": {"cell_frequency": 4.0, "core_energy": 1.6},
	"K": {"cell_frequency": 5.0, "core_energy": 1.7},
	"G": {"cell_frequency": 6.0, "core_energy": 1.8},
	"F": {"cell_frequency": 7.0, "core_energy": 1.9},
	"A": {"cell_frequency": 8.0, "core_energy": 2.0},
	"B": {"cell_frequency": 9.0, "core_energy": 2.2},
	"O": {"cell_frequency": 10.0, "core_energy": 2.4},
}

var _star: Dictionary = {}
var _visual_config: Dictionary = {}
var _beams_pivot: Node3D = null
var _plasma_arms_root: Node3D = null


func configure(star: Dictionary) -> void:
	_star = star.duplicate(true)
	_visual_config = build_visual_config(_star)
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	if not _visual_config.is_empty():
		_rebuild()


func _process(delta: float) -> void:
	if _beams_pivot != null:
		_beams_pivot.rotate_y(float(_visual_config.get("beam_spin", 0.45)) * delta)
	if _plasma_arms_root != null:
		_plasma_arms_root.rotate_y(0.035 * delta)


# Pure-data dict (no Resources). RNG draw order (append only, never reorder):
# surface rotation -> disk tilt -> phase offset -> noise offset (3) ->
# kind-specific draws (neutron: pulse speed, beam spin, beam tilt).
static func build_visual_config(star: Dictionary) -> Dictionary:
	var metadata_variant: Variant = star.get("metadata", {})
	var metadata: Dictionary = metadata_variant if metadata_variant is Dictionary else {}
	var visual_variant: Variant = metadata.get("star_visual", {})
	var visual: Dictionary = visual_variant if visual_variant is Dictionary else {}
	var seed_value: int = _get_star_seed(star)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var special_type: String = str(star.get("special_type", "none"))
	var is_black_hole: bool = special_type == "Black hole"
	var is_neutron: bool = special_type == "Neutron star"
	var base_color: Color = star.get("color", Color(1.0, 0.9, 0.7, 1.0))
	var star_scale: float = float(star.get("scale", 1.0))
	var star_class: String = _resolve_star_class(star, special_type)
	var class_params: Dictionary = STAR_CLASS_PARAMS.get(star_class, STAR_CLASS_PARAMS["G"])

	var halo_color: Color = base_color
	var halo_alpha := 0.22
	# Tight glow fringe: the cloud reaches only ~15% of the diameter past
	# the limb, hugging the star.
	var halo_scale := 1.3
	var surface_rotation: float = float(visual.get("rotation", rng.randf_range(-PI, PI)))
	var disk_yaw: float = wrapf(surface_rotation * 0.55 + 0.7, -PI, PI)
	var disk_tilt: float = deg_to_rad(rng.randf_range(18.0, 30.0))
	var phase_offset: float = rng.randf_range(0.0, 1000.0)
	var noise_offset := Vector3(
		rng.randf_range(0.0, 512.0),
		rng.randf_range(0.0, 512.0),
		rng.randf_range(0.0, 512.0)
	)

	var color_hot: Color = _soften_color(base_color.lightened(0.45), 0.18).lerp(Color.WHITE, 0.25)
	var color_cool: Color = _soften_color(base_color.darkened(0.2), 0.12)
	var cell_frequency: float = float(class_params.get("cell_frequency", 6.0))
	var core_energy: float = float(class_params.get("core_energy", 1.8))
	var kind := STAR_KIND_NORMAL
	var pulse_speed := 0.0
	var beam_spin := 0.0
	var beam_tilt := 0.0

	if special_type == "O class star":
		halo_scale = 1.4
		halo_alpha = 0.26
		cell_frequency = 10.0
		core_energy = 2.4
		color_hot = Color(0.78, 0.86, 1.0).lerp(Color.WHITE, 0.3)
		color_cool = Color(0.52, 0.62, 0.95)
	elif is_neutron:
		kind = STAR_KIND_NEUTRON
		halo_color = Color(0.78, 0.88, 1.0, 1.0)
		halo_alpha = 0.3
		halo_scale = 1.5
		color_hot = Color(0.94, 0.97, 1.0)
		color_cool = Color(0.7, 0.82, 1.0)
		core_energy = 3.0
		cell_frequency = 9.0
		pulse_speed = rng.randf_range(4.0, 8.0)
		beam_spin = rng.randf_range(0.08, 0.18)
		beam_tilt = rng.randf_range(0.15, 0.4)
	elif is_black_hole:
		kind = STAR_KIND_BLACK_HOLE
		halo_color = Color(0.52, 0.72, 1.0, 1.0)
		halo_alpha = 0.08
		halo_scale = 1.34

	return {
		"kind": kind,
		"seed": seed_value,
		"rotation": surface_rotation,
		"base_diameter": (5.0 if is_black_hole else 4.0) * star_scale * STAR_SCALE_MULTIPLIER,
		"halo_color": halo_color,
		"halo_alpha": halo_alpha,
		"halo_scale": halo_scale,
		"color_cool": color_cool,
		"color_hot": color_hot,
		"cell_frequency": cell_frequency,
		"core_energy": core_energy,
		"pulse_speed": pulse_speed,
		"beam_spin": beam_spin,
		"beam_tilt": beam_tilt,
		"phase_offset": phase_offset,
		"noise_offset": noise_offset,
		"is_black_hole": is_black_hole,
		"disk_yaw": float(visual.get("disk_yaw", disk_yaw)),
		"disk_tilt": float(visual.get("disk_tilt", disk_tilt)),
	}


func _rebuild() -> void:
	for child in get_children():
		child.free()
	_beams_pivot = null
	_plasma_arms_root = null

	if _visual_config.is_empty():
		return

	var kind: String = str(_visual_config.get("kind", STAR_KIND_NORMAL))
	var base_diameter: float = float(_visual_config.get("base_diameter", 12.8))

	match kind:
		STAR_KIND_BLACK_HOLE:
			_build_black_hole(base_diameter)
		STAR_KIND_NEUTRON:
			_build_star_body(base_diameter, base_diameter * 0.35)
			_build_neutron_beams(base_diameter)
		_:
			_build_star_body(base_diameter, base_diameter)


func _build_star_body(base_diameter: float, sphere_diameter: float) -> void:
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = CelestialMeshLibrary.get_body_sphere()
	surface.scale = Vector3.ONE * sphere_diameter
	surface.rotation.y = float(_visual_config.get("rotation", 0.0))
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.material_override = _build_surface_material()
	add_child(surface)
	_build_corona(base_diameter, sphere_diameter)
	if str(_visual_config.get("kind", STAR_KIND_NORMAL)) == STAR_KIND_NORMAL:
		_build_plasma_arms(sphere_diameter)


## True-3D solar prominences: half-torus arc tubes anchored on the star
## sphere, randomly oriented in 3D (seeded hash — no extra RNG draws), each
## with its own lifecycle phase. The whole arm group rotates slowly so the
## arcs parallax with the camera and travel across the surface.
func _build_plasma_arms(sphere_diameter: float) -> void:
	var star_radius: float = sphere_diameter * 0.5
	var seed_value: int = int(_visual_config.get("seed", 0))
	var arm_count: int = 5 + absi(seed_value * 2654435761) % 3

	# Thin pale streamers in the star's own tint (Stellaris artwork wisps).
	var base: Color = _visual_config.get("halo_color", Color(1.0, 0.85, 0.6))
	var plasma: Color = base.lerp(Color.WHITE, 0.35)
	plasma.a = 0.55
	var tip: Color = base.lerp(Color.WHITE, 0.15)
	var phase_base: float = float(_visual_config.get("phase_offset", 0.0))

	_plasma_arms_root = Node3D.new()
	_plasma_arms_root.name = "PlasmaArms"
	# Seeded global tilt so the stratified pattern differs per star.
	_plasma_arms_root.basis = Basis.from_euler(Vector3(
		_hash01(seed_value, 901) * TAU,
		_hash01(seed_value, 902) * TAU,
		0.0
	))
	add_child(_plasma_arms_root)

	var golden_angle := PI * (3.0 - sqrt(5.0))
	for arm_index in range(arm_count):
		var h1 := _hash01(seed_value, arm_index * 3 + 1)
		var h2 := _hash01(seed_value, arm_index * 3 + 2)
		var h3 := _hash01(seed_value, arm_index * 3 + 3)

		# Arc chord on the sphere; feet pushed slightly below the surface.
		var arc_scale: float = star_radius * lerpf(0.35, 0.65, h2)
		var foot_half_span: float = arc_scale * 0.5
		var lift: float = sqrt(maxf(star_radius * star_radius - foot_half_span * foot_half_span, 0.0)) * 0.97

		# Stratified placement: fibonacci-sphere apex directions with seeded
		# jitter — evenly spread, never clumped on one hemisphere.
		var apex_y: float = 1.0 - 2.0 * (float(arm_index) + 0.5) / float(arm_count)
		apex_y = clampf(apex_y + (h3 - 0.5) * 0.3, -0.98, 0.98)
		var apex_theta: float = golden_angle * float(arm_index) + (h1 - 0.5) * 1.2
		var ring_radius: float = sqrt(maxf(1.0 - apex_y * apex_y, 0.0))
		var apex_dir := Vector3(cos(apex_theta) * ring_radius, apex_y, sin(apex_theta) * ring_radius)

		var helper := Vector3.RIGHT if absf(apex_dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var x_axis := helper.cross(apex_dir).normalized()
		var arc_basis := Basis(x_axis, apex_dir, x_axis.cross(apex_dir)).rotated(apex_dir, h2 * TAU)

		var pivot := Node3D.new()
		pivot.name = "ArmPivot%d" % arm_index
		pivot.basis = arc_basis
		_plasma_arms_root.add_child(pivot)

		var arm := MeshInstance3D.new()
		arm.name = "Arc"
		arm.mesh = CelestialMeshLibrary.get_prominence_arc()
		arm.position = Vector3(0.0, lift, 0.0)
		# Varied arch heights: stretch only the rise direction.
		arm.scale = Vector3(arc_scale, arc_scale * lerpf(0.8, 1.3, h3), arc_scale)
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var material := ShaderMaterial.new()
		material.shader = STAR_PLASMA_ARMS_SHADER
		material.render_priority = 1
		material.set_shader_parameter("plasma_color", plasma)
		material.set_shader_parameter("plasma_tip_color", tip)
		material.set_shader_parameter("phase_offset", phase_base + float(arm_index) * 17.3)
		material.set_shader_parameter("life_speed", lerpf(0.05, 0.12, h3))
		material.set_shader_parameter("flow_speed", lerpf(0.7, 1.3, h1))
		arm.material_override = material
		pivot.add_child(arm)


# Well-mixed integer hash: consecutive salts must decorrelate, otherwise the
# prominence arcs cluster on one hemisphere.
static func _hash01(seed_value: int, salt: int) -> float:
	var hashed: int = seed_value * 2654435761 + salt * 0x9E3779B9
	hashed = (hashed ^ (hashed >> 16)) * 73856093
	hashed = hashed ^ (hashed >> 13)
	hashed = hashed * 0x85EBCA6B
	hashed = hashed ^ (hashed >> 16)
	return float(absi(hashed) % 1048576) / 1048576.0


func _build_black_hole(base_diameter: float) -> void:
	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = CelestialMeshLibrary.get_body_sphere()
	core.scale = Vector3.ONE * base_diameter * 0.5
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_material := ShaderMaterial.new()
	core_material.shader = BLACK_HOLE_CORE_SHADER
	core.material_override = core_material
	add_child(core)

	var disk := MeshInstance3D.new()
	disk.name = "AccretionDisk"
	disk.mesh = CelestialMeshLibrary.get_annulus_mesh()
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disk.transform = Transform3D(
		_build_disk_basis(
			float(_visual_config.get("disk_tilt", deg_to_rad(24.0))),
			float(_visual_config.get("disk_yaw", 0.0))
		).scaled(Vector3.ONE * base_diameter * 0.7),
		Vector3.ZERO
	)
	var disk_material := ShaderMaterial.new()
	disk_material.shader = ACCRETION_DISK_SHADER
	disk_material.render_priority = 1
	var seed_value: int = int(_visual_config.get("seed", 0))
	disk_material.set_shader_parameter("band_seed", float(absi(seed_value) % 1000) / 1000.0)
	disk.material_override = disk_material
	add_child(disk)

	_build_corona(base_diameter, base_diameter * 0.5)


# Long thin polar jets tapering to a point far from the star, plus a flat
# equatorial glow disk — the classic pulsar look. Both live under the tilted
# pivot so they precess together.
func _build_neutron_beams(base_diameter: float) -> void:
	_beams_pivot = Node3D.new()
	_beams_pivot.name = "BeamsPivot"
	add_child(_beams_pivot)

	var beams_tilt := Node3D.new()
	beams_tilt.name = "BeamsTilt"
	beams_tilt.rotation.z = float(_visual_config.get("beam_tilt", 0.3))
	_beams_pivot.add_child(beams_tilt)

	var beam_material := ShaderMaterial.new()
	beam_material.shader = NEUTRON_BEAMS_SHADER
	beam_material.render_priority = 1
	beam_material.set_shader_parameter("pulse_speed", float(_visual_config.get("pulse_speed", 5.0)))
	beam_material.set_shader_parameter("phase_offset", float(_visual_config.get("phase_offset", 0.0)))

	# One tall quad spans both jets (y = 0 at the star, tips at +/-2.6
	# diameters); the shader billboards it around the jet axis.
	var beam := MeshInstance3D.new()
	beam.name = "Beam0"
	var beam_quad := QuadMesh.new()
	beam_quad.size = Vector2(base_diameter * 0.55, base_diameter * 5.2)
	beam.mesh = beam_quad
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.material_override = beam_material
	beams_tilt.add_child(beam)

	var disk := MeshInstance3D.new()
	disk.name = "EquatorialDisk"
	disk.mesh = CelestialMeshLibrary.get_annulus_mesh()
	disk.scale = Vector3.ONE * base_diameter * 1.4
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var disk_material := ShaderMaterial.new()
	disk_material.shader = ACCRETION_DISK_SHADER
	disk_material.render_priority = 1
	disk_material.set_shader_parameter("inner_color", Color(0.88, 0.94, 1.0))
	disk_material.set_shader_parameter("mid_color", Color(0.6, 0.76, 1.0))
	disk_material.set_shader_parameter("outer_color", Color(0.34, 0.5, 0.9))
	disk_material.set_shader_parameter("disk_emission", 1.1)
	disk_material.set_shader_parameter("doppler_strength", 0.0)
	disk_material.set_shader_parameter("scroll_speed", 0.05)
	disk_material.set_shader_parameter("spiral_shear", 2.0)
	disk_material.set_shader_parameter("disk_alpha", 0.4)
	disk_material.set_shader_parameter("band_seed", float(absi(int(_visual_config.get("seed", 0))) % 1000) / 1000.0)
	disk.material_override = disk_material
	beams_tilt.add_child(disk)


# Volumetric fog shell between the actual body surface (inner_diameter) and
# the fringe edge (inner_diameter * halo_scale) — true 3D, raymarched. The
# fringe scales with the BODY, so the tiny neutron core keeps a tight halo.
func _build_corona(_base_diameter: float, inner_diameter: float) -> void:
	if float(_visual_config.get("halo_alpha", 0.0)) <= 0.001:
		return
	var halo_scale: float = maxf(float(_visual_config.get("halo_scale", 1.3)), 1.05)
	var outer_diameter: float = inner_diameter * halo_scale
	var corona := MeshInstance3D.new()
	corona.name = "Corona"
	corona.mesh = CelestialMeshLibrary.get_body_sphere()
	corona.scale = Vector3.ONE * outer_diameter
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = STAR_CORONA_SHADER
	material.render_priority = 2
	var corona_color: Color = _visual_config.get("halo_color", Color.WHITE)
	corona_color.a = clampf(float(_visual_config.get("halo_alpha", 0.18)) * 2.2, 0.0, 1.0)
	material.set_shader_parameter("corona_color", corona_color)
	material.set_shader_parameter("inner_radius", inner_diameter * 0.5 * 0.99)
	material.set_shader_parameter("outer_radius", outer_diameter * 0.5 * 0.98)
	material.set_shader_parameter("noise_offset", _visual_config.get("noise_offset", Vector3.ZERO))
	material.set_shader_parameter("phase_offset", float(_visual_config.get("phase_offset", 0.0)))
	corona.material_override = material
	add_child(corona)


func _build_surface_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STAR_SURFACE_SHADER
	material.set_shader_parameter("noise_offset", _visual_config.get("noise_offset", Vector3.ZERO))
	material.set_shader_parameter("cell_frequency", float(_visual_config.get("cell_frequency", 6.0)))
	material.set_shader_parameter("color_cool", _visual_config.get("color_cool", Color(0.95, 0.62, 0.35)))
	material.set_shader_parameter("color_hot", _visual_config.get("color_hot", Color(1.0, 0.94, 0.78)))
	material.set_shader_parameter("core_energy", float(_visual_config.get("core_energy", 1.8)))
	material.set_shader_parameter("pulse_speed", float(_visual_config.get("pulse_speed", 0.0)))
	material.set_shader_parameter("phase_offset", float(_visual_config.get("phase_offset", 0.0)))
	return material


func _build_disk_basis(disk_tilt: float, disk_yaw: float) -> Basis:
	var disk_normal := Vector3.UP.rotated(Vector3.RIGHT, disk_tilt).rotated(Vector3.UP, disk_yaw).normalized()
	var x_axis := disk_normal.cross(Vector3.UP)
	if x_axis.length() < 0.001:
		x_axis = disk_normal.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var y_axis := disk_normal.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, disk_normal)


static func _resolve_star_class(star: Dictionary, special_type: String) -> String:
	if special_type == "O class star":
		return "O"
	var star_class := str(star.get("star_class", "")).strip_edges().to_upper()
	if STAR_CLASS_PARAMS.has(star_class):
		return star_class
	return "G"


static func _get_star_seed(star: Dictionary) -> int:
	return str(star.get("id", star.get("name", "star"))).hash() * 131 + int(round(float(star.get("scale", 1.0)) * 100.0))


static func _soften_color(color: Color, desaturate_amount: float) -> Color:
	return Color.from_hsv(color.h, clampf(color.s * (1.0 - desaturate_amount), 0.0, 1.0), color.v, color.a)
