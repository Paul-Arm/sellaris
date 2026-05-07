extends SceneTree

const GALAXY_GENERATOR_SCRIPT: Script = preload("res://scene/galaxy/GalaxyGenerator.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Galaxy generator name test passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var generator: GalaxyGenerator = GALAXY_GENERATOR_SCRIPT.new()
	var layout := generator.build_layout({
		"seed_text": "galaxy-name-test",
		"star_count": 220,
		"galaxy_radius": 1500.0,
		"min_system_distance": 30.0,
		"shape": GalaxyGenerator.SHAPE_ELLIPTICAL,
		"hyperlane_density": 2,
	}, [])
	var used_names: Dictionary = {}
	var systems: Array = layout.get("systems", [])
	_expect(not systems.is_empty(), "generator should create systems", failures)

	for system_variant in systems:
		var system_record: Dictionary = system_variant
		var system_name := str(system_record.get("name", "")).strip_edges()
		_expect(not system_name.is_empty(), "system should have a readable name", failures)
		_expect(not system_name.begins_with("System "), "procedural system should not use legacy System #### name", failures)
		_expect(not _has_number_suffix(system_name), "system should prefer standalone names over numeric suffixes: %s" % system_name, failures)
		var name_key := system_name.to_lower()
		_expect(not used_names.has(name_key), "system names should be unique: %s" % system_name, failures)
		used_names[name_key] = true


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)


func _has_number_suffix(value: String) -> bool:
	var suffixes := [" II", " III", " IV", " V", " VI", " VII", " VIII", " IX", " X"]
	for suffix in suffixes:
		if value.ends_with(suffix):
			return true
	return false
