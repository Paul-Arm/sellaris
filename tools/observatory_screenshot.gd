extends Node

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var menu: Control = load("res://scene/MainMenue/MainUI.tscn").instantiate()
	add_child(menu)
	await _capture("observatory_menu")
	menu.call("_show_page", 3)
	await _capture("observatory_lobby")
	menu.queue_free()
	await get_tree().process_frame
	var setup: Control = load("res://scene/GennerateMenue/GennerateMenue.tscn").instantiate()
	add_child(setup)
	await _capture("observatory_setup")
	setup.queue_free()
	await get_tree().process_frame
	var game: Node = load("res://scene/game/GameScene.tscn").instantiate()
	game.configure({"seed_text": "observatory-review", "star_count": 64})
	add_child(game)
	for i in range(120):
		await get_tree().process_frame
	await _capture("observatory_galaxy")
	get_tree().quit(0)

func _capture(name: String) -> void:
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error := image.save_png("res://tools/screenshots/%s.png" % name)
	assert(error == OK)
