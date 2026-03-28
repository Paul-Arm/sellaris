extends Control

const GENERATE_MENU_SCENE_PATH := "res://scene/GennerateMenue/GennerateMenue.tscn"
const DEFAULT_EDITOR_COLOR := Color(0.36, 0.72, 1.0, 1.0)

@onready var preset_count_label: Label = $MarginContainer/ContentRow/NavigationPanel/MarginContainer/VBoxContainer/PresetCountLabel
@onready var preset_list: ItemList = $MarginContainer/ContentRow/NavigationPanel/MarginContainer/VBoxContainer/PresetList
@onready var delete_preset_button: Button = $MarginContainer/ContentRow/NavigationPanel/MarginContainer/VBoxContainer/PresetActionRow/DeletePresetButton
@onready var status_label: Label = $MarginContainer/ContentRow/NavigationPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var preset_name_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/PresetNameEdit
@onready var empire_name_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/EmpireNameEdit
@onready var species_type_id_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/SpeciesTypeIdEdit
@onready var species_visuals_id_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/SpeciesVisualsIdEdit
@onready var species_name_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/SpeciesNameEdit
@onready var species_plural_name_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/SpeciesPluralNameEdit
@onready var species_adjective_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/SpeciesAdjectiveEdit
@onready var name_set_id_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/NameSetIdEdit
@onready var government_type_id_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/GovernmentTypeIdEdit
@onready var authority_type_id_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/AuthorityTypeIdEdit
@onready var civic_ids_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/CivicIdsEdit
@onready var flag_path_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/FlagPathEdit
@onready var origin_id_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/OriginIdEdit
@onready var starting_system_type_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/StartingSystemTypeEdit
@onready var starting_planet_type_edit: LineEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/StartingPlanetTypeEdit
@onready var ship_set_spin_box: SpinBox = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/ShipSetSpinBox
@onready var color_picker_button: ColorPickerButton = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/FieldsGrid/ColorPickerButton
@onready var biography_edit: TextEdit = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ScrollContainer/FormVBox/BiographyEdit
@onready var save_preset_button: Button = $MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ActionRow/SavePresetButton

var _selected_preset_name: String = ""


func _ready() -> void:
	MusicManager.play_menu_loops()
	preset_list.item_selected.connect(_on_preset_selected)
	preset_list.item_activated.connect(_on_preset_activated)
	$MarginContainer/ContentRow/NavigationPanel/MarginContainer/VBoxContainer/MenuButtonRow/OpenGalaxySetupButton.pressed.connect(_on_open_galaxy_setup_pressed)
	$MarginContainer/ContentRow/NavigationPanel/MarginContainer/VBoxContainer/MenuButtonRow/QuitButton.pressed.connect(_on_quit_pressed)
	$MarginContainer/ContentRow/NavigationPanel/MarginContainer/VBoxContainer/PresetActionRow/NewPresetButton.pressed.connect(_on_new_preset_pressed)
	delete_preset_button.pressed.connect(_on_delete_preset_pressed)
	save_preset_button.pressed.connect(_on_save_preset_pressed)
	$MarginContainer/ContentRow/DesignerPanel/MarginContainer/VBoxContainer/ActionRow/ClearFormButton.pressed.connect(_on_clear_form_pressed)
	ship_set_spin_box.min_value = 0
	ship_set_spin_box.max_value = 999
	ship_set_spin_box.step = 1
	ship_set_spin_box.rounded = true
	_refresh_preset_list()
	_clear_form()


func _refresh_preset_list(selected_name: String = "") -> void:
	EmpirePresetManager.load_presets()
	preset_list.clear()

	var presets := EmpirePresetManager.get_presets()
	for preset in presets:
		preset_list.add_item("%s  |  %s" % [preset.preset_name, preset.empire_name])
		var item_index := preset_list.get_item_count() - 1
		preset_list.set_item_metadata(item_index, preset.preset_name)
		preset_list.set_item_custom_fg_color(item_index, preset.color)

		if not selected_name.is_empty() and preset.preset_name == selected_name:
			preset_list.select(item_index)

	preset_count_label.text = "Saved Empires: %d" % presets.size()
	delete_preset_button.disabled = _get_selected_preset_name().is_empty()


func _clear_form() -> void:
	_selected_preset_name = ""
	preset_name_edit.text = ""
	empire_name_edit.text = ""
	species_type_id_edit.text = ""
	species_visuals_id_edit.text = ""
	species_name_edit.text = ""
	species_plural_name_edit.text = ""
	species_adjective_edit.text = ""
	name_set_id_edit.text = ""
	government_type_id_edit.text = ""
	authority_type_id_edit.text = ""
	civic_ids_edit.text = ""
	flag_path_edit.text = ""
	origin_id_edit.text = ""
	starting_system_type_edit.text = ""
	starting_planet_type_edit.text = ""
	ship_set_spin_box.value = 0
	color_picker_button.color = DEFAULT_EDITOR_COLOR
	biography_edit.text = ""
	preset_list.deselect_all()
	delete_preset_button.disabled = true
	status_label.text = "Create a new empire preset or select one to edit."


func _load_preset_into_form(preset_name: String) -> void:
	var preset := EmpirePresetManager.get_preset_by_name(preset_name)
	if preset == null:
		status_label.text = "Preset '%s' could not be loaded." % preset_name
		return

	_selected_preset_name = preset.preset_name
	preset_name_edit.text = preset.preset_name
	empire_name_edit.text = preset.empire_name
	species_type_id_edit.text = str(preset.species_type_id)
	species_visuals_id_edit.text = str(preset.species_visuals_id)
	species_name_edit.text = preset.species_name
	species_plural_name_edit.text = preset.species_plural_name
	species_adjective_edit.text = preset.species_adjective
	name_set_id_edit.text = str(preset.name_set_id)
	government_type_id_edit.text = str(preset.government_type_id)
	authority_type_id_edit.text = str(preset.authority_type_id)
	civic_ids_edit.text = ", ".join(_stringify_string_name_array(preset.civic_ids))
	flag_path_edit.text = preset.flag_path
	origin_id_edit.text = str(preset.origin_id)
	starting_system_type_edit.text = str(preset.starting_system_type)
	starting_planet_type_edit.text = str(preset.starting_planet_type)
	ship_set_spin_box.value = preset.ship_set_id
	color_picker_button.color = preset.color
	biography_edit.text = preset.biography
	delete_preset_button.disabled = false
	status_label.text = "Editing preset '%s'." % preset.preset_name


func _build_preset_from_form() -> EmpirePreset:
	var preset := EmpirePreset.new()
	preset.preset_name = preset_name_edit.text
	preset.empire_name = empire_name_edit.text
	preset.species_type_id = StringName(species_type_id_edit.text.strip_edges())
	preset.species_visuals_id = StringName(species_visuals_id_edit.text.strip_edges())
	preset.species_name = species_name_edit.text
	preset.species_plural_name = species_plural_name_edit.text
	preset.species_adjective = species_adjective_edit.text
	preset.name_set_id = StringName(name_set_id_edit.text.strip_edges())
	preset.government_type_id = StringName(government_type_id_edit.text.strip_edges())
	preset.authority_type_id = StringName(authority_type_id_edit.text.strip_edges())
	preset.civic_ids = _parse_civic_ids(civic_ids_edit.text)
	preset.flag_path = flag_path_edit.text
	preset.biography = biography_edit.text
	preset.color = color_picker_button.color
	preset.ship_set_id = int(ship_set_spin_box.value)
	preset.origin_id = StringName(origin_id_edit.text.strip_edges())
	preset.starting_system_type = StringName(starting_system_type_edit.text.strip_edges())
	preset.starting_planet_type = StringName(starting_planet_type_edit.text.strip_edges())
	preset.ensure_defaults()
	return preset


func _parse_civic_ids(value: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for civic_id in value.split(",", false):
		var trimmed := civic_id.strip_edges()
		if trimmed.is_empty():
			continue
		result.append(StringName(trimmed))
	return result


func _stringify_string_name_array(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


func _get_selected_preset_name() -> String:
	var selected_items := preset_list.get_selected_items()
	if selected_items.size() == 0:
		return ""
	return str(preset_list.get_item_metadata(int(selected_items[0])))


func _on_preset_selected(_index: int) -> void:
	var preset_name := _get_selected_preset_name()
	delete_preset_button.disabled = preset_name.is_empty()
	if preset_name.is_empty():
		return
	_load_preset_into_form(preset_name)


func _on_preset_activated(_index: int) -> void:
	_on_preset_selected(_index)


func _on_new_preset_pressed() -> void:
	_clear_form()


func _on_clear_form_pressed() -> void:
	_clear_form()


func _on_save_preset_pressed() -> void:
	var preset := _build_preset_from_form()
	var save_error := EmpirePresetManager.save_preset(preset, _selected_preset_name)
	if save_error != OK:
		status_label.text = "Saving failed with error code %d." % save_error
		return

	_selected_preset_name = preset.preset_name
	_refresh_preset_list(_selected_preset_name)
	_load_preset_into_form(_selected_preset_name)
	status_label.text = "Saved preset '%s'." % _selected_preset_name


func _on_delete_preset_pressed() -> void:
	if _selected_preset_name.is_empty():
		status_label.text = "Select a preset before deleting it."
		return

	var deleted_name := _selected_preset_name
	var delete_error := EmpirePresetManager.delete_preset(_selected_preset_name)
	if delete_error != OK:
		status_label.text = "Delete failed with error code %d." % delete_error
		return

	_clear_form()
	_refresh_preset_list()
	status_label.text = "Deleted preset '%s'." % deleted_name


func _on_open_galaxy_setup_pressed() -> void:
	get_tree().change_scene_to_file(GENERATE_MENU_SCENE_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()
