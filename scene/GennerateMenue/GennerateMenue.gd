extends Control

const GALAXY_SCENE := preload("res://scene/galaxy/galaxy.tscn")
const GALAXY_GENERATOR_SCRIPT := preload("res://scene/galaxy/GalaxyGenerator.gd")

@onready var seed_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SeedInput
@onready var star_count_spin_box: SpinBox = $Panel/MarginContainer/VBoxContainer/SettingsGrid/StarCountSpinBox
@onready var shape_option_button: OptionButton = $Panel/MarginContainer/VBoxContainer/SettingsGrid/ShapeOptionButton
@onready var hyperlane_density_spin_box: SpinBox = $Panel/MarginContainer/VBoxContainer/SettingsGrid/HyperlaneDensitySpinBox
@onready var generate_button: Button = $Panel/MarginContainer/VBoxContainer/GenerateButton

var generator: RefCounted = GALAXY_GENERATOR_SCRIPT.new()


func _ready() -> void:
	MusicManager.play_menu_loops()
	generate_button.pressed.connect(_on_generate_pressed)
	seed_input.text_submitted.connect(_on_seed_submitted)
	_setup_controls()


func _on_seed_submitted(_submitted_text: String) -> void:
	_on_generate_pressed()


func _on_generate_pressed() -> void:
	var galaxy := GALAXY_SCENE.instantiate()
	var settings := {
		"seed_text": seed_input.text.strip_edges(),
		"star_count": int(star_count_spin_box.value),
		"shape": generator.get_shape_options()[shape_option_button.selected],
		"hyperlane_density": int(hyperlane_density_spin_box.value),
	}
	if galaxy.has_method("configure"):
		galaxy.configure(settings)

	var tree := get_tree()
	var current_scene := tree.current_scene
	tree.root.add_child(galaxy)
	tree.current_scene = galaxy

	if current_scene != null:
		current_scene.queue_free()


func _setup_controls() -> void:
	var shape_options: PackedStringArray = generator.get_shape_options()
	shape_option_button.clear()
	for shape_name in shape_options:
		shape_option_button.add_item(shape_name.capitalize())

	star_count_spin_box.min_value = 500
	star_count_spin_box.max_value = 3000
	star_count_spin_box.step = 50
	star_count_spin_box.value = 900

	hyperlane_density_spin_box.min_value = 1
	hyperlane_density_spin_box.max_value = 8
	hyperlane_density_spin_box.step = 1
	hyperlane_density_spin_box.value = 2
