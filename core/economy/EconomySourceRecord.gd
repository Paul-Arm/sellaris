extends RefCounted
class_name EconomySourceRecord

const RESOURCE_BUNDLE_SCRIPT := preload("res://core/economy/ResourceBundle.gd")

var source_id: String = ""
var owner_empire_index: int = -1
var kind: String = ""
var active: bool = true
var income_bundle: ResourceBundle = RESOURCE_BUNDLE_SCRIPT.new()
var expense_bundle: ResourceBundle = RESOURCE_BUNDLE_SCRIPT.new()
var capacity_bundle: ResourceBundle = RESOURCE_BUNDLE_SCRIPT.new()
var tags: PackedStringArray = PackedStringArray()


func to_dict() -> Dictionary:
	return {
		"source_id": source_id,
		"owner_empire_index": owner_empire_index,
		"kind": kind,
		"active": active,
		"income_bundle": income_bundle.to_dict() if income_bundle != null else {},
		"expense_bundle": expense_bundle.to_dict() if expense_bundle != null else {},
		"capacity_bundle": capacity_bundle.to_dict() if capacity_bundle != null else {},
		"tags": tags.duplicate(),
	}


static func from_dict(data: Dictionary) -> EconomySourceRecord:
	var record := EconomySourceRecord.new()
	record.source_id = str(data.get("source_id", ""))
	record.owner_empire_index = int(data.get("owner_empire_index", -1))
	record.kind = str(data.get("kind", ""))
	record.active = bool(data.get("active", true))
	record.income_bundle = RESOURCE_BUNDLE_SCRIPT.from_dict(data.get("income_bundle", {}))
	record.expense_bundle = RESOURCE_BUNDLE_SCRIPT.from_dict(data.get("expense_bundle", {}))
	record.capacity_bundle = RESOURCE_BUNDLE_SCRIPT.from_dict(data.get("capacity_bundle", {}))
	var tags_variant: Variant = data.get("tags", PackedStringArray())
	if tags_variant is PackedStringArray:
		record.tags = tags_variant
	elif tags_variant is Array:
		for tag_variant in tags_variant:
			var tag: String = str(tag_variant).strip_edges()
			if tag.is_empty():
				continue
			record.tags.append(tag)
	return record
