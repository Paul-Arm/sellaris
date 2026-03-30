extends Control

const GALAXY_SCENE := preload("res://scene/galaxy/galaxy.tscn")
const GALAXY_GENERATOR_SCRIPT := preload("res://scene/galaxy/GalaxyGenerator.gd")
const MAIN_MENU_SCENE_PATH := "res://scene/MainMenue/MainUI.tscn"

@onready var seed_input: LineEdit = $MarginContainer/RootVBox/MainShell/MarginContainer/ShellRow/ContentPanel/MarginContainer/ContentVBox/SettingsGrid/SeedInput
@onready var star_count_spin_box: SpinBox = $MarginContainer/RootVBox/MainShell/MarginContainer/ShellRow/ContentPanel/MarginContainer/ContentVBox/SettingsGrid/StarCountSpinBox
@onready var min_radius_spin_box: SpinBox = $MarginContainer/RootVBox/MainShell/MarginContainer/ShellRow/ContentPanel/MarginContainer/ContentVBox/SettingsGrid/MinRadiusSpinBox
@onready var shape_option_button: OptionButton = $MarginContainer/RootVBox/MainShell/MarginContainer/ShellRow/ContentPanel/MarginContainer/ContentVBox/SettingsGrid/ShapeOptionButton
@onready var hyperlane_density_spin_box: SpinBox = $MarginContainer/RootVBox/MainShell/MarginContainer/ShellRow/ContentPanel/MarginContainer/ContentVBox/SettingsGrid/HyperlaneDensitySpinBox
@onready var generate_button: Button = $MarginContainer/RootVBox/MainShell/MarginContainer/ShellRow/Sidebar/GenerateButton
@onready var back_button: Button = $MarginContainer/RootVBox/MainShell/MarginContainer/ShellRow/Sidebar/BackButton

var generator: RefCounted = GALAXY_GENERATOR_SCRIPT.new()


func _ready() -> void:
	MusicManager.play_menu_loops()
	generate_button.pressed.connect(_on_generate_pressed)
	back_button.pressed.connect(_on_back_pressed)
	seed_input.text_submitted.connect(_on_seed_submitted)
	_setup_controls()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _on_seed_submitted(_submitted_text: String) -> void:
	_on_generate_pressed()


func _on_generate_pressed() -> void:
	var galaxy := GALAXY_SCENE.instantiate()
	var settings := {
		"seed_text": seed_input.text.strip_edges(),
		"star_count": int(star_count_spin_box.value),
		"min_system_distance": float(min_radius_spin_box.value),
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


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _setup_controls() -> void:
	var shape_options: PackedStringArray = generator.get_shape_options()
	shape_option_button.clear()
	for shape_name in shape_options:
		shape_option_button.add_item(shape_name.capitalize())

	star_count_spin_box.min_value = 500
	star_count_spin_box.max_value = 3000
	star_count_spin_box.step = 50
	star_count_spin_box.value = 900

	min_radius_spin_box.min_value = 36
	min_radius_spin_box.max_value = 96
	min_radius_spin_box.step = 2
	min_radius_spin_box.value = 48

	hyperlane_density_spin_box.min_value = 1
	hyperlane_density_spin_box.max_value = 8
	hyperlane_density_spin_box.step = 1
	hyperlane_density_spin_box.value = 2
