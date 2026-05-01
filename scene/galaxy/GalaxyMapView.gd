extends Node3D
class_name GalaxyMapView

signal hovered_system_changed(system_id: String)
signal inspect_system_requested(system_id: String)
signal pinned_system_changed(system_id: String)

const GALAXY_MAP_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyMapRenderer.gd")
const GALAXY_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT: Script = preload("res://scene/galaxy/GalaxyRuntimePlaceholderRenderer.gd")
const STAR_CORE_SHADER: Shader = preload("res://scene/galaxy/StarCore.gdshader")
const STAR_GLOW_SHADER: Shader = preload("res://scene/galaxy/StarGlow.gdshader")
const SYSTEM_PICK_RADIUS: float = 26.0
const BACKGROUND_MIN_EXTENT: float = 9000.0
const BACKGROUND_RADIUS_FACTOR: float = 3.8
const BACKGROUND_STAR_COUNT: int = 680
const BACKGROUND_NEBULA_SEGMENTS: int = 28
const BACKGROUND_NEBULA_FAR_CLOUD_COUNT: int = 74
const BACKGROUND_NEBULA_NEAR_CLOUD_COUNT: int = 48
const BACKGROUND_NEBULA_FAR_HEIGHT: float = -320.0
const BACKGROUND_NEBULA_NEAR_HEIGHT: float = -170.0
const BACKGROUND_STAR_HEIGHT: float = -280.0
const BACKGROUND_RANDOM_SEED: int = 421337

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var background_root: Node3D = $Background
@onready var background_nebula_far: MeshInstance3D = $Background/NebulaFar
@onready var background_nebula_near: MeshInstance3D = $Background/NebulaNear
@onready var background_starfield: MultiMeshInstance3D = $Background/Starfield
@onready var stars: Node3D = $Stars
@onready var star_backplates: MultiMeshInstance3D = $Stars/StarBackplates
@onready var core_stars: MultiMeshInstance3D = $Stars/CoreStars
@onready var glow_stars: MultiMeshInstance3D = $Stars/GlowStars
@onready var ownership_markers: MeshInstance3D = $Stars/OwnershipMarkers
@onready var ownership_connectors: MeshInstance3D = $Stars/OwnershipConnectors
@onready var hyperlanes: MeshInstance3D = $Hyperlanes
@onready var runtime_placeholders: Node3D = $RuntimePlaceholders
@onready var station_markers: MultiMeshInstance3D = $RuntimePlaceholders/StationMarkers
@onready var fleet_markers: MultiMeshInstance3D = $RuntimePlaceholders/FleetMarkers
@onready var ship_markers: MultiMeshInstance3D = $RuntimePlaceholders/ShipMarkers

var system_positions: Array[Vector3] = []
var system_records: Array[Dictionary] = []
var hyperlane_links: Array[Vector2i] = []
var empires_by_id: Dictionary = {}
var min_system_distance: float = 48.0
var ownership_bright_rim_enabled: bool = true
var ownership_core_opacity: float = 0.0
var pinned_system_id: String = ""
var system_intel_by_id: Dictionary = {}
var debug_reveal_galaxy: bool = false
var _hovered_system_id: String = ""
var _map_renderer: RefCounted = GALAXY_MAP_RENDERER_SCRIPT.new()
var _runtime_placeholder_renderer: RefCounted = GALAXY_RUNTIME_PLACEHOLDER_RENDERER_SCRIPT.new()
var _nebula_extent: float = 0.0
var _background_time: float = 0.0


func _ready() -> void:
	_map_renderer.bind(self, STAR_CORE_SHADER, STAR_GLOW_SHADER)
	_runtime_placeholder_renderer.bind(self)
	_resize_background(0.0)


func _exit_tree() -> void:
	if _map_renderer != null:
		_map_renderer.unbind()
	if _runtime_placeholder_renderer != null:
		_runtime_placeholder_renderer.unbind()


func _process(delta: float) -> void:
	_background_time += delta
	_animate_background()


func sync_state(
	next_system_positions: Array[Vector3],
	next_system_records: Array[Dictionary],
	next_hyperlane_links: Array[Vector2i],
	next_empires_by_id: Dictionary,
	next_min_system_distance: float,
	next_ownership_bright_rim_enabled: bool,
	next_ownership_core_opacity: float,
	next_pinned_system_id: String,
	next_system_intel_by_id: Dictionary = {},
	next_debug_reveal_galaxy: bool = false
) -> void:
	system_positions = next_system_positions
	system_records = next_system_records
	hyperlane_links = next_hyperlane_links
	empires_by_id = next_empires_by_id
	min_system_distance = next_min_system_distance
	ownership_bright_rim_enabled = next_ownership_bright_rim_enabled
	ownership_core_opacity = next_ownership_core_opacity
	pinned_system_id = next_pinned_system_id
	system_intel_by_id = next_system_intel_by_id.duplicate(true)
	debug_reveal_galaxy = next_debug_reveal_galaxy
	_resize_background(0.0)


func sync_interaction_state(hovered_system_id: String, next_pinned_system_id: String) -> void:
	_hovered_system_id = hovered_system_id
	pinned_system_id = next_pinned_system_id


func handle_view_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		if _is_pointer_over_gui():
			return
		if pinned_system_id.is_empty():
			var hovered_system_id: String = _pick_system_at_screen_position(event.position)
			if hovered_system_id != _hovered_system_id:
				_hovered_system_id = hovered_system_id
				render_stars()
				hovered_system_changed.emit(_hovered_system_id)
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_pointer_over_gui():
			return

		var clicked_system_id: String = _pick_system_at_screen_position(event.position)
		if clicked_system_id.is_empty():
			return
		_hovered_system_id = clicked_system_id
		hovered_system_changed.emit(clicked_system_id)
		inspect_system_requested.emit(clicked_system_id)
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _is_pointer_over_gui():
			return

		var clicked_system_id: String = _pick_system_at_screen_position(event.position)
		pinned_system_id = clicked_system_id
		_hovered_system_id = clicked_system_id
		render_stars()
		hovered_system_changed.emit(clicked_system_id)
		pinned_system_changed.emit(clicked_system_id)


func render_stars() -> void:
	_map_renderer.render_stars()


func render_hyperlanes() -> void:
	_map_renderer.render_hyperlanes()


func render_ownership_markers() -> void:
	_map_renderer.render_ownership_markers()


func clear_rendered_map() -> void:
	star_backplates.multimesh = null
	core_stars.multimesh = null
	glow_stars.multimesh = null
	ownership_markers.mesh = null
	ownership_connectors.mesh = null
	hyperlanes.mesh = null
	clear_runtime_placeholders()


func render_runtime_placeholders() -> void:
	_runtime_placeholder_renderer.render_runtime_placeholders()


func clear_runtime_placeholders() -> void:
	_runtime_placeholder_renderer.clear_runtime_placeholders()


func set_camera_input_blocked(blocked: bool) -> void:
	if camera_rig != null and camera_rig.has_method("set_input_blocked"):
		camera_rig.set_input_blocked(blocked)


func is_middle_dragging() -> bool:
	return camera_rig != null and camera_rig.has_method("is_middle_dragging") and camera_rig.is_middle_dragging()


func set_galaxy_radius(radius: float) -> void:
	if camera_rig != null and camera_rig.has_method("set_galaxy_radius"):
		camera_rig.set_galaxy_radius(radius)
	_resize_background(radius)


func reset_camera_view(galaxy_radius: float) -> void:
	if camera_rig != null and camera_rig.has_method("reset_view"):
		camera_rig.reset_view(galaxy_radius)


func focus_camera_on_system(system_id: String) -> void:
	if camera_rig == null or not camera_rig.has_method("configure_view"):
		return
	for system_record in system_records:
		if str(system_record.get("id", "")) != system_id:
			continue
		var focus_position: Vector3 = system_record.get("position", Vector3.ZERO)
		camera_rig.configure_view(focus_position, maxf(min_system_distance * 18.0, 760.0))
		return


func is_system_visible_on_map(system_id: String) -> bool:
	return has_sensor_system_intel_on_map(system_id)


func is_system_hint_visible_on_map(system_id: String) -> bool:
	return not system_id.is_empty()


func has_sensor_system_intel_on_map(system_id: String) -> bool:
	return debug_reveal_galaxy or int(system_intel_by_id.get(system_id, GalaxyState.INTEL_NONE)) >= GalaxyState.INTEL_SENSOR


func has_full_system_intel_on_map(system_id: String) -> bool:
	return debug_reveal_galaxy or int(system_intel_by_id.get(system_id, GalaxyState.INTEL_NONE)) >= GalaxyState.INTEL_EXPLORED


func get_system_intel_level_on_map(system_id: String) -> int:
	if debug_reveal_galaxy:
		return GalaxyState.INTEL_SURVEYED
	return int(system_intel_by_id.get(system_id, GalaxyState.INTEL_NONE))


func get_hovered_system_id_on_map() -> String:
	return _hovered_system_id


func _pick_system_at_screen_position(screen_position: Vector2) -> String:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var best_system_id: String = ""
	var best_distance_sq: float = SYSTEM_PICK_RADIUS * SYSTEM_PICK_RADIUS
	var best_camera_distance_sq: float = INF

	for system_record in system_records:
		var system_id: String = str(system_record.get("id", ""))
		if not is_system_hint_visible_on_map(system_id):
			continue
		var system_position: Vector3 = system_record.get("position", Vector3.ZERO)
		if camera.is_position_behind(system_position):
			continue

		var projected_position: Vector2 = camera.unproject_position(system_position)
		if not viewport_rect.has_point(projected_position):
			continue

		var screen_distance_sq: float = projected_position.distance_squared_to(screen_position)
		if screen_distance_sq > best_distance_sq:
			continue

		var camera_distance_sq: float = camera.global_position.distance_squared_to(system_position)
		if screen_distance_sq < best_distance_sq or (is_equal_approx(screen_distance_sq, best_distance_sq) and camera_distance_sq < best_camera_distance_sq):
			best_distance_sq = screen_distance_sq
			best_camera_distance_sq = camera_distance_sq
			best_system_id = system_id

	return best_system_id


func _is_pointer_over_gui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _resize_background(radius: float) -> void:
	var target_radius: float = maxf(radius, _get_current_system_extent())
	var background_extent: float = maxf(target_radius * BACKGROUND_RADIUS_FACTOR, BACKGROUND_MIN_EXTENT)
	if is_equal_approx(background_extent, _nebula_extent):
		return
	_nebula_extent = background_extent
	_configure_environment_backdrop()
	_rebuild_background(background_extent)


func _configure_environment_backdrop() -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	environment.background_color = Color(0.012, 0.018, 0.04, 1.0)
	environment.ambient_light_color = Color(0.7, 0.76, 0.94, 1.0)
	environment.ambient_light_energy = 0.58
	environment.tonemap_exposure = 1.05
	environment.glow_enabled = true
	environment.glow_intensity = 0.13
	environment.glow_bloom = 0.06
	environment.volumetric_fog_enabled = false


func _rebuild_background(background_extent: float) -> void:
	if background_root != null:
		background_root.position = Vector3.ZERO
	_rebuild_nebula_layer(
		background_nebula_far,
		background_extent,
		BACKGROUND_RANDOM_SEED + 17,
		BACKGROUND_NEBULA_FAR_CLOUD_COUNT,
		BACKGROUND_NEBULA_FAR_HEIGHT,
		false
	)
	_rebuild_nebula_layer(
		background_nebula_near,
		background_extent,
		BACKGROUND_RANDOM_SEED + 83,
		BACKGROUND_NEBULA_NEAR_CLOUD_COUNT,
		BACKGROUND_NEBULA_NEAR_HEIGHT,
		true
	)
	_rebuild_background_starfield(background_extent)


func _animate_background() -> void:
	if _nebula_extent <= 0.0:
		return

	if background_nebula_far != null:
		var far_drift := _nebula_extent * 0.014
		background_nebula_far.rotation.y = _background_time * 0.009
		background_nebula_far.position = Vector3(
			sin(_background_time * 0.035) * far_drift,
			0.0,
			cos(_background_time * 0.029) * far_drift
		)
		var far_pulse := 1.0 + sin(_background_time * 0.11) * 0.018
		background_nebula_far.scale = Vector3(far_pulse, 1.0, far_pulse)
		var far_material := background_nebula_far.material_override as StandardMaterial3D
		if far_material != null:
			far_material.emission_energy_multiplier = 0.5 + sin(_background_time * 0.18) * 0.035

	if background_nebula_near != null:
		var near_drift := _nebula_extent * 0.021
		background_nebula_near.rotation.y = -_background_time * 0.014
		background_nebula_near.position = Vector3(
			cos(_background_time * 0.031 + 1.7) * near_drift,
			0.0,
			sin(_background_time * 0.037 + 0.8) * near_drift
		)
		var near_pulse := 1.0 + sin(_background_time * 0.15 + 0.9) * 0.024
		background_nebula_near.scale = Vector3(near_pulse, 1.0, near_pulse)
		var near_material := background_nebula_near.material_override as StandardMaterial3D
		if near_material != null:
			near_material.emission_energy_multiplier = 0.68 + sin(_background_time * 0.21 + 0.4) * 0.05

	if background_starfield != null:
		background_starfield.rotation.y = _background_time * 0.0018


func _rebuild_nebula_layer(
	target_layer: MeshInstance3D,
	background_extent: float,
	seed: int,
	cloud_count: int,
	height: float,
	is_near_layer: bool
) -> void:
	if target_layer == null:
		return

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + int(round(background_extent))
	var field_radius := background_extent * (0.54 if is_near_layer else 0.64)
	var cluster_radius := field_radius * (0.42 if is_near_layer else 0.48)
	var cluster_count := 5
	var clusters: Array[Vector2] = []

	for cluster_index in range(cluster_count):
		var cluster_angle := float(cluster_index) * TAU / float(cluster_count) + rng.randf_range(-0.42, 0.42)
		var cluster_distance := field_radius * rng.randf_range(0.12, 0.62)
		clusters.append(Vector2(cos(cluster_angle), sin(cluster_angle)) * cluster_distance)

	for cloud_index in range(cloud_count):
		var cluster := clusters[cloud_index % clusters.size()]
		var center := _get_nebula_cloud_center(rng, cluster, cluster_radius, field_radius)
		var distance_ratio := clampf(center.length() / maxf(field_radius, 1.0), 0.0, 1.0)
		var base_radius := background_extent * rng.randf_range(
			0.06 if is_near_layer else 0.078,
			0.155 if is_near_layer else 0.205
		)
		var aspect := rng.randf_range(0.48, 1.42)
		var radius_x := base_radius * maxf(aspect, 0.74)
		var radius_z := base_radius / maxf(aspect, 0.74)
		var cloud_color := _get_nebula_cloud_color(rng, is_near_layer, distance_ratio)
		var cloud_height := height + rng.randf_range(-32.0, 32.0)
		_append_nebula_puff(
			surface_tool,
			center,
			cloud_height,
			radius_x,
			radius_z,
			rng.randf_range(0.0, TAU),
			cloud_color
		)

	target_layer.mesh = surface_tool.commit()
	target_layer.material_override = _build_background_nebula_material(0.68 if is_near_layer else 0.5)
	target_layer.position = Vector3.ZERO
	target_layer.rotation = Vector3.ZERO
	target_layer.scale = Vector3.ONE


func _rebuild_background_starfield(background_extent: float) -> void:
	if background_starfield == null:
		return

	var star_mesh := SphereMesh.new()
	var star_radius := maxf(background_extent * 0.00042, 2.0)
	star_mesh.radius = star_radius
	star_mesh.height = star_radius * 2.0
	star_mesh.radial_segments = 6
	star_mesh.rings = 4

	var star_material := _build_background_star_material()
	star_mesh.material = star_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = star_mesh
	multimesh.instance_count = BACKGROUND_STAR_COUNT

	var rng := RandomNumberGenerator.new()
	rng.seed = BACKGROUND_RANDOM_SEED + int(round(background_extent))
	var starfield_radius := background_extent * 0.56

	for star_index in range(BACKGROUND_STAR_COUNT):
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = starfield_radius * sqrt(rng.randf())
		if rng.randf() < 0.28:
			radius = starfield_radius * rng.randf_range(0.58, 1.0)

		var star_position := Vector3(
			cos(angle) * radius,
			BACKGROUND_STAR_HEIGHT + rng.randf_range(-150.0, 90.0),
			sin(angle) * radius
		)
		var size_scale: float = rng.randf_range(0.55, 1.55)
		if rng.randf() < 0.08:
			size_scale *= rng.randf_range(1.7, 2.45)

		var basis := Basis().scaled(Vector3.ONE * size_scale)
		multimesh.set_instance_transform(star_index, Transform3D(basis, star_position))
		multimesh.set_instance_color(star_index, _get_background_star_color(rng))

	background_starfield.multimesh = multimesh
	background_starfield.material_override = star_material


func _get_nebula_cloud_center(
	rng: RandomNumberGenerator,
	cluster: Vector2,
	cluster_radius: float,
	field_radius: float
) -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var radius := cluster_radius * sqrt(rng.randf())
	var center := cluster + Vector2(cos(angle), sin(angle)) * radius
	if center.length() > field_radius:
		center = center.normalized() * field_radius * rng.randf_range(0.72, 0.98)
	return center


func _append_nebula_puff(
	surface_tool: SurfaceTool,
	center: Vector2,
	height: float,
	radius_x: float,
	radius_z: float,
	rotation: float,
	color: Color
) -> void:
	var center_color := color
	center_color.a *= 0.94
	var middle_color := color
	middle_color.a *= 0.56
	var edge_color := color
	edge_color.a = 0.0

	for segment_index in range(BACKGROUND_NEBULA_SEGMENTS):
		var next_index := (segment_index + 1) % BACKGROUND_NEBULA_SEGMENTS
		var angle_a := float(segment_index) * TAU / float(BACKGROUND_NEBULA_SEGMENTS)
		var angle_b := float(next_index) * TAU / float(BACKGROUND_NEBULA_SEGMENTS)
		var center_point := Vector3(center.x, height, center.y)
		var mid_a_2d := _get_nebula_ellipse_point(center, radius_x * 0.42, radius_z * 0.42, angle_a, rotation)
		var mid_b_2d := _get_nebula_ellipse_point(center, radius_x * 0.42, radius_z * 0.42, angle_b, rotation)
		var edge_a_2d := _get_nebula_ellipse_point(center, radius_x, radius_z, angle_a, rotation)
		var edge_b_2d := _get_nebula_ellipse_point(center, radius_x, radius_z, angle_b, rotation)
		var mid_a := Vector3(mid_a_2d.x, height, mid_a_2d.y)
		var mid_b := Vector3(mid_b_2d.x, height, mid_b_2d.y)
		var edge_a := Vector3(edge_a_2d.x, height, edge_a_2d.y)
		var edge_b := Vector3(edge_b_2d.x, height, edge_b_2d.y)

		surface_tool.set_color(center_color)
		surface_tool.add_vertex(center_point)
		surface_tool.set_color(middle_color)
		surface_tool.add_vertex(mid_a)
		surface_tool.set_color(middle_color)
		surface_tool.add_vertex(mid_b)

		_append_background_gradient_quad(
			surface_tool,
			mid_a,
			edge_a,
			edge_b,
			mid_b,
			middle_color,
			edge_color,
			edge_color,
			middle_color
		)


func _get_nebula_ellipse_point(
	center: Vector2,
	radius_x: float,
	radius_z: float,
	angle: float,
	rotation: float
) -> Vector2:
	var local := Vector2(cos(angle) * radius_x, sin(angle) * radius_z)
	var cos_rotation := cos(rotation)
	var sin_rotation := sin(rotation)
	return center + Vector2(
		local.x * cos_rotation - local.y * sin_rotation,
		local.x * sin_rotation + local.y * cos_rotation
	)


func _get_nebula_cloud_color(rng: RandomNumberGenerator, is_near_layer: bool, distance_ratio: float) -> Color:
	var palette: Array[Color] = [
		Color(0.24, 0.58, 0.76, 1.0),
		Color(0.54, 0.28, 0.64, 1.0),
		Color(0.3, 0.62, 0.52, 1.0),
		Color(0.82, 0.48, 0.28, 1.0),
		Color(0.45, 0.54, 0.86, 1.0),
	]
	var base_color: Color = palette[rng.randi_range(0, palette.size() - 1)]
	var mix_color: Color = palette[rng.randi_range(0, palette.size() - 1)]
	var color := base_color.lerp(mix_color, rng.randf_range(0.0, 0.38))
	var alpha_base := 0.085 if is_near_layer else 0.063
	color.a = alpha_base * lerpf(1.05, 0.46, distance_ratio) * rng.randf_range(0.72, 1.18)
	return color


func _append_background_gradient_quad(
	surface_tool: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	color_a: Color,
	color_b: Color,
	color_c: Color,
	color_d: Color
) -> void:
	surface_tool.set_color(color_a)
	surface_tool.add_vertex(a)
	surface_tool.set_color(color_b)
	surface_tool.add_vertex(b)
	surface_tool.set_color(color_c)
	surface_tool.add_vertex(c)
	surface_tool.set_color(color_a)
	surface_tool.add_vertex(a)
	surface_tool.set_color(color_c)
	surface_tool.add_vertex(c)
	surface_tool.set_color(color_d)
	surface_tool.add_vertex(d)


func _get_background_star_color(rng: RandomNumberGenerator) -> Color:
	var color_roll := rng.randf()
	var color := Color(0.78, 0.9, 1.0, 1.0)
	if color_roll < 0.18:
		color = Color(1.0, 0.86, 0.58, 1.0)
	elif color_roll < 0.32:
		color = Color(1.0, 0.64, 0.7, 1.0)
	elif color_roll < 0.56:
		color = Color(0.58, 0.86, 1.0, 1.0)
	color.a = rng.randf_range(0.38, 0.86)
	return color


func _build_background_nebula_material(emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = emission_energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material


func _build_background_star_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.2
	return material


func _get_current_system_extent() -> float:
	var extent: float = 0.0
	for system_position in system_positions:
		extent = maxf(extent, Vector2(system_position.x, system_position.z).length())
	return extent
