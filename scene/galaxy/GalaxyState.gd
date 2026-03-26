extends RefCounted

const DEFAULT_STAR_PROFILE := {
	"system_type": "normal",
	"star_count": 1,
	"special_type": "none",
	"display_color": Color(1.0, 0.86, 0.22, 1.0),
	"primary_color_name": "Yellow",
	"primary_size_name": "Normal",
	"star_class": "G",
	"stars": [{
		"index": 0,
		"color_name": "Yellow",
		"color": Color(1.0, 0.86, 0.22, 1.0),
		"size_name": "Normal",
		"scale": 1.0,
		"is_primary": true,
		"special_type": "none",
		"star_class": "G",
	}],
}
const DEFAULT_SYSTEM_SUMMARY := {
	"star_count": 1,
	"star_class": "G",
	"special_type": "none",
	"planet_count": 0,
	"asteroid_belt_count": 0,
	"structure_count": 0,
	"ruin_count": 0,
	"colonizable_worlds": 0,
	"habitable_worlds": 0,
	"anomaly_risk": 0.0,
}

var generated_seed: int = 0
var system_records: Array[Dictionary] = []
var system_positions: Array[Vector3] = []
var hyperlane_links: Array[Vector2i] = []
var hyperlane_graph: Dictionary = {}
var systems_by_id: Dictionary = {}
var system_indices_by_id: Dictionary = {}
var system_detail_overrides_by_id: Dictionary = {}
var ownership_by_system_id: Dictionary = {}
var empires: Array[Dictionary] = []
var empires_by_id: Dictionary = {}
var empire_ids: PackedStringArray = PackedStringArray()


func reset() -> void:
	generated_seed = 0
	system_records.clear()
	system_positions.clear()
	hyperlane_links.clear()
	hyperlane_graph.clear()
	systems_by_id.clear()
	system_indices_by_id.clear()
	system_detail_overrides_by_id.clear()
	ownership_by_system_id.clear()
	empires.clear()
	empires_by_id.clear()
	empire_ids = PackedStringArray()


func load_from_layout(layout: Dictionary) -> void:
	reset()
	generated_seed = int(layout.get("seed", 0))

	for system_variant in layout.get("systems", []):
		var system_record: Dictionary = _normalize_system_record(system_variant.duplicate(true))
		system_records.append(system_record)

	system_detail_overrides_by_id = layout.get("system_detail_overrides", {}).duplicate(true)

	for link_variant in layout.get("links", []):
		var link: Vector2i = link_variant
		if link.x == link.y:
			continue
		hyperlane_links.append(Vector2i(mini(link.x, link.y), maxi(link.x, link.y)))

	hyperlane_graph = layout.get("hyperlane_graph", {}).duplicate(true)
	_rebuild_system_indexes()
	_rebuild_ownership_index()
	_rebuild_hyperlane_graph()


func set_empires(empire_records: Array[Dictionary]) -> void:
	empires.clear()
	for empire_index in range(empire_records.size()):
		var empire_record: Dictionary = _normalize_empire_record(empire_records[empire_index].duplicate(true), empire_index)
		empires.append(empire_record)

	_rebuild_empire_indexes()
	_rebuild_empire_owned_system_ids()


func get_system(system_id: String) -> Dictionary:
	return systems_by_id.get(system_id, {})


func get_system_summary(system_id: String) -> Dictionary:
	if not systems_by_id.has(system_id):
		return DEFAULT_SYSTEM_SUMMARY.duplicate(true)
	return systems_by_id[system_id].get("system_summary", DEFAULT_SYSTEM_SUMMARY).duplicate(true)


func get_system_detail_override(system_id: String) -> Dictionary:
	return system_detail_overrides_by_id.get(system_id, {}).duplicate(true)


func get_empire(empire_id: String) -> Dictionary:
	return empires_by_id.get(empire_id, {})


func get_system_owner_id(system_id: String) -> String:
	return str(ownership_by_system_id.get(system_id, ""))


func get_system_owner(system_id: String) -> Dictionary:
	var owner_id := get_system_owner_id(system_id)
	if owner_id.is_empty():
		return {}
	return empires_by_id.get(owner_id, {})


func get_owned_system_ids(empire_id: String) -> PackedStringArray:
	if not empires_by_id.has(empire_id):
		return PackedStringArray()
	return empires_by_id[empire_id].get("owned_system_ids", PackedStringArray())


func get_neighbor_system_ids(system_id: String) -> PackedStringArray:
	if not system_indices_by_id.has(system_id):
		return PackedStringArray()

	var system_index: int = system_indices_by_id[system_id]
	var adjacency: Dictionary = hyperlane_graph.get("adjacency", {})
	var neighbor_indices: Array = adjacency.get(system_index, [])
	var neighbor_ids := PackedStringArray()

	for neighbor_variant in neighbor_indices:
		var neighbor_index: int = int(neighbor_variant)
		if neighbor_index < 0 or neighbor_index >= system_records.size():
			continue
		neighbor_ids.append(str(system_records[neighbor_index].get("id", "")))

	return neighbor_ids


func set_system_owner(system_id: String, empire_id: String) -> bool:
	if not system_indices_by_id.has(system_id):
		return false
	if not empire_id.is_empty() and not empires_by_id.has(empire_id):
		return false

	var system_index: int = system_indices_by_id[system_id]
	var system_record: Dictionary = system_records[system_index]
	var current_owner_id: String = str(system_record.get("owner_empire_id", ""))
	if current_owner_id == empire_id:
		return false

	system_record["owner_empire_id"] = empire_id
	system_records[system_index] = system_record
	systems_by_id[system_id] = system_record

	if empire_id.is_empty():
		ownership_by_system_id.erase(system_id)
	else:
		ownership_by_system_id[system_id] = empire_id

	_rebuild_empire_owned_system_ids()
	return true


func clear_system_owner(system_id: String) -> bool:
	return set_system_owner(system_id, "")


func set_system_detail_override(system_id: String, detail_override: Dictionary) -> bool:
	if not system_indices_by_id.has(system_id):
		return false

	if detail_override.is_empty():
		system_detail_overrides_by_id.erase(system_id)
	else:
		system_detail_overrides_by_id[system_id] = detail_override.duplicate(true)
	return true


func clear_system_detail_override(system_id: String) -> bool:
	if not system_detail_overrides_by_id.has(system_id):
		return false
	system_detail_overrides_by_id.erase(system_id)
	return true


func update_system_record(system_id: String, updated_fields: Dictionary) -> bool:
	if not system_indices_by_id.has(system_id):
		return false

	var system_index: int = int(system_indices_by_id[system_id])
	var system_record: Dictionary = system_records[system_index]
	for field_key_variant in updated_fields.keys():
		var field_key: String = str(field_key_variant)
		var field_value: Variant = updated_fields[field_key_variant]
		system_record[field_key] = field_value

	system_records[system_index] = _normalize_system_record(system_record)
	_rebuild_system_indexes()
	_rebuild_ownership_index()
	return true


func set_local_player_empire(empire_id: String) -> bool:
	if not empire_id.is_empty() and not empires_by_id.has(empire_id):
		return false

	for empire_index in range(empires.size()):
		var empire_record: Dictionary = empires[empire_index]
		var current_empire_id: String = str(empire_record.get("id", ""))
		var is_selected := current_empire_id == empire_id and not empire_id.is_empty()
		var was_local := bool(empire_record.get("is_local_player", false)) or str(empire_record.get("controller_kind", "")) == "local_player"
		if is_selected:
			empire_record["is_local_player"] = true
			empire_record["controller_kind"] = "local_player"
		elif was_local:
			empire_record["is_local_player"] = false
			empire_record["controller_kind"] = "unassigned"
			empire_record["controller_peer_id"] = 0
		empires[empire_index] = empire_record

	_rebuild_empire_indexes()
	_rebuild_empire_owned_system_ids()
	return true


func add_system(system_record: Dictionary) -> bool:
	var normalized_record: Dictionary = _normalize_system_record(system_record.duplicate(true))
	var system_id: String = str(normalized_record.get("id", ""))
	if system_id.is_empty() or systems_by_id.has(system_id):
		return false

	system_records.append(normalized_record)
	_rebuild_system_indexes()
	_rebuild_ownership_index()
	_rebuild_hyperlane_graph()
	_rebuild_empire_owned_system_ids()
	return true


func add_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if not system_indices_by_id.has(system_a_id) or not system_indices_by_id.has(system_b_id):
		return false

	var a_index: int = int(system_indices_by_id[system_a_id])
	var b_index: int = int(system_indices_by_id[system_b_id])
	if a_index == b_index:
		return false

	var normalized_link := Vector2i(mini(a_index, b_index), maxi(a_index, b_index))
	for existing_link in hyperlane_links:
		if existing_link == normalized_link:
			return false

	hyperlane_links.append(normalized_link)
	_rebuild_hyperlane_graph()
	return true


func remove_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if not system_indices_by_id.has(system_a_id) or not system_indices_by_id.has(system_b_id):
		return false

	var a_index: int = int(system_indices_by_id[system_a_id])
	var b_index: int = int(system_indices_by_id[system_b_id])
	var normalized_link := Vector2i(mini(a_index, b_index), maxi(a_index, b_index))
	var removed: bool = false
	var remaining_links: Array[Vector2i] = []

	for existing_link in hyperlane_links:
		if existing_link == normalized_link:
			removed = true
			continue
		remaining_links.append(existing_link)

	if not removed:
		return false

	hyperlane_links = remaining_links
	_rebuild_hyperlane_graph()
	return true


func build_snapshot() -> Dictionary:
	return {
		"seed": generated_seed,
		"systems": system_records.duplicate(true),
		"system_positions": system_positions.duplicate(),
		"links": hyperlane_links.duplicate(),
		"hyperlane_graph": hyperlane_graph.duplicate(true),
		"system_detail_overrides": system_detail_overrides_by_id.duplicate(true),
		"empires": empires.duplicate(true),
		"ownership_by_system_id": ownership_by_system_id.duplicate(true),
	}


func _normalize_system_record(system_record: Dictionary) -> Dictionary:
	if not system_record.has("id"):
		system_record["id"] = "sys_%04d" % system_records.size()
	if not system_record.has("name"):
		system_record["name"] = str(system_record["id"])
	if not system_record.has("position"):
		system_record["position"] = Vector3.ZERO
	if not system_record.has("is_custom"):
		system_record["is_custom"] = false
	if not system_record.has("custom_index"):
		system_record["custom_index"] = -1
	if not system_record.has("owner_empire_id"):
		system_record["owner_empire_id"] = ""
	if not system_record.has("star_profile"):
		system_record["star_profile"] = DEFAULT_STAR_PROFILE.duplicate(true)
	if not system_record.has("system_summary"):
		system_record["system_summary"] = DEFAULT_SYSTEM_SUMMARY.duplicate(true)
	return system_record


func _normalize_empire_record(empire_record: Dictionary, empire_index: int) -> Dictionary:
	if not empire_record.has("id"):
		empire_record["id"] = "empire_%02d" % empire_index
	if not empire_record.has("name"):
		empire_record["name"] = "Empire %02d" % (empire_index + 1)
	if not empire_record.has("color"):
		empire_record["color"] = Color.from_hsv(float(empire_index) / 8.0, 0.65, 1.0)
	if not empire_record.has("controller_kind"):
		empire_record["controller_kind"] = "unassigned"
	if not empire_record.has("controller_peer_id"):
		empire_record["controller_peer_id"] = 0
	if not empire_record.has("is_local_player"):
		empire_record["is_local_player"] = false
	if not empire_record.has("ai_profile"):
		empire_record["ai_profile"] = ""
	if not empire_record.has("player_slot"):
		empire_record["player_slot"] = empire_index
	if not empire_record.has("home_system_id"):
		empire_record["home_system_id"] = ""
	empire_record["owned_system_ids"] = PackedStringArray()
	return empire_record


func _rebuild_system_indexes() -> void:
	systems_by_id.clear()
	system_indices_by_id.clear()
	system_positions.clear()

	for system_index in range(system_records.size()):
		var system_record: Dictionary = system_records[system_index]
		var system_id: String = str(system_record.get("id", ""))
		systems_by_id[system_id] = system_record
		system_indices_by_id[system_id] = system_index
		system_positions.append(system_record.get("position", Vector3.ZERO))


func _rebuild_ownership_index() -> void:
	ownership_by_system_id.clear()
	for system_index in range(system_records.size()):
		var system_record: Dictionary = system_records[system_index]
		var owner_empire_id: String = str(system_record.get("owner_empire_id", ""))
		if owner_empire_id.is_empty():
			continue
		ownership_by_system_id[str(system_record.get("id", ""))] = owner_empire_id


func _rebuild_empire_indexes() -> void:
	empires_by_id.clear()
	empire_ids = PackedStringArray()

	for empire_record_variant in empires:
		var empire_record: Dictionary = empire_record_variant
		var empire_id: String = str(empire_record.get("id", ""))
		if empire_id.is_empty():
			continue
		empires_by_id[empire_id] = empire_record
		empire_ids.append(empire_id)


func _rebuild_empire_owned_system_ids() -> void:
	for empire_index in range(empires.size()):
		var empire_record: Dictionary = empires[empire_index]
		empire_record["owned_system_ids"] = PackedStringArray()
		empires[empire_index] = empire_record

	for system_record_variant in system_records:
		var system_record: Dictionary = system_record_variant
		var owner_empire_id: String = str(system_record.get("owner_empire_id", ""))
		if owner_empire_id.is_empty():
			continue

		for empire_index in range(empires.size()):
			var empire_record: Dictionary = empires[empire_index]
			if str(empire_record.get("id", "")) != owner_empire_id:
				continue

			var owned_ids: PackedStringArray = empire_record.get("owned_system_ids", PackedStringArray())
			owned_ids.append(str(system_record.get("id", "")))
			empire_record["owned_system_ids"] = owned_ids
			empires[empire_index] = empire_record
			break

	_rebuild_empire_indexes()


func _rebuild_hyperlane_graph() -> void:
	var previous_graph := hyperlane_graph.duplicate(true)
	var adjacency: Dictionary = {}
	var normalized_links: Array[Vector2i] = []
	var seen_links: Dictionary = {}

	for system_index in range(system_records.size()):
		adjacency[system_index] = []

	for link_variant in hyperlane_links:
		var link: Vector2i = link_variant
		if link.x < 0 or link.y < 0:
			continue
		if link.x >= system_records.size() or link.y >= system_records.size():
			continue
		if link.x == link.y:
			continue

		var normalized_link := Vector2i(mini(link.x, link.y), maxi(link.x, link.y))
		var link_key := "%s:%s" % [normalized_link.x, normalized_link.y]
		if seen_links.has(link_key):
			continue

		seen_links[link_key] = true
		normalized_links.append(normalized_link)

		var a_neighbors: Array = adjacency.get(normalized_link.x, [])
		a_neighbors.append(normalized_link.y)
		adjacency[normalized_link.x] = a_neighbors

		var b_neighbors: Array = adjacency.get(normalized_link.y, [])
		b_neighbors.append(normalized_link.x)
		adjacency[normalized_link.y] = b_neighbors

	hyperlane_links = normalized_links
	hyperlane_graph = {
		"links": hyperlane_links.duplicate(),
		"adjacency": adjacency,
		"min_links_per_system": int(previous_graph.get("min_links_per_system", mini(2, maxi(system_records.size() - 1, 0)))),
		"max_links_per_system": int(previous_graph.get("max_links_per_system", mini(5, maxi(system_records.size() - 1, 0)))),
		"target_links_per_system": int(previous_graph.get("target_links_per_system", mini(3, maxi(system_records.size() - 1, 0)))),
	}
