extends RefCounted
class_name GalaxyGenerator

const SHAPE_SPIRAL := "spiral"
const SHAPE_RING := "ring"
const SHAPE_ELLIPTICAL := "elliptical"
const SHAPE_CLUSTERED := "clustered"
const STAR_COLOR_RED := "Red"
const STAR_COLOR_YELLOW := "Yellow"
const STAR_COLOR_ORANGE := "Orange"
const STAR_COLOR_BLUE := "Blue"
const STAR_SIZE_GIGANT := "Gigant"
const STAR_SIZE_NORMAL := "Normal"
const STAR_SIZE_MEDIUM := "Medium"
const STAR_SIZE_SMALL := "Small"
const STAR_SYSTEM_NORMAL := "normal"
const STAR_SYSTEM_RARE := "rare"
const STAR_SYSTEM_SUPER_RARE := "super_rare"
const SPECIAL_TYPE_NONE := "none"
const SPECIAL_TYPE_NEUTRON := "Neutron star"
const SPECIAL_TYPE_BLACK_HOLE := "Black hole"
const SPECIAL_TYPE_O_CLASS := "O class star"

const STAR_COLOR_MAP := {
	STAR_COLOR_RED: Color(1.0, 0.28, 0.34, 1.0),
	STAR_COLOR_YELLOW: Color(1.0, 0.86, 0.22, 1.0),
	STAR_COLOR_ORANGE: Color(1.0, 0.52, 0.12, 1.0),
	STAR_COLOR_BLUE: Color(0.35, 0.72, 1.0, 1.0),
}

const STAR_SIZE_SCALE_MAP := {
	STAR_SIZE_GIGANT: 2.4,
	STAR_SIZE_NORMAL: 1.3,
	STAR_SIZE_MEDIUM: 1.0,
	STAR_SIZE_SMALL: 0.72,
}

const STAR_CLASS_BY_COLOR := {
	STAR_COLOR_RED: "M",
	STAR_COLOR_ORANGE: "K",
	STAR_COLOR_YELLOW: "G",
	STAR_COLOR_BLUE: "B",
}


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
	var backbone_links: Array[Vector2i] = []
	var cell_size: float = min_system_distance
	var custom_count: int = _append_custom_systems(systems, custom_systems, grid, cell_size, backbone_links)
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
			"is_custom": false,
			"custom_index": -1,
		}
		record["star_profile"] = _build_star_profile(galaxy_seed, record)
		systems.append(record)
		_add_to_grid(position, grid, cell_size)
		_append_backbone_link_for_new_system(systems.size() - 1, systems, backbone_links)

	if systems.size() < target_system_count:
		push_warning("Galaxy generator reached the placement limit before hitting the requested system count.")

	var links: Array[Vector2i] = _build_hyperlanes(systems, hyperlane_density, backbone_links)
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
	var star_profile: Dictionary = system_record.get("star_profile", _build_star_profile(galaxy_seed, system_record))

	var planet_count: int = detail_rng.randi_range(2, 12)
	var habitable_count: int = detail_rng.randi_range(0, mini(3, planet_count))
	var anomaly_risk: float = snapped(detail_rng.randf_range(0.0, 1.0), 0.01)
	var planet_names: PackedStringArray = PackedStringArray()

	for i in range(planet_count):
		planet_names.append("%s-%d" % [system_record.get("name", system_id), i + 1])

	return {
		"id": system_id,
		"name": str(system_record.get("name", system_id)),
		"star_class": star_profile.get("star_class", "G"),
		"star_profile": star_profile,
		"star_count": int(star_profile.get("star_count", 1)),
		"planet_count": planet_count,
		"habitable_worlds": habitable_count,
		"anomaly_risk": anomaly_risk,
		"planet_names": planet_names,
		"is_custom": false,
	}


func _build_custom_system_details(system_record: Dictionary, custom_system: Resource) -> Dictionary:
	var resolved_name: String = str(system_record.get("name", custom_system.system_name))
	var planet_count: int = custom_system.planet_count_override
	var star_profile: Dictionary = system_record.get("star_profile", _build_star_profile(0, system_record))
	if planet_count < 0:
		planet_count = custom_system.planet_names.size()

	return {
		"id": str(system_record.get("id", custom_system.system_id)),
		"name": resolved_name,
		"star_class": custom_system.star_class,
		"star_profile": star_profile,
		"star_count": int(star_profile.get("star_count", 1)),
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


func _append_custom_systems(systems: Array[Dictionary], custom_systems: Array[Resource], grid: Dictionary, cell_size: float, backbone_links: Array[Vector2i]) -> int:
	var added_count: int = 0

	for i in range(custom_systems.size()):
		var custom_system: Resource = custom_systems[i]
		if custom_system == null:
			continue

		var record := {
			"id": custom_system.get_resolved_id(i),
			"name": custom_system.get_resolved_name(i),
			"position": custom_system.position,
			"is_custom": true,
			"custom_index": i,
		}
		record["star_profile"] = _build_custom_star_profile(custom_system)
		systems.append(record)
		_add_to_grid(custom_system.position, grid, cell_size)
		_append_backbone_link_for_new_system(systems.size() - 1, systems, backbone_links)
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


func _build_hyperlanes(systems: Array[Dictionary], density: int, backbone_links: Array[Vector2i]) -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	var dedupe: Dictionary = {}
	if systems.size() <= 1:
		return links

	for backbone_link in backbone_links:
		_add_hyperlane_link(backbone_link.x, backbone_link.y, links, dedupe)

	for i in range(systems.size()):
		var nearest: Array[int] = _find_nearest_neighbors(i, systems, density)
		for neighbor_index in nearest:
			_add_hyperlane_link(i, neighbor_index, links, dedupe)

	return links


func _append_backbone_link_for_new_system(system_index: int, systems: Array[Dictionary], backbone_links: Array[Vector2i]) -> void:
	if system_index <= 0:
		return

	var nearest_index := _find_nearest_existing_system_index(system_index, systems)
	if nearest_index >= 0:
		backbone_links.append(Vector2i(system_index, nearest_index))


func _add_hyperlane_link(a_index: int, b_index: int, links: Array[Vector2i], dedupe: Dictionary) -> void:
	if a_index == b_index:
		return

	var a: int = mini(a_index, b_index)
	var b: int = maxi(a_index, b_index)
	var key: String = "%s:%s" % [a, b]
	if dedupe.has(key):
		return

	dedupe[key] = true
	links.append(Vector2i(a, b))


func _find_nearest_existing_system_index(system_index: int, systems: Array[Dictionary]) -> int:
	var origin: Vector3 = systems[system_index]["position"]
	var best_index := -1
	var best_distance_sq := INF

	for candidate_index in range(system_index):
		var candidate_position: Vector3 = systems[candidate_index]["position"]
		var distance_sq := origin.distance_squared_to(candidate_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = candidate_index

	return best_index


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


func _build_star_profile(galaxy_seed: int, system_record: Dictionary) -> Dictionary:
	var system_id: String = str(system_record.get("id", ""))
	var star_rng := RandomNumberGenerator.new()
	star_rng.seed = _combine_seed(galaxy_seed, "%s:star_profile" % system_id)

	var system_type := STAR_SYSTEM_NORMAL
	var star_count := 1
	var rarity_roll := star_rng.randf()
	if rarity_roll < 0.01:
		system_type = STAR_SYSTEM_SUPER_RARE
		star_count = 3
	elif rarity_roll < 0.1:
		system_type = STAR_SYSTEM_RARE
		star_count = 2

	var special_type := SPECIAL_TYPE_NONE
	var special_roll := star_rng.randf()
	if special_roll < 0.003:
		special_type = SPECIAL_TYPE_O_CLASS
	elif special_roll < 0.015:
		special_type = SPECIAL_TYPE_BLACK_HOLE
	elif special_roll < 0.045:
		special_type = SPECIAL_TYPE_NEUTRON

	var primary_color_name := _pick_star_color_name(star_rng)
	var primary_size_name := _pick_star_size_name(star_rng)
	var primary_color: Color = STAR_COLOR_MAP[primary_color_name]
	var primary_star_class: String = STAR_CLASS_BY_COLOR[primary_color_name]

	match special_type:
		SPECIAL_TYPE_NEUTRON:
			primary_color_name = STAR_COLOR_BLUE
			primary_color = Color(0.52, 0.86, 1.0, 1.0)
			primary_size_name = STAR_SIZE_SMALL
			primary_star_class = "Neutron"
		SPECIAL_TYPE_BLACK_HOLE:
			primary_color_name = "Void"
			primary_color = Color(0.18, 0.2, 0.28, 1.0)
			primary_size_name = STAR_SIZE_GIGANT
			primary_star_class = "Black Hole"
		SPECIAL_TYPE_O_CLASS:
			primary_color_name = STAR_COLOR_BLUE
			primary_color = Color(0.42, 0.78, 1.0, 1.0)
			primary_size_name = STAR_SIZE_GIGANT
			primary_star_class = "O"

	var stars: Array[Dictionary] = []
	stars.append({
		"index": 0,
		"color_name": primary_color_name,
		"color": primary_color,
		"size_name": primary_size_name,
		"scale": STAR_SIZE_SCALE_MAP[primary_size_name],
		"is_primary": true,
		"special_type": special_type,
		"star_class": primary_star_class,
	})

	for i in range(1, star_count):
		var companion_color_name := _pick_star_color_name(star_rng)
		var companion_size_name := _pick_star_size_name(star_rng)
		stars.append({
			"index": i,
			"color_name": companion_color_name,
			"color": STAR_COLOR_MAP[companion_color_name],
			"size_name": companion_size_name,
			"scale": STAR_SIZE_SCALE_MAP[companion_size_name] * star_rng.randf_range(0.7, 0.95),
			"is_primary": false,
			"special_type": SPECIAL_TYPE_NONE,
			"star_class": STAR_CLASS_BY_COLOR[companion_color_name],
		})

	return {
		"system_type": system_type,
		"star_count": star_count,
		"special_type": special_type,
		"display_color": primary_color,
		"primary_color_name": primary_color_name,
		"primary_size_name": primary_size_name,
		"star_class": primary_star_class,
		"stars": stars,
	}


func _build_custom_star_profile(custom_system: Resource) -> Dictionary:
	var custom_color_name := _closest_star_color_name(custom_system.star_color)
	var stars: Array[Dictionary] = [{
		"index": 0,
		"color_name": custom_color_name,
		"color": custom_system.star_color,
		"size_name": STAR_SIZE_NORMAL,
		"scale": STAR_SIZE_SCALE_MAP[STAR_SIZE_NORMAL],
		"is_primary": true,
		"special_type": SPECIAL_TYPE_NONE,
		"star_class": custom_system.star_class,
	}]

	return {
		"system_type": STAR_SYSTEM_NORMAL,
		"star_count": 1,
		"special_type": SPECIAL_TYPE_NONE,
		"display_color": custom_system.star_color,
		"primary_color_name": custom_color_name,
		"primary_size_name": STAR_SIZE_NORMAL,
		"star_class": custom_system.star_class,
		"stars": stars,
	}


func _pick_star_color_name(star_rng: RandomNumberGenerator) -> String:
	var roll := star_rng.randf()
	if roll < 0.2:
		return STAR_COLOR_BLUE
	if roll < 0.42:
		return STAR_COLOR_YELLOW
	if roll < 0.68:
		return STAR_COLOR_ORANGE
	return STAR_COLOR_RED


func _pick_star_size_name(star_rng: RandomNumberGenerator) -> String:
	var roll := star_rng.randf()
	if roll < 0.08:
		return STAR_SIZE_GIGANT
	if roll < 0.4:
		return STAR_SIZE_NORMAL
	if roll < 0.75:
		return STAR_SIZE_MEDIUM
	return STAR_SIZE_SMALL


func _closest_star_color_name(target_color: Color) -> String:
	var best_name := STAR_COLOR_YELLOW
	var best_distance := INF

	for color_name in STAR_COLOR_MAP.keys():
		var candidate: Color = STAR_COLOR_MAP[color_name]
		var distance := absf(candidate.r - target_color.r) + absf(candidate.g - target_color.g) + absf(candidate.b - target_color.b)
		if distance < best_distance:
			best_distance = distance
			best_name = color_name

	return best_name
