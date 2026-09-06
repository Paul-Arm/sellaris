extends Node

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 8)
	viewport.disable_3d = true
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(64, 8)
	var material := ShaderMaterial.new()
	material.shader = load("res://tests/map_light_probe.gdshader")
	var bodies := PackedVector4Array()
	var colors := PackedVector4Array()
	bodies.resize(32)
	colors.resize(32)
	bodies[0] = Vector4(0, 0, 2.7, 1)
	colors[0] = Vector4(1, 1, 1, 1)
	material.set_shader_parameter("bodies", bodies)
	material.set_shader_parameter("body_colors", colors)
	material.set_shader_parameter("body_count", 1)
	rect.material = material
	viewport.add_child(rect)
	var data := await _render(viewport)
	for y in range(8):
		var expected := asin(2.7 / (12.0 + y * 4.0)) / PI * 8.0
		var minimum := 1.0
		var maximum := 0.0
		for x in range(64):
			var value := data.get_pixel(x, y).r
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
			assert(absf(value - expected) < 0.008, "Radial energy must match analytic circular emitter")
		assert(maximum - minimum < 0.008, "No directional petals at equal distance")
	print("PASS: 64 angles at eight radii are circular within texture precision")
	bodies[1] = Vector4(7, 0, 2, 0)
	material.set_shader_parameter("bodies", bodies)
	material.set_shader_parameter("body_count", 2)
	data = await _render(viewport)
	assert(data.get_pixel(0, 3).r < 0.005, "Blocker must cast a shadow")
	assert(data.get_pixel(32, 3).r > 0.1, "Opposite side stays illuminated")
	material.set_shader_parameter("body_count", 0)
	data = await _render(viewport)
	assert(data.get_pixel(0, 3).r < 0.005, "Empty map has no light")
	print("PASS: direct-light blocker and empty-map baseline")
	get_tree().quit()

func _render(viewport: SubViewport) -> Image:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
