extends Node3D
class_name ProceduralPlanetVisual

const LANDMASSES_SCENE: PackedScene = preload("res://Planets/LandMasses/LandMasses.tscn")
const RIVERS_SCENE: PackedScene = preload("res://Planets/Rivers/Rivers.tscn")
const DRY_TERRAN_SCENE: PackedScene = preload("res://Planets/DryTerran/DryTerran.tscn")
const NO_ATMOSPHERE_SCENE: PackedScene = preload("res://Planets/NoAtmosphere/NoAtmosphere.tscn")
const ICE_WORLD_SCENE: PackedScene = preload("res://Planets/IceWorld/IceWorld.tscn")
const LAVA_WORLD_SCENE: PackedScene = preload("res://Planets/LavaWorld/LavaWorld.tscn")
const GAS_PLANET_SCENE: PackedScene = preload("res://Planets/GasPlanet/GasPlanet.tscn")
const GAS_PLANET_LAYERS_SCENE: PackedScene = preload("res://Planets/GasPlanetLayers/GasPlanetLayers.tscn")
const ATMOSPHERE_HALO_SHADER: Shader = preload("res://scene/StarSystem/procedural_planets/shaders/AtmosphereHalo.gdshader")

const WORLD_KIND_LANDMASS := "landmass"
const WORLD_KIND_DRY := "dry_terran"
const WORLD_KIND_BARREN := "no_atmosphere"
const WORLD_KIND_ICE := "ice_world"
const WORLD_KIND_LAVA := "lava_world"
const WORLD_KIND_GAS := "gas_planet"

const VIEWPORT_TARGET_SIZE := 768.0
const DEFAULT_PIXELS := 2200.0
const MIN_PIXELS := 1500.0
const MAX_PIXELS := 3200.0
const GAS_GIANT_FORCE_RING := true

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
var _camera_facing_nodes: Array[Node3D] = []


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


func _process(_delta: float) -> void:
	_update_camera_facing_nodes()


static func describe_planet(system_details: Dictionary, orbital: Dictionary, orbital_index: int = -1) -> Dictionary:
	var visual_config: Dictionary = build_visual_config(system_details, orbital, orbital_index)
	return {
		"kind": str(visual_config.get("kind", WORLD_KIND_BARREN)),
		"label": str(visual_config.get("label", "Planet")),
	}


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
	var scene_variant: String = _resolve_scene_variant(rng, kind, has_ring, visual_metadata)
	var scene: PackedScene = _get_scene_for_variant(scene_variant)
	var base_diameter: float = maxf(float(orbital.get("size", 1.0)) * 2.0, 1.4)
	var surface_rotation: float = _resolve_float_override(visual_metadata, "rotation", rng.randf_range(-PI, PI))
	var ring_yaw: float = _resolve_float_override(visual_metadata, "ring_yaw", wrapf(surface_rotation * 0.6, -PI, PI))
	var ring_tilt: float = _resolve_float_override(visual_metadata, "ring_tilt", deg_to_rad(rng.randf_range(14.0, 28.0)))

	return {
		"kind": kind,
		"label": WORLD_KIND_LABELS.get(kind, "Planet"),
		"scene": scene,
		"scene_variant": scene_variant,
		"seed": orbital_seed,
		"pixels": clampf(_resolve_float_override(visual_metadata, "pixels", DEFAULT_PIXELS), MIN_PIXELS, MAX_PIXELS),
		"rotation": surface_rotation,
		"light_origin": _resolve_light_origin(scene_variant, visual_metadata),
		"base_diameter": base_diameter,
		"has_ring": has_ring,
		"split_ring": has_ring and scene_variant == "gas_planet_layers",
		"ring_yaw": ring_yaw,
		"ring_tilt": ring_tilt,
		"has_atmosphere": has_atmosphere,
		"atmosphere_color": _get_atmosphere_color(scene_variant),
		"atmosphere_alpha": _get_atmosphere_alpha(kind, has_atmosphere),
		"atmosphere_scale": _get_atmosphere_scale(kind),
		"emission_energy": _get_emission_energy(kind),
	}


func _rebuild() -> void:
	for child in get_children():
		child.free()
	_camera_facing_nodes.clear()

	if _visual_config.is_empty():
		return

	var scene_variant: Variant = _visual_config.get("scene", null)
	var scene: PackedScene = scene_variant as PackedScene
	if scene == null:
		return

	var body_layer: Dictionary = {}
	var ring_layer: Dictionary = {}
	if bool(_visual_config.get("split_ring", false)):
		body_layer = _build_planet_texture_layer(scene, PackedStringArray(["Ring"]), 1.0)
		ring_layer = _build_planet_texture_layer(scene, PackedStringArray(["GasLayers"]), 3.0)
	else:
		body_layer = _build_planet_texture_layer(scene)
	if body_layer.is_empty():
		return

	var base_diameter: float = float(_visual_config.get("base_diameter", 2.0))
	if _visual_config.get("atmosphere_alpha", 0.0) > 0.001:
		var atmosphere := MeshInstance3D.new()
		var atmosphere_mesh := QuadMesh.new()
		atmosphere_mesh.size = Vector2.ONE * base_diameter * float(_visual_config.get("atmosphere_scale", 1.16))
		atmosphere.mesh = atmosphere_mesh
		atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		atmosphere.material_override = _build_halo_material(
			_visual_config.get("atmosphere_color", Color(0.7, 0.86, 1.0, 1.0)),
			float(_visual_config.get("atmosphere_alpha", 0.14))
		)
		add_child(atmosphere)
		_register_camera_facing_node(atmosphere)

	if not ring_layer.is_empty():
		var ring_texture: Texture2D = ring_layer.get("texture", null) as Texture2D
		if ring_texture != null:
			var ring_quad := MeshInstance3D.new()
			var ring_mesh := QuadMesh.new()
			ring_mesh.size = Vector2.ONE * base_diameter * float(ring_layer.get("relative_scale", 3.0))
			ring_quad.mesh = ring_mesh
			ring_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring_quad.transform = Transform3D(
				_build_ring_basis(
					float(_visual_config.get("ring_tilt", deg_to_rad(20.0))),
					float(_visual_config.get("ring_yaw", 0.0))
				),
				Vector3.ZERO
			)
			ring_quad.material_override = _build_planet_material(
				ring_texture,
				_visual_config.get("atmosphere_color", Color.WHITE),
				0.1,
				BaseMaterial3D.BILLBOARD_DISABLED,
				1
			)
			add_child(ring_quad)

	var body_texture: Texture2D = body_layer.get("texture", null) as Texture2D
	if body_texture == null:
		return

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * base_diameter * float(body_layer.get("relative_scale", 1.0))
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.material_override = _build_planet_material(
		body_texture,
		_visual_config.get("atmosphere_color", Color.WHITE),
		float(_visual_config.get("emission_energy", 0.18)),
		BaseMaterial3D.BILLBOARD_ENABLED,
		0
	)
	add_child(quad)
	_update_camera_facing_nodes()


func _build_planet_texture_layer(
	scene: PackedScene,
	hidden_nodes: PackedStringArray = PackedStringArray(),
	relative_scale_override: float = -1.0
) -> Dictionary:
	if scene == null:
		return {}

	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(int(VIEWPORT_TARGET_SIZE), int(VIEWPORT_TARGET_SIZE))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var holder := Control.new()
	holder.position = Vector2.ZERO
	holder.size = Vector2.ONE * VIEWPORT_TARGET_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(holder)

	var planet_canvas: Node = scene.instantiate()
	holder.add_child(planet_canvas)
	_set_canvas_nodes_visible(planet_canvas, hidden_nodes, false)

	var pixels: float = float(_visual_config.get("pixels", DEFAULT_PIXELS))
	if planet_canvas.has_method("set_pixels"):
		planet_canvas.call("set_pixels", pixels)

	var relative_scale := 1.0
	if relative_scale_override > 0.0:
		relative_scale = relative_scale_override
	else:
		var relative_scale_variant: Variant = planet_canvas.get("relative_scale")
		if relative_scale_variant != null:
			relative_scale = maxf(float(relative_scale_variant), 1.0)
	var content_extent: float = maxf(pixels * relative_scale, 1.0)
	holder.scale = Vector2.ONE * (VIEWPORT_TARGET_SIZE / content_extent)

	if planet_canvas is Control:
		var planet_control: Control = planet_canvas as Control
		planet_control.position = Vector2.ONE * pixels * 0.5 * (relative_scale - 1.0)

	var seed_value: int = int(_visual_config.get("seed", 0))
	seed(seed_value)
	if planet_canvas.has_method("set_seed"):
		planet_canvas.call("set_seed", seed_value)
	if planet_canvas.has_method("set_rotates"):
		planet_canvas.call("set_rotates", float(_visual_config.get("rotation", 0.0)))
	if planet_canvas.has_method("set_light"):
		planet_canvas.call("set_light", _visual_config.get("light_origin", Vector2(0.39, 0.39)))
	if planet_canvas.has_method("set_dither"):
		planet_canvas.call("set_dither", true)

	return {
		"texture": viewport.get_texture(),
		"relative_scale": relative_scale,
	}


func _set_canvas_nodes_visible(planet_canvas: Node, node_names: PackedStringArray, is_visible: bool) -> void:
	for node_name in node_names:
		var canvas_item: CanvasItem = planet_canvas.find_child(node_name, true, false) as CanvasItem
		if canvas_item != null:
			canvas_item.visible = is_visible


func _build_planet_material(
	texture: Texture2D,
	emission_color: Color,
	emission_energy: float,
	billboard_mode: BaseMaterial3D.BillboardMode,
	render_priority: int = 0
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = billboard_mode
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = emission_energy
	material.render_priority = render_priority
	return material


func _build_ring_basis(ring_tilt: float, ring_yaw: float) -> Basis:
	var ring_normal := Vector3.UP.rotated(Vector3.RIGHT, ring_tilt).rotated(Vector3.UP, ring_yaw).normalized()
	var x_axis := ring_normal.cross(Vector3.UP)
	if x_axis.length() < 0.001:
		x_axis = ring_normal.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var y_axis := ring_normal.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, ring_normal)


func _register_camera_facing_node(node: Node3D) -> void:
	if node == null:
		return
	_camera_facing_nodes.append(node)


func _update_camera_facing_nodes() -> void:
	if _camera_facing_nodes.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_basis: Basis = camera.global_transform.basis.orthonormalized()
	for node in _camera_facing_nodes:
		if not is_instance_valid(node):
			continue
		var node_transform: Transform3D = node.global_transform
		node_transform.basis = camera_basis
		node.global_transform = node_transform


func _build_halo_material(color: Color, alpha: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ATMOSPHERE_HALO_SHADER
	material.render_priority = 2
	var halo_color: Color = color
	halo_color.a = alpha
	material.set_shader_parameter("halo_color", halo_color)
	material.set_shader_parameter("inner_radius", 0.3)
	material.set_shader_parameter("outer_radius", 0.5)
	material.set_shader_parameter("softness", 0.2)
	return material


static func _resolve_scene_variant(
	rng: RandomNumberGenerator,
	kind: String,
	has_ring: bool,
	visual_metadata: Dictionary
) -> String:
	var explicit_variant: String = str(visual_metadata.get("scene_variant", "")).strip_edges().to_lower()
	if not explicit_variant.is_empty():
		return explicit_variant

	match kind:
		WORLD_KIND_LANDMASS:
			if visual_metadata.has("variant_index"):
				return "rivers" if int(visual_metadata.get("variant_index", 0)) % 2 == 1 else "landmass"
			return "rivers" if rng.randf() < 0.38 else "landmass"
		WORLD_KIND_DRY:
			return "dry_terran"
		WORLD_KIND_ICE:
			return "ice_world"
		WORLD_KIND_LAVA:
			return "lava_world"
		WORLD_KIND_GAS:
			return "gas_planet_layers"
		_:
			return "no_atmosphere"


static func _get_scene_for_variant(scene_variant: String) -> PackedScene:
	match scene_variant:
		"rivers":
			return RIVERS_SCENE
		"dry_terran":
			return DRY_TERRAN_SCENE
		"ice_world":
			return ICE_WORLD_SCENE
		"lava_world":
			return LAVA_WORLD_SCENE
		"gas_planet":
			return GAS_PLANET_SCENE
		"gas_planet_layers":
			return GAS_PLANET_LAYERS_SCENE
		"no_atmosphere":
			return NO_ATMOSPHERE_SCENE
		_:
			return LANDMASSES_SCENE


static func _resolve_light_origin(scene_variant: String, visual_metadata: Dictionary) -> Vector2:
	if visual_metadata.has("light_origin") and visual_metadata["light_origin"] is Vector2:
		return visual_metadata["light_origin"]

	match scene_variant:
		"dry_terran":
			return Vector2(0.4, 0.3)
		"ice_world":
			return Vector2(0.3, 0.3)
		"lava_world":
			return Vector2(0.3, 0.3)
		"no_atmosphere":
			return Vector2(0.25, 0.25)
		"gas_planet":
			return Vector2(0.25, 0.25)
		"gas_planet_layers":
			return Vector2(-0.1, 0.3)
		_:
			return Vector2(0.39, 0.39)


static func _get_atmosphere_color(scene_variant: String) -> Color:
	match scene_variant:
		"ice_world":
			return Color(0.78, 0.9, 1.0, 1.0)
		"dry_terran":
			return Color(0.98, 0.84, 0.72, 1.0)
		"lava_world":
			return Color(1.0, 0.62, 0.42, 1.0)
		"gas_planet":
			return Color(0.96, 0.84, 0.66, 1.0)
		"gas_planet_layers":
			return Color(0.96, 0.82, 0.68, 1.0)
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
