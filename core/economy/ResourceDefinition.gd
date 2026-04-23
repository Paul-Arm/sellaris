extends Resource
class_name ResourceDefinition

@export var resource_id: String = ""
@export var sort_key: int = 0
@export var display_name: String = ""
@export var category: String = "basic"
@export var is_special: bool = false
@export var max_stockpile_milliunits: int = 1000000
@export var starting_amount_milliunits: int = 0
@export var ai_weight: int = 100
@export var visibility_rule: String = "always"

var resource_index: int = -1


func ensure_defaults() -> void:
	resource_id = resource_id.strip_edges()
	display_name = display_name.strip_edges()
	category = category.strip_edges()
	visibility_rule = visibility_rule.strip_edges()

	if resource_id.is_empty():
		resource_id = "resource_%02d" % maxi(sort_key, 0)
	if display_name.is_empty():
		display_name = resource_id.replace("_", " ").capitalize()
	if category.is_empty():
		category = "basic"
	if visibility_rule.is_empty():
		visibility_rule = "always"

	max_stockpile_milliunits = maxi(max_stockpile_milliunits, 0)
	starting_amount_milliunits = clampi(starting_amount_milliunits, 0, max_stockpile_milliunits)
	ai_weight = maxi(ai_weight, 0)


func to_dict() -> Dictionary:
	ensure_defaults()
	return {
		"resource_id": resource_id,
		"sort_key": sort_key,
		"display_name": display_name,
		"category": category,
		"is_special": is_special,
		"max_stockpile_milliunits": max_stockpile_milliunits,
		"starting_amount_milliunits": starting_amount_milliunits,
		"ai_weight": ai_weight,
		"visibility_rule": visibility_rule,
		"resource_index": resource_index,
	}
