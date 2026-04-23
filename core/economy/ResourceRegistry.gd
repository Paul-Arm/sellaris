extends RefCounted
class_name ResourceRegistry

const RESOURCE_DEFINITION_SCRIPT := preload("res://core/economy/ResourceDefinition.gd")
const RESOURCE_AMOUNT_DEF_SCRIPT := preload("res://core/economy/ResourceAmountDef.gd")
const RESOURCE_BUNDLE_SCRIPT := preload("res://core/economy/ResourceBundle.gd")
const RESOURCE_DIRECTORY := "res://core/economy/resources"

var definitions: Array[ResourceDefinition] = []
var definitions_by_id: Dictionary = {}
var registry_hash: String = ""


func load_definitions() -> bool:
	definitions.clear()
	definitions_by_id.clear()
	registry_hash = ""

	var file_paths := _list_resource_definition_paths()
	for file_path in file_paths:
		var loaded_definition := load(file_path) as ResourceDefinition
		if loaded_definition == null:
			push_warning("Skipping invalid resource definition at %s." % file_path)
			continue

		var definition := loaded_definition.duplicate() as ResourceDefinition
		definition.ensure_defaults()
		if definition.resource_id.is_empty():
			push_warning("Skipping unnamed resource definition at %s." % file_path)
			continue
		if definitions_by_id.has(definition.resource_id):
			push_warning("Skipping duplicate resource id %s." % definition.resource_id)
			continue

		definitions.append(definition)
		definitions_by_id[definition.resource_id] = definition

	definitions.sort_custom(_sort_definitions)

	definitions_by_id.clear()
	for definition_index in range(definitions.size()):
		var definition: ResourceDefinition = definitions[definition_index]
		definition.resource_index = definition_index
		definitions_by_id[definition.resource_id] = definition

	registry_hash = _compute_registry_hash()
	return not definitions.is_empty()


func size() -> int:
	return definitions.size()


func has_resource(resource_id: String) -> bool:
	return definitions_by_id.has(resource_id)


func get_definition(resource_id: String) -> ResourceDefinition:
	return definitions_by_id.get(resource_id, null)


func get_definition_by_index(resource_index: int) -> ResourceDefinition:
	if resource_index < 0 or resource_index >= definitions.size():
		return null
	return definitions[resource_index]


func get_resource_index(resource_id: String) -> int:
	var definition := get_definition(resource_id)
	if definition == null:
		return -1
	return definition.resource_index


func get_resource_id(resource_index: int) -> String:
	var definition := get_definition_by_index(resource_index)
	if definition == null:
		return ""
	return definition.resource_id


func get_resource_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for definition in definitions:
		ids.append(definition.resource_id)
	return ids


func compile_bundle(value: Variant) -> ResourceBundle:
	if value is ResourceBundle:
		return (value as ResourceBundle).duplicate_bundle()

	var normalized_amounts := RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(value)
	var merged_by_index: Dictionary = {}
	for amount in normalized_amounts:
		var definition := get_definition(amount.resource_id)
		if definition == null:
			continue
		merged_by_index[definition.resource_index] = int(merged_by_index.get(definition.resource_index, 0)) + amount.milliunits

	var sorted_indices: Array[int] = []
	for resource_index_variant in merged_by_index.keys():
		sorted_indices.append(int(resource_index_variant))
	sorted_indices.sort()

	var bundle := RESOURCE_BUNDLE_SCRIPT.new()
	var packed_indices := PackedInt32Array()
	var packed_amounts := PackedInt64Array()
	for resource_index in sorted_indices:
		var milliunits: int = int(merged_by_index.get(resource_index, 0))
		if milliunits == 0:
			continue
		packed_indices.append(resource_index)
		packed_amounts.append(milliunits)

	bundle.resource_indices = packed_indices
	bundle.amounts = packed_amounts
	return bundle


func bundle_to_resource_map(bundle: ResourceBundle) -> Dictionary:
	var result: Dictionary = {}
	if bundle == null:
		return result

	for entry_index in range(bundle.resource_indices.size()):
		var resource_id := get_resource_id(bundle.resource_indices[entry_index])
		if resource_id.is_empty():
			continue
		result[resource_id] = int(bundle.amounts[entry_index])
	return result


func build_base_capacity_row() -> PackedInt64Array:
	var row := PackedInt64Array()
	row.resize(definitions.size())
	for definition_index in range(definitions.size()):
		row[definition_index] = definitions[definition_index].max_stockpile_milliunits
	return row


func build_starting_stockpile_row() -> PackedInt64Array:
	var row := PackedInt64Array()
	row.resize(definitions.size())
	for definition_index in range(definitions.size()):
		row[definition_index] = definitions[definition_index].starting_amount_milliunits
	return row


func _list_resource_definition_paths() -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(RESOURCE_DIRECTORY)
	if directory == null:
		push_warning("Resource directory %s does not exist." % RESOURCE_DIRECTORY)
		return result

	directory.list_dir_begin()
	while true:
		var file_name := directory.get_next()
		if file_name.is_empty():
			break
		if directory.current_is_dir() or not file_name.ends_with(".tres"):
			continue
		result.append("%s/%s" % [RESOURCE_DIRECTORY, file_name])
	directory.list_dir_end()

	result.sort()
	return result


func _compute_registry_hash() -> String:
	var canonical_entries: Array[Dictionary] = []
	for definition in definitions:
		canonical_entries.append({
			"resource_id": definition.resource_id,
			"sort_key": definition.sort_key,
			"display_name": definition.display_name,
			"category": definition.category,
			"is_special": definition.is_special,
			"max_stockpile_milliunits": definition.max_stockpile_milliunits,
			"starting_amount_milliunits": definition.starting_amount_milliunits,
			"ai_weight": definition.ai_weight,
			"visibility_rule": definition.visibility_rule,
		})

	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256 as HashingContext.HashType)
	hash_context.update(JSON.stringify(canonical_entries).to_utf8_buffer())
	return hash_context.finish().hex_encode()


static func _sort_definitions(a: ResourceDefinition, b: ResourceDefinition) -> bool:
	if a.sort_key == b.sort_key:
		return a.resource_id < b.resource_id
	return a.sort_key < b.sort_key
