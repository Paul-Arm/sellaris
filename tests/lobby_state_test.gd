extends SceneTree

func _initialize() -> void:
	var state := LobbyState.new()
	assert(not state.register_peer(1, "Host", 999), "Version mismatch must be rejected")
	assert(not state.register_peer(0, "Host", 1), "Invalid identities must be rejected")
	assert(not state.register_peer(1, "\n\t", 1), "Empty callsigns must be rejected")
	assert(state.register_peer(1, "  Host\n ", 1))
	assert(state.players[1]["name"] == "Host")
	assert(not state.register_peer(1, "Impersonator", 1))
	assert(not state.set_ready(99, true), "Unknown peers cannot become ready")
	for id in range(2, 7):
		assert(state.register_peer(id, "Commander %d" % id, 1))
	assert(not state.register_peer(7, "Overflow", 1), "Lobby capacity is enforced")
	state.set_ready(2, true)
	assert(state.players[2]["ready"])
	assert(not state.players[1]["ready"], "Readiness is scoped to the sender")
	var snapshot := state.snapshot()
	snapshot[1]["name"] = "Mutated"
	assert(state.players[1]["name"] == "Host", "Snapshots cannot mutate server state")
	state.remove_peer(3)
	assert(state.register_peer(7, "Replacement", 1))
	assert(state.players[7]["slot"] == 2, "Disconnected slots are reusable")
	assert(LobbyState.clean_name("a".repeat(100)).length() == 24)
	print("PASS: lobby validation, capacity, readiness, snapshot isolation and slot reuse")
	quit(0)
