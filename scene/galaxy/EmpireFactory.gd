extends RefCounted

const NAME_PREFIXES := [
	"Auroran",
	"Cygnan",
	"Helion",
	"Nebular",
	"Orion",
	"Solari",
	"Vesper",
	"Zephran",
	"Lyrian",
	"Dracon",
	"Altair",
	"Ecliptic",
]

const NAME_SUFFIXES := [
	"League",
	"Compact",
	"Union",
	"Dominion",
	"Assembly",
	"Mandate",
	"Accord",
	"Consortium",
	"Conclave",
	"Collective",
]

const EMPIRE_COLORS := [
	Color(0.26, 0.79, 1.0, 1.0),
	Color(1.0, 0.46, 0.32, 1.0),
	Color(1.0, 0.81, 0.27, 1.0),
	Color(0.47, 0.89, 0.56, 1.0),
	Color(0.78, 0.47, 1.0, 1.0),
	Color(1.0, 0.4, 0.68, 1.0),
	Color(0.55, 0.88, 0.94, 1.0),
	Color(0.93, 0.62, 0.26, 1.0),
]

const MIN_DEFAULT_EMPIRES := 4
const MAX_DEFAULT_EMPIRES := 8


func build_default_empires(galaxy_seed: int, system_count: int, desired_count: int = -1) -> Array[Dictionary]:
	var empire_count: int = desired_count
	if empire_count <= 0:
		empire_count = clampi(int(round(float(system_count) / 280.0)), MIN_DEFAULT_EMPIRES, MAX_DEFAULT_EMPIRES)

	var rng := RandomNumberGenerator.new()
	rng.seed = galaxy_seed + 918273645
	var color_offset: int = 0
	if not EMPIRE_COLORS.is_empty():
		color_offset = int(abs(galaxy_seed) % EMPIRE_COLORS.size())

	var empires: Array[Dictionary] = []
	var used_names: Dictionary = {}

	for empire_index in range(empire_count):
		var empire_name := _build_unique_name(rng, used_names)
		var color: Color = EMPIRE_COLORS[(empire_index + color_offset) % EMPIRE_COLORS.size()]
		empires.append({
			"id": "empire_%02d" % empire_index,
			"name": empire_name,
			"color": color,
			"controller_kind": "unassigned",
			"controller_peer_id": 0,
			"is_local_player": false,
			"ai_profile": "",
			"player_slot": empire_index,
			"home_system_id": "",
		})

	return empires


func _build_unique_name(rng: RandomNumberGenerator, used_names: Dictionary) -> String:
	for _attempt in range(32):
		var prefix: String = NAME_PREFIXES[rng.randi_range(0, NAME_PREFIXES.size() - 1)]
		var suffix: String = NAME_SUFFIXES[rng.randi_range(0, NAME_SUFFIXES.size() - 1)]
		var candidate := "%s %s" % [prefix, suffix]
		if used_names.has(candidate):
			continue
		used_names[candidate] = true
		return candidate

	var fallback_name := "Empire %02d" % (used_names.size() + 1)
	used_names[fallback_name] = true
	return fallback_name
