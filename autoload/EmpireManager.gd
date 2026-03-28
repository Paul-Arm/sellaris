extends Node

var _next_empire_id: int = 1
var _empires: Dictionary = {} # empire_id -> Empire



func _ready() -> void:
	
	create_empire(
		"Empire 1",
		Color.ROYAL_BLUE,
		"human",
		1, #origin world id
		1, #capital world id
	)


func get_next_empire_id() -> int:
	var id := _next_empire_id
	_next_empire_id += 1
	return id


func create_empire(
	empire_name: String,
	color: Color,
	played_by: String,
	origin_world_id: int,
	capital_world_id: int,
	flag: Texture2D = null
) -> Empire:
	var empire := Empire.new(
		get_next_empire_id(),
		empire_name,
		color,
		played_by,
		origin_world_id,
		capital_world_id,
		flag
	)

	_empires[empire.id] = empire
	return empire


func get_empire(empire_id: int) -> Empire:
	return _empires.get(empire_id, null)


func has_empire(empire_id: int) -> bool:
	return _empires.has(empire_id)


func remove_empire(empire_id: int) -> void:
	_empires.erase(empire_id)


func get_all_empires() -> Array[Empire]:
	var result: Array[Empire] = []
	for empire in _empires.values():
		result.append(empire)
	return result
