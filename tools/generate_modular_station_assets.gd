extends SceneTree

const OUT_DIR := "res://assets/stations/modular_space_station"

var hull_dark: StandardMaterial3D
var hull_mid: StandardMaterial3D
var hull_light: StandardMaterial3D
var panel_dark: StandardMaterial3D
var glass_cyan: StandardMaterial3D
var dome_glass: StandardMaterial3D
var dome_frame: StandardMaterial3D
var glow_cyan: StandardMaterial3D
var solar_blue: StandardMaterial3D
var accent_gold: StandardMaterial3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_create_materials()

	_save_scene("station_hub_core.tscn", _build_hub_core())
	_save_scene("corridor_segment.tscn", _build_corridor_segment())
	_save_scene("habitation_dome_module.tscn", _build_habitation_dome())
	_save_scene("industrial_tank_cluster.tscn", _build_tank_cluster())
	_save_scene("defense_turret_module.tscn", _build_defense_turret())
	_save_scene("solar_array_module.tscn", _build_solar_array())
	_save_scene("comms_spire_module.tscn", _build_comms_spire())
	_save_scene("station_assembly_showcase.tscn", _build_showcase())

	print("Generated modular station assets in %s" % OUT_DIR)
	quit()


func _create_materials() -> void:
	hull_dark = _material("Hull dark graphite", Color(0.10, 0.13, 0.15), 0.7, 0.42)
	hull_mid = _material("Hull gunmetal", Color(0.23, 0.28, 0.30), 0.62, 0.36)
	hull_light = _material("Hull worn alloy", Color(0.46, 0.50, 0.49), 0.55, 0.31)
	panel_dark = _material("Inset armor panels", Color(0.05, 0.07, 0.08), 0.8, 0.5)
	glass_cyan = _material("Cyan window glass", Color(0.08, 0.75, 0.88), 0.1, 0.14, Color(0.05, 0.9, 1.0), 1.35)
	dome_glass = _material("Layered cyan dome glass", Color(0.04, 0.78, 0.9, 0.52), 0.0, 0.08, Color(0.02, 0.75, 0.95), 0.75)
	dome_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dome_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome_frame = _material("Dome titanium hex frame", Color(0.58, 0.66, 0.66), 0.72, 0.24)
	glow_cyan = _material("Cyan emissive trim", Color(0.02, 0.72, 0.9), 0.0, 0.2, Color(0.05, 0.95, 1.0), 2.5)
	solar_blue = _material("Solar panel blue", Color(0.03, 0.12, 0.24), 0.25, 0.18, Color(0.0, 0.17, 0.32), 0.5)
	accent_gold = _material("Warning brass accent", Color(0.78, 0.53, 0.18), 0.45, 0.28)


func _material(label: String, color: Color, metallic: float, roughness: float, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = label
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


func _build_hub_core() -> Node3D:
	var root := _root("StationHubCore")
	_add_cylinder(root, "octagonal_pressure_hull", 2.0, 2.15, 16, hull_mid, Vector3.ZERO)
	_add_cylinder(root, "upper_armor_ring", 1.68, 0.32, 16, hull_light, Vector3(0, 1.22, 0))
	_add_cylinder(root, "lower_armor_ring", 1.72, 0.3, 16, hull_dark, Vector3(0, -1.2, 0))
	_add_cylinder(root, "command_cap", 0.86, 0.35, 16, hull_dark, Vector3(0, 1.58, 0))
	_add_cylinder(root, "reactor_glow_cap", 0.38, 0.08, 24, glow_cyan, Vector3(0, 1.8, 0))

	for i in range(16):
		var angle := TAU * float(i) / 16.0
		_add_radial_box(root, "window_band_%02d" % i, Vector3(0.42, 0.14, 0.04), 2.03, 0.06, angle, glass_cyan)
		if i % 2 == 0:
			_add_radial_box(root, "armor_inset_%02d" % i, Vector3(0.58, 0.28, 0.05), 2.045, -0.58, angle, panel_dark)
			_add_radial_box(root, "upper_inset_%02d" % i, Vector3(0.48, 0.18, 0.05), 1.78, 0.76, angle, panel_dark)

	for i in range(6):
		var angle := TAU * float(i) / 6.0
		_add_radial_cylinder(root, "docking_tube_%02d" % i, 0.45, 0.95, 18, hull_light, 2.34, 0.0, angle)
		_add_radial_cylinder(root, "docking_collar_%02d" % i, 0.63, 0.26, 18, hull_dark, 2.86, 0.0, angle)
		_add_radial_cylinder(root, "port_glow_%02d" % i, 0.47, 0.04, 18, glow_cyan, 3.02, 0.0, angle)

	for i in range(4):
		var angle := TAU * float(i) / 4.0 + PI / 4.0
		_add_radial_box(root, "vertical_signal_light_%02d" % i, Vector3(0.08, 0.52, 0.045), 1.82, 1.08, angle, glow_cyan)

	return root


func _build_corridor_segment() -> Node3D:
	var root := _root("CorridorSegment")
	_add_cylinder(root, "armored_tunnel", 0.35, 4.2, 16, hull_mid, Vector3.ZERO, Vector3(0, 0, 90))
	_add_cylinder(root, "left_docking_collar", 0.54, 0.32, 18, hull_light, Vector3(-2.23, 0, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "right_docking_collar", 0.54, 0.32, 18, hull_light, Vector3(2.23, 0, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "left_port_glow", 0.39, 0.045, 18, glow_cyan, Vector3(-2.42, 0, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "right_port_glow", 0.39, 0.045, 18, glow_cyan, Vector3(2.42, 0, 0), Vector3(0, 0, 90))

	for x in [-1.35, -0.45, 0.45, 1.35]:
		_add_box(root, "service_panel_top_%s" % str(x), Vector3(0.46, 0.045, 0.16), hull_dark, Vector3(x, 0.36, 0))
		_add_box(root, "cyan_conduit_%s" % str(x), Vector3(0.5, 0.035, 0.05), glow_cyan, Vector3(x, 0.0, 0.36))

	return root


func _build_habitation_dome() -> Node3D:
	var root := _root("HabitationDomeModule")
	_add_cylinder(root, "large_round_habitation_base", 1.66, 0.96, 28, hull_mid, Vector3(0, -0.22, 0))
	_add_sphere(root, "continuous_round_cyan_dome", 1.42, dome_glass, Vector3(0, 0.36, 0), Vector3(1, 0.6, 1))
	_add_cylinder(root, "heavy_equator_armor_ring", 1.74, 0.2, 28, hull_dark, Vector3(0, 0.08, 0))
	_add_cylinder(root, "inner_cyan_equator_glow", 1.48, 0.04, 36, glow_cyan, Vector3(0, 0.26, 0))
	_add_dome_ring_segments(root, "outer_clamp_ring", 1.64, 0.23, 28, 0.06, 0.065, dome_frame)
	_add_surface_hex_grid(root, "primary_dome_hex_lattice", Vector3.ZERO, 1.42, 0.36, 0.6, 0.28, 3)
	_add_cylinder(root, "underside_utility_socket", 0.56, 0.5, 18, hull_light, Vector3(0, -0.98, 0))
	_add_habitat_side_connector(root)

	_add_rim_sub_dome(root, "left_sub_dome", deg_to_rad(140.0), 2.02, 0.3, 0.48)
	_add_rim_sub_dome(root, "right_sub_dome", deg_to_rad(-42.0), 2.0, 0.28, 0.46)

	for i in range(16):
		var angle := TAU * float(i) / 16.0
		if i % 2 == 0:
			_add_radial_box(root, "hab_window_%02d" % i, Vector3(0.32, 0.2, 0.045), 1.68, -0.22, angle, glass_cyan)

	_add_cylinder(root, "short_central_sensor", 0.1, 0.34, 12, glow_cyan, Vector3(0, 1.32, 0))
	return root


func _build_tank_cluster() -> Node3D:
	var root := _root("IndustrialTankCluster")
	var points := [
		Vector3(-0.7, 0, -0.55),
		Vector3(0.7, 0, -0.55),
		Vector3(-0.7, 0, 0.55),
		Vector3(0.7, 0, 0.55),
		Vector3(0, 0, 0),
	]
	for i in range(points.size()):
		_add_cylinder(root, "storage_tank_%02d" % i, 0.42, 1.75, 18, hull_mid, points[i] + Vector3(0, 0.15, 0))
		_add_cylinder(root, "tank_top_cap_%02d" % i, 0.34, 0.08, 18, hull_dark, points[i] + Vector3(0, 1.08, 0))
		_add_cylinder(root, "tank_bottom_cap_%02d" % i, 0.34, 0.08, 18, hull_dark, points[i] + Vector3(0, -0.78, 0))
		_add_box(root, "tank_level_light_%02d" % i, Vector3(0.06, 0.48, 0.035), glow_cyan, points[i] + Vector3(0.42, 0.08, 0))

	_add_cylinder(root, "horizontal_feed_pipe", 0.11, 1.85, 12, hull_light, Vector3(0, -0.42, 0), Vector3(90, 0, 0))
	_add_cylinder(root, "dock_pipe", 0.23, 1.1, 16, hull_light, Vector3(-1.45, -0.08, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "dock_collar", 0.39, 0.18, 16, hull_dark, Vector3(-2.05, -0.08, 0), Vector3(0, 0, 90))
	return root


func _build_defense_turret() -> Node3D:
	var root := _root("DefenseTurretModule")
	_add_cylinder(root, "compact_bastion_hull", 1.05, 1.28, 16, hull_mid, Vector3.ZERO)
	_add_cylinder(root, "port_socket_left", 0.42, 0.5, 18, hull_light, Vector3(-1.15, -0.08, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "port_socket_right", 0.42, 0.5, 18, hull_light, Vector3(1.15, -0.08, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "turret_turntable", 0.42, 0.22, 18, hull_dark, Vector3(0, 0.78, 0))
	_add_box(root, "turret_body", Vector3(0.74, 0.28, 0.46), hull_light, Vector3(0, 1.0, 0))
	_add_cylinder(root, "upper_barrel", 0.055, 1.04, 12, hull_light, Vector3(0.62, 1.06, 0.12), Vector3(0, 0, 90))
	_add_cylinder(root, "lower_barrel", 0.055, 1.04, 12, hull_light, Vector3(0.62, 0.94, -0.12), Vector3(0, 0, 90))
	_add_cylinder(root, "muzzle_glow_upper", 0.07, 0.05, 12, glow_cyan, Vector3(1.18, 1.06, 0.12), Vector3(0, 0, 90))
	_add_cylinder(root, "muzzle_glow_lower", 0.07, 0.05, 12, glow_cyan, Vector3(1.18, 0.94, -0.12), Vector3(0, 0, 90))

	for i in range(8):
		var angle := TAU * float(i) / 8.0
		_add_radial_box(root, "bastion_window_%02d" % i, Vector3(0.22, 0.12, 0.04), 1.07, 0.06, angle, glass_cyan)

	return root


func _build_solar_array() -> Node3D:
	var root := _root("SolarArrayModule")
	_add_cylinder(root, "clear_front_docking_collar", 0.42, 0.36, 18, hull_light, Vector3(-1.28, 0, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "cyan_docking_face", 0.31, 0.04, 18, glow_cyan, Vector3(-1.49, 0, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "central_service_spine", 0.16, 2.75, 14, hull_light, Vector3(0.18, 0, 0), Vector3(0, 0, 90))
	_add_box(root, "offset_equipment_bus", Vector3(0.84, 0.64, 0.72), hull_mid, Vector3(-0.36, 0, 0))
	_add_box(root, "bus_window", Vector3(0.08, 0.22, 0.32), glass_cyan, Vector3(-0.02, 0.14, 0.37))
	_add_cylinder(root, "rear_hinge_joint", 0.28, 0.34, 16, hull_dark, Vector3(1.48, 0, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "panel_crossboom", 0.07, 3.25, 12, hull_light, Vector3(1.62, 0, 0), Vector3(90, 0, 0))

	_add_solar_wing(root, "port", -1.95)
	_add_solar_wing(root, "starboard", 1.95)

	for z in [-1.42, 1.42]:
		_add_beam_3d(root, "diagonal_truss_a_%s" % str(z), Vector3(0.66, 0.05, 0), Vector3(1.12, 0.05, z), 0.045, hull_light)
		_add_beam_3d(root, "diagonal_truss_b_%s" % str(z), Vector3(1.48, 0.05, 0), Vector3(2.06, 0.05, z), 0.045, hull_light)

	return root


func _build_comms_spire() -> Node3D:
	var root := _root("CommsSpireModule")
	_add_cylinder(root, "comms_base", 0.9, 0.72, 16, hull_mid, Vector3(0, -0.16, 0))
	_add_cylinder(root, "antenna_turntable", 0.36, 0.16, 18, hull_dark, Vector3(0, 0.3, 0))
	_add_cylinder(root, "main_spire", 0.035, 1.55, 10, hull_light, Vector3(0, 1.05, 0))
	_add_cylinder(root, "cyan_spire_tip", 0.055, 0.08, 10, glow_cyan, Vector3(0, 1.88, 0))
	_add_cylinder(root, "side_mast_left", 0.026, 1.0, 8, hull_light, Vector3(-0.36, 0.9, 0.08), Vector3(0, 0, -12))
	_add_cylinder(root, "side_mast_right", 0.026, 1.0, 8, hull_light, Vector3(0.36, 0.9, -0.08), Vector3(0, 0, 12))
	_add_box(root, "sensor_dish", Vector3(0.12, 0.66, 0.5), hull_light, Vector3(0.04, 0.63, -0.46), Vector3(0, 18, 0))
	_add_radial_cylinder(root, "lower_docking_collar", 0.42, 0.46, 18, hull_light, 1.04, -0.18, PI)

	for i in range(8):
		var angle := TAU * float(i) / 8.0
		_add_radial_box(root, "comms_status_light_%02d" % i, Vector3(0.16, 0.08, 0.035), 0.91, 0.06, angle, glow_cyan)

	return root


func _build_showcase() -> Node3D:
	var root := _root("StationAssemblyShowcase")
	var hub := _build_hub_core()
	hub.name = "central_hub_core"
	_add_existing(root, hub, Vector3.ZERO)

	_add_existing(root, _build_corridor_segment(), Vector3(4.2, 0, 0))
	_add_existing(root, _build_defense_turret(), Vector3(7.1, 0, 0))
	_add_existing(root, _build_corridor_segment(), Vector3(-4.2, 0, 0), Vector3(0, 180, 0))
	_add_existing(root, _build_habitation_dome(), Vector3(-8.95, 0, 0))
	_add_existing(root, _build_corridor_segment(), Vector3(0, 0, 4.2), Vector3(0, 90, 0))
	_add_existing(root, _build_tank_cluster(), Vector3(0, 0.05, 7.1))
	_add_existing(root, _build_corridor_segment(), Vector3(0, 0, -4.2), Vector3(0, 90, 0))
	_add_existing(root, _build_solar_array(), Vector3(0, 0, -7.0), Vector3(0, 90, 0))
	_add_existing(root, _build_comms_spire(), Vector3(0, 2.25, 0))

	var light := DirectionalLight3D.new()
	light.name = "preview_key_light"
	light.light_energy = 3.0
	light.rotation_degrees = Vector3(-45, 35, 0)
	_add_existing(root, light)

	var fill := OmniLight3D.new()
	fill.name = "cyan_fill_light"
	fill.light_color = Color(0.1, 0.85, 1.0)
	fill.light_energy = 1.2
	fill.omni_range = 8.0
	_add_existing(root, fill, Vector3(0, 3, 2))

	var camera := Camera3D.new()
	camera.name = "preview_camera"
	camera.look_at_from_position(Vector3(7.6, 5.2, 8.4), Vector3.ZERO)
	camera.fov = 42
	_add_existing(root, camera)

	return root


func _root(node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	return root


func _save_scene(file_name: String, root: Node3D) -> void:
	_set_owner_recursive(root, root)
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		push_error("Could not pack %s: %s" % [file_name, error_string(pack_error)])
		return
	var save_error := ResourceSaver.save(packed, "%s/%s" % [OUT_DIR, file_name])
	if save_error != OK:
		push_error("Could not save %s: %s" % [file_name, error_string(save_error)])
	root.free()


func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)


func _add_existing(root: Node3D, node: Node3D, position := Vector3.ZERO, rotation := Vector3.ZERO) -> Node3D:
	root.add_child(node)
	node.owner = root
	node.position = position
	node.rotation_degrees = rotation
	_set_owner_recursive(node, root)
	return node


func _add_box(root: Node3D, node_name: String, size: Vector3, mat: Material, position := Vector3.ZERO, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(root, node_name, mesh, mat, position, rotation)


func _add_cylinder(root: Node3D, node_name: String, radius: float, height: float, segments: int, mat: Material, position := Vector3.ZERO, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return _add_mesh(root, node_name, mesh, mat, position, rotation)


func _add_sphere(root: Node3D, node_name: String, radius: float, mat: Material, position := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var instance := _add_mesh(root, node_name, mesh, mat, position)
	instance.scale = scale
	return instance


func _add_mesh(root: Node3D, node_name: String, mesh: Mesh, mat: Material, position := Vector3.ZERO, rotation := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = position
	instance.rotation_degrees = rotation
	root.add_child(instance)
	instance.owner = root
	return instance


func _add_radial_box(root: Node3D, node_name: String, size: Vector3, radius: float, y: float, angle: float, mat: Material) -> MeshInstance3D:
	var pos := Vector3(cos(angle) * radius, y, sin(angle) * radius)
	var box := _add_box(root, node_name, size, mat, pos)
	box.rotation_degrees = Vector3(0, -rad_to_deg(angle) + 90.0, 0)
	return box


func _add_radial_cylinder(root: Node3D, node_name: String, radius: float, height: float, segments: int, mat: Material, distance: float, y: float, angle: float) -> MeshInstance3D:
	var pos := Vector3(cos(angle) * distance, y, sin(angle) * distance)
	var cylinder := _add_cylinder(root, node_name, radius, height, segments, mat, pos)
	cylinder.rotation_degrees = Vector3(0, -rad_to_deg(angle), 90)
	return cylinder


func _add_solar_wing(root: Node3D, side_name: String, z: float) -> void:
	var center := Vector3(1.95, -0.03, z)
	var panel_size := Vector3(2.75, 0.035, 1.05)
	_add_box(root, "%s_large_solar_blanket" % side_name, panel_size, solar_blue, center)
	_add_box(root, "%s_front_frame" % side_name, Vector3(0.065, 0.075, 1.18), hull_light, center + Vector3(-panel_size.x * 0.5, 0.025, 0))
	_add_box(root, "%s_rear_frame" % side_name, Vector3(0.065, 0.075, 1.18), hull_light, center + Vector3(panel_size.x * 0.5, 0.025, 0))
	_add_box(root, "%s_outer_frame" % side_name, Vector3(2.9, 0.075, 0.065), hull_light, center + Vector3(0, 0.025, sign(z) * panel_size.z * 0.5))
	_add_box(root, "%s_inner_frame" % side_name, Vector3(2.9, 0.075, 0.065), hull_light, center + Vector3(0, 0.025, -sign(z) * panel_size.z * 0.5))
	_add_box(root, "%s_inner_mount_bar" % side_name, Vector3(2.28, 0.075, 0.06), hull_light, Vector3(1.78, 0.04, z - sign(z) * 0.68))

	for x in [1.26, 1.95, 2.64]:
		_add_box(root, "%s_vertical_cell_divider_%s" % [side_name, str(x)], Vector3(0.045, 0.065, 1.04), hull_light, Vector3(x, 0.02, z))
	for offset in [-0.24, 0.24]:
		_add_box(root, "%s_horizontal_cell_divider_%s" % [side_name, str(offset)], Vector3(2.58, 0.062, 0.04), hull_light, Vector3(1.95, 0.02, z + offset))


func _add_habitat_side_connector(root: Node3D) -> void:
	_add_cylinder(root, "habitat_access_neck", 0.34, 1.18, 18, hull_light, Vector3(1.72, -0.02, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "habitat_inner_pressure_collar", 0.5, 0.22, 18, hull_dark, Vector3(1.15, -0.02, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "habitat_outer_docking_collar", 0.58, 0.26, 18, hull_dark, Vector3(2.32, -0.02, 0), Vector3(0, 0, 90))
	_add_cylinder(root, "habitat_docking_glow_face", 0.43, 0.045, 18, glow_cyan, Vector3(2.48, -0.02, 0), Vector3(0, 0, 90))
	_add_box(root, "habitat_top_access_spine", Vector3(1.12, 0.08, 0.12), hull_dark, Vector3(1.74, 0.36, 0))
	_add_box(root, "habitat_bottom_access_spine", Vector3(1.04, 0.08, 0.12), hull_dark, Vector3(1.7, -0.38, 0))
	_add_beam_3d(root, "habitat_upper_left_support", Vector3(1.16, 0.1, -0.34), Vector3(0.86, 0.22, -0.94), 0.055, hull_light)
	_add_beam_3d(root, "habitat_upper_right_support", Vector3(1.16, 0.1, 0.34), Vector3(0.86, 0.22, 0.94), 0.055, hull_light)
	_add_beam_3d(root, "habitat_lower_left_support", Vector3(1.2, -0.28, -0.28), Vector3(0.96, -0.22, -1.02), 0.05, hull_light)
	_add_beam_3d(root, "habitat_lower_right_support", Vector3(1.2, -0.28, 0.28), Vector3(0.96, -0.22, 1.02), 0.05, hull_light)


func _add_surface_hex_grid(root: Node3D, prefix: String, center: Vector3, dome_radius: float, center_y: float, y_scale: float, hex_radius: float, rings: int) -> void:
	var index := 0
	for q in range(-rings, rings + 1):
		for r in range(-rings, rings + 1):
			var s := -q - r
			if max(abs(q), abs(r), abs(s)) > rings:
				continue
			var local_x := hex_radius * 1.5 * float(q)
			var local_z := hex_radius * sqrt(3.0) * (float(r) + float(q) * 0.5)
			if Vector2(local_x, local_z).length() + hex_radius * 0.98 > dome_radius * 0.93:
				continue
			_add_hex_outline_on_dome(root, "%s_%02d" % [prefix, index], center, local_x, local_z, dome_radius, center_y, y_scale, hex_radius * 0.78, 0.022)
			index += 1


func _add_hex_outline_on_dome(root: Node3D, prefix: String, center: Vector3, local_x: float, local_z: float, dome_radius: float, center_y: float, y_scale: float, hex_radius: float, thickness: float) -> void:
	var points: Array[Vector3] = []
	for i in range(6):
		var angle := PI / 6.0 + TAU * float(i) / 6.0
		var vertex_x := local_x + cos(angle) * hex_radius
		var vertex_z := local_z + sin(angle) * hex_radius
		points.append(_dome_surface_point(center, vertex_x, vertex_z, dome_radius, center_y, y_scale))
	for i in range(points.size()):
		_add_beam_3d(root, "%s_edge_%02d" % [prefix, i], points[i], points[(i + 1) % points.size()], thickness, dome_frame)
	var center_point := _dome_surface_point(center, local_x, local_z, dome_radius, center_y, y_scale)
	_add_cylinder(root, "%s_center_glow" % prefix, hex_radius * 0.18, 0.018, 6, glow_cyan, center_point + Vector3(0, 0.015, 0), Vector3(0, 30, 0))


func _dome_surface_point(center: Vector3, local_x: float, local_z: float, dome_radius: float, center_y: float, y_scale: float) -> Vector3:
	var radial_fraction: float = clamp((local_x * local_x + local_z * local_z) / (dome_radius * dome_radius), 0.0, 1.0)
	var y := center_y + dome_radius * y_scale * sqrt(1.0 - radial_fraction)
	return Vector3(center.x + local_x, center.y + y, center.z + local_z)


func _add_sub_dome(root: Node3D, node_name: String, center: Vector3, radius: float, y_scale: float) -> void:
	_add_cylinder(root, "%s_armored_socket" % node_name, radius * 1.24, 0.12, 18, hull_dark, center + Vector3(0, -0.01, 0))
	_add_cylinder(root, "%s_inner_glow_ring" % node_name, radius * 1.02, 0.025, 18, glow_cyan, center + Vector3(0, 0.08, 0))
	_add_sphere(root, "%s_round_glass" % node_name, radius, dome_glass, center + Vector3(0, radius * 0.12, 0), Vector3(1, y_scale, 1))
	_add_surface_hex_grid(root, "%s_hex_lattice" % node_name, center, radius, radius * 0.12, y_scale, radius * 0.33, 1)
	_add_cylinder(root, "%s_sensor_cap" % node_name, radius * 0.18, 0.08, 10, glow_cyan, center + Vector3(0, radius * (y_scale + 0.18), 0))


func _add_rim_sub_dome(root: Node3D, node_name: String, angle: float, distance: float, radius: float, y_scale: float) -> void:
	var direction := Vector3(cos(angle), 0, sin(angle))
	var center := direction * distance + Vector3(0, 0.14, 0)
	var rim_anchor := direction * 1.18 + Vector3(0, 0.13, 0)
	var neck_anchor := direction * (distance - radius * 0.95) + Vector3(0, 0.13, 0)
	_add_beam_3d(root, "%s_external_neck" % node_name, rim_anchor, neck_anchor, 0.105, hull_light)
	_add_cylinder(root, "%s_rim_hardpoint" % node_name, radius * 0.42, 0.08, 12, hull_dark, rim_anchor, Vector3(0, 0, 90))
	_add_sub_dome(root, node_name, center, radius, y_scale)


func _add_beam_3d(root: Node3D, node_name: String, start: Vector3, end: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	var delta := end - start
	var length := delta.length()
	var beam := _add_box(root, node_name, Vector3(length, thickness, thickness), mat, (start + end) * 0.5)
	if length > 0.001:
		beam.basis = Basis(Quaternion(Vector3.RIGHT, delta.normalized()))
	return beam


func _dome_point(radius: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, _dome_y(radius), sin(angle) * radius)


func _dome_y(radius: float) -> float:
	var dome_radius := 1.08
	var height := 0.82
	var base_y := 0.12
	var normalized: float = clamp(radius / dome_radius, 0.0, 1.0)
	return base_y + height * sqrt(1.0 - normalized * normalized)


func _add_hex_pane(root: Node3D, node_name: String, position: Vector3, radius: float) -> void:
	_add_cylinder(root, "%s_frame" % node_name, radius * 1.16, 0.035, 6, dome_frame, position + Vector3(0, 0.014, 0), Vector3(0, 30, 0))
	_add_cylinder(root, "%s_glass" % node_name, radius * 0.88, 0.04, 6, dome_glass, position + Vector3(0, 0.036, 0), Vector3(0, 30, 0))
	_add_cylinder(root, "%s_inner_glow" % node_name, radius * 0.35, 0.045, 6, glow_cyan, position + Vector3(0, 0.06, 0), Vector3(0, 30, 0))


func _add_dome_ring_segments(root: Node3D, prefix: String, radius: float, y: float, count: int, thickness: float, depth: float, mat: Material) -> void:
	var segment_length := TAU * radius / float(count) * 0.86
	for i in range(count):
		var angle := TAU * (float(i) + 0.5) / float(count)
		_add_radial_box(root, "%s_%02d" % [prefix, i], Vector3(segment_length, thickness, depth), radius, y, angle, mat)


func _add_horizontal_beam(root: Node3D, node_name: String, start: Vector3, end: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	var delta := end - start
	var length := Vector2(delta.x, delta.z).length()
	var midpoint := (start + end) * 0.5 + Vector3(0, 0.035, 0)
	var beam := _add_box(root, node_name, Vector3(length, thickness, thickness), mat, midpoint)
	beam.rotation_degrees = Vector3(0, -rad_to_deg(atan2(delta.z, delta.x)), 0)
	return beam
