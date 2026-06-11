extends Node3D

## Dev harness: renders each celestial body type through the real 3D pipeline
## in a controlled showcase (own camera, preview-matching environment) and
## saves one screenshot per body to res://tools/screenshots/, plus a full
## system overview through StarSystemPreview. Run windowed (not headless):
##   & $env:GODOT_CONSOLE --path "O:\Spiele\sellaris" "res://tools/celestial_visual_screenshot.tscn"

const PREVIEW_SCENE: PackedScene = preload("res://scene/StarSystem/StarSystemPreview.tscn")
const PLANET_VISUAL_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralPlanetVisual.gd")
const STAR_VISUAL_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralStarVisual.gd")
const PASTEL_SHADER: Shader = preload("res://scene/StarSystem/SystemViewPastel.gdshader")
const SKY_SHADER: Shader = preload("res://scene/StarSystem/SystemSkyBackdrop.gdshader")

const SUN_POSITION := Vector3(120.0, 40.0, 90.0)

var _camera: Camera3D = null
var _stage: Node3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://tools/screenshots")
	_setup_environment()
	_stage = Node3D.new()
	add_child(_stage)
	_camera = Camera3D.new()
	_camera.fov = 34.0
	_camera.near = 0.1
	_camera.far = 1200.0
	add_child(_camera)
	_camera.current = true

	var system_details := _system_details()
	for shot in _body_shots():
		_clear_stage()
		var body: Node3D = null
		if shot.has("star"):
			body = STAR_VISUAL_SCRIPT.new() as ProceduralStarVisual
			body.configure(shot["star"])
		else:
			body = PLANET_VISUAL_SCRIPT.new() as ProceduralPlanetVisual
			body.configure(system_details, shot["orbital"], int(shot.get("index", 0)))
		_stage.add_child(body)
		if body.has_method("set_sun_world_position"):
			body.set_sun_world_position(SUN_POSITION)
		var distance: float = float(shot.get("distance", 14.0))
		_camera.look_at_from_position(Vector3(0.0, distance * 0.25, distance), Vector3.ZERO, Vector3.UP)
		await _settle(20)
		await _capture("res://tools/screenshots/body_%s.png" % shot["name"])

	_clear_stage()
	var preview := PREVIEW_SCENE.instantiate() as StarSystemPreview
	add_child(preview)
	await get_tree().process_frame
	preview.set_system_details(_preview_system_details())
	await _settle(30)
	await _capture("res://tools/screenshots/celestial_overview.png")
	await _capture_through_post(
		"res://tools/screenshots/celestial_overview.png",
		"res://tools/screenshots/celestial_overview_post.png"
	)

	get_tree().quit(0)


## Re-displays a captured frame through the SystemViewPastel post material —
## judges the post shader exactly as SystemView applies it.
func _capture_through_post(source_path: String, out_path: String) -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
	if image == null:
		push_error("could not reload %s" % source_path)
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	var post_material := ShaderMaterial.new()
	post_material.shader = PASTEL_SHADER
	rect.material = post_material
	layer.add_child(rect)
	await _settle(4)
	await _capture(out_path)
	layer.free()


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0509804, 0.0745098, 0.133333)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85098, 0.823529, 0.980392)
	environment.ambient_light_energy = 0.9
	environment.tonemap_exposure = 1.15
	environment.glow_enabled = true
	environment.glow_intensity = 0.22
	environment.glow_bloom = 0.16
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("seed_offset", 421.0)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


func _clear_stage() -> void:
	for child in _stage.get_children():
		child.free()


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("Saved %s" % path)


func _body_shots() -> Array:
	return [
		{"name": "terran", "distance": 12.0, "index": 0, "orbital": _orbital("p_terran", "landmass", 2.6, 16.0, Color(0.5, 0.72, 0.55))},
		{"name": "desert", "distance": 11.0, "index": 1, "orbital": _orbital("p_desert", "dry_terran", 2.2, 26.0, Color(0.85, 0.7, 0.5))},
		{"name": "barren", "distance": 10.0, "index": 2, "orbital": _orbital("p_barren", "no_atmosphere", 1.8, 36.0, Color(0.66, 0.64, 0.7))},
		{"name": "lava", "distance": 11.0, "index": 3, "orbital": _orbital("p_lava", "lava_world", 2.4, 46.0, Color(0.9, 0.5, 0.4))},
		{"name": "ice", "distance": 10.0, "index": 4, "orbital": _orbital("p_ice", "ice_world", 2.0, 56.0, Color(0.7, 0.85, 0.95))},
		{"name": "gas_ring", "distance": 26.0, "index": 5, "orbital": _orbital("p_gas", "gas_planet", 4.6, 66.0, Color(0.9, 0.78, 0.62), true)},
		{"name": "star_g", "distance": 42.0, "star": {"id": "star_g", "name": "Primary", "star_class": "G", "color": Color(1.0, 0.88, 0.55), "scale": 1.1}},
		{"name": "star_neutron", "distance": 34.0, "star": {"id": "star_n", "name": "Pulse", "special_type": "Neutron star", "color": Color(0.85, 0.92, 1.0), "scale": 0.8}},
		{"name": "black_hole", "distance": 48.0, "star": {"id": "star_bh", "name": "Maw", "special_type": "Black hole", "color": Color(0.4, 0.5, 0.9), "scale": 0.9}},
	]


func _orbital(orbital_id: String, kind: String, size: float, orbit_radius: float, color: Color, has_ring: bool = false) -> Dictionary:
	return {
		"id": orbital_id,
		"name": orbital_id,
		"type": "planet",
		"size": size,
		"orbit_radius": orbit_radius,
		"orbit_angle": 0.0,
		"color": color,
		"metadata": {"planet_visual": {"kind": kind, "has_ring": has_ring}},
	}


func _system_details() -> Dictionary:
	return {
		"id": "sys_showcase",
		"name": "Showcase",
		"seed": 20260611,
		"star_profile": {"star_class": "G", "special_type": "none"},
		"stars": [],
		"orbitals": [],
	}


func _preview_system_details() -> Dictionary:
	var details := _system_details()
	details["has_full_intel"] = false
	details["space_renderables"] = {}
	details["stars"] = [
		{"id": "star_primary", "name": "Primary", "star_class": "G", "color": Color(1.0, 0.88, 0.55), "scale": 1.1, "is_primary": true},
	]
	details["orbitals"] = [
		_orbital("p_terran", "landmass", 2.6, 16.0, Color(0.5, 0.72, 0.55)),
		_orbital("p_desert", "dry_terran", 2.2, 26.0, Color(0.85, 0.7, 0.5)),
		_orbital("p_barren", "no_atmosphere", 1.8, 36.0, Color(0.66, 0.64, 0.7)),
		_orbital("p_lava", "lava_world", 2.4, 46.0, Color(0.9, 0.5, 0.4)),
		_orbital("p_ice", "ice_world", 2.0, 56.0, Color(0.7, 0.85, 0.95)),
		_orbital("p_gas", "gas_planet", 4.6, 66.0, Color(0.9, 0.78, 0.62), true),
		{
			"id": "belt_main", "name": "Belt", "type": "asteroid_belt", "size": 1.0,
			"orbit_radius": 78.0, "orbit_width": 8.0, "color": Color(0.62, 0.58, 0.52),
			"metadata": {"belt_visual": {"density": 45}},
		},
	]
	var angles := [0.0, 2.2, 4.0, 3.6, 5.2, 1.1]
	for orbital_index in range(6):
		details["orbitals"][orbital_index]["orbit_angle"] = angles[orbital_index]
	return details
