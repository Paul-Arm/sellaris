extends RefCounted
class_name LobbyState

## Server-owned roster. Clients never supply a peer ID or an empire assignment.
const MAX_PLAYERS := 6
const PROTOCOL_VERSION := 1
var players: Dictionary = {}

static func clean_name(value: String) -> String:
	var result := ""
	for character in value.strip_edges():
		var code := character.unicode_at(0)
		if code >= 32 and code != 127 and code != 8232 and code != 8233:
			result += character
	return result.left(24).strip_edges()

func register_peer(peer_id: int, display_name: String, version: int) -> bool:
	if peer_id <= 0 or version != PROTOCOL_VERSION or players.has(peer_id) or players.size() >= MAX_PLAYERS:
		return false
	var callsign := clean_name(display_name)
	if callsign.is_empty():
		return false
	var used_slots: Array = []
	for player: Dictionary in players.values():
		used_slots.append(int(player["slot"]))
	var slot := 0
	while used_slots.has(slot):
		slot += 1
	players[peer_id] = {"name": callsign, "slot": slot, "ready": false}
	return true

func set_ready(peer_id: int, ready: bool) -> bool:
	if not players.has(peer_id):
		return false
	players[peer_id]["ready"] = ready
	return true

func remove_peer(peer_id: int) -> void:
	players.erase(peer_id)

func snapshot() -> Dictionary:
	return players.duplicate(true)
