extends VBoxContainer

var _name_edit: LineEdit
var _address_edit: LineEdit
var _port_edit: SpinBox
var _host_button: Button
var _join_button: Button
var _leave_button: Button
var _ready_button: Button
var _status_label: Label
var _roster_box: VBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	_name_edit = _field(grid, "Your callsign", "Commander")
	_name_edit.max_length = 24
	_address_edit = _field(grid, "Host address", "127.0.0.1")
	var port_label := Label.new()
	port_label.text = "UDP port"
	grid.add_child(port_label)
	_port_edit = SpinBox.new()
	_port_edit.min_value = 1024
	_port_edit.max_value = 65535
	_port_edit.value = NetworkSession.DEFAULT_PORT
	grid.add_child(_port_edit)
	var actions := HBoxContainer.new()
	add_child(actions)
	_host_button = _button(actions, "Host lobby", _host)
	_host_button.theme_type_variation = &"PrimaryButton"
	_join_button = _button(actions, "Join lobby", _join)
	_leave_button = _button(actions, "Disconnect", func() -> void: NetworkSession.leave_lobby())
	_ready_button = _button(actions, "Mark ready", func() -> void: NetworkSession.toggle_ready())
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)
	var heading := Label.new()
	heading.text = "COMMANDERS  /  6 SLOTS"
	heading.theme_type_variation = &"CaptionLabel"
	add_child(heading)
	_roster_box = VBoxContainer.new()
	add_child(_roster_box)
	NetworkSession.lobby_changed.connect(_refresh)
	NetworkSession.status_changed.connect(_on_status)
	_refresh()

func _field(grid: GridContainer, title: String, value: String) -> LineEdit:
	var label := Label.new()
	label.text = title
	grid.add_child(label)
	var input := LineEdit.new()
	input.text = value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.x = 250
	grid.add_child(input)
	return input

func _button(row: HBoxContainer, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	row.add_child(button)
	return button

func _host() -> void:
	NetworkSession.host_lobby(_name_edit.text, int(_port_edit.value))
	_refresh()

func _join() -> void:
	NetworkSession.join_lobby(_address_edit.text, _name_edit.text, int(_port_edit.value))
	_refresh()

func _on_status(_message: String) -> void:
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = NetworkSession.status
	var active := NetworkSession.is_active()
	_host_button.disabled = active
	_join_button.disabled = active
	_leave_button.disabled = not active
	_ready_button.disabled = not NetworkSession.is_lobby_connected()
	_name_edit.editable = not active
	_address_edit.editable = not active
	_port_edit.editable = not active
	var local: Dictionary = NetworkSession.roster.get(multiplayer.get_unique_id(), {})
	_ready_button.text = "Not ready" if bool(local.get("ready", false)) else "Mark ready"
	for child in _roster_box.get_children():
		_roster_box.remove_child(child)
		child.queue_free()
	for slot in range(LobbyState.MAX_PLAYERS):
		var player: Dictionary = {}
		var peer_id := 0
		for id: int in NetworkSession.roster.keys():
			if int(NetworkSession.roster[id]["slot"]) == slot:
				player = NetworkSession.roster[id]
				peer_id = id
		var label := Label.new()
		label.custom_minimum_size.y = 24
		if player.is_empty():
			label.text = "%02d    Open slot" % [slot + 1]
			label.modulate = ObservatoryStyle.MUTED
		else:
			label.text = "%02d    %s%s    /    %s" % [slot + 1, str(player["name"]), " · HOST" if peer_id == 1 else "", "READY" if bool(player["ready"]) else "Preparing"]
			label.modulate = ObservatoryStyle.ACCENT if bool(player["ready"]) else ObservatoryStyle.TEXT
		_roster_box.add_child(label)
