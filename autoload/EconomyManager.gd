extends Node

const RESOURCE_REGISTRY_SCRIPT := preload("res://core/economy/ResourceRegistry.gd")
const RESOURCE_BUNDLE_SCRIPT := preload("res://core/economy/ResourceBundle.gd")
const ECONOMY_SOURCE_RECORD_SCRIPT := preload("res://core/economy/EconomySourceRecord.gd")

signal registry_loaded(registry_hash: String, resource_ids: PackedStringArray)
signal economy_bootstrapped(empire_ids: PackedStringArray)
signal empire_stockpile_changed(empire_id: String, revision: int)
signal monthly_settlement_completed(month_serial: int)
signal source_registered(source_id: String)
signal source_removed(source_id: String)

var _registry: ResourceRegistry = RESOURCE_REGISTRY_SCRIPT.new()
var _bootstrapped: bool = false
var _month_serial: int = 0
var _empire_ids: PackedStringArray = PackedStringArray()
var _empire_indices_by_id: Dictionary = {}
var _stockpile: PackedInt64Array = PackedInt64Array()
var _capacity: PackedInt64Array = PackedInt64Array()
var _monthly_income: PackedInt64Array = PackedInt64Array()
var _monthly_expense: PackedInt64Array = PackedInt64Array()
var _last_shortage: PackedInt64Array = PackedInt64Array()
var _revision_by_empire: PackedInt64Array = PackedInt64Array()
var _sources: Dictionary = {}
var _source_ids_by_system_id: Dictionary = {}


func _ready() -> void:
	load_registry()
	if SimClock != null and not SimClock.month_tick.is_connected(_on_month_tick):
		SimClock.month_tick.connect(_on_month_tick)


func load_registry() -> bool:
	var loaded: bool = _registry.load_definitions()
	if loaded:
		registry_loaded.emit(_registry.registry_hash, _registry.get_resource_ids())
	return loaded


func is_bootstrapped() -> bool:
	return _bootstrapped


func get_registry_hash() -> String:
	return _registry.registry_hash


func get_resource_ids() -> PackedStringArray:
	return _registry.get_resource_ids()


func has_resource(resource_id: String) -> bool:
	return _registry.has_resource(resource_id)


func has_source(source_id: String) -> bool:
	return _sources.has(source_id)


func compile_bundle(value: Variant) -> ResourceBundle:
	return _registry.compile_bundle(value)


func bootstrap(empire_ids_variant: Variant, galaxy_snapshot: Dictionary) -> void:
	if _registry.size() == 0 and not load_registry():
		clear_runtime_state()
		return

	clear_runtime_state(false)

	var normalized_empire_ids := _normalize_empire_ids(empire_ids_variant)
	_empire_ids = normalized_empire_ids
	for empire_index in range(_empire_ids.size()):
		_empire_indices_by_id[_empire_ids[empire_index]] = empire_index

	var resource_count := _registry.size()
	var empire_count := _empire_ids.size()
	var total_cell_count := resource_count * empire_count
	_stockpile.resize(total_cell_count)
	_capacity.resize(total_cell_count)
	_monthly_income.resize(total_cell_count)
	_monthly_expense.resize(total_cell_count)
	_last_shortage.resize(total_cell_count)
	_revision_by_empire.resize(empire_count)

	var starting_stockpile_row := _registry.build_starting_stockpile_row()
	var base_capacity_row := _registry.build_base_capacity_row()
	for empire_index in range(empire_count):
		for resource_index in range(resource_count):
			var cell_index := _get_cell_index(empire_index, resource_index)
			_stockpile[cell_index] = starting_stockpile_row[resource_index]
			_capacity[cell_index] = base_capacity_row[resource_index]
			_monthly_income[cell_index] = 0
			_monthly_expense[cell_index] = 0
			_last_shortage[cell_index] = 0
		_revision_by_empire[empire_index] = 0

	_bootstrapped = true
	_month_serial = SimClock.get_current_month_serial() if SimClock != null and SimClock.has_method("get_current_month_serial") else 0
	_register_galaxy_sources_from_snapshot(galaxy_snapshot)
	economy_bootstrapped.emit(_empire_ids.duplicate())


func clear_runtime_state(clear_registry: bool = false) -> void:
	_bootstrapped = false
	_month_serial = 0
	_empire_ids = PackedStringArray()
	_empire_indices_by_id.clear()
	_stockpile = PackedInt64Array()
	_capacity = PackedInt64Array()
	_monthly_income = PackedInt64Array()
	_monthly_expense = PackedInt64Array()
	_last_shortage = PackedInt64Array()
	_revision_by_empire = PackedInt64Array()
	_sources.clear()
	_source_ids_by_system_id.clear()
	if clear_registry:
		_registry = RESOURCE_REGISTRY_SCRIPT.new()


func register_source(
	source_id: String,
	owner_empire_id: String,
	income: Variant,
	expense: Variant,
	capacity: Variant = [],
	kind: String = "",
	tags: PackedStringArray = PackedStringArray()
) -> bool:
	if not _bootstrapped:
		return false
	source_id = source_id.strip_edges()
	owner_empire_id = owner_empire_id.strip_edges()
	if source_id.is_empty() or owner_empire_id.is_empty() or _sources.has(source_id):
		return false

	var owner_empire_index := _get_empire_index(owner_empire_id)
	if owner_empire_index < 0:
		return false

	var record := ECONOMY_SOURCE_RECORD_SCRIPT.new() as EconomySourceRecord
	record.source_id = source_id
	record.owner_empire_index = owner_empire_index
	record.kind = kind
	record.active = true
	record.income_bundle = _registry.compile_bundle(income)
	record.expense_bundle = _registry.compile_bundle(expense)
	record.capacity_bundle = _registry.compile_bundle(capacity)
	record.tags = tags.duplicate()
	_sources[source_id] = record
	_apply_source_to_owner(record, 1)
	source_registered.emit(source_id)
	return true


func update_source(source_id: String, income: Variant, expense: Variant, capacity: Variant = []) -> bool:
	var record := _sources.get(source_id, null) as EconomySourceRecord
	if record == null:
		return false

	_apply_source_to_owner(record, -1)
	record.income_bundle = _registry.compile_bundle(income)
	record.expense_bundle = _registry.compile_bundle(expense)
	record.capacity_bundle = _registry.compile_bundle(capacity)
	_apply_source_to_owner(record, 1)
	return true


func transfer_source(source_id: String, new_owner_empire_id: String) -> bool:
	var record := _sources.get(source_id, null) as EconomySourceRecord
	if record == null:
		return false

	var new_owner_index := _get_empire_index(new_owner_empire_id)
	if new_owner_index < 0 or new_owner_index == record.owner_empire_index:
		return false

	_apply_source_to_owner(record, -1)
	record.owner_empire_index = new_owner_index
	_apply_source_to_owner(record, 1)
	return true


func remove_source(source_id: String) -> bool:
	var record := _sources.get(source_id, null) as EconomySourceRecord
	if record == null:
		return false

	_apply_source_to_owner(record, -1)
	if record.kind == "orbital_deposit" and record.tags.size() > 0:
		var system_id: String = str(record.tags[0]).strip_edges()
		if not system_id.is_empty() and _source_ids_by_system_id.has(system_id):
			var system_source_ids: Dictionary = _source_ids_by_system_id[system_id]
			system_source_ids.erase(source_id)
			if system_source_ids.is_empty():
				_source_ids_by_system_id.erase(system_id)
			else:
				_source_ids_by_system_id[system_id] = system_source_ids
	_sources.erase(source_id)
	source_removed.emit(source_id)
	return true


func sync_system_sources(system_id: String, owner_empire_id: String, orbitals: Array, galaxy_seed: int = 0) -> void:
	system_id = system_id.strip_edges()
	if system_id.is_empty():
		return

	var existing_source_ids: Dictionary = _source_ids_by_system_id.get(system_id, {}).duplicate()
	if owner_empire_id.strip_edges().is_empty():
		for source_id_variant in existing_source_ids.keys():
			remove_source(str(source_id_variant))
		_source_ids_by_system_id.erase(system_id)
		return

	var desired_source_ids: Dictionary = {}
	for orbital_variant in orbitals:
		if orbital_variant is not Dictionary:
			continue
		var orbital: Dictionary = orbital_variant
		var orbital_id: String = str(orbital.get("id", "")).strip_edges()
		if orbital_id.is_empty():
			continue

		var income_bundle := _compile_orbital_income_bundle(galaxy_seed, system_id, orbital)
		if income_bundle.is_empty():
			continue

		var source_id := _build_orbital_source_id(system_id, orbital_id)
		desired_source_ids[source_id] = true
		var source_tags := PackedStringArray([system_id, orbital_id, str(orbital.get("type", ""))])
		if _sources.has(source_id):
			var source_record := _sources[source_id] as EconomySourceRecord
			source_record.kind = "orbital_deposit"
			source_record.tags = source_tags
			if source_record.owner_empire_index != _get_empire_index(owner_empire_id):
				transfer_source(source_id, owner_empire_id)
			if not source_record.income_bundle.is_equal_to(income_bundle):
				update_source(source_id, income_bundle, RESOURCE_BUNDLE_SCRIPT.new(), RESOURCE_BUNDLE_SCRIPT.new())
		else:
			register_source(source_id, owner_empire_id, income_bundle, RESOURCE_BUNDLE_SCRIPT.new(), RESOURCE_BUNDLE_SCRIPT.new(), "orbital_deposit", source_tags)

	existing_source_ids = _source_ids_by_system_id.get(system_id, {}).duplicate()
	for source_id_variant in existing_source_ids.keys():
		var source_id: String = str(source_id_variant)
		if desired_source_ids.has(source_id):
			continue
		remove_source(source_id)

	_source_ids_by_system_id[system_id] = desired_source_ids


func can_afford(empire_id: String, bundle_variant: Variant) -> bool:
	var empire_index := _get_empire_index(empire_id)
	if empire_index < 0:
		return false

	var bundle := _registry.compile_bundle(bundle_variant)
	for entry_index in range(bundle.resource_indices.size()):
		var resource_index := bundle.resource_indices[entry_index]
		if _stockpile[_get_cell_index(empire_index, resource_index)] < bundle.amounts[entry_index]:
			return false
	return true


func commit_cost(empire_id: String, bundle_variant: Variant) -> bool:
	var empire_index := _get_empire_index(empire_id)
	if empire_index < 0:
		return false

	var bundle := _registry.compile_bundle(bundle_variant)
	if not can_afford(empire_id, bundle):
		return false

	for entry_index in range(bundle.resource_indices.size()):
		var resource_index := bundle.resource_indices[entry_index]
		var cell_index := _get_cell_index(empire_index, resource_index)
		_stockpile[cell_index] -= bundle.amounts[entry_index]
	_mark_empire_changed(empire_index)
	return true


func grant_resources(empire_id: String, bundle_variant: Variant) -> bool:
	var empire_index := _get_empire_index(empire_id)
	if empire_index < 0:
		return false

	var bundle := _registry.compile_bundle(bundle_variant)
	for entry_index in range(bundle.resource_indices.size()):
		var resource_index := bundle.resource_indices[entry_index]
		var cell_index := _get_cell_index(empire_index, resource_index)
		_stockpile[cell_index] = mini(_stockpile[cell_index] + bundle.amounts[entry_index], _capacity[cell_index])
	_mark_empire_changed(empire_index)
	return true


func transfer_resources(from_empire_id: String, to_empire_id: String, bundle_variant: Variant) -> bool:
	if not commit_cost(from_empire_id, bundle_variant):
		return false
	return grant_resources(to_empire_id, bundle_variant)


func get_amount(empire_id: String, resource_id: String) -> int:
	var empire_index := _get_empire_index(empire_id)
	var resource_index := _registry.get_resource_index(resource_id)
	if empire_index < 0 or resource_index < 0:
		return 0
	return int(_stockpile[_get_cell_index(empire_index, resource_index)])


func get_projected_monthly_net(empire_id: String, resource_id: String) -> int:
	var empire_index := _get_empire_index(empire_id)
	var resource_index := _registry.get_resource_index(resource_id)
	if empire_index < 0 or resource_index < 0:
		return 0
	var cell_index := _get_cell_index(empire_index, resource_index)
	return int(_monthly_income[cell_index] - _monthly_expense[cell_index])


func get_shortage_last_tick(empire_id: String, resource_id: String) -> int:
	var empire_index := _get_empire_index(empire_id)
	var resource_index := _registry.get_resource_index(resource_id)
	if empire_index < 0 or resource_index < 0:
		return 0
	return int(_last_shortage[_get_cell_index(empire_index, resource_index)])


func get_stockpile_map(empire_id: String) -> Dictionary:
	return _build_resource_map(empire_id, _stockpile)


func get_projected_monthly_net_map(empire_id: String) -> Dictionary:
	var empire_index := _get_empire_index(empire_id)
	if empire_index < 0:
		return {}

	var result: Dictionary = {}
	for resource_index in range(_registry.size()):
		var resource_id := _registry.get_resource_id(resource_index)
		if resource_id.is_empty():
			continue
		var cell_index := _get_cell_index(empire_index, resource_index)
		result[resource_id] = int(_monthly_income[cell_index] - _monthly_expense[cell_index])
	return result


func get_shortage_map(empire_id: String) -> Dictionary:
	return _build_resource_map(empire_id, _last_shortage)


func months_until_shortage(empire_id: String, resource_id: String) -> int:
	var projected_net := get_projected_monthly_net(empire_id, resource_id)
	if projected_net >= 0:
		return -1

	var current_amount := get_amount(empire_id, resource_id)
	if current_amount <= 0:
		return 0

	var monthly_deficit := -projected_net
	return int(ceili(float(current_amount) / float(monthly_deficit)))


func get_bottleneck_resource(empire_id: String) -> String:
	var best_resource_id := ""
	var best_score := -INF
	for resource_id in _registry.get_resource_ids():
		var projected_net := get_projected_monthly_net(empire_id, resource_id)
		if projected_net >= 0:
			continue
		var months_left := months_until_shortage(empire_id, resource_id)
		var score := absf(float(projected_net))
		if months_left >= 0:
			score += maxf(0.0, 1000.0 - float(months_left) * 25.0)
		if score <= best_score:
			continue
		best_score = score
		best_resource_id = resource_id
	return best_resource_id


func build_snapshot() -> Dictionary:
	var source_snapshots: Array[Dictionary] = []
	for source_id_variant in _sources.keys():
		var source_id: String = str(source_id_variant)
		var source_record := _sources[source_id] as EconomySourceRecord
		if source_record == null:
			continue
		source_snapshots.append(source_record.to_dict())
	source_snapshots.sort_custom(_sort_source_snapshots)

	return {
		"registry_hash": _registry.registry_hash,
		"month_serial": _month_serial,
		"empire_ids": _packed_string_array_to_array(_empire_ids),
		"stockpile": _packed_int64_to_array(_stockpile),
		"capacity": _packed_int64_to_array(_capacity),
		"monthly_income": _packed_int64_to_array(_monthly_income),
		"monthly_expense": _packed_int64_to_array(_monthly_expense),
		"last_shortage": _packed_int64_to_array(_last_shortage),
		"revision_by_empire": _packed_int64_to_array(_revision_by_empire),
		"sources": source_snapshots,
	}


func load_snapshot(snapshot: Dictionary) -> void:
	if _registry.size() == 0:
		load_registry()

	clear_runtime_state(false)
	var snapshot_empire_ids := _normalize_empire_ids(snapshot.get("empire_ids", PackedStringArray()))
	_empire_ids = snapshot_empire_ids
	for empire_index in range(_empire_ids.size()):
		_empire_indices_by_id[_empire_ids[empire_index]] = empire_index

	var resource_count := _registry.size()
	var empire_count := _empire_ids.size()
	var total_cell_count := resource_count * empire_count

	_stockpile = _array_to_packed_int64(snapshot.get("stockpile", []), total_cell_count)
	_capacity = _array_to_packed_int64(snapshot.get("capacity", []), total_cell_count)
	_monthly_income = _array_to_packed_int64(snapshot.get("monthly_income", []), total_cell_count)
	_monthly_expense = _array_to_packed_int64(snapshot.get("monthly_expense", []), total_cell_count)
	_last_shortage = _array_to_packed_int64(snapshot.get("last_shortage", []), total_cell_count)
	_revision_by_empire = _array_to_packed_int64(snapshot.get("revision_by_empire", []), empire_count)
	_month_serial = int(snapshot.get("month_serial", 0))
	_bootstrapped = true

	for source_variant in snapshot.get("sources", []):
		if source_variant is not Dictionary:
			continue
		var source_record := ECONOMY_SOURCE_RECORD_SCRIPT.from_dict(source_variant)
		if source_record.source_id.is_empty():
			continue
		_sources[source_record.source_id] = source_record
		if source_record.kind == "orbital_deposit" and source_record.tags.size() > 0:
			var system_id: String = str(source_record.tags[0])
			if not system_id.is_empty():
				var system_source_ids: Dictionary = _source_ids_by_system_id.get(system_id, {})
				system_source_ids[source_record.source_id] = true
				_source_ids_by_system_id[system_id] = system_source_ids


func _on_month_tick(_year: int, _month: int) -> void:
	if not _bootstrapped:
		return

	var resource_count := _registry.size()
	for empire_index in range(_empire_ids.size()):
		var row_changed := false
		for resource_index in range(resource_count):
			var cell_index := _get_cell_index(empire_index, resource_index)
			var next_amount := _stockpile[cell_index] + _monthly_income[cell_index] - _monthly_expense[cell_index]
			var shortage := 0
			if next_amount < 0:
				shortage = -next_amount
				next_amount = 0
			next_amount = mini(next_amount, _capacity[cell_index])
			_last_shortage[cell_index] = shortage
			if _stockpile[cell_index] != next_amount:
				_stockpile[cell_index] = next_amount
				row_changed = true
		if row_changed:
			_mark_empire_changed(empire_index)

	_month_serial = SimClock.get_current_month_serial() if SimClock != null and SimClock.has_method("get_current_month_serial") else (_month_serial + 1)
	monthly_settlement_completed.emit(_month_serial)


func _register_galaxy_sources_from_snapshot(galaxy_snapshot: Dictionary) -> void:
	var generated_seed: int = int(galaxy_snapshot.get("generated_seed", galaxy_snapshot.get("seed", 0)))
	for system_variant in galaxy_snapshot.get("systems", []):
		if system_variant is not Dictionary:
			continue
		var system_record: Dictionary = system_variant
		sync_system_sources(
			str(system_record.get("id", "")),
			str(system_record.get("owner_empire_id", "")),
			system_record.get("orbitals", []),
			generated_seed
		)


func _compile_orbital_income_bundle(galaxy_seed: int, system_id: String, orbital: Dictionary) -> ResourceBundle:
	var orbital_type: String = str(orbital.get("type", "")).strip_edges()
	if orbital_type.is_empty():
		return RESOURCE_BUNDLE_SCRIPT.new()

	var richness_points: int = _resolve_points(orbital, "resource_richness_points", "resource_richness", 50)
	var habitability_points: int = _resolve_points(orbital, "habitability_points", "habitability", 0)
	var is_colonizable: bool = bool(orbital.get("is_colonizable", false)) or habitability_points >= 45
	var amounts: Array[Dictionary] = []

	match orbital_type:
		"planet":
			amounts.append({"resource_id": "matter", "milliunits": 20000 + richness_points * 800})
			amounts.append({"resource_id": "energy", "milliunits": 5000 + richness_points * 250})
			if is_colonizable:
				amounts.append({"resource_id": "food", "milliunits": 10000 + maxi(habitability_points, 20) * 500})
		"asteroid_belt":
			amounts.append({"resource_id": "matter", "milliunits": 40000 + richness_points * 1200})
			amounts.append({"resource_id": "alloys", "milliunits": 5000 + richness_points * 300})
		"structure":
			amounts.append({"resource_id": "energy", "milliunits": 25000 + richness_points * 600})
			amounts.append({"resource_id": "alloys", "milliunits": 2500 + richness_points * 120})
		"ruin":
			amounts.append({"resource_id": "matter", "milliunits": 10000 + richness_points * 400})
			amounts.append({"resource_id": "energy", "milliunits": 5000 + richness_points * 300})
		_:
			return RESOURCE_BUNDLE_SCRIPT.new()

	var orbital_id: String = str(orbital.get("id", "")).strip_edges()
	var base_hash: int = _stable_hash("%s:%s:%s:%s" % [galaxy_seed, system_id, orbital_id, orbital_type])
	if orbital_type in ["planet", "asteroid_belt", "ruin"] and base_hash % 100 < 10:
		amounts.append({"resource_id": "exotic_gases", "milliunits": 1500 + richness_points * 80})
	if orbital_type in ["structure", "ruin"] and base_hash % 211 == 0:
		amounts.append({"resource_id": "living_metal", "milliunits": 800 + richness_points * 35})
	if orbital_type in ["asteroid_belt", "ruin", "structure"] and base_hash % 257 == 0:
		amounts.append({"resource_id": "dark_matter", "milliunits": 600 + richness_points * 25})

	return _registry.compile_bundle(amounts)


func _apply_source_to_owner(record: EconomySourceRecord, delta_sign: int) -> void:
	if record == null or not record.active:
		return
	if record.owner_empire_index < 0 or record.owner_empire_index >= _empire_ids.size():
		return

	_apply_bundle_to_dense_row(record.owner_empire_index, record.income_bundle, _monthly_income, delta_sign)
	_apply_bundle_to_dense_row(record.owner_empire_index, record.expense_bundle, _monthly_expense, delta_sign)
	_apply_bundle_to_dense_row(record.owner_empire_index, record.capacity_bundle, _capacity, delta_sign)
	_clamp_stockpile_to_capacity(record.owner_empire_index)
	_mark_empire_changed(record.owner_empire_index)


func _apply_bundle_to_dense_row(empire_index: int, bundle: ResourceBundle, target: PackedInt64Array, delta_sign: int) -> void:
	if bundle == null:
		return

	for entry_index in range(bundle.resource_indices.size()):
		var resource_index := bundle.resource_indices[entry_index]
		var cell_index := _get_cell_index(empire_index, resource_index)
		target[cell_index] += bundle.amounts[entry_index] * delta_sign


func _clamp_stockpile_to_capacity(empire_index: int) -> void:
	for resource_index in range(_registry.size()):
		var cell_index := _get_cell_index(empire_index, resource_index)
		var max_capacity := maxi(_capacity[cell_index], 0)
		if _stockpile[cell_index] > max_capacity:
			_stockpile[cell_index] = max_capacity


func _mark_empire_changed(empire_index: int) -> void:
	if empire_index < 0 or empire_index >= _empire_ids.size():
		return
	_revision_by_empire[empire_index] += 1
	empire_stockpile_changed.emit(_empire_ids[empire_index], int(_revision_by_empire[empire_index]))


func _build_resource_map(empire_id: String, target: PackedInt64Array) -> Dictionary:
	var empire_index := _get_empire_index(empire_id)
	if empire_index < 0:
		return {}

	var result: Dictionary = {}
	for resource_index in range(_registry.size()):
		var resource_id := _registry.get_resource_id(resource_index)
		if resource_id.is_empty():
			continue
		result[resource_id] = int(target[_get_cell_index(empire_index, resource_index)])
	return result


func _get_cell_index(empire_index: int, resource_index: int) -> int:
	return empire_index * _registry.size() + resource_index


func _get_empire_index(empire_id: String) -> int:
	return int(_empire_indices_by_id.get(empire_id, -1))


func _normalize_empire_ids(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is PackedStringArray:
		for empire_id in value:
			var normalized_empire_id: String = str(empire_id).strip_edges()
			if normalized_empire_id.is_empty():
				continue
			result.append(normalized_empire_id)
		return result
	if value is not Array:
		return result
	for empire_id_variant in value:
		var empire_id: String = str(empire_id_variant).strip_edges()
		if empire_id.is_empty():
			continue
		result.append(empire_id)
	return result


func _resolve_points(data: Dictionary, points_key: String, legacy_float_key: String, default_points: int) -> int:
	if data.has(points_key):
		return clampi(int(data.get(points_key, default_points)), 0, 100)
	if data.has(legacy_float_key):
		return clampi(int(round(float(data.get(legacy_float_key, float(default_points) / 100.0)) * 100.0)), 0, 100)
	return clampi(default_points, 0, 100)


func _build_orbital_source_id(system_id: String, orbital_id: String) -> String:
	return "orbital:%s:%s" % [system_id, orbital_id]


func _stable_hash(value: String) -> int:
	var hash_value: int = 2166136261
	var bytes := value.to_utf8_buffer()
	for byte in bytes:
		hash_value = int(((hash_value ^ int(byte)) * 16777619) & 0x7fffffff)
	return hash_value


static func _packed_string_array_to_array(values: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(value)
	return result


static func _packed_int64_to_array(values: PackedInt64Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(value)
	return result


static func _array_to_packed_int64(value: Variant, target_size: int) -> PackedInt64Array:
	var result := PackedInt64Array()
	result.resize(target_size)
	if value is not Array:
		return result
	var array_value: Array = value
	for entry_index in range(mini(array_value.size(), target_size)):
		result[entry_index] = int(array_value[entry_index])
	return result


static func _sort_source_snapshots(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("source_id", "")).nocasecmp_to(str(b.get("source_id", ""))) < 0
