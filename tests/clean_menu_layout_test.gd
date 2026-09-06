extends Node

func _ready() -> void:
	SettingsManager.set_design_variant("clean", false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(960, 540))
	var menu: Control = load("res://scene/MainMenue/MainUI.tscn").instantiate()
	add_child(menu)
	for page in range(4):
		menu.call("_show_page", page)
		for frame in range(8): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/screenshots/clean_menu_960_%d.png" % page)
		var tabs: Control = menu.content_tabs if page != 0 else menu.get("_atlas_menu").welcome
		assert(tabs.get_global_rect().end.x <= 961 and tabs.get_global_rect().end.y <= 541, "Menu page %d must fit 960x540: %s" % [page, tabs.get_global_rect()])
		print("PASS: compact menu page ", page)
	SettingsManager.set_design_variant("pastel", false)
	for frame in range(8): await get_tree().process_frame
	assert(menu.content_tabs.has_node("PresetsPage/ContentRow"), "Pastel restores original page hierarchy")
	assert(get_tree().root.content_scale_size == Vector2i(1600, 900))
	SettingsManager.set_design_variant("clean", false)
	for frame in range(8): await get_tree().process_frame
	assert(menu.content_tabs.has_node("PresetsPage/AtlasScroll/ContentRow"))
	assert(get_tree().root.content_scale_size == Vector2i.ZERO)
	print("PASS: UI layout and scale restore across design switches")
	get_tree().quit()
