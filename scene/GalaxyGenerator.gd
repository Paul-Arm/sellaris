extends RefCounted
class_name GalaxyGenerator

const DEFAULT_STAR_COLORS := [
	Color(0.55, 0.75, 1.0),
	Color(0.67, 0.82, 1.0),
	Color(0.93, 0.94, 1.0),
	Color(1.0, 0.95, 0.82),
	Color(1.0, 0.8, 0.62),
]

const STAR_CLASSES := ["B", "A", "F", "G", "K", "M"]
const SHAPE_SPIRAL := "spiral"
const SHAPE_RING := "ring"
const SHAPE_ELLIPTICAL := "elliptical"
const SHAPE_CLUSTERED := "clustered"


func get_shape_options() -> PackedStringArray:
	return PackedStringArray([SHAPE_SPIRAL, SHAPE_RING, SHAPE_ELLIPTICAL, SHAPE_CLUSTERED])


func build_layout(config: Dictionary, custom_systems: Array[Resource]) -> Dictionary:
	var galaxy_seed: int = _resolve_seed(config.get("seed_text", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = galaxy_seed

	var target_system_count: int = maxi(1, int(config.get("star_count", 900)))
	var galaxy_radius: float = float(config.get("galaxy_radius", 2600.0))
	var min_system_distance: float = float(config.get("min_system_distance", 34.0))
	var shape: String = str(config.get("shape", SHAPE_SPIRAL)).to_lower()
	var spiral_arms: int = maxi(1, int(config.get("spiral_arms", 4)))
	var hyperlane_density: int = clampi(int(config.get("hyperlane_density", 2)), 1, 8)

	var systems: Array[Dictionary] = []
	var grid: Dictionary = {}
	var cell_size: float = min_system_distance
	var custom_count: int = _append_custom_systems(systems, custom_systems, grid, cell_size)
	var procedural_target: int = maxi(0, target_system_count - custom_count)
	var max_attempts: int = maxi(2000, procedural_target * 70)
	var attempt: int = 0

	while systems.size() < target_system_count and attempt < max_attempts:
		attempt += 1
		var position: Vector3 = _sample_position(rng, shape, galaxy_radius, spiral_arms)
		if _has_nearby_system(position, grid, cell_size, min_system_distance):
			continue

		var index: int = systems.size()
		var system_id: String = "sys_%04d" % index
		var record := {
			"id": system_id,
			"name": "System %04d" % (index + 1),
			"position": position,
			"star_color": DEFAULT_STAR_COLORS[rng.randi_range(0, DEFAULT_STAR_COLORS.size() - 1)],
			"is_custom": false,
			"custom_index": -1,
		}
		systems.append(record)
		_add_to_grid(position, grid, cell_size)

	if systems.size() < target_system_count:
		push_warning("Galaxy generator reached the placement limit before hitting the requested system count.")

	var links: Array[Vector2i] = _build_hyperlanes(systems, hyperlane_density)
	return {
		"seed": galaxy_seed,
		"systems": systems,
		"links": links,
		"shape": shape,
		"hyperlane_density": hyperlane_density,
	}


func generate_system_details(galaxy_seed: int, system_record: Dictionary, custom_systems: Array[Resource]) -> Dictionary:
	if bool(system_record.get("is_custom", false)):
		var custom_index: int = int(system_record.get("custom_index", -1))
		if custom_index >= 0 and custom_index < custom_systems.size():
			return _build_custom_system_details(system_record, custom_systems[custom_index])

	var system_id: String = str(system_record.get("id", ""))
	var detail_rng := RandomNumberGenerator.new()
	detail_rng.seed = _combine_seed(galaxy_seed, system_id)

	var star_class_index: int = detail_rng.randi_range(0, STAR_CLASSES.size() - 1)
	var planet_count: int = detail_rng.randi_range(2, 12)
	var habitable_count: int = detail_rng.randi_range(0, mini(3, planet_count))
	var anomaly_risk: float = snapped(detail_rng.randf_range(0.0, 1.0), 0.01)
	var planet_names: PackedStringArray = PackedStringArray()

	for i in range(planet_count):
		planet_names.append("%s-%d" % [system_record.get("name", system_id), i + 1])

	return {
		"id": system_id,
		"name": str(system_record.get("name", system_id)),
		"star_class": STAR_CLASSES[star_class_index],
		"planet_count": planet_count,
		"habitable_worlds": habitable_count,
		"anomaly_risk": anomaly_risk,
		"planet_names": planet_names,
		"is_custom": false,
	}


func _build_custom_system_details(system_record: Dictionary, custom_system: Resource) -> Dictionary:
	var resolved_name: String = str(system_record.get("name", custom_system.system_name))
	var planet_count: int = custom_system.planet_count_override
	if planet_count < 0:
		planet_count = custom_system.planet_names.size()

	return {
		"id": str(system_record.get("id", custom_system.system_id)),
		"name": resolved_name,
		"star_class": custom_system.star_class,
		"planet_count": maxi(planet_count, 0),
		"habitable_worlds": 0,
		"anomaly_risk": 0.0,
		"planet_names": custom_system.planet_names,
		"is_custom": true,
		"notes": custom_system.notes,
	}


func _resolve_seed(seed_text: String) -> int:
	if seed_text.is_empty():
		return int(Time.get_unix_time_from_system() * 1000000.0) + int(Time.get_ticks_usec())
	return seed_text.hash()


func _combine_seed(galaxy_seed: int, system_id: String) -> int:
	return galaxy_seed + system_id.hash() * 31


func _append_custom_systems(systems: Array[Dictionary], custom_systems: Array[Resource], grid: Dictionary, cell_size: float) -> int:
	var added_count: int = 0

	for i in range(custom_systems.size()):
		var custom_system: Resource = custom_systems[i]
		if custom_system == null:
			continue

		var record := {
			"id": custom_system.get_resolved_id(i),
			"name": custom_system.get_resolved_name(i),
			"position": custom_system.position,
			"star_color": custom_system.star_color,
			"is_custom": true,
			"custom_index": i,
		}
		systems.append(record)
		_add_to_grid(custom_system.position, grid, cell_size)
		added_count += 1

	return added_count


func _sample_position(rng: RandomNumberGenerator, shape: String, galaxy_radius: float, spiral_arms: int) -> Vector3:
	match shape:
		SHAPE_RING:
			return _sample_ring_position(rng, galaxy_radius)
		SHAPE_ELLIPTICAL:
			return _sample_elliptical_position(rng, galaxy_radius)
		SHAPE_CLUSTERED:
			return _sample_clustered_position(rng, galaxy_radius)
		_:
			return _sample_spiral_position(rng, galaxy_radius, spiral_arms)


func _sample_spiral_position(rng: RandomNumberGenerator, galaxy_radius: float, spiral_arms: int) -> Vector3:
	var radius_roll: float = pow(rng.randf(), 0.58)
	var radius: float = radius_roll * galaxy_radius
	var arm_index: int = rng.randi_range(0, maxi(spiral_arms - 1, 0))
	var arm_count: float = maxf(float(spiral_arms), 1.0)
	var arm_angle: float = float(arm_index) * TAU / arm_count
	var swirl: float = (radius / galaxy_radius) * 2.6
	var random_scatter: float = rng.randf_range(-0.28, 0.28)
	var angle: float = arm_angle + swirl + random_scatter

	if rng.randf() < 0.25:
		angle = rng.randf_range(0.0, TAU)
		radius *= rng.randf_range(0.15, 0.55)

	var x: float = cos(angle) * radius * rng.randf_range(0.9, 1.1)
	var z: float = sin(angle) * radius
	var y: float = rng.randf_range(-18.0, 18.0)
	return Vector3(x, y, z)


func _sample_ring_position(rng: RandomNumberGenerator, galaxy_radius: float) -> Vector3:
	var angle: float = rng.randf_range(0.0, TAU)
	var radius: float = rng.randf_range(galaxy_radius * 0.45, galaxy_radius * 0.95)
	var thickness: float = rng.randf_range(-galaxy_radius * 0.08, galaxy_radius * 0.08)
	var final_radius: float = radius + thickness
	return Vector3(cos(angle) * final_radius, rng.randf_range(-12.0, 12.0), sin(angle) * final_radius)


func _sample_elliptical_position(rng: RandomNumberGenerator, galaxy_radius: float) -> Vector3:
	var angle: float = rng.randf_range(0.0, TAU)
	var radius: float = sqrt(rng.randf()) * galaxy_radius
	var x: float = cos(angle) * radius * 1.1
	var z: float = sin(angle) * radius * 0.7
	return Vector3(x, rng.randf_range(-24.0, 24.0), z)


func _sample_clustered_position(rng: RandomNumberGenerator, galaxy_radius: float) -> Vector3:
	var cluster_angle: float = rng.randi_range(0, 4) * TAU / 5.0 + rng.randf_range(-0.25, 0.25)
	var cluster_radius: float = galaxy_radius * rng.randf_range(0.18, 0.75)
	var cluster_center := Vector2(cos(cluster_angle), sin(cluster_angle)) * cluster_radius
	var local_angle: float = rng.randf_range(0.0, TAU)
	var local_radius: float = sqrt(rng.randf()) * galaxy_radius * 0.17
	var offset := Vector2(cos(local_angle), sin(local_angle)) * local_radius
	return Vector3(cluster_center.x + offset.x, rng.randf_range(-16.0, 16.0), cluster_center.y + offset.y)


func _has_nearby_system(candidate: Vector3, grid: Dictionary, cell_size: float, min_system_distance: float) -> bool:
	var cell := Vector2i(
		int(floor(candidate.x / cell_size)),
		int(floor(candidate.z / cell_size))
	)
	var min_distance_sq: float = min_system_distance * min_system_distance

	for x_offset in range(-1, 2):
		for y_offset in range(-1, 2):
			var neighbor_cell := Vector2i(cell.x + x_offset, cell.y + y_offset)
			if not grid.has(neighbor_cell):
				continue

			var existing_positions: Array = grid[neighbor_cell]
			for existing_variant in existing_positions:
				var existing: Vector3 = existing_variant
				if candidate.distance_squared_to(existing) < min_distance_sq:
					return true

	return false


func _add_to_grid(position: Vector3, grid: Dictionary, cell_size: float) -> void:
	var cell := Vector2i(
		int(floor(position.x / cell_size)),
		int(floor(position.z / cell_size))
	)
	if not grid.has(cell):
		grid[cell] = []
	var existing_positions: Array = grid[cell]
	existing_positions.append(position)
	grid[cell] = existing_positions


func _build_hyperlanes(systems: Array[Dictionary], density: int) -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	var dedupe: Dictionary = {}

	for i in range(systems.size()):
		var nearest: Array[int] = _find_nearest_neighbors(i, systems, density)
		for neighbor_index in nearest:
			var a: int = mini(i, neighbor_index)
			var b: int = maxi(i, neighbor_index)
			var key: String = "%s:%s" % [a, b]
			if dedupe.has(key):
				continue
			dedupe[key] = true
			links.append(Vector2i(a, b))

	return links


func _find_nearest_neighbors(system_index: int, systems: Array[Dictionary], desired_count: int) -> Array[int]:
	var origin: Vector3 = systems[system_index]["position"]
	var nearest: Array[int] = []
	var nearest_distances: Array[float] = []

	for candidate_index in range(systems.size()):
		if candidate_index == system_index:
			continue

		var distance_sq: float = origin.distance_squared_to(systems[candidate_index]["position"])
		var insert_at: int = nearest_distances.size()

		for i in range(nearest_distances.size()):
			if distance_sq < nearest_distances[i]:
				insert_at = i
				break

		if insert_at < desired_count:
			nearest.insert(insert_at, candidate_index)
			nearest_distances.insert(insert_at, distance_sq)
			if nearest.size() > desired_count:
				nearest.resize(desired_count)
				nearest_distances.resize(desired_count)
		elif nearest.size() < desired_count:
			nearest.append(candidate_index)
			nearest_distances.append(distance_sq)

	return nearest
