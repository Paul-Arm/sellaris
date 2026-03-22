extends Control

const GALAXY_SCENE := preload("res://scene/galaxy.tscn")

@onready var seed_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SeedInput
@onready var generate_button: Button = $Panel/MarginContainer/VBoxContainer/GenerateButton


func _ready() -> void:
	generate_button.pressed.connect(_on_generate_pressed)
	seed_input.text_submitted.connect(_on_seed_submitted)


func _on_seed_submitted(_submitted_text: String) -> void:
	_on_generate_pressed()


func _on_generate_pressed() -> void:
	var galaxy := GALAXY_SCENE.instantiate()
	if galaxy.has_method("set_seed_text"):
		galaxy.set_seed_text(seed_input.text.strip_edges())

	var tree := get_tree()
	var current_scene := tree.current_scene
	tree.root.add_child(galaxy)
	tree.current_scene = galaxy

	if current_scene != null:
		current_scene.queue_free()
