extends SceneTree

func _initialize() -> void:
	var theme := load("res://scene/UI/theme/ObservatoryTheme.tres") as Theme
	assert(theme != null)
	assert(theme.has_stylebox("focus", "Button"), "Keyboard focus must remain visible")
	for key in ["corvette", "destroyer", "cruiser", "battleship", "science", "builder", "station", "stellar_station", "collector_station"]:
		var mesh := ObservatoryShipSet.build_mesh(key) as ArrayMesh
		assert(mesh != null and mesh.get_surface_count() == 2, "Hull and light surfaces are required")
		var bounds := mesh.get_aabb()
		assert(bounds.size.x > 0 and bounds.size.y > 0 and bounds.size.z > 0)
		var vertices := 0
		for surface in range(mesh.get_surface_count()):
			vertices += mesh.surface_get_array_len(surface)
			assert(mesh.surface_get_material(surface) != null)
		assert(vertices < 16000, "Models must remain within the fleet instancing budget")
	print("PASS: Observatory theme, all ship silhouettes, material surfaces and geometry budgets")
	quit(0)
