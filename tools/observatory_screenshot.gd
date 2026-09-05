extends Node

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://tools/screenshots")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	SettingsManager.set_design_variant("pastel", false)
	SimClock.pause_sim()
	var menu: Control = load("res://scene/MainMenue/MainUI.tscn").instantiate()
	add_child(menu)
	await _capture("observatory_menu")
	SettingsManager.set_design_variant("clean", false)
	await _capture("clean_menu")
	SettingsManager.set_design_variant("pastel", false)
	menu.call("_show_page", 3)
	await _capture("observatory_lobby")
	menu.queue_free()
	await get_tree().process_frame
	var setup: Control = load("res://scene/GennerateMenue/GennerateMenue.tscn").instantiate()
	add_child(setup)
	await _capture("observatory_setup")
	setup.queue_free()
	await get_tree().process_frame
	var game: Node = load("res://scene/game/GameScene.tscn").instantiate()
	game.configure({"seed_text": "observatory-review", "star_count": 64})
	add_child(game)
	var state: GameSceneState = game.get("_state")
	# Wait for actual generation completion, not a machine-dependent frame count.
	await get_tree().process_frame
	while state.is_generating:
		await get_tree().process_frame
	SimClock.pause_sim()
	await _capture("observatory_galaxy")
	SettingsManager.set_design_variant("clean", false)
	await _capture("clean_galaxy")
	SettingsManager.set_design_variant("pastel", false)
	for record: Dictionary in state.system_records:
		if str(record.get("owner_empire_id", "")) == state.active_empire_id:
			game.get_node("SceneSystems/ViewSystem").call("_on_galaxy_view_open_system_requested", str(record["id"]))
			await _capture("observatory_system")
			SettingsManager.set_design_variant("clean", false)
			await _capture("clean_system")
			SettingsManager.set_design_variant("pastel", false)
			break
	game.queue_free()
	await get_tree().process_frame
	await _capture_design_fixture()
	await _verify_radiance_occlusion()
	await _capture_fleet()
	get_tree().quit(0)

func _capture_fleet() -> void:
	var stage := Node3D.new()
	add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.028, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.78, 0.9)
	environment.ambient_light_energy = 0.65
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.5
	stage.add_child(sun)
	var keys := ["corvette", "destroyer", "cruiser", "battleship", "science", "builder", "station", "stellar_station"]
	for index in range(keys.size()):
		var model := MeshInstance3D.new()
		model.mesh = ObservatoryShipSet.build_mesh(keys[index])
		model.position = Vector3((index % 4 - 1.5) * 6.0, 0, (index / 4) * 6.0 - 3)
		stage.add_child(model)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 25
	camera.look_at_from_position(Vector3(0, 21, 15), Vector3.ZERO)
	camera.current = true
	await _capture("observatory_fleet")
	stage.queue_free()

func _capture(name: String) -> void:
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error := image.save_png("res://tools/screenshots/%s.png" % name)
	assert(error == OK)
	print("CAPTURED: ", name)


func _capture_design_fixture() -> void:
	var view: SystemView = load("res://scene/StarSystem/SystemView.tscn").instantiate()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var details: Dictionary = preload("res://tests/design_variants_test.gd").fixture()
	view.show_system(details, 3)
	await _capture("pastel_binary")
	SettingsManager.set_design_variant("clean", false)
	await _capture("clean_binary")
	var field := view.preview.get_node("Pivot/Bodies/GravityFieldMap") as GravityFieldMap
	assert(field.bake_complete, "Radiance cascade bake must finish")
	for body in field.body_records:
		var anchor := GravityFieldMap.visual_position(body, field.body_records)
		var screen := view.preview.camera.unproject_position(view.preview.pivot.to_global(anchor))
		var picked: SystemSelectableComponent = view.preview.call("_pick_selectable_at_screen_position", screen)
		assert(picked != null and picked.selection_id.ends_with(str(body["id"])), "Visible clean markers must remain clickable")
	var data := field.cascade_views[0].get_texture().get_image()
	var bright := 0
	for y in range(data.get_height()):
		for x in range(data.get_width()):
			var color := data.get_pixel(x, y)
			if color.r > 0.02:
				bright += 1
	assert(bright > 100, "Radiance transport must produce nonzero light away from emitters")
	print("PASS: rendered radiance cascade contains ", bright, " lit directional samples")
	view.queue_free()
	await get_tree().process_frame
	SettingsManager.set_design_variant("pastel", false)


func _verify_radiance_occlusion() -> void:
	var source := {"id": "light", "scale": 1.1, "orbit_radius": 12.0, "orbit_angle": PI}
	var clear_details := {"stars": [source], "orbitals": []}
	var blocked_details := {"stars": [source], "orbitals": [{"id": "blocker", "type": "planet", "size": 10.0, "orbit_radius": 8.0, "orbit_angle": 0.0}]}
	var energy: Array[float] = []
	for details: Dictionary in [clear_details, blocked_details, {"stars": [], "orbitals": []}]:
		var field := GravityFieldMap.new()
		add_child(field)
		field.configure(details, 80.0)
		while not field.bake_complete:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var atlas := field.cascade_views[0].get_texture().get_image()
		# Probe near (32, 0), behind the occluder as seen from the emitter.
		var probe := Vector2i(44, 32)
		var total := 0.0
		for y in range(2):
			for x in range(2):
				total += atlas.get_pixel(probe.x * 2 + x, probe.y * 2 + y).r
		energy.append(total * 0.25)
		field.free()
	assert(energy[0] > 0.005, "A distant emitter must illuminate an empty probe")
	assert(energy[1] < energy[0] * 0.8, "An intervening opaque body must reduce transported light")
	assert(energy[2] < 0.001, "An empty map must produce no radiance")
	print("PASS: GPU radiance transport, occlusion and empty-map baseline: ", energy)
