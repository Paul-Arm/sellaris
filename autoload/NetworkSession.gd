extends Node

## Direct-connect lobby transport. Campaign simulation is deliberately not
## started until all gameplay mutations have an authoritative command path.
signal lobby_changed
signal status_changed(message: String)
const DEFAULT_PORT := 24560
const CONNECT_TIMEOUT := 10.0
var roster: Dictionary = {}
var status: String = "Offline · ready to connect"
var _state := LobbyState.new()
var _peer: ENetMultiplayerPeer
var _callsign := "Commander"
var _connecting := false
var _elapsed := 0.0
var _pending_peers: Dictionary = {}
var _ready_requested := false

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	set_process(false)

func is_active() -> bool:
	return _peer != null

func is_host() -> bool:
	return is_active() and multiplayer.is_server()

func is_lobby_connected() -> bool:
	return is_active() and not _connecting and roster.has(multiplayer.get_unique_id())

func host_lobby(display_name: String, port: int = DEFAULT_PORT) -> Error:
	if is_active():
		return ERR_ALREADY_IN_USE
	_callsign = LobbyState.clean_name(display_name)
	if _callsign.is_empty() or port < 1024 or port > 65535:
		_set_status("Enter a callsign and a port from 1024 to 65535.")
		return ERR_INVALID_PARAMETER
	var candidate := ENetMultiplayerPeer.new()
	var error := candidate.create_server(port, LobbyState.MAX_PLAYERS - 1)
	if error != OK:
		_set_status("Could not host on port %d: %s" % [port, error_string(error)])
		return error
	_peer = candidate
	multiplayer.multiplayer_peer = _peer
	_state = LobbyState.new()
	_state.register_peer(1, _callsign, LobbyState.PROTOCOL_VERSION)
	roster = _state.snapshot()
	_ready_requested = false
	set_process(true)
	_set_status("Hosting · UDP %d · waiting for commanders" % port)
	lobby_changed.emit()
	return OK

func join_lobby(address: String, display_name: String, port: int = DEFAULT_PORT) -> Error:
	if is_active():
		return ERR_ALREADY_IN_USE
	_callsign = LobbyState.clean_name(display_name)
	address = address.strip_edges()
	if address.is_empty() or address.length() > 253 or _callsign.is_empty() or port < 1024 or port > 65535:
		_set_status("Enter the host address, your callsign and a valid port.")
		return ERR_INVALID_PARAMETER
	var candidate := ENetMultiplayerPeer.new()
	var error := candidate.create_client(address, port)
	if error != OK:
		_set_status("Could not connect: %s" % error_string(error))
		return error
	_peer = candidate
	multiplayer.multiplayer_peer = _peer
	_connecting = true
	_elapsed = 0.0
	_ready_requested = false
	set_process(true)
	_set_status("Connecting to %s:%d…" % [address, port])
	lobby_changed.emit()
	return OK

func leave_lobby(message: String = "Offline · connection closed") -> void:
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	_connecting = false
	_ready_requested = false
	_pending_peers.clear()
	roster.clear()
	_state = LobbyState.new()
	set_process(false)
	_set_status(message)
	lobby_changed.emit()

func toggle_ready() -> void:
	if not is_lobby_connected():
		return
	_ready_requested = not _ready_requested
	if is_host():
		_state.set_ready(1, _ready_requested)
		_publish_roster()
	else:
		_request_ready.rpc_id(1, _ready_requested)

func _process(delta: float) -> void:
	if _connecting:
		_elapsed += delta
		if _elapsed >= CONNECT_TIMEOUT:
			leave_lobby("Connection timed out. Check the address and UDP port.")
	elif is_host():
		for peer_id: int in _pending_peers.keys():
			_pending_peers[peer_id] += delta
			if float(_pending_peers[peer_id]) > CONNECT_TIMEOUT:
				_pending_peers.erase(peer_id)
				_peer.disconnect_peer(peer_id)

func _on_connected() -> void:
	_register_player.rpc_id(1, _callsign, LobbyState.PROTOCOL_VERSION)
	_set_status("Connected · registering commander…")

func _on_connection_failed() -> void:
	leave_lobby("Connection failed. Check the host address and port.")

func _on_server_disconnected() -> void:
	leave_lobby("The host closed the lobby.")

func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		_pending_peers[peer_id] = 0.0

func _on_peer_disconnected(peer_id: int) -> void:
	if is_host():
		_pending_peers.erase(peer_id)
		_state.remove_peer(peer_id)
		_publish_roster()

@rpc("any_peer", "call_remote", "reliable")
func _register_player(display_name: String, version: int) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _pending_peers.has(sender):
		return
	_pending_peers.erase(sender)
	if not _state.register_peer(sender, display_name, version):
		_peer.disconnect_peer(sender)
		return
	_publish_roster()

@rpc("any_peer", "call_remote", "reliable")
func _request_ready(ready: bool) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _state.players.has(sender) and bool(_state.players[sender]["ready"]) != ready:
		_state.set_ready(sender, ready)
		_publish_roster()

func _publish_roster() -> void:
	roster = _state.snapshot()
	for peer_id: int in roster.keys():
		if peer_id != 1:
			_receive_roster.rpc_id(peer_id, roster)
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _receive_roster(snapshot: Dictionary) -> void:
	if not is_active() or is_host():
		return
	roster = snapshot.duplicate(true)
	_connecting = false
	set_process(false)
	_set_status("Connected · lobby synchronized")
	lobby_changed.emit()

func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)
