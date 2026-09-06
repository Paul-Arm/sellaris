extends OptionButton

func _ready() -> void:
	name = "DesignSwitcher"
	add_item("01 / Observatory")
	add_item("02 / Mission Control")
	tooltip_text = "Switch visual design without restarting. F6 switches anywhere in the game."
	custom_minimum_size = Vector2(160, 28)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sync(SettingsManager.get_design_variant())
	item_selected.connect(_select)
	SettingsManager.design_changed.connect(_sync)

func _select(index: int) -> void:
	SettingsManager.set_design_variant("clean" if index == 1 else "pastel")

func _sync(variant: String) -> void:
	select(1 if variant == "clean" else 0)
