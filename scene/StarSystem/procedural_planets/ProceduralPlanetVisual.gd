extends Node3D
class_name ProceduralPlanetVisual

## Real 3D procedural planet: shared sphere mesh + seeded live spatial shader
## per world kind (no texture baking, no SubViewports). Deterministic via the
## system/orbital seed chain; all randomness flows through one local RNG in
## build_visual_config(). Consumed by StarSystemPreview, SystemBodyDetailsPanel
## and ColonyModal — entry points (configure / build_visual_config /
## describe_planet) are stable API.

const TERRAN_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/PlanetTerran.gdshader")
const CLOUDS_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/PlanetClouds.gdshader")
const DESERT_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/PlanetDesert.gdshader")
const BARREN_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/PlanetBarren.gdshader")
const ICE_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/PlanetIce.gdshader")
const LAVA_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/PlanetLava.gdshader")
const GAS_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/GasGiant.gdshader")
const ATMOSPHERE_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/PlanetAtmosphere.gdshader")
const RING_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/PlanetRing.gdshader")

const WORLD_KIND_LANDMASS := "landmass"
const WORLD_KIND_DRY := "dry_terran"
const WORLD_KIND_BARREN := "no_atmosphere"
const WORLD_KIND_ICE := "ice_world"
const WORLD_KIND_LAVA := "lava_world"
const WORLD_KIND_GAS := "gas_planet"

# Legacy texture-resolution field from GalaxyGenerator metadata; remapped to
# the surface noise frequency so its deterministic influence survives.
const DEFAULT_PIXELS := 2200.0
const MIN_PIXELS := 1500.0
const MAX_PIXELS := 3200.0
const GAS_GIANT_FORCE_RING := true
const CLOUD_SHELL_SCALE := 1.025
const RING_SCALE := 1.15

const WORLD_KIND_LABELS := {
	WORLD_KIND_LANDMASS: "Terran World",
	WORLD_KIND_DRY: "Dry World",
	WORLD_KIND_BARREN: "Barren World",
	WORLD_KIND_ICE: "Ice World",
	WORLD_KIND_LAVA: "Lava World",
	WORLD_KIND_GAS: "Gas Giant",
}

const WORLD_KIND_ALIASES := {
	"terran": WORLD_KIND_LANDMASS,
	"gaia": WORLD_KIND_LANDMASS,
	"continental": WORLD_KIND_LANDMASS,
	"ocean": WORLD_KIND_LANDMASS,
	"habitable": WORLD_KIND_LANDMASS,
	"dry": WORLD_KIND_DRY,
	"desert": WORLD_KIND_DRY,
	"arid": WORLD_KIND_DRY,
	"savanna": WORLD_KIND_DRY,
	"rock": WORLD_KIND_BARREN,
	"rocky": WORLD_KIND_BARREN,
	"barren": WORLD_KIND_BARREN,
	"moon": WORLD_KIND_BARREN,
	"ice": WORLD_KIND_ICE,
	"frozen": WORLD_KIND_ICE,
	"tundra": WORLD_KIND_ICE,
	"lava": WORLD_KIND_LAVA,
	"molten": WORLD_KIND_LAVA,
	"volcanic": WORLD_KIND_LAVA,
	"gas": WORLD_KIND_GAS,
	"gas_giant": WORLD_KIND_GAS,
	"jovian": WORLD_KIND_GAS,
}

const STAR_HEAT_BY_CLASS := {
	"M": 0.28,
	"K": 0.4,
	"G": 0.52,
	"F": 0.58,
	"A": 0.68,
	"B": 0.78,
	"O": 0.9,
	"Neutron": 0.72,
	"Black Hole": 0.08,
}

var _system_details: Dictionary = {}
var _orbital: Dictionary = {}
var _orbital_index: int = -1
var _visual_config: Dictionary = {}
var _surface_node: MeshInstance3D = null
var _clouds_node: MeshInstance3D = null
var _sun_world_position := Vector3.ZERO
var _has_sun_position := false


func configure(system_details: Dictionary, orbital: Dictionary, orbital_index: int = -1) -> void:
	_system_details = system_details.duplicate(true)
	_orbital = orbital.duplicate(true)
	_orbital_index = orbital_index
	_visual_config = build_visual_config(_system_details, _orbital, _orbital_index)
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	if not _visual_config.is_empty():
		_rebuild()


func _process(delta: float) -> void:
	if _surface_node == null:
		return
	var spin_speed: float = float(_visual_config.get("spin_speed", 0.04))
	_surface_node.rotate_y(spin_speed * delta)
	if _clouds_node != null:
		_clouds_node.rotate_y(spin_speed * 1.4 * delta)


## Lights the planet from a point source (the system's primary star) instead
## of the fixed default direction used by the own-world panel previews.
func set_sun_world_position(sun_position: Vector3) -> void:
	_sun_world_position = sun_position
	_has_sun_position = true
	_apply_sun_to_materials(self)


static func describe_planet(system_details: Dictionary, orbital: Dictionary, orbital_index: int = -1) -> Dictionary:
	var visual_config: Dictionary = build_visual_config(system_details, orbital, orbital_index)
	return {
		"kind": str(visual_config.get("kind", WORLD_KIND_BARREN)),
		"label": str(visual_config.get("label", "Planet")),
	}


# Returns a pure-data dict (floats/ints/bools/Strings/Colors/Vector3 — no
# Resources) so determinism tests can deep-compare two builds.
#
# RNG draw order (append only, never reorder — same seed must keep producing
# the same body): kind rolls -> default ring roll -> ocean-variant roll
# (landmass without metadata variant_index only) -> surface rotation (ringless
# only) -> ring tilt -> axial tilt -> spin speed -> phase offset -> noise
# offset (3) -> palette (7) -> per-kind extras.
static func build_visual_config(
	system_details: Dictionary,
	orbital: Dictionary,
	orbital_index: int = -1
) -> Dictionary:
	var metadata_variant: Variant = orbital.get("metadata", {})
	var metadata: Dictionary = metadata_variant if metadata_variant is Dictionary else {}
	var visual_metadata_variant: Variant = metadata.get("planet_visual", {})
	var visual_metadata: Dictionary = visual_metadata_variant if visual_metadata_variant is Dictionary else {}
	var system_seed: int = _get_system_seed(system_details)
	var orbital_seed: int = _get_orbital_seed(system_seed, orbital, orbital_index)
	var rng := RandomNumberGenerator.new()
	rng.seed = orbital_seed

	var kind: String = _resolve_world_kind(rng, system_details, orbital, visual_metadata)
	var has_ring: bool = _resolve_bool_override(
		visual_metadata,
		"has_ring",
		_resolve_default_ring(rng, kind, orbital, visual_metadata)
	)
	if kind == WORLD_KIND_GAS and GAS_GIANT_FORCE_RING:
		has_ring = true
	var has_atmosphere: bool = _resolve_bool_override(
		visual_metadata,
		"has_atmosphere",
		_resolve_default_atmosphere(kind, orbital, visual_metadata)
	)
	var is_ocean_variant := false
	if kind == WORLD_KIND_LANDMASS:
		if visual_metadata.has("variant_index"):
			is_ocean_variant = int(visual_metadata.get("variant_index", 0)) % 2 == 1
		else:
			is_ocean_variant = rng.randf() < 0.38
	var base_diameter: float = maxf(float(orbital.get("size", 1.0)) * 2.0, 1.4)
	var default_surface_rotation := 0.0 if has_ring else rng.randf_range(-PI, PI)
	var surface_rotation: float = _resolve_float_override(visual_metadata, "rotation", default_surface_rotation)
	var ring_yaw: float = _resolve_float_override(visual_metadata, "ring_yaw", wrapf(surface_rotation * 0.6, -PI, PI))
	var ring_tilt: float = _resolve_float_override(visual_metadata, "ring_tilt", deg_to_rad(rng.randf_range(14.0, 28.0)))

	var pixels: float = clampf(_resolve_float_override(visual_metadata, "pixels", DEFAULT_PIXELS), MIN_PIXELS, MAX_PIXELS)
	var noise_frequency: float = remap(pixels, MIN_PIXELS, MAX_PIXELS, 2.2, 4.8)
	var axial_tilt: float = rng.randf_range(0.0, 0.35)
	var spin_speed: float = rng.randf_range(0.06, 0.18)
	var phase_offset: float = rng.randf_range(0.0, 1000.0)
	var noise_offset := Vector3(
		rng.randf_range(0.0, 512.0),
		rng.randf_range(0.0, 512.0),
		rng.randf_range(0.0, 512.0)
	)
	var palette_params: Dictionary = _get_palette_params(kind)
	var palette: Dictionary = CelestialBodyPalette.generate_palette(
		rng,
		float(palette_params.get("hue_diff", 0.5)),
		float(palette_params.get("saturation", 0.45))
	)
	var anchor_color: Color = orbital.get("color", Color(0.58, 0.68, 0.94, 1.0))
	if kind == WORLD_KIND_LAVA:
		# Lava crusts must stay warm and dark regardless of the accent color.
		anchor_color = anchor_color.lerp(Color(0.42, 0.27, 0.22), 0.65)
	palette = CelestialBodyPalette.anchor_palette(palette, anchor_color, float(palette_params.get("anchor_strength", 0.45)))

	var config := {
		"kind": kind,
		"label": WORLD_KIND_LABELS.get(kind, "Planet"),
		"seed": orbital_seed,
		"rotation": surface_rotation,
		"base_diameter": base_diameter,
		"has_ring": has_ring,
		"ring_yaw": ring_yaw,
		"ring_tilt": ring_tilt,
		"has_atmosphere": has_atmosphere,
		"atmosphere_color": _get_atmosphere_color(kind),
		"atmosphere_alpha": _get_atmosphere_alpha(kind, has_atmosphere),
		"atmosphere_scale": _get_atmosphere_scale(kind),
		"emission_energy": _get_emission_energy(kind),
		"noise_offset": noise_offset,
		"noise_frequency": noise_frequency,
		"palette": palette,
		"axial_tilt": axial_tilt,
		"spin_speed": spin_speed,
		"phase_offset": phase_offset,
	}
	_append_kind_config(config, rng, kind, is_ocean_variant)
	return config


static func _append_kind_config(config: Dictionary, rng: RandomNumberGenerator, kind: String, is_ocean_variant: bool) -> void:
	match kind:
		WORLD_KIND_LANDMASS:
			config["is_ocean_variant"] = is_ocean_variant
			config["ocean_level"] = rng.randf_range(0.56, 0.66) if is_ocean_variant else rng.randf_range(0.46, 0.56)
			config["cap_extent"] = rng.randf_range(0.62, 0.78)
			config["continent_warp"] = rng.randf_range(0.12, 0.25)
			config["glint_strength"] = rng.randf_range(0.4, 0.8)
			config["cloud_cover"] = rng.randf_range(0.42, 0.62)
			config["cloud_frequency"] = rng.randf_range(2.6, 3.6)
			config["cloud_density"] = rng.randf_range(0.7, 0.95)
		WORLD_KIND_DRY:
			config["band_frequency"] = rng.randf_range(3.0, 6.0)
			config["warp_amount"] = rng.randf_range(0.6, 1.6)
			var crater_roll := rng.randf()
			config["crater_strength"] = rng.randf_range(0.08, 0.2) if crater_roll < 0.4 else 0.0
			config["crater_frequency"] = rng.randf_range(4.0, 7.0)
		WORLD_KIND_BARREN:
			config["crater_frequency"] = rng.randf_range(5.0, 9.0)
			config["crater_depth"] = rng.randf_range(0.12, 0.25)
		WORLD_KIND_ICE:
			config["crack_frequency"] = rng.randf_range(5.0, 8.0)
			config["crack_strength"] = rng.randf_range(0.3, 0.6)
			var lake_roll := rng.randf()
			config["lake_amount"] = rng.randf_range(0.3, 0.5) if lake_roll < 0.45 else 0.0
		WORLD_KIND_LAVA:
			config["vein_frequency"] = rng.randf_range(3.5, 6.0)
			config["pulse_speed"] = rng.randf_range(0.4, 0.9)
			# Capped low: tonemapping washes hot HDR colors toward white.
			config["vein_emission"] = clampf(float(config.get("emission_energy", 0.36)) * 4.5, 1.3, 1.8)
			var hot := CelestialBodyPalette.evaluate(config.get("palette", {}), 0.95)
			config["vein_color"] = hot.lerp(Color(1.0, 0.45, 0.2), 0.85)
		WORLD_KIND_GAS:
			config["band_count"] = rng.randi_range(4, 9)
			config["band_warp"] = rng.randf_range(0.15, 0.45)
			config["turb_frequency"] = rng.randf_range(2.0, 4.0)
			config["band_drift"] = rng.randf_range(0.01, 0.025)
			var spot_roll := rng.randf()
			var spot_lat := rng.randf_range(0.15, 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
			var spot_lon := rng.randf_range(0.0, TAU)
			config["has_spot"] = spot_roll < 0.5
			var cos_lat := cos(asin(clampf(spot_lat, -1.0, 1.0)))
			config["spot_dir"] = Vector3(cos_lat * cos(spot_lon), spot_lat, cos_lat * sin(spot_lon)).normalized()
			config["spot_radius"] = rng.randf_range(0.12, 0.22)
			var spot_base := CelestialBodyPalette.evaluate(config.get("palette", {}), 0.95)
			config["spot_tint"] = spot_base.lerp(Color(0.9, 0.55, 0.5), 0.5)


## Single config -> shader/uniform mapping point. Also the seam for a future
## colony-view equirect baker, which renders the same surface function
## through a UV -> direction wrapper using this exact material setup.
static func build_surface_material(visual_config: Dictionary) -> ShaderMaterial:
	var kind: String = str(visual_config.get("kind", WORLD_KIND_BARREN))
	var material := ShaderMaterial.new()
	match kind:
		WORLD_KIND_LANDMASS:
			material.shader = TERRAN_SHADER
		WORLD_KIND_DRY:
			material.shader = DESERT_SHADER
		WORLD_KIND_ICE:
			material.shader = ICE_SHADER
		WORLD_KIND_LAVA:
			material.shader = LAVA_SHADER
		WORLD_KIND_GAS:
			material.shader = GAS_SHADER
		_:
			material.shader = BARREN_SHADER

	_apply_palette(material, visual_config.get("palette", {}))
	material.set_shader_parameter("noise_offset", visual_config.get("noise_offset", Vector3.ZERO))
	if kind != WORLD_KIND_GAS:
		material.set_shader_parameter("noise_frequency", float(visual_config.get("noise_frequency", 3.0)))

	match kind:
		WORLD_KIND_LANDMASS:
			material.set_shader_parameter("ocean_level", float(visual_config.get("ocean_level", 0.52)))
			material.set_shader_parameter("cap_extent", float(visual_config.get("cap_extent", 0.7)))
			material.set_shader_parameter("continent_warp", float(visual_config.get("continent_warp", 0.18)))
			material.set_shader_parameter("glint_strength", float(visual_config.get("glint_strength", 0.6)))
		WORLD_KIND_DRY:
			material.set_shader_parameter("band_frequency", float(visual_config.get("band_frequency", 4.5)))
			material.set_shader_parameter("warp_amount", float(visual_config.get("warp_amount", 1.1)))
			material.set_shader_parameter("crater_strength", float(visual_config.get("crater_strength", 0.0)))
			material.set_shader_parameter("crater_frequency", float(visual_config.get("crater_frequency", 5.0)))
		WORLD_KIND_BARREN:
			material.set_shader_parameter("crater_frequency", float(visual_config.get("crater_frequency", 6.0)))
			material.set_shader_parameter("crater_depth", float(visual_config.get("crater_depth", 0.18)))
		WORLD_KIND_ICE:
			material.set_shader_parameter("crack_frequency", float(visual_config.get("crack_frequency", 6.0)))
			material.set_shader_parameter("crack_strength", float(visual_config.get("crack_strength", 0.45)))
			material.set_shader_parameter("lake_amount", float(visual_config.get("lake_amount", 0.0)))
		WORLD_KIND_LAVA:
			material.set_shader_parameter("vein_frequency", float(visual_config.get("vein_frequency", 4.5)))
			material.set_shader_parameter("vein_emission", float(visual_config.get("vein_emission", 2.4)))
			material.set_shader_parameter("vein_color", visual_config.get("vein_color", Color(1.0, 0.62, 0.35)))
			material.set_shader_parameter("pulse_speed", float(visual_config.get("pulse_speed", 0.6)))
			material.set_shader_parameter("phase_offset", float(visual_config.get("phase_offset", 0.0)))
		WORLD_KIND_GAS:
			material.set_shader_parameter("band_count", float(visual_config.get("band_count", 6)))
			material.set_shader_parameter("band_warp", float(visual_config.get("band_warp", 0.3)))
			material.set_shader_parameter("turb_frequency", float(visual_config.get("turb_frequency", 3.0)))
			material.set_shader_parameter("band_drift", float(visual_config.get("band_drift", 0.004)))
			material.set_shader_parameter("phase_offset", float(visual_config.get("phase_offset", 0.0)))
			material.set_shader_parameter("has_spot", 1.0 if bool(visual_config.get("has_spot", false)) else 0.0)
			material.set_shader_parameter("spot_dir", visual_config.get("spot_dir", Vector3(0.8, 0.3, 0.5)))
			material.set_shader_parameter("spot_radius", float(visual_config.get("spot_radius", 0.16)))
			material.set_shader_parameter("spot_tint", visual_config.get("spot_tint", Color(0.9, 0.6, 0.55)))
	return material


func _rebuild() -> void:
	for child in get_children():
		child.free()
	_surface_node = null
	_clouds_node = null

	if _visual_config.is_empty():
		return

	var kind: String = str(_visual_config.get("kind", WORLD_KIND_BARREN))
	var base_diameter: float = float(_visual_config.get("base_diameter", 2.0))

	var planet_root := Node3D.new()
	planet_root.name = "PlanetRoot"
	planet_root.rotation.z = float(_visual_config.get("axial_tilt", 0.0))
	add_child(planet_root)

	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = CelestialMeshLibrary.get_body_sphere()
	surface.scale = Vector3.ONE * base_diameter
	surface.rotation.y = float(_visual_config.get("rotation", 0.0))
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.material_override = build_surface_material(_visual_config)
	planet_root.add_child(surface)
	_surface_node = surface

	if kind == WORLD_KIND_LANDMASS:
		var clouds := MeshInstance3D.new()
		clouds.name = "Clouds"
		clouds.mesh = CelestialMeshLibrary.get_body_sphere()
		clouds.scale = Vector3.ONE * base_diameter * CLOUD_SHELL_SCALE
		clouds.rotation.y = float(_visual_config.get("rotation", 0.0)) * 0.7
		clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		clouds.material_override = _build_clouds_material(_visual_config)
		planet_root.add_child(clouds)
		_clouds_node = clouds

	if bool(_visual_config.get("has_atmosphere", false)) and float(_visual_config.get("atmosphere_alpha", 0.0)) > 0.001:
		var atmosphere := MeshInstance3D.new()
		atmosphere.name = "Atmosphere"
		atmosphere.mesh = CelestialMeshLibrary.get_body_sphere()
		var atmosphere_scale: float = float(_visual_config.get("atmosphere_scale", 1.12))
		atmosphere.scale = Vector3.ONE * base_diameter * atmosphere_scale
		atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		atmosphere.material_override = _build_atmosphere_material(_visual_config)
		planet_root.add_child(atmosphere)

	if bool(_visual_config.get("has_ring", false)):
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		ring.mesh = CelestialMeshLibrary.get_annulus_mesh()
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.transform = Transform3D(
			_build_ring_basis(
				float(_visual_config.get("ring_tilt", deg_to_rad(20.0))),
				float(_visual_config.get("ring_yaw", 0.0))
			).scaled(Vector3.ONE * base_diameter * RING_SCALE),
			Vector3.ZERO
		)
		ring.material_override = _build_ring_material(_visual_config)
		add_child(ring)

	if _has_sun_position:
		_apply_sun_to_materials(self)


static func _apply_palette(material: ShaderMaterial, palette: Dictionary) -> void:
	material.set_shader_parameter("palette_a", palette.get("a", Vector3(0.5, 0.5, 0.5)))
	material.set_shader_parameter("palette_b", palette.get("b", Vector3(0.25, 0.25, 0.25)))
	material.set_shader_parameter("palette_c", palette.get("c", Vector3.ONE))
	material.set_shader_parameter("palette_d", palette.get("d", Vector3.ZERO))


static func _build_clouds_material(visual_config: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLOUDS_SHADER
	material.render_priority = 1
	material.set_shader_parameter("noise_offset", visual_config.get("noise_offset", Vector3.ZERO) + Vector3(101.3, 57.1, 211.7))
	material.set_shader_parameter("cloud_frequency", float(visual_config.get("cloud_frequency", 3.0)))
	material.set_shader_parameter("cloud_cover", float(visual_config.get("cloud_cover", 0.52)))
	material.set_shader_parameter("cloud_density", float(visual_config.get("cloud_density", 0.85)))
	var cloud_tint := CelestialBodyPalette.evaluate(visual_config.get("palette", {}), 0.85)
	material.set_shader_parameter("cloud_tint", Color.WHITE.lerp(cloud_tint, 0.1))
	return material


static func _build_atmosphere_material(visual_config: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ATMOSPHERE_SHADER
	material.render_priority = 2
	var atmosphere_color: Color = visual_config.get("atmosphere_color", Color(0.72, 0.9, 1.0, 1.0))
	atmosphere_color.a = float(visual_config.get("atmosphere_alpha", 0.14)) * 4.0
	material.set_shader_parameter("atmosphere_color", atmosphere_color)
	material.set_shader_parameter("intensity", 1.3)
	material.set_shader_parameter("limb_ratio", 1.0 / maxf(float(visual_config.get("atmosphere_scale", 1.12)), 1.001))
	return material


static func _build_ring_material(visual_config: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RING_SHADER
	material.render_priority = 3
	_apply_palette(material, visual_config.get("palette", {}))
	var seed_value: int = int(visual_config.get("seed", 0))
	material.set_shader_parameter("band_seed", float(absi(seed_value) % 1000) / 1000.0)
	material.set_shader_parameter("band_frequency", 6.0 + float(absi(seed_value) % 7))
	material.set_shader_parameter("gap_position", 0.35 + float(absi(seed_value) % 35) / 100.0)
	material.set_shader_parameter("planet_radius", float(visual_config.get("base_diameter", 2.0)) * 0.5)
	return material


func _apply_sun_to_materials(node: Node) -> void:
	if node is GeometryInstance3D:
		var material := (node as GeometryInstance3D).material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("sun_mode", 1.0)
			material.set_shader_parameter("sun_position", _sun_world_position)
	for child in node.get_children():
		_apply_sun_to_materials(child)


func _build_ring_basis(ring_tilt: float, ring_yaw: float) -> Basis:
	var ring_normal := Vector3.UP.rotated(Vector3.RIGHT, ring_tilt).rotated(Vector3.UP, ring_yaw).normalized()
	var x_axis := ring_normal.cross(Vector3.UP)
	if x_axis.length() < 0.001:
		x_axis = ring_normal.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var y_axis := ring_normal.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, ring_normal)


static func _get_palette_params(kind: String) -> Dictionary:
	match kind:
		WORLD_KIND_LANDMASS:
			return {"hue_diff": 0.6, "saturation": 0.55, "anchor_strength": 0.35}
		WORLD_KIND_DRY:
			return {"hue_diff": 0.4, "saturation": 0.5, "anchor_strength": 0.45}
		WORLD_KIND_ICE:
			return {"hue_diff": 0.35, "saturation": 0.3, "anchor_strength": 0.45}
		WORLD_KIND_LAVA:
			return {"hue_diff": 0.25, "saturation": 0.5, "anchor_strength": 0.6}
		WORLD_KIND_GAS:
			return {"hue_diff": 0.5, "saturation": 0.45, "anchor_strength": 0.5}
		_:
			return {"hue_diff": 0.3, "saturation": 0.25, "anchor_strength": 0.5}


static func _get_atmosphere_color(kind: String) -> Color:
	match kind:
		WORLD_KIND_ICE:
			return Color(0.78, 0.9, 1.0, 1.0)
		WORLD_KIND_DRY:
			return Color(0.98, 0.84, 0.72, 1.0)
		WORLD_KIND_LAVA:
			return Color(1.0, 0.62, 0.42, 1.0)
		WORLD_KIND_GAS:
			return Color(0.96, 0.84, 0.66, 1.0)
		_:
			return Color(0.72, 0.9, 1.0, 1.0)


static func _get_atmosphere_alpha(kind: String, has_atmosphere: bool) -> float:
	if not has_atmosphere:
		return 0.0
	match kind:
		WORLD_KIND_GAS:
			return 0.14
		WORLD_KIND_ICE:
			return 0.12
		WORLD_KIND_DRY:
			return 0.08
		WORLD_KIND_LAVA:
			return 0.07
		_:
			return 0.14


static func _get_atmosphere_scale(kind: String) -> float:
	match kind:
		WORLD_KIND_GAS:
			return 1.1
		WORLD_KIND_DRY:
			return 1.12
		WORLD_KIND_LAVA:
			return 1.1
		_:
			return 1.16


static func _get_emission_energy(kind: String) -> float:
	match kind:
		WORLD_KIND_GAS:
			return 0.24
		WORLD_KIND_LAVA:
			return 0.36
		WORLD_KIND_ICE:
			return 0.24
		_:
			return 0.18


static func _resolve_world_kind(
	rng: RandomNumberGenerator,
	system_details: Dictionary,
	orbital: Dictionary,
	visual_metadata: Dictionary
) -> String:
	var override_kind := _normalize_world_kind(str(visual_metadata.get("kind", "")))
	if override_kind.is_empty():
		override_kind = _normalize_world_kind(str(visual_metadata.get("type", "")))
	if not override_kind.is_empty():
		return override_kind

	var size: float = float(orbital.get("size", 1.0))
	var habitability: float = clampf(float(orbital.get("habitability", 0.0)), 0.0, 1.0)
	var is_colonizable: bool = bool(orbital.get("is_colonizable", false))
	var base_color: Color = orbital.get("color", Color(0.58, 0.68, 0.94, 1.0))
	var temperature: float = _resolve_temperature(system_details, orbital)

	if size >= 3.1 and habitability < 0.35 and not is_colonizable:
		return WORLD_KIND_GAS
	if size >= 2.7 and habitability < 0.28 and rng.randf() < 0.7:
		return WORLD_KIND_GAS
	if temperature > 0.72 and habitability < 0.3:
		return WORLD_KIND_LAVA if rng.randf() < 0.84 else WORLD_KIND_DRY
	if temperature < 0.24 and (habitability < 0.55 or (base_color.h > 0.48 and base_color.h < 0.72)):
		return WORLD_KIND_ICE if rng.randf() < 0.86 else WORLD_KIND_BARREN
	if habitability >= 0.7:
		return WORLD_KIND_LANDMASS if temperature <= 0.62 or rng.randf() < 0.72 else WORLD_KIND_DRY
	if is_colonizable or habitability >= 0.45:
		return WORLD_KIND_DRY if temperature > 0.56 and rng.randf() < 0.56 else WORLD_KIND_LANDMASS
	if (base_color.h < 0.08 or base_color.h > 0.94) and temperature > 0.54:
		return WORLD_KIND_LAVA
	if base_color.h > 0.5 and base_color.h < 0.72 and base_color.v > 0.55:
		return WORLD_KIND_ICE
	return WORLD_KIND_BARREN


static func _resolve_default_atmosphere(kind: String, orbital: Dictionary, visual_metadata: Dictionary) -> bool:
	if visual_metadata.has("atmosphere"):
		return bool(visual_metadata.get("atmosphere", false))
	if kind == WORLD_KIND_GAS:
		return true
	if kind == WORLD_KIND_LANDMASS or kind == WORLD_KIND_ICE:
		return true
	if kind == WORLD_KIND_DRY:
		return bool(orbital.get("is_colonizable", false)) or float(orbital.get("habitability", 0.0)) >= 0.42
	if kind == WORLD_KIND_LAVA:
		return float(orbital.get("size", 1.0)) >= 1.7 and float(orbital.get("habitability", 0.0)) >= 0.12
	return false


static func _resolve_default_ring(
	rng: RandomNumberGenerator,
	kind: String,
	orbital: Dictionary,
	visual_metadata: Dictionary
) -> bool:
	if visual_metadata.has("ring"):
		return bool(visual_metadata.get("ring", false))
	if kind == WORLD_KIND_GAS:
		return float(orbital.get("size", 1.0)) >= 3.2 and rng.randf() < 0.48
	if kind == WORLD_KIND_ICE:
		return float(orbital.get("size", 1.0)) >= 2.4 and rng.randf() < 0.14
	return false


static func _resolve_temperature(system_details: Dictionary, orbital: Dictionary) -> float:
	var outer_radius := _get_outer_orbit_radius(system_details)
	var orbit_ratio := clampf(float(orbital.get("orbit_radius", 0.0)) / maxf(outer_radius, 1.0), 0.0, 1.0)
	var star_profile_variant: Variant = system_details.get("star_profile", {})
	var star_profile: Dictionary = star_profile_variant if star_profile_variant is Dictionary else {}
	var star_class: String = str(star_profile.get("star_class", system_details.get("star_class", "G")))
	var special_type: String = str(star_profile.get("special_type", "none"))

	var star_heat: float = STAR_HEAT_BY_CLASS.get(star_class, 0.52)
	match special_type:
		"Black hole":
			star_heat = 0.08
		"Neutron star":
			star_heat = 0.74
		"O class star":
			star_heat = 0.92

	var orbital_heat := 1.0 - orbit_ratio
	return clampf(lerpf(star_heat, orbital_heat, 0.72), 0.0, 1.0)


static func _get_outer_orbit_radius(system_details: Dictionary) -> float:
	var max_radius := 1.0
	var orbitals_variant: Variant = system_details.get("orbitals", [])
	if orbitals_variant is Array:
		for orbital_variant in orbitals_variant:
			var orbital: Dictionary = orbital_variant
			if str(orbital.get("type", "")) != "planet":
				continue
			max_radius = maxf(max_radius, float(orbital.get("orbit_radius", 0.0)))
	return max_radius


static func _normalize_world_kind(value: String) -> String:
	var normalized_value: String = value.strip_edges().to_lower()
	if normalized_value.is_empty():
		return ""
	if WORLD_KIND_LABELS.has(normalized_value):
		return normalized_value
	return str(WORLD_KIND_ALIASES.get(normalized_value, ""))


static func _get_system_seed(system_details: Dictionary) -> int:
	var system_seed: int = int(system_details.get("seed", 0))
	if system_seed != 0:
		return system_seed
	return str(system_details.get("id", system_details.get("name", "system"))).hash() * 31


static func _get_orbital_seed(system_seed: int, orbital: Dictionary, orbital_index: int) -> int:
	var orbital_key := "%s:%s:%d" % [
		str(orbital.get("id", orbital.get("name", "planet"))),
		str(orbital.get("name", "")),
		orbital_index,
	]
	return system_seed * 31 + orbital_key.hash() * 131 + int(round(float(orbital.get("orbit_radius", 0.0)) * 100.0))


static func _resolve_float_override(metadata: Dictionary, key: String, fallback: float) -> float:
	if not metadata.has(key):
		return fallback
	return float(metadata.get(key, fallback))


static func _resolve_bool_override(metadata: Dictionary, key: String, fallback: bool) -> bool:
	if not metadata.has(key):
		return fallback
	return bool(metadata.get(key, fallback))
