extends Node

var _host_mode := false
var _phase := 0
var _time := 0.0

func _ready() -> void:
	_host_mode = "--lobby-host" in OS.get_cmdline_user_args()
	var result: Error
	if _host_mode:
		result = NetworkSession.host_lobby("Host integration", 24619)
	else:
		result = NetworkSession.join_lobby("127.0.0.1", "Client integration", 24619)
	if result != OK:
		_fail("Transport creation failed")

func _process(delta: float) -> void:
	_time += delta
	if _time > 20.0:
		_fail("Lobby handshake / readiness / disconnect timed out: " + NetworkSession.status)
		return
	if _host_mode:
		if _phase == 0 and NetworkSession.roster.size() == 2:
			for peer_id: int in NetworkSession.roster:
				if peer_id != 1 and bool(NetworkSession.roster[peer_id]["ready"]):
					_phase = 1
					NetworkSession.toggle_ready()
		elif _phase == 1 and NetworkSession.roster.size() == 1:
			NetworkSession.leave_lobby()
			print("PASS: host registered client, received readiness, and removed disconnected peer")
			get_tree().quit(0)
	else:
		if _phase == 0 and NetworkSession.roster.size() == 2:
			_phase = 1
			NetworkSession.toggle_ready()
		elif _phase == 1 and bool(NetworkSession.roster.get(1, {}).get("ready", false)):
			assert(NetworkSession.roster[multiplayer.get_unique_id()]["ready"])
			NetworkSession.leave_lobby()
			assert(not NetworkSession.is_active())
			assert(NetworkSession.roster.is_empty())
			print("PASS: client connected, synchronized readiness, and cleaned up transport")
			get_tree().quit(0)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
