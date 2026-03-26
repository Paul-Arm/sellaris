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
const ORBITAL_TYPE_PLANET := "planet"
const ORBITAL_TYPE_ASTEROID_BELT := "asteroid_belt"
const ORBITAL_TYPE_STRUCTURE := "structure"
const ORBITAL_TYPE_RUIN := "ruin"
const PLANET_COLOR_PALETTE := [
	Color(0.52, 0.67, 0.95, 1.0),
	Color(0.82, 0.61, 0.4, 1.0),
	Color(0.74, 0.8, 0.42, 1.0),
	Color(0.64, 0.58, 0.88, 1.0),
	Color(0.86, 0.48, 0.38, 1.0),
	Color(0.56, 0.76, 0.72, 1.0),
]
const ASTEROID_BELT_COLOR := Color(0.6, 0.58, 0.54, 1.0)
const STRUCTURE_COLOR := Color(0.42, 0.8, 1.0, 1.0)
const RUIN_COLOR := Color(0.72, 0.73, 0.78, 1.0)
const MIN_HYPERLANES_PER_SYSTEM := 2
const MAX_HYPERLANES_PER_SYSTEM := 5
const EXTRA_HYPERLANE_CANDIDATES := 6
const HYPERLANE_DISTANCE_FACTOR_BASE := 2.35
const HYPERLANE_DISTANCE_FACTOR_PER_DENSITY := 0.22
const SYSTEM_SPREAD_DISTANCE_FACTOR := 1.18
const SYSTEM_SPREAD_RADIUS_FACTOR := 1.1


func get_shape_options() -> PackedStringArray:
	return PackedStringArray([SHAPE_SPIRAL, SHAPE_RING, SHAPE_ELLIPTICAL, SHAPE_CLUSTERED])


func build_layout(config: Dictionary, custom_systems: Array[Resource]) -> Dictionary:
	var galaxy_seed: int = _resolve_seed(config.get("seed_text", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = galaxy_seed

	var target_system_count: int = maxi(1, int(config.get("star_count", 900)))
	var galaxy_radius: float = float(config.get("galaxy_radius", 3000.0)) * SYSTEM_SPREAD_RADIUS_FACTOR
	var min_system_distance: float = float(config.get("min_system_distance", 44.0)) * SYSTEM_SPREAD_DISTANCE_FACTOR
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
			"is_custom": false,
			"custom_index": -1,
		}
		record["star_profile"] = _build_star_profile(galaxy_seed, record)
		record["system_summary"] = build_system_summary(galaxy_seed, record, custom_systems)
		systems.append(record)
		_add_to_grid(position, grid, cell_size)

	if systems.size() < target_system_count:
		push_warning("Galaxy generator reached the placement limit before hitting the requested system count.")

	var hyperlane_graph := build_hyperlane_graph(systems, hyperlane_density)
	return {
		"seed": galaxy_seed,
		"systems": systems,
		"links": hyperlane_graph["links"],
		"hyperlane_graph": hyperlane_graph,
		"galaxy_radius": galaxy_radius,
		"min_system_distance": min_system_distance,
		"shape": shape,
		"hyperlane_density": hyperlane_density,
	}


func build_system_summary(
	galaxy_seed: int,
	system_record: Dictionary,
	custom_systems: Array[Resource],
	detail_override: Dictionary = {}
) -> Dictionary:
	var details: Dictionary = generate_system_details(galaxy_seed, system_record, custom_systems, detail_override)
	return details.get("system_summary", {}).duplicate(true)


func generate_system_details(
	galaxy_seed: int,
	system_record: Dictionary,
	custom_systems: Array[Resource],
	detail_override: Dictionary = {}
) -> Dictionary:
	var details: Dictionary = {}
	if bool(system_record.get("is_custom", false)):
		var custom_index: int = int(system_record.get("custom_index", -1))
		if custom_index >= 0 and custom_index < custom_systems.size():
			details = _build_custom_system_details(system_record, custom_systems[custom_index])
		else:
			details = _build_procedural_system_details(galaxy_seed, system_record)
	else:
		details = _build_procedural_system_details(galaxy_seed, system_record)

	if not detail_override.is_empty():
		return apply_system_detail_patch(details, detail_override)
	return _finalize_system_details(details)


func _build_custom_system_details(system_record: Dictionary, custom_system: Resource) -> Dictionary:
	var resolved_id: String = str(system_record.get("id", custom_system.system_id))
	var resolved_name: String = str(system_record.get("name", custom_system.system_name))
	var details := {
		"id": resolved_id,
		"name": resolved_name,
		"seed": 0,
		"star_class": custom_system.star_class,
		"star_profile": system_record.get("star_profile", _build_custom_star_profile(custom_system)),
		"stars": custom_system.build_star_entries(),
		"orbitals": custom_system.build_orbital_entries(resolved_name),
		"is_custom": true,
		"notes": custom_system.notes,
	}
	return _finalize_system_details(details)


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
			"is_custom": true,
			"custom_index": i,
		}
		var custom_details: Dictionary = _build_custom_system_details(record, custom_system)
		record["star_profile"] = custom_details.get("star_profile", _build_custom_star_profile(custom_system))
		record["system_summary"] = custom_details.get("system_summary", build_system_summary_from_details(custom_details))
		systems.append(record)
		_add_to_grid(custom_system.position, grid, cell_size)
		added_count += 1

	return added_count


func _build_procedural_system_details(galaxy_seed: int, system_record: Dictionary) -> Dictionary:
	var system_id: String = str(system_record.get("id", ""))
	var resolved_name: String = str(system_record.get("name", system_id))
	var detail_rng := RandomNumberGenerator.new()
	detail_rng.seed = _combine_seed(galaxy_seed, "%s:system_details" % system_id)

	var star_profile: Dictionary = system_record.get("star_profile", _build_star_profile(galaxy_seed, system_record))
	var stars: Array = _build_detail_stars_from_profile(star_profile, detail_rng, resolved_name)
	var special_type: String = str(star_profile.get("special_type", SPECIAL_TYPE_NONE))
	var orbitals: Array = []
	var occupied_orbits: Array = []
	var planet_count: int = detail_rng.randi_range(2, 12)

	if special_type == SPECIAL_TYPE_BLACK_HOLE:
		planet_count = clampi(planet_count - 2, 0, 9)
	elif special_type == SPECIAL_TYPE_NEUTRON:
		planet_count = clampi(planet_count - 1, 1, 10)

	var habitable_target: int = 0
	if planet_count > 0:
		habitable_target = detail_rng.randi_range(0, mini(3, planet_count))
	var habitable_indices: Dictionary = _pick_unique_index_map(detail_rng, planet_count, habitable_target)

	var colonizable_target: int = habitable_target
	if planet_count > colonizable_target and detail_rng.randf() < 0.42:
		colonizable_target += 1
	var colonizable_indices: Dictionary = habitable_indices.duplicate()
	for colonizable_index in _pick_additional_unique_indices(detail_rng, planet_count, colonizable_target, colonizable_indices):
		colonizable_indices[colonizable_index] = true

	var current_orbit: float = _get_initial_orbit_radius(stars)
	for planet_index in range(planet_count):
		current_orbit += detail_rng.randf_range(11.0, 19.0)
		occupied_orbits.append(current_orbit)
		var is_habitable := habitable_indices.has(planet_index)
		var is_colonizable := colonizable_indices.has(planet_index)
		var planet_color: Color = PLANET_COLOR_PALETTE[detail_rng.randi_range(0, PLANET_COLOR_PALETTE.size() - 1)]
		if is_habitable:
			planet_color = planet_color.lerp(Color(0.46, 0.92, 0.56, 1.0), 0.28)
		elif is_colonizable:
			planet_color = planet_color.lerp(Color(0.74, 0.86, 0.54, 1.0), 0.18)

		orbitals.append({
			"id": "planet_%02d" % planet_index,
			"name": "%s %s" % [resolved_name, _to_roman(planet_index + 1)],
			"type": ORBITAL_TYPE_PLANET,
			"orbit_radius": current_orbit,
			"orbit_angle": detail_rng.randf_range(0.0, TAU),
			"vertical_offset": detail_rng.randf_range(-1.8, 1.8),
			"size": detail_rng.randf_range(1.0, 3.9),
			"color": planet_color,
			"orbit_width": 0.0,
			"is_colonizable": is_colonizable,
			"habitability": 0.76 if is_habitable else (0.48 if is_colonizable else snapped(detail_rng.randf_range(0.0, 0.28), 0.01)),
			"resource_richness": snapped(detail_rng.randf_range(0.1, 1.0), 0.01),
			"metadata": {},
		})

	if planet_count > 0 and detail_rng.randf() < 0.68:
		var asteroid_belt_count: int = detail_rng.randi_range(1, 2)
		if special_type == SPECIAL_TYPE_BLACK_HOLE:
			asteroid_belt_count = maxi(asteroid_belt_count, 1)
		for belt_index in range(asteroid_belt_count):
			var belt_radius := _find_open_orbit_radius(
				detail_rng,
				occupied_orbits,
				_get_initial_orbit_radius(stars) + 8.0,
				maxf(current_orbit + 30.0, 64.0),
				9.0
			)
			occupied_orbits.append(belt_radius)
			orbitals.append({
				"id": "belt_%02d" % belt_index,
				"name": "%s Belt %d" % [resolved_name, belt_index + 1],
				"type": ORBITAL_TYPE_ASTEROID_BELT,
				"orbit_radius": belt_radius,
				"orbit_angle": detail_rng.randf_range(0.0, TAU),
				"vertical_offset": detail_rng.randf_range(-0.8, 0.8),
				"size": detail_rng.randf_range(1.0, 1.5),
				"color": ASTEROID_BELT_COLOR,
				"orbit_width": detail_rng.randf_range(8.0, 18.0),
				"is_colonizable": false,
				"habitability": 0.0,
				"resource_richness": snapped(detail_rng.randf_range(0.35, 1.0), 0.01),
				"metadata": {},
			})

	var structure_count: int = detail_rng.randi_range(0, 2)
	if detail_rng.randf() < 0.2:
		structure_count += 1
	for structure_index in range(structure_count):
		var structure_radius := _find_open_orbit_radius(
			detail_rng,
			occupied_orbits,
			_get_initial_orbit_radius(stars) + 6.0,
			maxf(current_orbit + 18.0, 54.0),
			6.5
		)
		occupied_orbits.append(structure_radius)
		orbitals.append({
			"id": "structure_%02d" % structure_index,
			"name": "%s Relay %d" % [resolved_name, structure_index + 1],
			"type": ORBITAL_TYPE_STRUCTURE,
			"orbit_radius": structure_radius,
			"orbit_angle": detail_rng.randf_range(0.0, TAU),
			"vertical_offset": detail_rng.randf_range(-2.2, 2.2),
			"size": detail_rng.randf_range(0.8, 1.45),
			"color": STRUCTURE_COLOR,
			"orbit_width": 0.0,
			"is_colonizable": false,
			"habitability": 0.0,
			"resource_richness": snapped(detail_rng.randf_range(0.2, 0.85), 0.01),
			"metadata": {},
		})

	var ruin_count: int = 0
	if detail_rng.randf() < 0.38:
		ruin_count = detail_rng.randi_range(1, 2)
	for ruin_index in range(ruin_count):
		var ruin_radius := _find_open_orbit_radius(
			detail_rng,
			occupied_orbits,
			_get_initial_orbit_radius(stars) + 6.0,
			maxf(current_orbit + 12.0, 50.0),
			6.0
		)
		occupied_orbits.append(ruin_radius)
		orbitals.append({
			"id": "ruin_%02d" % ruin_index,
			"name": "%s Ruin %d" % [resolved_name, ruin_index + 1],
			"type": ORBITAL_TYPE_RUIN,
			"orbit_radius": ruin_radius,
			"orbit_angle": detail_rng.randf_range(0.0, TAU),
			"vertical_offset": detail_rng.randf_range(-2.4, 2.4),
			"size": detail_rng.randf_range(0.85, 1.55),
			"color": RUIN_COLOR,
			"orbit_width": 0.0,
			"is_colonizable": false,
			"habitability": 0.0,
			"resource_richness": snapped(detail_rng.randf_range(0.15, 0.92), 0.01),
			"metadata": {},
		})

	var anomaly_risk: float = snapped(
		clampf(
			0.08
			+ float(ruin_count) * 0.18
			+ float(structure_count) * 0.04
			+ float(_count_entries_of_type(orbitals, ORBITAL_TYPE_ASTEROID_BELT)) * 0.05
			+ (0.16 if special_type != SPECIAL_TYPE_NONE else 0.0)
			+ detail_rng.randf_range(0.0, 0.2),
			0.0,
			1.0
		),
		0.01
	)

	return {
		"id": system_id,
		"name": resolved_name,
		"seed": _combine_seed(galaxy_seed, "%s:system_details" % system_id),
		"star_class": star_profile.get("star_class", "G"),
		"star_profile": star_profile,
		"stars": stars,
		"orbitals": orbitals,
		"is_custom": false,
		"anomaly_risk": anomaly_risk,
	}


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


func build_hyperlane_graph(systems: Array[Dictionary], density: int) -> Dictionary:
	var links: Array[Vector2i] = _build_hyperlanes(systems, density)
	return {
		"links": links,
		"adjacency": build_hyperlane_adjacency(systems.size(), links),
		"min_links_per_system": mini(MIN_HYPERLANES_PER_SYSTEM, maxi(systems.size() - 1, 0)),
		"max_links_per_system": mini(MAX_HYPERLANES_PER_SYSTEM, maxi(systems.size() - 1, 0)),
		"target_links_per_system": mini(clampi(density + 1, MIN_HYPERLANES_PER_SYSTEM, MAX_HYPERLANES_PER_SYSTEM), maxi(systems.size() - 1, 0)),
	}


func build_hyperlane_adjacency(system_count: int, links: Array[Vector2i]) -> Dictionary:
	var adjacency: Dictionary = {}
	for system_index in range(system_count):
		adjacency[system_index] = []

	for link in links:
		var a_neighbors: Array = adjacency.get(link.x, [])
		a_neighbors.append(link.y)
		adjacency[link.x] = a_neighbors

		var b_neighbors: Array = adjacency.get(link.y, [])
		b_neighbors.append(link.x)
		adjacency[link.y] = b_neighbors

	return adjacency


func _build_hyperlanes(systems: Array[Dictionary], density: int) -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	var dedupe: Dictionary = {}
	if systems.size() <= 1:
		return links

	var target_links := mini(clampi(density + 1, MIN_HYPERLANES_PER_SYSTEM, MAX_HYPERLANES_PER_SYSTEM), systems.size() - 1)
	var min_links := mini(MIN_HYPERLANES_PER_SYSTEM, systems.size() - 1)
	var max_links := mini(MAX_HYPERLANES_PER_SYSTEM, systems.size() - 1)
	var candidate_count := mini(max_links + EXTRA_HYPERLANE_CANDIDATES, systems.size() - 1)
	var neighbor_cache: Array = []
	var nearest_distance_sq: Array[float] = []
	var candidate_edges: Array = []

	for system_index in range(systems.size()):
		var nearest: Array[int] = _find_nearest_neighbors(system_index, systems, candidate_count)
		neighbor_cache.append(nearest)
		if nearest.is_empty():
			nearest_distance_sq.append(INF)
		else:
			var nearest_position: Vector3 = systems[nearest[0]]["position"]
			nearest_distance_sq.append(systems[system_index]["position"].distance_squared_to(nearest_position))

	var edge_dedupe: Dictionary = {}
	for system_index in range(systems.size()):
		var cached_neighbors: Array = neighbor_cache[system_index]
		for neighbor_index_variant in cached_neighbors:
			var neighbor_index: int = int(neighbor_index_variant)
			var a: int = mini(system_index, neighbor_index)
			var b: int = maxi(system_index, neighbor_index)
			var edge_key: String = "%s:%s" % [a, b]
			if edge_dedupe.has(edge_key):
				continue

			var distance_sq: float = systems[a]["position"].distance_squared_to(systems[b]["position"])
			if not _is_hyperlane_distance_allowed(a, b, distance_sq, nearest_distance_sq, density):
				continue

			edge_dedupe[edge_key] = true
			candidate_edges.append({
				"a": a,
				"b": b,
				"distance_sq": distance_sq,
			})

	candidate_edges.sort_custom(_sort_hyperlane_edges_by_distance)
	var parent: Array[int] = []
	var rank: Array[int] = []
	var degrees: Array[int] = []
	parent.resize(systems.size())
	rank.resize(systems.size())
	degrees.resize(systems.size())
	for system_index in range(systems.size()):
		parent[system_index] = system_index
		rank[system_index] = 0
		degrees[system_index] = 0

	# Backbone: shortest nearby edges first, so the graph stays connected without weird long jumps.
	for edge_variant in candidate_edges:
		var edge: Dictionary = edge_variant
		var a_index: int = edge["a"]
		var b_index: int = edge["b"]
		if _uf_find(parent, a_index) == _uf_find(parent, b_index):
			continue

		_add_hyperlane_link(a_index, b_index, links, dedupe)
		degrees[a_index] += 1
		degrees[b_index] += 1
		_uf_union(parent, rank, a_index, b_index)

	if links.size() < systems.size() - 1:
		_connect_remaining_components(systems, links, dedupe, parent, rank, degrees)

	# Fill sparse systems first so most systems land in the 2-5 link range.
	for edge_variant in candidate_edges:
		var edge: Dictionary = edge_variant
		var a_index: int = edge["a"]
		var b_index: int = edge["b"]
		if degrees[a_index] >= max_links or degrees[b_index] >= max_links:
			continue
		if degrees[a_index] >= min_links and degrees[b_index] >= min_links:
			continue
		if _add_hyperlane_link(a_index, b_index, links, dedupe):
			degrees[a_index] += 1
			degrees[b_index] += 1

	# Then add a few more local links for richer travel choices, still respecting the distance cap.
	for edge_variant in candidate_edges:
		var edge: Dictionary = edge_variant
		var a_index: int = edge["a"]
		var b_index: int = edge["b"]
		if degrees[a_index] >= max_links or degrees[b_index] >= max_links:
			continue
		if degrees[a_index] >= target_links and degrees[b_index] >= target_links:
			continue
		if _add_hyperlane_link(a_index, b_index, links, dedupe):
			degrees[a_index] += 1
			degrees[b_index] += 1

	return links


func _add_hyperlane_link(a_index: int, b_index: int, links: Array[Vector2i], dedupe: Dictionary) -> bool:
	if a_index == b_index:
		return false

	var a: int = mini(a_index, b_index)
	var b: int = maxi(a_index, b_index)
	var key: String = "%s:%s" % [a, b]
	if dedupe.has(key):
		return false

	dedupe[key] = true
	links.append(Vector2i(a, b))
	return true


func _sort_hyperlane_edges_by_distance(a: Dictionary, b: Dictionary) -> bool:
	return float(a["distance_sq"]) < float(b["distance_sq"])


func _uf_find(parent: Array[int], index: int) -> int:
	if parent[index] != index:
		parent[index] = _uf_find(parent, parent[index])
	return parent[index]


func _uf_union(parent: Array[int], rank: Array[int], a_index: int, b_index: int) -> void:
	var root_a := _uf_find(parent, a_index)
	var root_b := _uf_find(parent, b_index)
	if root_a == root_b:
		return

	if rank[root_a] < rank[root_b]:
		parent[root_a] = root_b
	elif rank[root_a] > rank[root_b]:
		parent[root_b] = root_a
	else:
		parent[root_b] = root_a
		rank[root_a] += 1


func _is_hyperlane_distance_allowed(a_index: int, b_index: int, distance_sq: float, nearest_distance_sq: Array[float], density: int) -> bool:
	var distance_factor := HYPERLANE_DISTANCE_FACTOR_BASE + float(density - 1) * HYPERLANE_DISTANCE_FACTOR_PER_DENSITY
	var a_reference := nearest_distance_sq[a_index]
	var b_reference := nearest_distance_sq[b_index]

	if is_inf(a_reference) or is_inf(b_reference):
		return true

	var max_allowed_sq := maxf(a_reference, b_reference) * distance_factor * distance_factor
	return distance_sq <= max_allowed_sq


func _connect_remaining_components(systems: Array[Dictionary], links: Array[Vector2i], dedupe: Dictionary, parent: Array[int], rank: Array[int], degrees: Array[int]) -> void:
	while links.size() < systems.size() - 1:
		var best_a := -1
		var best_b := -1
		var best_distance_sq := INF

		for a_index in range(systems.size()):
			var a_root := _uf_find(parent, a_index)
			for b_index in range(a_index + 1, systems.size()):
				if a_root == _uf_find(parent, b_index):
					continue

				var distance_sq: float = systems[a_index]["position"].distance_squared_to(systems[b_index]["position"])
				if distance_sq < best_distance_sq:
					best_distance_sq = distance_sq
					best_a = a_index
					best_b = b_index

		if best_a == -1:
			break

		if _add_hyperlane_link(best_a, best_b, links, dedupe):
			degrees[best_a] += 1
			degrees[best_b] += 1
			_uf_union(parent, rank, best_a, best_b)


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
	return _build_star_profile_from_star_entries(custom_system.build_star_entries())
 
 
func build_star_profile_from_details(system_details: Dictionary) -> Dictionary:
	var star_entries: Array = system_details.get("stars", [])
	if star_entries.is_empty():
		var fallback_profile: Dictionary = system_details.get("star_profile", {})
		star_entries = fallback_profile.get("stars", [])
	return _build_star_profile_from_star_entries(star_entries)
 
 
func build_system_summary_from_details(system_details: Dictionary) -> Dictionary:
	var orbitals: Array = system_details.get("orbitals", [])
	var star_profile: Dictionary = build_star_profile_from_details(system_details)
	var planet_count := _count_entries_of_type(orbitals, ORBITAL_TYPE_PLANET)
	var asteroid_belt_count := _count_entries_of_type(orbitals, ORBITAL_TYPE_ASTEROID_BELT)
	var structure_count := _count_entries_of_type(orbitals, ORBITAL_TYPE_STRUCTURE)
	var ruin_count := _count_entries_of_type(orbitals, ORBITAL_TYPE_RUIN)
	var habitable_worlds := 0
	var colonizable_worlds := 0

	for orbital_variant in orbitals:
		var orbital: Dictionary = orbital_variant
		if str(orbital.get("type", "")) != ORBITAL_TYPE_PLANET:
			continue
		var habitability: float = float(orbital.get("habitability", 0.0))
		if habitability >= 0.7:
			habitable_worlds += 1
		if bool(orbital.get("is_colonizable", false)) or habitability >= 0.45:
			colonizable_worlds += 1

	var anomaly_risk: float = float(system_details.get("anomaly_risk", 0.0))
	if not system_details.has("anomaly_risk"):
		anomaly_risk = clampf(
			float(ruin_count) * 0.2
			+ float(structure_count) * 0.04
			+ float(asteroid_belt_count) * 0.05,
			0.0,
			1.0
		)

	return {
		"star_count": int(star_profile.get("star_count", 1)),
		"star_class": str(star_profile.get("star_class", "G")),
		"special_type": str(star_profile.get("special_type", SPECIAL_TYPE_NONE)),
		"planet_count": planet_count,
		"asteroid_belt_count": asteroid_belt_count,
		"structure_count": structure_count,
		"ruin_count": ruin_count,
		"colonizable_worlds": colonizable_worlds,
		"habitable_worlds": habitable_worlds,
		"object_count": orbitals.size(),
		"anomaly_risk": snapped(clampf(anomaly_risk, 0.0, 1.0), 0.01),
	}
 
 
func apply_system_detail_patch(base_details: Dictionary, detail_patch: Dictionary) -> Dictionary:
	var result := _deep_merge_dictionary(base_details, detail_patch, {
		"stars": true,
		"orbitals": true,
		"upsert_stars": true,
		"upsert_orbitals": true,
		"remove_star_ids": true,
		"remove_orbital_ids": true,
	})

	if detail_patch.has("stars"):
		result["stars"] = detail_patch.get("stars", []).duplicate(true)
	if detail_patch.has("orbitals"):
		result["orbitals"] = detail_patch.get("orbitals", []).duplicate(true)
	if detail_patch.has("upsert_stars"):
		result["stars"] = _upsert_dictionary_entries(result.get("stars", []), detail_patch.get("upsert_stars", []), "id")
	if detail_patch.has("upsert_orbitals"):
		result["orbitals"] = _upsert_dictionary_entries(result.get("orbitals", []), detail_patch.get("upsert_orbitals", []), "id")
	if detail_patch.has("remove_star_ids"):
		result["stars"] = _remove_entries_by_id(result.get("stars", []), detail_patch.get("remove_star_ids", []), "id")
	if detail_patch.has("remove_orbital_ids"):
		result["orbitals"] = _remove_entries_by_id(result.get("orbitals", []), detail_patch.get("remove_orbital_ids", []), "id")

	return _finalize_system_details(result)
 
 
func _finalize_system_details(system_details: Dictionary) -> Dictionary:
	var details: Dictionary = system_details.duplicate(true)
	var stars: Array = []
	var orbitals: Array = []

	for star_index in range(details.get("stars", []).size()):
		var raw_star: Dictionary = details.get("stars", [])[star_index]
		stars.append(_normalize_star_entry(raw_star, star_index))

	if stars.is_empty():
		var fallback_stars: Array = details.get("star_profile", {}).get("stars", [])
		for star_index in range(fallback_stars.size()):
			var fallback_star: Dictionary = fallback_stars[star_index]
			stars.append(_normalize_star_entry(fallback_star, star_index))

	for orbital_index in range(details.get("orbitals", []).size()):
		var raw_orbital: Dictionary = details.get("orbitals", [])[orbital_index]
		orbitals.append(_normalize_orbital_entry(raw_orbital, orbital_index))
	orbitals.sort_custom(_sort_orbitals_by_radius)

	details["stars"] = stars
	details["orbitals"] = orbitals
	details["star_profile"] = build_star_profile_from_details(details)
	details["system_summary"] = build_system_summary_from_details(details)
	details["star_class"] = str(details["system_summary"].get("star_class", details.get("star_class", "G")))
	details["star_count"] = int(details["system_summary"].get("star_count", stars.size()))
	details["planet_count"] = int(details["system_summary"].get("planet_count", 0))
	details["asteroid_belt_count"] = int(details["system_summary"].get("asteroid_belt_count", 0))
	details["structure_count"] = int(details["system_summary"].get("structure_count", 0))
	details["ruin_count"] = int(details["system_summary"].get("ruin_count", 0))
	details["colonizable_worlds"] = int(details["system_summary"].get("colonizable_worlds", 0))
	details["habitable_worlds"] = int(details["system_summary"].get("habitable_worlds", 0))
	details["anomaly_risk"] = float(details["system_summary"].get("anomaly_risk", 0.0))
	details["planet_names"] = _extract_orbital_names(orbitals, ORBITAL_TYPE_PLANET)
	return details
 
 
func _build_star_profile_from_star_entries(star_entries: Array) -> Dictionary:
	var stars: Array = []
	for star_index in range(star_entries.size()):
		var raw_star: Dictionary = star_entries[star_index]
		stars.append(_normalize_star_entry(raw_star, star_index))

	if stars.is_empty():
		stars.append(_normalize_star_entry({
			"id": "star_00",
			"name": "Primary",
			"color": STAR_COLOR_MAP[STAR_COLOR_YELLOW],
			"color_name": STAR_COLOR_YELLOW,
			"size_name": STAR_SIZE_NORMAL,
			"scale": STAR_SIZE_SCALE_MAP[STAR_SIZE_NORMAL],
			"is_primary": true,
			"special_type": SPECIAL_TYPE_NONE,
			"star_class": "G",
		}, 0))

	var primary_index := 0
	for star_index in range(stars.size()):
		if bool(stars[star_index].get("is_primary", false)):
			primary_index = star_index
			break
	var primary_star: Dictionary = stars[primary_index]
	var primary_color: Color = primary_star.get("color", STAR_COLOR_MAP[STAR_COLOR_YELLOW])
	var special_type: String = str(primary_star.get("special_type", SPECIAL_TYPE_NONE))
	var primary_color_name: String = str(primary_star.get("color_name", ""))
	if primary_color_name.is_empty():
		primary_color_name = _closest_star_color_name(primary_color)
	if special_type == SPECIAL_TYPE_BLACK_HOLE:
		primary_color_name = "Void"

	var primary_size_name: String = str(primary_star.get("size_name", STAR_SIZE_NORMAL))
	var primary_star_class: String = str(primary_star.get("star_class", "G"))
	var star_count: int = stars.size()
	var system_type := STAR_SYSTEM_NORMAL
	if star_count == 2:
		system_type = STAR_SYSTEM_RARE
	elif star_count >= 3:
		system_type = STAR_SYSTEM_SUPER_RARE

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
 
 
func _build_detail_stars_from_profile(
	star_profile: Dictionary,
	detail_rng: RandomNumberGenerator,
	system_name: String
) -> Array:
	var stars: Array = []
	var profile_stars: Array = star_profile.get("stars", [])
	var star_count: int = maxi(profile_stars.size(), 1)
	var letters := ["A", "B", "C"]
	var orbit_radius := 0.0
	if star_count == 2:
		orbit_radius = 12.0
	elif star_count >= 3:
		orbit_radius = 15.0

	for star_index in range(profile_stars.size()):
		var profile_star: Dictionary = profile_stars[star_index]
		var star_entry := profile_star.duplicate(true)
		star_entry["id"] = star_entry.get("id", "star_%02d" % star_index)
		star_entry["name"] = star_entry.get("name", "%s %s" % [system_name, letters[mini(star_index, letters.size() - 1)]])
		star_entry["orbit_radius"] = 0.0
		star_entry["orbit_angle"] = 0.0
		star_entry["vertical_offset"] = 0.0

		if star_count == 2:
			star_entry["orbit_radius"] = orbit_radius
			star_entry["orbit_angle"] = PI if star_index == 0 else 0.0
			star_entry["vertical_offset"] = detail_rng.randf_range(-1.0, 1.0)
		elif star_count >= 3:
			star_entry["orbit_radius"] = orbit_radius * detail_rng.randf_range(0.88, 1.08)
			star_entry["orbit_angle"] = float(star_index) * TAU / float(star_count) + detail_rng.randf_range(-0.18, 0.18)
			star_entry["vertical_offset"] = detail_rng.randf_range(-1.4, 1.4)

		stars.append(_normalize_star_entry(star_entry, star_index))

	return stars
 
 
func _normalize_star_entry(star_entry: Dictionary, star_index: int) -> Dictionary:
	var result := star_entry.duplicate(true)
	var special_type: String = str(result.get("special_type", SPECIAL_TYPE_NONE))
	var size_name: String = str(result.get("size_name", STAR_SIZE_NORMAL))
	var color: Color = result.get("color", STAR_COLOR_MAP[STAR_COLOR_YELLOW])
	var color_name: String = str(result.get("color_name", ""))
	if color_name.is_empty() and special_type != SPECIAL_TYPE_BLACK_HOLE:
		color_name = _closest_star_color_name(color)

	result["id"] = str(result.get("id", "star_%02d" % star_index))
	result["name"] = str(result.get("name", "Star %d" % (star_index + 1)))
	result["index"] = star_index
	result["kind"] = "black_hole" if special_type == SPECIAL_TYPE_BLACK_HOLE else str(result.get("kind", "star"))
	result["color"] = color
	result["color_name"] = color_name
	result["size_name"] = size_name
	result["scale"] = float(result.get("scale", STAR_SIZE_SCALE_MAP.get(size_name, 1.0)))
	result["is_primary"] = bool(result.get("is_primary", star_index == 0))
	result["special_type"] = special_type
	result["star_class"] = str(result.get("star_class", _infer_star_class_from_entry(color_name, special_type)))
	result["orbit_radius"] = float(result.get("orbit_radius", 0.0))
	result["orbit_angle"] = float(result.get("orbit_angle", 0.0))
	result["vertical_offset"] = float(result.get("vertical_offset", 0.0))
	return result
 
 
func _normalize_orbital_entry(orbital_entry: Dictionary, orbital_index: int) -> Dictionary:
	var result := orbital_entry.duplicate(true)
	var orbital_type: String = str(result.get("type", ORBITAL_TYPE_PLANET))
	result["id"] = str(result.get("id", "%s_%02d" % [orbital_type, orbital_index]))
	result["name"] = str(result.get("name", "%s %d" % [orbital_type.replace("_", " ").capitalize(), orbital_index + 1]))
	result["type"] = orbital_type
	result["color"] = result.get("color", _get_default_orbital_color(orbital_type, orbital_index))
	result["size"] = float(result.get("size", 1.0))
	result["orbit_radius"] = float(result.get("orbit_radius", 28.0 + float(orbital_index) * 14.0))
	result["orbit_angle"] = float(result.get("orbit_angle", 0.0))
	result["vertical_offset"] = float(result.get("vertical_offset", 0.0))
	result["orbit_width"] = float(result.get("orbit_width", 0.0))
	result["is_colonizable"] = bool(result.get("is_colonizable", false))
	result["habitability"] = clampf(float(result.get("habitability", 0.0)), 0.0, 1.0)
	result["resource_richness"] = clampf(float(result.get("resource_richness", 0.5)), 0.0, 1.0)
	result["metadata"] = result.get("metadata", {}).duplicate(true)
	return result
 
 
func _get_default_orbital_color(orbital_type: String, orbital_index: int) -> Color:
	match orbital_type:
		ORBITAL_TYPE_ASTEROID_BELT:
			return ASTEROID_BELT_COLOR
		ORBITAL_TYPE_STRUCTURE:
			return STRUCTURE_COLOR
		ORBITAL_TYPE_RUIN:
			return RUIN_COLOR
		_:
			return PLANET_COLOR_PALETTE[orbital_index % PLANET_COLOR_PALETTE.size()]
 
 
func _infer_star_class_from_entry(color_name: String, special_type: String) -> String:
	match special_type:
		SPECIAL_TYPE_BLACK_HOLE:
			return "Black Hole"
		SPECIAL_TYPE_NEUTRON:
			return "Neutron"
		SPECIAL_TYPE_O_CLASS:
			return "O"
		_:
			return STAR_CLASS_BY_COLOR.get(color_name, "G")
 
 
func _pick_unique_index_map(
	detail_rng: RandomNumberGenerator,
	population_size: int,
	pick_count: int
) -> Dictionary:
	var picked: Dictionary = {}
	var candidates: Array = []
	for candidate_index in range(population_size):
		candidates.append(candidate_index)

	for _pick in range(mini(pick_count, candidates.size())):
		var selection_index: int = detail_rng.randi_range(0, candidates.size() - 1)
		var selected_value: int = int(candidates[selection_index])
		candidates.remove_at(selection_index)
		picked[selected_value] = true

	return picked
 
 
func _pick_additional_unique_indices(
	detail_rng: RandomNumberGenerator,
	population_size: int,
	target_count: int,
	existing_index_map: Dictionary
) -> Array:
	var picked: Array = []
	var candidates: Array = []
	for candidate_index in range(population_size):
		if existing_index_map.has(candidate_index):
			continue
		candidates.append(candidate_index)

	var remaining_count: int = maxi(0, target_count - existing_index_map.size())
	for _pick in range(mini(remaining_count, candidates.size())):
		var selection_index: int = detail_rng.randi_range(0, candidates.size() - 1)
		var selected_value: int = int(candidates[selection_index])
		candidates.remove_at(selection_index)
		picked.append(selected_value)

	return picked
 
 
func _get_initial_orbit_radius(stars: Array) -> float:
	if stars.size() <= 1:
		return 24.0
	if stars.size() == 2:
		return 34.0
	return 42.0
 
 
func _find_open_orbit_radius(
	detail_rng: RandomNumberGenerator,
	occupied_orbits: Array,
	min_radius: float,
	max_radius: float,
	min_gap: float
) -> float:
	var safe_max_radius := maxf(max_radius, min_radius + min_gap)
	for _attempt in range(20):
		var candidate: float = detail_rng.randf_range(min_radius, safe_max_radius)
		var is_valid := true
		for occupied_radius_variant in occupied_orbits:
			var occupied_radius: float = float(occupied_radius_variant)
			if absf(candidate - occupied_radius) < min_gap:
				is_valid = false
				break
		if is_valid:
			return candidate
	return safe_max_radius + float(occupied_orbits.size()) * min_gap * 0.35
 
 
func _count_entries_of_type(entries: Array, entry_type: String) -> int:
	var count := 0
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if str(entry.get("type", "")) == entry_type:
			count += 1
	return count
 
 
func _extract_orbital_names(entries: Array, entry_type: String) -> PackedStringArray:
	var names := PackedStringArray()
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if str(entry.get("type", "")) != entry_type:
			continue
		names.append(str(entry.get("name", entry.get("id", ""))))
	return names
 
 
func _deep_merge_dictionary(base: Dictionary, patch: Dictionary, ignored_keys: Dictionary = {}) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key_variant in patch.keys():
		var key_string: String = str(key_variant)
		if ignored_keys.has(key_string):
			continue

		var patch_value = patch[key_variant]
		if result.has(key_variant) and result[key_variant] is Dictionary and patch_value is Dictionary:
			result[key_variant] = _deep_merge_dictionary(result[key_variant], patch_value, ignored_keys)
		elif patch_value is Array:
			result[key_variant] = patch_value.duplicate(true)
		elif patch_value is Dictionary:
			result[key_variant] = patch_value.duplicate(true)
		else:
			result[key_variant] = patch_value
	return result
 
 
func _upsert_dictionary_entries(existing_entries: Array, updates: Array, id_key: String) -> Array:
	var result: Array = existing_entries.duplicate(true)
	for update_variant in updates:
		var update_entry: Dictionary = update_variant
		var update_id: String = str(update_entry.get(id_key, ""))
		var merged := false
		if not update_id.is_empty():
			for entry_index in range(result.size()):
				var existing_entry: Dictionary = result[entry_index]
				if str(existing_entry.get(id_key, "")) != update_id:
					continue
				result[entry_index] = _deep_merge_dictionary(existing_entry, update_entry)
				merged = true
				break
		if not merged:
			result.append(update_entry.duplicate(true))
	return result
 
 
func _remove_entries_by_id(existing_entries: Array, ids_to_remove_variant, id_key: String) -> Array:
	var ids_to_remove := _extract_string_ids(ids_to_remove_variant)
	if ids_to_remove.is_empty():
		return existing_entries.duplicate(true)

	var remaining_entries: Array = []
	for entry_variant in existing_entries:
		var entry: Dictionary = entry_variant
		if ids_to_remove.has(str(entry.get(id_key, ""))):
			continue
		remaining_entries.append(entry.duplicate(true))
	return remaining_entries
 
 
func _extract_string_ids(ids_variant) -> PackedStringArray:
	var ids := PackedStringArray()
	if ids_variant is PackedStringArray:
		return ids_variant
	if ids_variant is String:
		ids.append(str(ids_variant))
		return ids
	if ids_variant is Array:
		for value_variant in ids_variant:
			ids.append(str(value_variant))
	return ids
 
 
func _sort_orbitals_by_radius(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("orbit_radius", 0.0)) < float(b.get("orbit_radius", 0.0))
 
 
func _to_roman(value: int) -> String:
	var remaining := maxi(value, 1)
	var numerals := [
		{"value": 10, "symbol": "X"},
		{"value": 9, "symbol": "IX"},
		{"value": 5, "symbol": "V"},
		{"value": 4, "symbol": "IV"},
		{"value": 1, "symbol": "I"},
	]
	var result := ""
	for numeral_variant in numerals:
		var numeral: Dictionary = numeral_variant
		var numeral_value: int = numeral["value"]
		while remaining >= numeral_value:
			result += str(numeral["symbol"])
			remaining -= numeral_value
	return result


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
