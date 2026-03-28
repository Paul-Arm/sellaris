class_name Empire
extends RefCounted



var id: int

var name: String

var color: Color #todo: Palletize this

var flag: Texture2D #todo: make this a sprite or something, for now just a texture to identify the empire

var played_by: String #todo: make this an enum or something, for now just a string to identify the player type (human, ai, etc.)

# Planet the empire spawned on
var origin_world_id:  int

# Planet the empire currently set as its capital
var capital_world_id: int


func _init(_id: int, _name: String, _color: Color,  _played_by: String, _origin_world_id: int, _capital_world_id: int, _flag: Texture2D = null,) -> void:
	id = _id
	name = _name
	color = _color
	flag = _flag
	played_by = _played_by
	origin_world_id = _origin_world_id
	capital_world_id = _capital_world_id


	
	
