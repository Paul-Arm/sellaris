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
const PLANET_VISUAL_LANDMASS := "landmass"
const PLANET_VISUAL_DRY := "dry_terran"
const PLANET_VISUAL_BARREN := "no_atmosphere"
const PLANET_VISUAL_ICE := "ice_world"
const PLANET_VISUAL_LAVA := "lava_world"
const PLANET_VISUAL_GAS := "gas_planet"
const PASTEL_LAND_COLORS := [
	Color(0.62, 0.78, 0.74, 1.0),
	Color(0.7, 0.79, 0.92, 1.0),
	Color(0.68, 0.84, 0.72, 1.0),
]
const PASTEL_DRY_COLORS := [
	Color(0.86, 0.73, 0.6, 1.0),
	Color(0.9, 0.76, 0.62, 1.0),
	Color(0.83, 0.68, 0.58, 1.0),
]
const PASTEL_BARREN_COLORS := [
	Color(0.78, 0.79, 0.84, 1.0),
	Color(0.72, 0.74, 0.79, 1.0),
	Color(0.82, 0.78, 0.86, 1.0),
]
const PASTEL_ICE_COLORS := [
	Color(0.76, 0.88, 0.96, 1.0),
	Color(0.82, 0.9, 0.98, 1.0),
	Color(0.7, 0.84, 0.94, 1.0),
]
const PASTEL_LAVA_COLORS := [
	Color(0.94, 0.66, 0.54, 1.0),
	Color(0.9, 0.58, 0.52, 1.0),
	Color(0.86, 0.54, 0.48, 1.0),
]
const PASTEL_GAS_COLORS := [
	Color(0.9, 0.78, 0.66, 1.0),
	Color(0.84, 0.72, 0.8, 1.0),
	Color(0.8, 0.78, 0.92, 1.0),
]
const ASTEROID_BELT_COLOR := Color(0.6, 0.58, 0.54, 1.0)
const STRUCTURE_COLOR := Color(0.42, 0.8, 1.0, 1.0)
const RUIN_COLOR := Color(0.72, 0.73, 0.78, 1.0)
const MIN_HYPERLANES_PER_SYSTEM := 1
const MAX_HYPERLANES_PER_SYSTEM := 5
const POISSON_CANDIDATE_ATTEMPTS := 30
const POISSON_SEED_POINT_ATTEMPTS := 128
const SPIRAL_SWIRL_FACTOR := 2.7
const SPIRAL_CORE_RADIUS_FACTOR := 0.12
const SPIRAL_ARM_WIDTH_FACTOR := 0.058
const RING_INNER_RADIUS_FACTOR := 0.42
const RING_OUTER_RADIUS_FACTOR := 0.95
const ELLIPTICAL_RADIUS_X_FACTOR := 1.08
const ELLIPTICAL_RADIUS_Z_FACTOR := 0.72
const CLUSTER_COUNT := 5
const CLUSTER_CENTER_MIN_RADIUS_FACTOR := 0.2
const CLUSTER_CENTER_MAX_RADIUS_FACTOR := 0.72
const CLUSTER_RADIUS_MIN_FACTOR := 0.14
const CLUSTER_RADIUS_MAX_FACTOR := 0.22
const HYPERLANE_SYSTEM_CLEARANCE_FACTOR := 0.52
const HYPERLANE_SYSTEM_CLEARANCE_MIN := 18.0
const SYSTEM_SPREAD_DISTANCE_FACTOR := 1.18
const SYSTEM_SPREAD_RADIUS_FACTOR := 1.1
const HYPERLANE_INTERSECTION_EPSILON := 0.001

var _hyperlane_map_points: Array[Vector2] = []
var _hyperlane_system_query_grid: Dictionary = {}
var _hyperlane_system_query_cell_size: float = 0.0


func get_shape_options() -> PackedStringArray:
	return PackedStringArray([SHAPE_SPIRAL, SHAPE_RING, SHAPE_ELLIPTICAL, SHAPE_CLUSTERED])


func build_layout(config: Dictionary, custom_systems: Array[Resource]) -> Dictionary:
	var galaxy_seed: int = _resolve_seed(config.get("seed_text", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = galaxy_seed

	var target_system_count: int = maxi(1, int(config.get("star_count", 900)))
	var galaxy_radius: float = float(config.get("galaxy_radius", 3000.0)) * SYSTEM_SPREAD_RADIUS_FACTOR
	var min_system_distance: float = float(config.get("min_system_distance", 48.0)) * SYSTEM_SPREAD_DISTANCE_FACTOR
	var shape: String = str(config.get("shape", SHAPE_SPIRAL)).to_lower()
	var spiral_arms: int = maxi(1, int(config.get("spiral_arms", 4)))
	var hyperlane_density: int = clampi(int(config.get("hyperlane_density", 2)), 1, 8)

	var systems: Array[Dictionary] = []
	var grid: Dictionary = {}
	var cell_size: float = maxf(min_system_distance / sqrt(2.0), 1.0)
	var custom_count: int = _append_custom_systems(systems, custom_systems, grid, cell_size, min_system_distance)
	var procedural_target: int = maxi(0, target_system_count - custom_count)
	var shape_context: Dictionary = _build_shape_context(rng, shape, galaxy_radius, spiral_arms, min_system_distance)
	var procedural_positions: Array[Vector3] = _generate_procedural_positions(
		rng,
		shape_context,
		procedural_target,
		systems,
		grid,
		cell_size,
		min_system_distance
	)

	for position in procedural_positions:
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

	if systems.size() < target_system_count:
		push_warning(
			"Galaxy generator reached the Poisson placement limit before hitting the requested system count (%d/%d)." % [
				systems.size(),
				target_system_count,
			]
		)

	var hyperlane_graph := build_hyperlane_graph(systems, hyperlane_density, min_system_distance, galaxy_seed)
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


func _append_custom_systems(
	systems: Array[Dictionary],
	custom_systems: Array[Resource],
	grid: Dictionary,
	cell_size: float,
	min_system_distance: float
) -> int:
	var added_count: int = 0

	for i in range(custom_systems.size()):
		var custom_system: Resource = custom_systems[i]
		if custom_system == null:
			continue
		if _has_nearby_system(custom_system.position, grid, cell_size, min_system_distance):
			push_warning(
				"Custom system '%s' is too close to another system and was skipped to preserve galaxy spacing." % custom_system.get_resolved_name(i)
			)
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
		var orbit_progress: float = 0.0 if planet_count <= 1 else float(planet_index) / float(planet_count - 1)
		var visual_info: Dictionary = _build_planet_visual_info(
			detail_rng,
			star_profile,
			orbit_progress,
			is_habitable,
			is_colonizable,
			planet_index
		)
		var planet_color: Color = visual_info.get("color", PLANET_COLOR_PALETTE[planet_index % PLANET_COLOR_PALETTE.size()])
		var planet_size: float = float(visual_info.get("size", detail_rng.randf_range(1.0, 3.9)))
		var habitability: float = float(visual_info.get("habitability", 0.0))
		var habitability_points: int = _to_points(habitability)
		is_colonizable = bool(visual_info.get("is_colonizable", is_colonizable))
		var resource_richness_points: int = _to_points(snapped(detail_rng.randf_range(0.1, 1.0), 0.01))

		orbitals.append({
			"id": "planet_%02d" % planet_index,
			"name": "%s %s" % [resolved_name, _to_roman(planet_index + 1)],
			"type": ORBITAL_TYPE_PLANET,
			"orbit_radius": current_orbit,
			"orbit_angle": detail_rng.randf_range(0.0, TAU),
			"vertical_offset": detail_rng.randf_range(-1.8, 1.8),
			"size": planet_size,
			"color": planet_color,
			"orbit_width": 0.0,
			"is_colonizable": is_colonizable,
			"habitability": habitability,
			"habitability_points": habitability_points,
			"resource_richness_points": resource_richness_points,
			"resource_richness": float(resource_richness_points) / 100.0,
			"metadata": {
				"planet_visual": visual_info.get("planet_visual", {}),
			},
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
			var belt_resource_richness_points: int = _to_points(snapped(detail_rng.randf_range(0.35, 1.0), 0.01))
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
				"habitability_points": 0,
				"resource_richness_points": belt_resource_richness_points,
				"resource_richness": float(belt_resource_richness_points) / 100.0,
				"metadata": {
					"belt_visual": _build_belt_visual_metadata(detail_rng),
				},
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
		var structure_resource_richness_points: int = _to_points(snapped(detail_rng.randf_range(0.2, 0.85), 0.01))
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
			"habitability_points": 0,
			"resource_richness_points": structure_resource_richness_points,
			"resource_richness": float(structure_resource_richness_points) / 100.0,
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
		var ruin_resource_richness_points: int = _to_points(snapped(detail_rng.randf_range(0.15, 0.92), 0.01))
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
			"habitability_points": 0,
			"resource_richness_points": ruin_resource_richness_points,
			"resource_richness": float(ruin_resource_richness_points) / 100.0,
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


func _build_planet_visual_info(
	detail_rng: RandomNumberGenerator,
	star_profile: Dictionary,
	orbit_progress: float,
	is_habitable: bool,
	is_colonizable: bool,
	planet_index: int
) -> Dictionary:
	var special_type: String = str(star_profile.get("special_type", SPECIAL_TYPE_NONE))
	var world_kind := PLANET_VISUAL_BARREN

	if is_habitable:
		world_kind = PLANET_VISUAL_LANDMASS if detail_rng.randf() < 0.74 else PLANET_VISUAL_DRY
	elif is_colonizable:
		if orbit_progress < 0.3:
			world_kind = PLANET_VISUAL_DRY
		else:
			world_kind = PLANET_VISUAL_LANDMASS if detail_rng.randf() < 0.55 else PLANET_VISUAL_DRY
	else:
		if orbit_progress < 0.15:
			world_kind = PLANET_VISUAL_LAVA if detail_rng.randf() < 0.52 else PLANET_VISUAL_DRY
		elif orbit_progress < 0.35:
			world_kind = PLANET_VISUAL_DRY if detail_rng.randf() < 0.55 else PLANET_VISUAL_BARREN
		elif orbit_progress > 0.72:
			world_kind = PLANET_VISUAL_GAS if detail_rng.randf() < 0.52 else PLANET_VISUAL_ICE
		elif orbit_progress > 0.5:
			world_kind = PLANET_VISUAL_GAS if detail_rng.randf() < 0.32 else PLANET_VISUAL_BARREN
		else:
			world_kind = PLANET_VISUAL_BARREN

	if special_type == SPECIAL_TYPE_BLACK_HOLE and detail_rng.randf() < 0.5:
		world_kind = PLANET_VISUAL_BARREN
	elif special_type == SPECIAL_TYPE_NEUTRON and world_kind == PLANET_VISUAL_LANDMASS:
		world_kind = PLANET_VISUAL_ICE if detail_rng.randf() < 0.55 else PLANET_VISUAL_BARREN

	var size: float = 1.2
	var habitability: float = 0.0
	var resolved_colonizable: bool = is_colonizable
	match world_kind:
		PLANET_VISUAL_LANDMASS:
			size = detail_rng.randf_range(1.4, 2.8)
			habitability = 0.78 if is_habitable else 0.52
		PLANET_VISUAL_DRY:
			size = detail_rng.randf_range(1.2, 2.7)
			habitability = 0.72 if is_habitable else (0.46 if is_colonizable else snapped(detail_rng.randf_range(0.08, 0.26), 0.01))
		PLANET_VISUAL_ICE:
			size = detail_rng.randf_range(1.3, 3.0)
			habitability = 0.5 if is_colonizable else snapped(detail_rng.randf_range(0.02, 0.22), 0.01)
			resolved_colonizable = is_colonizable and detail_rng.randf() < 0.5
		PLANET_VISUAL_LAVA:
			size = detail_rng.randf_range(1.2, 2.4)
			habitability = snapped(detail_rng.randf_range(0.0, 0.12), 0.01)
			resolved_colonizable = false
		PLANET_VISUAL_GAS:
			size = detail_rng.randf_range(3.2, 5.8)
			habitability = 0.0
			resolved_colonizable = false
		_:
			size = detail_rng.randf_range(1.0, 2.6)
			habitability = snapped(detail_rng.randf_range(0.0, 0.18), 0.01)
			resolved_colonizable = false

	var palette: Array = _get_planet_palette_for_kind(world_kind)
	var planet_color: Color = palette[detail_rng.randi_range(0, palette.size() - 1)]
	var pixels: float = snappedf(detail_rng.randf_range(1700.0, 2800.0), 1.0)

	return {
		"kind": world_kind,
		"color": planet_color,
		"size": snappedf(size, 0.01),
		"habitability": habitability,
		"is_colonizable": resolved_colonizable,
		"planet_visual": {
			"kind": world_kind,
			"pixels": pixels,
			"has_atmosphere": world_kind in [PLANET_VISUAL_LANDMASS, PLANET_VISUAL_ICE, PLANET_VISUAL_GAS] or (world_kind == PLANET_VISUAL_DRY and resolved_colonizable),
			"has_ring": world_kind == PLANET_VISUAL_GAS,
			"variant_index": planet_index,
		},
	}


func _build_belt_visual_metadata(detail_rng: RandomNumberGenerator) -> Dictionary:
	return {
		"pixels": snappedf(detail_rng.randf_range(1850.0, 2500.0), 1.0),
		"density": detail_rng.randi_range(30, 70),
	}


func _build_star_visual_metadata(
	star_rng: RandomNumberGenerator,
	special_type: String,
	is_primary: bool
) -> Dictionary:
	return {
		"kind": "black_hole" if special_type == SPECIAL_TYPE_BLACK_HOLE else "star",
		"pixels": snappedf(star_rng.randf_range(1900.0 if is_primary else 1700.0, 2800.0 if is_primary else 2400.0), 1.0),
		"rotation": star_rng.randf_range(-0.5, 0.5),
	}


func _get_planet_palette_for_kind(world_kind: String) -> Array:
	match world_kind:
		PLANET_VISUAL_LANDMASS:
			return PASTEL_LAND_COLORS
		PLANET_VISUAL_DRY:
			return PASTEL_DRY_COLORS
		PLANET_VISUAL_ICE:
			return PASTEL_ICE_COLORS
		PLANET_VISUAL_LAVA:
			return PASTEL_LAVA_COLORS
		PLANET_VISUAL_GAS:
			return PASTEL_GAS_COLORS
		_:
			return PASTEL_BARREN_COLORS


func _build_shape_context(
	rng: RandomNumberGenerator,
	shape: String,
	galaxy_radius: float,
	spiral_arms: int,
	min_system_distance: float
) -> Dictionary:
	var context := {
		"shape": shape,
		"galaxy_radius": galaxy_radius,
		"spiral_arms": spiral_arms,
		"spiral_swirl": SPIRAL_SWIRL_FACTOR,
		"spiral_core_radius": maxf(min_system_distance * 3.25, galaxy_radius * SPIRAL_CORE_RADIUS_FACTOR),
		"spiral_arm_half_width": maxf(min_system_distance * 2.6, galaxy_radius * SPIRAL_ARM_WIDTH_FACTOR),
		"ring_inner_radius": galaxy_radius * RING_INNER_RADIUS_FACTOR,
		"ring_outer_radius": galaxy_radius * RING_OUTER_RADIUS_FACTOR,
		"elliptical_radius_x": galaxy_radius * ELLIPTICAL_RADIUS_X_FACTOR,
		"elliptical_radius_z": galaxy_radius * ELLIPTICAL_RADIUS_Z_FACTOR,
		"cluster_centers": [],
		"cluster_radii": [],
	}

	if shape == SHAPE_CLUSTERED:
		var cluster_centers: Array[Vector2] = []
		var cluster_radii: Array[float] = []
		var base_angle: float = rng.randf_range(0.0, TAU)
		for cluster_index in range(CLUSTER_COUNT):
			var angle := base_angle + float(cluster_index) * TAU / float(CLUSTER_COUNT) + rng.randf_range(-0.18, 0.18)
			var center_radius := galaxy_radius * rng.randf_range(
				CLUSTER_CENTER_MIN_RADIUS_FACTOR,
				CLUSTER_CENTER_MAX_RADIUS_FACTOR
			)
			cluster_centers.append(Vector2(cos(angle), sin(angle)) * center_radius)
			cluster_radii.append(
				maxf(
					min_system_distance * 4.5,
					galaxy_radius * rng.randf_range(CLUSTER_RADIUS_MIN_FACTOR, CLUSTER_RADIUS_MAX_FACTOR)
				)
			)
		context["cluster_centers"] = cluster_centers
		context["cluster_radii"] = cluster_radii

	return context


func _generate_procedural_positions(
	rng: RandomNumberGenerator,
	shape_context: Dictionary,
	desired_count: int,
	existing_systems: Array[Dictionary],
	grid: Dictionary,
	cell_size: float,
	min_system_distance: float
) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if desired_count <= 0:
		return positions

	var active_points: Array[Vector2] = []
	for system_record_variant in existing_systems:
		var system_record: Dictionary = system_record_variant
		var map_point := _to_map_point(system_record["position"])
		if _is_map_point_in_shape(map_point, shape_context):
			active_points.append(map_point)

	# Bridson sampling with random restarts lets disconnected shapes like clusters fill cleanly.
	while positions.size() < desired_count:
		if active_points.is_empty():
			var seed_result: Dictionary = _find_poisson_seed_point(
				rng,
				shape_context,
				grid,
				cell_size,
				min_system_distance
			)
			if not bool(seed_result.get("success", false)):
				break

			var seed_point: Vector2 = seed_result.get("point", Vector2.ZERO)
			active_points.append(seed_point)
			var seed_position := _build_position_from_map_point(rng, seed_point, shape_context)
			positions.append(seed_position)
			_add_to_grid(seed_position, grid, cell_size)
			continue

		var active_index: int = rng.randi_range(0, active_points.size() - 1)
		var origin: Vector2 = active_points[active_index]
		var accepted_candidate := false

		for _candidate_attempt in range(POISSON_CANDIDATE_ATTEMPTS):
			var candidate := _sample_poisson_candidate(rng, origin, min_system_distance)
			if not _is_map_point_in_shape(candidate, shape_context):
				continue
			if _has_nearby_system(Vector3(candidate.x, 0.0, candidate.y), grid, cell_size, min_system_distance):
				continue

			active_points.append(candidate)
			var candidate_position := _build_position_from_map_point(rng, candidate, shape_context)
			positions.append(candidate_position)
			_add_to_grid(candidate_position, grid, cell_size)
			accepted_candidate = true
			if positions.size() >= desired_count:
				break

		if not accepted_candidate:
			active_points.remove_at(active_index)

	return positions


func _find_poisson_seed_point(
	rng: RandomNumberGenerator,
	shape_context: Dictionary,
	grid: Dictionary,
	cell_size: float,
	min_system_distance: float
) -> Dictionary:
	for _attempt in range(POISSON_SEED_POINT_ATTEMPTS):
		var point := _sample_shape_map_point(rng, shape_context)
		if not _is_map_point_in_shape(point, shape_context):
			continue
		if _has_nearby_system(Vector3(point.x, 0.0, point.y), grid, cell_size, min_system_distance):
			continue
		return {
			"success": true,
			"point": point,
		}

	return {
		"success": false,
		"point": Vector2.ZERO,
	}


func _sample_poisson_candidate(rng: RandomNumberGenerator, origin: Vector2, min_system_distance: float) -> Vector2:
	var angle: float = rng.randf_range(0.0, TAU)
	var radius: float = min_system_distance * sqrt(rng.randf_range(1.0, 4.0))
	return origin + Vector2(cos(angle), sin(angle)) * radius


func _sample_shape_map_point(rng: RandomNumberGenerator, shape_context: Dictionary) -> Vector2:
	var shape: String = str(shape_context.get("shape", SHAPE_SPIRAL))
	match shape:
		SHAPE_RING:
			return _sample_ring_map_point(rng, shape_context)
		SHAPE_ELLIPTICAL:
			return _sample_elliptical_map_point(rng, shape_context)
		SHAPE_CLUSTERED:
			return _sample_clustered_map_point(rng, shape_context)
		_:
			return _sample_spiral_map_point(rng, shape_context)


func _sample_spiral_map_point(rng: RandomNumberGenerator, shape_context: Dictionary) -> Vector2:
	var galaxy_radius: float = float(shape_context.get("galaxy_radius", 0.0))
	var spiral_arms: int = maxi(1, int(shape_context.get("spiral_arms", 4)))
	var radius_roll: float = pow(rng.randf(), 0.58)
	var radius: float = radius_roll * galaxy_radius
	var arm_index: int = rng.randi_range(0, spiral_arms - 1)
	var arm_angle: float = float(arm_index) * TAU / float(spiral_arms)
	var swirl: float = float(shape_context.get("spiral_swirl", SPIRAL_SWIRL_FACTOR)) * (radius / maxf(galaxy_radius, 1.0))
	var arm_half_width: float = float(shape_context.get("spiral_arm_half_width", 0.0))
	var angle_jitter := 0.0
	if radius > 1.0:
		angle_jitter = rng.randf_range(-arm_half_width, arm_half_width) / radius

	var angle: float = arm_angle + swirl + angle_jitter
	if rng.randf() < 0.18:
		angle = rng.randf_range(0.0, TAU)
		radius *= rng.randf_range(0.08, 0.26)

	return Vector2(cos(angle), sin(angle)) * radius


func _sample_ring_map_point(rng: RandomNumberGenerator, shape_context: Dictionary) -> Vector2:
	var inner_radius: float = float(shape_context.get("ring_inner_radius", 0.0))
	var outer_radius: float = float(shape_context.get("ring_outer_radius", inner_radius))
	var angle: float = rng.randf_range(0.0, TAU)
	var radius: float = sqrt(rng.randf_range(inner_radius * inner_radius, outer_radius * outer_radius))
	return Vector2(cos(angle), sin(angle)) * radius


func _sample_elliptical_map_point(rng: RandomNumberGenerator, shape_context: Dictionary) -> Vector2:
	var angle: float = rng.randf_range(0.0, TAU)
	var radius: float = sqrt(rng.randf())
	return Vector2(
		cos(angle) * radius * float(shape_context.get("elliptical_radius_x", 0.0)),
		sin(angle) * radius * float(shape_context.get("elliptical_radius_z", 0.0))
	)


func _sample_clustered_map_point(rng: RandomNumberGenerator, shape_context: Dictionary) -> Vector2:
	var cluster_centers: Array = shape_context.get("cluster_centers", [])
	var cluster_radii: Array = shape_context.get("cluster_radii", [])
	if cluster_centers.is_empty():
		return Vector2.ZERO

	var cluster_index: int = rng.randi_range(0, cluster_centers.size() - 1)
	var cluster_center: Vector2 = cluster_centers[cluster_index]
	var cluster_radius: float = float(cluster_radii[min(cluster_index, cluster_radii.size() - 1)])
	var angle: float = rng.randf_range(0.0, TAU)
	var radius: float = sqrt(rng.randf()) * cluster_radius
	return cluster_center + Vector2(cos(angle), sin(angle)) * radius


func _is_map_point_in_shape(point: Vector2, shape_context: Dictionary) -> bool:
	var shape: String = str(shape_context.get("shape", SHAPE_SPIRAL))
	match shape:
		SHAPE_RING:
			return _is_ring_map_point(point, shape_context)
		SHAPE_ELLIPTICAL:
			return _is_elliptical_map_point(point, shape_context)
		SHAPE_CLUSTERED:
			return _is_clustered_map_point(point, shape_context)
		_:
			return _is_spiral_map_point(point, shape_context)


func _is_spiral_map_point(point: Vector2, shape_context: Dictionary) -> bool:
	var galaxy_radius: float = float(shape_context.get("galaxy_radius", 0.0))
	var radius: float = point.length()
	if radius > galaxy_radius:
		return false

	var core_radius: float = float(shape_context.get("spiral_core_radius", 0.0))
	if radius <= core_radius:
		return true

	var spiral_arms: int = maxi(1, int(shape_context.get("spiral_arms", 4)))
	var adjusted_angle: float = wrapf(
		point.angle() - float(shape_context.get("spiral_swirl", SPIRAL_SWIRL_FACTOR)) * (radius / maxf(galaxy_radius, 1.0)),
		0.0,
		TAU
	)
	var arm_step: float = TAU / float(spiral_arms)
	var nearest_delta: float = PI
	for arm_index in range(spiral_arms):
		var arm_angle: float = float(arm_index) * arm_step
		var delta := absf(wrapf(adjusted_angle - arm_angle + PI, 0.0, TAU) - PI)
		nearest_delta = minf(nearest_delta, delta)

	var arm_half_width: float = float(shape_context.get("spiral_arm_half_width", 0.0)) + radius * 0.035
	return nearest_delta * radius <= arm_half_width


func _is_ring_map_point(point: Vector2, shape_context: Dictionary) -> bool:
	var radius: float = point.length()
	return (
		radius >= float(shape_context.get("ring_inner_radius", 0.0))
		and radius <= float(shape_context.get("ring_outer_radius", 0.0))
	)


func _is_elliptical_map_point(point: Vector2, shape_context: Dictionary) -> bool:
	var radius_x: float = maxf(float(shape_context.get("elliptical_radius_x", 0.0)), 1.0)
	var radius_z: float = maxf(float(shape_context.get("elliptical_radius_z", 0.0)), 1.0)
	return (point.x * point.x) / (radius_x * radius_x) + (point.y * point.y) / (radius_z * radius_z) <= 1.0


func _is_clustered_map_point(point: Vector2, shape_context: Dictionary) -> bool:
	var cluster_centers: Array = shape_context.get("cluster_centers", [])
	var cluster_radii: Array = shape_context.get("cluster_radii", [])
	for cluster_index in range(cluster_centers.size()):
		var cluster_center: Vector2 = cluster_centers[cluster_index]
		var cluster_radius: float = float(cluster_radii[min(cluster_index, cluster_radii.size() - 1)])
		if point.distance_squared_to(cluster_center) <= cluster_radius * cluster_radius:
			return true
	return false


func _build_position_from_map_point(
	rng: RandomNumberGenerator,
	map_point: Vector2,
	shape_context: Dictionary
) -> Vector3:
	var shape: String = str(shape_context.get("shape", SHAPE_SPIRAL))
	var y: float = 0.0
	match shape:
		SHAPE_RING:
			y = rng.randf_range(-12.0, 12.0)
		SHAPE_ELLIPTICAL:
			y = rng.randf_range(-24.0, 24.0)
		SHAPE_CLUSTERED:
			y = rng.randf_range(-16.0, 16.0)
		_:
			y = rng.randf_range(-18.0, 18.0)
	return Vector3(map_point.x, y, map_point.y)


func _has_nearby_system(candidate: Vector3, grid: Dictionary, cell_size: float, min_system_distance: float) -> bool:
	var cell := Vector2i(
		int(floor(candidate.x / cell_size)),
		int(floor(candidate.z / cell_size))
	)
	var candidate_map_point := _to_map_point(candidate)
	var min_distance_sq: float = min_system_distance * min_system_distance
	var search_radius: int = maxi(1, int(ceil(min_system_distance / maxf(cell_size, 0.001))))

	for x_offset in range(-search_radius, search_radius + 1):
		for y_offset in range(-search_radius, search_radius + 1):
			var neighbor_cell := Vector2i(cell.x + x_offset, cell.y + y_offset)
			if not grid.has(neighbor_cell):
				continue

			var existing_positions: Array = grid[neighbor_cell]
			for existing_variant in existing_positions:
				var existing: Vector3 = existing_variant
				if candidate_map_point.distance_squared_to(_to_map_point(existing)) < min_distance_sq:
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


func build_hyperlane_graph(
	systems: Array[Dictionary],
	density: int,
	min_system_distance: float = 0.0,
	graph_seed: int = 0
) -> Dictionary:
	var links: Array[Vector2i] = _build_hyperlanes(systems, density, min_system_distance, graph_seed)
	var target_links_per_system: int = mini(
		clampi(int(round(_get_target_average_hyperlane_degree(density))), MIN_HYPERLANES_PER_SYSTEM, MAX_HYPERLANES_PER_SYSTEM),
		maxi(systems.size() - 1, 0)
	)
	return {
		"links": links,
		"adjacency": build_hyperlane_adjacency(systems.size(), links),
		"min_links_per_system": mini(MIN_HYPERLANES_PER_SYSTEM, maxi(systems.size() - 1, 0)),
		"max_links_per_system": mini(MAX_HYPERLANES_PER_SYSTEM, maxi(systems.size() - 1, 0)),
		"target_links_per_system": target_links_per_system,
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


func _build_hyperlanes(
	systems: Array[Dictionary],
	density: int,
	min_system_distance: float,
	graph_seed: int
) -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	var dedupe: Dictionary = {}
	if systems.size() <= 1:
		return links

	_prepare_hyperlane_query_cache(systems, maxf(min_system_distance / sqrt(2.0), 1.0))
	var edge_records: Array = _build_delaunay_edge_records(systems)
	if edge_records.is_empty():
		edge_records = _build_fallback_hyperlane_edge_records(systems)
	edge_records.sort_custom(_sort_hyperlane_edges_by_distance)

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

	# Kruskal over Delaunay edges gives us a connected, non-crossing backbone.
	for edge_variant in edge_records:
		var edge: Dictionary = edge_variant
		var a_index: int = int(edge.get("a", -1))
		var b_index: int = int(edge.get("b", -1))
		if a_index == -1 or b_index == -1:
			continue
		if _uf_find(parent, a_index) == _uf_find(parent, b_index):
			continue
		if _add_hyperlane_link(a_index, b_index, systems, 0.0, links, dedupe):
			degrees[a_index] += 1
			degrees[b_index] += 1
			_uf_union(parent, rank, a_index, b_index)

	if links.size() < systems.size() - 1:
		_bridge_hyperlane_components(systems, links, dedupe, parent, rank, degrees)

	var unused_edges: Array = []
	for edge_variant in edge_records:
		var edge: Dictionary = edge_variant
		var edge_key: String = _make_hyperlane_edge_key(int(edge.get("a", -1)), int(edge.get("b", -1)))
		if dedupe.has(edge_key):
			continue
		unused_edges.append(edge)

	var target_edge_count: int = _get_target_hyperlane_edge_count(systems.size(), density)
	var extra_edge_skip_chance: float = _get_extra_hyperlane_skip_chance(density)
	var extra_rng := RandomNumberGenerator.new()
	var extra_seed: int = graph_seed if graph_seed != 0 else int(systems.size()) * 131071 + density * 8191
	extra_rng.seed = extra_seed

	for edge_variant in unused_edges:
		if links.size() >= target_edge_count:
			break

		var edge: Dictionary = edge_variant
		var a_index: int = int(edge.get("a", -1))
		var b_index: int = int(edge.get("b", -1))
		if a_index == -1 or b_index == -1:
			continue
		if degrees[a_index] >= MAX_HYPERLANES_PER_SYSTEM or degrees[b_index] >= MAX_HYPERLANES_PER_SYSTEM:
			continue
		if extra_rng.randf() < extra_edge_skip_chance:
			continue
		if _add_hyperlane_link(a_index, b_index, systems, 0.0, links, dedupe):
			degrees[a_index] += 1
			degrees[b_index] += 1

	_clear_hyperlane_query_cache()
	return links


func _build_delaunay_edge_records(systems: Array[Dictionary]) -> Array:
	var edge_records: Array = []
	var dedupe: Dictionary = {}
	for edge in _build_delaunay_edges(systems):
		_append_candidate_edge(edge_records, dedupe, edge.x, edge.y, _get_map_distance_sq(systems, edge.x, edge.y))
	return edge_records


func _build_delaunay_edges(systems: Array[Dictionary]) -> Array[Vector2i]:
	var delaunay_edges: Array[Vector2i] = []
	if systems.size() <= 1:
		return delaunay_edges
	if systems.size() == 2:
		delaunay_edges.append(Vector2i(0, 1))
		return delaunay_edges

	var points := PackedVector2Array()
	if not _hyperlane_map_points.is_empty() and _hyperlane_map_points.size() == systems.size():
		for map_point in _hyperlane_map_points:
			points.append(map_point)
	else:
		for system_record_variant in systems:
			var system_record: Dictionary = system_record_variant
			points.append(_to_map_point(system_record["position"]))

	var triangle_indices: PackedInt32Array = Geometry2D.triangulate_delaunay(points)
	if triangle_indices.is_empty():
		return delaunay_edges

	var dedupe: Dictionary = {}
	for triangle_index in range(0, triangle_indices.size(), 3):
		if triangle_index + 2 >= triangle_indices.size():
			break
		_append_delaunay_edge(delaunay_edges, dedupe, triangle_indices[triangle_index], triangle_indices[triangle_index + 1])
		_append_delaunay_edge(delaunay_edges, dedupe, triangle_indices[triangle_index + 1], triangle_indices[triangle_index + 2])
		_append_delaunay_edge(delaunay_edges, dedupe, triangle_indices[triangle_index + 2], triangle_indices[triangle_index])

	return delaunay_edges


func _append_delaunay_edge(edges: Array[Vector2i], dedupe: Dictionary, a_index: int, b_index: int) -> void:
	if a_index == b_index:
		return
	var a: int = mini(a_index, b_index)
	var b: int = maxi(a_index, b_index)
	var key: String = "%s:%s" % [a, b]
	if dedupe.has(key):
		return
	dedupe[key] = true
	edges.append(Vector2i(a, b))


func _append_candidate_edge(candidate_edges: Array, dedupe: Dictionary, a_index: int, b_index: int, distance_sq: float) -> void:
	if a_index == b_index:
		return
	var a: int = mini(a_index, b_index)
	var b: int = maxi(a_index, b_index)
	var key: String = _make_hyperlane_edge_key(a, b)
	if dedupe.has(key):
		return
	dedupe[key] = true
	candidate_edges.append({
		"a": a,
		"b": b,
		"distance_sq": distance_sq,
	})


func _add_hyperlane_link(
	a_index: int,
	b_index: int,
	systems: Array[Dictionary],
	system_clearance_radius: float,
	links: Array[Vector2i],
	dedupe: Dictionary
) -> bool:
	if a_index == b_index:
		return false

	var a: int = mini(a_index, b_index)
	var b: int = maxi(a_index, b_index)
	var key: String = "%s:%s" % [a, b]
	if dedupe.has(key):
		return false
	if _hyperlane_crosses_existing(a, b, systems, links):
		return false
	if not _hyperlane_has_system_clearance(a, b, systems, system_clearance_radius):
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


func _bridge_hyperlane_components(
	systems: Array[Dictionary],
	links: Array[Vector2i],
	dedupe: Dictionary,
	parent: Array[int],
	rank: Array[int],
	degrees: Array[int]
) -> void:
	var fallback_edges: Array = _build_fallback_hyperlane_edge_records(systems)
	fallback_edges.sort_custom(_sort_hyperlane_edges_by_distance)

	for edge_variant in fallback_edges:
		if links.size() >= systems.size() - 1:
			return

		var edge: Dictionary = edge_variant
		var a_index: int = int(edge.get("a", -1))
		var b_index: int = int(edge.get("b", -1))
		if a_index == -1 or b_index == -1:
			continue
		if _uf_find(parent, a_index) == _uf_find(parent, b_index):
			continue
		if _add_hyperlane_link(a_index, b_index, systems, 0.0, links, dedupe):
			degrees[a_index] += 1
			degrees[b_index] += 1
			_uf_union(parent, rank, a_index, b_index)


func _build_fallback_hyperlane_edge_records(systems: Array[Dictionary]) -> Array:
	var fallback_points: Array = []
	for system_index in range(systems.size()):
		fallback_points.append({
			"index": system_index,
			"point": _get_cached_map_point(system_index, systems[system_index]["position"]),
		})
	fallback_points.sort_custom(_sort_fallback_hyperlane_points)

	var fallback_edges: Array = []
	var dedupe: Dictionary = {}
	for point_index in range(fallback_points.size() - 1):
		var a_index: int = int(fallback_points[point_index].get("index", -1))
		var b_index: int = int(fallback_points[point_index + 1].get("index", -1))
		if a_index == -1 or b_index == -1:
			continue
		_append_candidate_edge(fallback_edges, dedupe, a_index, b_index, _get_map_distance_sq(systems, a_index, b_index))
	return fallback_edges


func _sort_fallback_hyperlane_points(a: Dictionary, b: Dictionary) -> bool:
	var a_point: Vector2 = a.get("point", Vector2.ZERO)
	var b_point: Vector2 = b.get("point", Vector2.ZERO)
	if not is_equal_approx(a_point.x, b_point.x):
		return a_point.x < b_point.x
	return a_point.y < b_point.y


func _get_target_average_hyperlane_degree(density: int) -> float:
	var density_ratio: float = clampf(float(density - 1) / 7.0, 0.0, 1.0)
	return lerpf(2.1, 3.7, density_ratio)


func _get_target_hyperlane_edge_count(system_count: int, density: int) -> int:
	if system_count <= 1:
		return 0
	var max_planar_edges: int = 1 if system_count == 2 else 3 * system_count - 6
	var target_edges := int(round(float(system_count) * _get_target_average_hyperlane_degree(density) * 0.5))
	return clampi(target_edges, system_count - 1, max_planar_edges)


func _get_extra_hyperlane_skip_chance(density: int) -> float:
	var density_ratio: float = clampf(float(density - 1) / 7.0, 0.0, 1.0)
	return lerpf(0.45, 0.12, density_ratio)


func _hyperlane_crosses_existing(a_index: int, b_index: int, systems: Array[Dictionary], links: Array[Vector2i]) -> bool:
	var start_point := _get_cached_map_point(a_index, systems[a_index]["position"])
	var end_point := _get_cached_map_point(b_index, systems[b_index]["position"])

	for existing_link in links:
		if existing_link.x == a_index or existing_link.x == b_index or existing_link.y == a_index or existing_link.y == b_index:
			continue
		var existing_start := _get_cached_map_point(existing_link.x, systems[existing_link.x]["position"])
		var existing_end := _get_cached_map_point(existing_link.y, systems[existing_link.y]["position"])
		if _segments_intersect_2d(start_point, end_point, existing_start, existing_end):
			return true

	return false


func _hyperlane_has_system_clearance(
	a_index: int,
	b_index: int,
	systems: Array[Dictionary],
	clearance_radius: float
) -> bool:
	if clearance_radius <= 0.0:
		return true

	var segment_start := _get_cached_map_point(a_index, systems[a_index]["position"])
	var segment_end := _get_cached_map_point(b_index, systems[b_index]["position"])
	var clearance_sq := clearance_radius * clearance_radius
	var min_x := minf(segment_start.x, segment_end.x) - clearance_radius
	var max_x := maxf(segment_start.x, segment_end.x) + clearance_radius
	var min_y := minf(segment_start.y, segment_end.y) - clearance_radius
	var max_y := maxf(segment_start.y, segment_end.y) + clearance_radius

	if _hyperlane_system_query_grid.is_empty() or _hyperlane_system_query_cell_size <= 0.0:
		for system_index in range(systems.size()):
			if system_index == a_index or system_index == b_index:
				continue
			var system_point := _get_cached_map_point(system_index, systems[system_index]["position"])
			if _distance_sq_to_segment(system_point, segment_start, segment_end) < clearance_sq:
				return false
		return true

	var min_cell := _get_hyperlane_query_cell(Vector2(min_x, min_y))
	var max_cell := _get_hyperlane_query_cell(Vector2(max_x, max_y))
	for x_index in range(min_cell.x, max_cell.x + 1):
		for y_index in range(min_cell.y, max_cell.y + 1):
			var cell := Vector2i(x_index, y_index)
			if not _hyperlane_system_query_grid.has(cell):
				continue
			var candidate_indices: Array = _hyperlane_system_query_grid[cell]
			for candidate_index_variant in candidate_indices:
				var system_index: int = int(candidate_index_variant)
				if system_index == a_index or system_index == b_index:
					continue
				var system_point := _hyperlane_map_points[system_index]
				if system_point.x < min_x or system_point.x > max_x or system_point.y < min_y or system_point.y > max_y:
					continue
				if _distance_sq_to_segment(system_point, segment_start, segment_end) < clearance_sq:
					return false

	return true


func _distance_sq_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var segment_length_sq := segment.length_squared()
	if segment_length_sq <= 0.001:
		return point.distance_squared_to(segment_start)

	var t := clampf((point - segment_start).dot(segment) / segment_length_sq, 0.0, 1.0)
	var closest_point := segment_start + segment * t
	return point.distance_squared_to(closest_point)


func _segments_intersect_2d(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var orientation_abc := _segment_orientation(a, b, c)
	var orientation_abd := _segment_orientation(a, b, d)
	var orientation_cda := _segment_orientation(c, d, a)
	var orientation_cdb := _segment_orientation(c, d, b)

	if orientation_abc * orientation_abd < 0.0 and orientation_cda * orientation_cdb < 0.0:
		return true
	if is_zero_approx(orientation_abc) and _point_on_segment(c, a, b):
		return true
	if is_zero_approx(orientation_abd) and _point_on_segment(d, a, b):
		return true
	if is_zero_approx(orientation_cda) and _point_on_segment(a, c, d):
		return true
	if is_zero_approx(orientation_cdb) and _point_on_segment(b, c, d):
		return true

	return false


func _segment_orientation(a: Vector2, b: Vector2, c: Vector2) -> float:
	var value: float = (b - a).cross(c - a)
	if absf(value) <= HYPERLANE_INTERSECTION_EPSILON:
		return 0.0
	return value


func _point_on_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> bool:
	return (
		point.x >= minf(segment_start.x, segment_end.x) - HYPERLANE_INTERSECTION_EPSILON
		and point.x <= maxf(segment_start.x, segment_end.x) + HYPERLANE_INTERSECTION_EPSILON
		and point.y >= minf(segment_start.y, segment_end.y) - HYPERLANE_INTERSECTION_EPSILON
		and point.y <= maxf(segment_start.y, segment_end.y) + HYPERLANE_INTERSECTION_EPSILON
	)


func _get_map_distance_sq(systems: Array[Dictionary], a_index: int, b_index: int) -> float:
	return _get_cached_map_point(a_index, systems[a_index]["position"]).distance_squared_to(_get_cached_map_point(b_index, systems[b_index]["position"]))


func _get_hyperlane_system_clearance_radius(min_system_distance: float) -> float:
	return maxf(min_system_distance * HYPERLANE_SYSTEM_CLEARANCE_FACTOR, HYPERLANE_SYSTEM_CLEARANCE_MIN)


func _make_hyperlane_edge_key(a_index: int, b_index: int) -> String:
	return "%s:%s" % [mini(a_index, b_index), maxi(a_index, b_index)]


func _prepare_hyperlane_query_cache(systems: Array[Dictionary], cell_size: float) -> void:
	_hyperlane_map_points.clear()
	_hyperlane_map_points.resize(systems.size())
	_hyperlane_system_query_grid.clear()
	_hyperlane_system_query_cell_size = maxf(cell_size, 1.0)

	for system_index in range(systems.size()):
		var position: Vector3 = systems[system_index]["position"]
		var map_point := _to_map_point(position)
		_hyperlane_map_points[system_index] = map_point
		var cell := _get_hyperlane_query_cell(map_point)
		var cell_entries: Array = _hyperlane_system_query_grid.get(cell, [])
		cell_entries.append(system_index)
		_hyperlane_system_query_grid[cell] = cell_entries


func _clear_hyperlane_query_cache() -> void:
	_hyperlane_map_points.clear()
	_hyperlane_system_query_grid.clear()
	_hyperlane_system_query_cell_size = 0.0


func _get_cached_map_point(system_index: int, fallback_position: Vector3) -> Vector2:
	if system_index >= 0 and system_index < _hyperlane_map_points.size():
		return _hyperlane_map_points[system_index]
	return _to_map_point(fallback_position)


func _get_hyperlane_query_cell(point: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(point.x / _hyperlane_system_query_cell_size)),
		int(floor(point.y / _hyperlane_system_query_cell_size))
	)


func _to_map_point(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z)


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
		"metadata": {
			"star_visual": _build_star_visual_metadata(star_rng, special_type, true),
		},
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
			"metadata": {
				"star_visual": _build_star_visual_metadata(star_rng, SPECIAL_TYPE_NONE, false),
			},
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
	result["metadata"] = result.get("metadata", {}).duplicate(true)
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
	var habitability_points: int = clampi(int(result.get("habitability_points", _to_points(float(result.get("habitability", 0.0))))), 0, 100)
	var resource_richness_points: int = clampi(int(result.get("resource_richness_points", _to_points(float(result.get("resource_richness", 0.5))))), 0, 100)
	result["habitability_points"] = habitability_points
	result["habitability"] = float(habitability_points) / 100.0
	result["resource_richness_points"] = resource_richness_points
	result["resource_richness"] = float(resource_richness_points) / 100.0
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


func _to_points(value: float) -> int:
	return clampi(int(round(clampf(value, 0.0, 1.0) * 100.0)), 0, 100)
 
 
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
