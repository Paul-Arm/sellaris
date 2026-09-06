extends Node

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.05, 0.12)
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 120
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0, 150, 0), Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	await frames()
	var baseline := viewport.get_texture().get_image()
	var field := GravityFieldMap.new()
	viewport.add_child(field)
	field.configure({"stars": [{"id": "test", "scale": 1.0}], "orbitals": []}, 60)
	await frames()
	var actual := viewport.get_texture().get_image()
	var changed := 0
	var edge_changed := 0
	for y in range(256):
		for x in range(256):
			var difference := actual.get_pixel(x, y) - baseline.get_pixel(x, y)
			if maxf(absf(difference.r), maxf(absf(difference.g), absf(difference.b))) > 0.008:
				changed += 1
				if x < 3 or x > 252 or y < 3 or y > 252: edge_changed += 1
	assert(changed > 500, "Spacetime lines must still be rendered")
	assert(changed < 256 * 256 * 0.4, "Most of the mesh must be fully transparent")
	assert(edge_changed == 0, "No visible rectangular mesh boundary")
	print("PASS: transparent spacetime, visible lines, no mesh boundary; changed pixels: ", changed)
	get_tree().quit()

func frames() -> void:
	for frame in range(6): await get_tree().process_frame
	await RenderingServer.frame_post_draw
