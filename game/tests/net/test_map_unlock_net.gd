# The host's level decides which map a hosted night is on (#1067), over a real WebSocket to a real
# `GameServer`: the server reads the host's level from the ticket the backend signed (`hostLevel`),
# never from the rules a client sends, so a level-3 host who asks for the back rooms (level 10) has
# the drive-in lot, a level-12 host has the back rooms, and a guest of either level plays the host's
# map: a guest below a map's level still plays a hosted night there as a visitor, and a guest above
# it cannot lift a host below it. Every ticket of a match carries the host's level, so the order the
# players arrive in decides nothing. A ticket that says no level is level 1 (a backend from before
# levels never opens the back rooms).
#
# The second half is the same against the real thing (#1107): the platform backend is the real one
# (`spikes/backend`, run by Node) and signs `hostLevel` from the host's account, the accounts are
# paid the XP of their level with a game server's report, and the room is a real `GameServer`
# heartbeating to it. A level-3 host cannot even ask the backend for the back rooms, so its night is
# on the lot for a level-12 guest too; a level-12 host has the back rooms and a level-3 guest plays
# there. That half needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without
# them it is skipped with a line saying so.
extends GdUnitTestSuite

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"
const BACK_ROOMS := "small_indoor"
const BACKEND_DIR := "res://../spikes/backend"
const SESSION_SECRET := "session-secret-of-at-least-32-characters-a"
const TICKET_SECRET := "ticket-secret-of-at-least-32-characters-b"
const GAME_SERVER_SECRET := "server-secret-of-at-least-32-characters-c"
const SKIP := "needs node 24 and npm ci in spikes/backend"

var _server: GameServer
var _nights: Array[Night] = []
var _pid := 0
var _backend := ""


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	if is_instance_valid(_server):
		_server.get_parent().queue_free()
	if _pid != 0:
		OS.kill(_pid)
		_pid = 0


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable, seconds: float = 30.0) -> bool:
	var began := Time.get_ticks_msec()
	while not await condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _start() -> void:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 4
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())


## A player entering `match_id` with a ticket that says the host is `host_level` and carries the
## host's rules (the backend signs the same rules and the same host level into every ticket).
func _enter(match_id: String, user: String, host_level: Variant, map_id: String) -> Night:
	var rules := {"count_multiplier": 1.0, "max_alive": 0, "break_seconds": 0.0, "map": map_id}
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = TicketMaker.make(SECRET, SERVER_ID, match_id, user, user, 60, rules, host_level)
	var url := "ws://127.0.0.1:%d" % _server.listener.port()
	var joined := await night.start_remote(url, Night.Mode.MANUAL, 60.0, link)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


func test_a_level_3_host_asking_for_the_back_rooms_gets_the_lot_for_everyone() -> void:
	await _start()
	var host := await _enter("low-host", "host", 3, BACK_ROOMS)
	var room := _server.room_of_match("low-host")
	assert_str(room.world.map_info.id).is_equal("drive_in")
	assert_str(room.server.rules.settings.map).is_equal("drive_in")
	assert_str(host.match_settings.map).is_equal("drive_in")
	# A level-12 guest of that host cannot lift it: the ticket says whose level decides.
	var guest := await _enter("low-host", "guest", 3, BACK_ROOMS)
	assert_str(guest.match_settings.map).is_equal("drive_in")
	assert_str(guest.world.map_info.id).is_equal("drive_in")


func test_a_level_12_host_has_the_back_rooms_and_a_level_3_guest_plays_there() -> void:
	await _start()
	var host := await _enter("high-host", "host", 12, BACK_ROOMS)
	var room := _server.room_of_match("high-host")
	assert_str(room.world.map_info.id).is_equal(BACK_ROOMS)
	assert_str(host.world.map_info.id).is_equal(BACK_ROOMS)
	# The guest's own level is nowhere in the ticket: it is a visitor on the host's map.
	var guest := await _enter("high-host", "guest", 12, BACK_ROOMS)
	assert_str(guest.match_settings.map).is_equal(BACK_ROOMS)
	assert_str(guest.world.map_info.id).is_equal(BACK_ROOMS)


func test_the_order_the_players_arrive_in_decides_nothing() -> void:
	await _start()
	# The guest's ticket reaches the server first: it opens the room, with the host's level.
	var guest := await _enter("order", "guest", 4, BACK_ROOMS)
	assert_str(guest.world.map_info.id).is_equal("drive_in")
	var host := await _enter("order", "host", 4, BACK_ROOMS)
	assert_str(host.world.map_info.id).is_equal("drive_in")


func test_a_ticket_that_says_no_level_counts_the_host_as_level_1() -> void:
	await _start()
	var night := await _enter("no-level", "host", null, BACK_ROOMS)
	assert_str(night.world.map_info.id).is_equal("drive_in")
	assert_str(_server.room_of_match("no-level").world.map_info.id).is_equal("drive_in")


# --- The real backend (#1107) ---


static func _backend_path() -> String:
	return ProjectSettings.globalize_path(BACKEND_DIR).simplify_path()


static func _why_not() -> String:
	var out := []
	if OS.execute("node", ["--version"], out) != OK:
		return "no node on this machine"
	var major := str(out[0]).strip_edges().trim_prefix("v").split(".")[0].to_int()
	if major < 24:
		return "node %d is too old (the backend needs 24)" % major
	if not DirAccess.dir_exists_absolute(_backend_path() + "/node_modules/fastify"):
		return "run `npm ci` in spikes/backend first"
	return ""


func _free_port() -> int:
	var probe := TCPServer.new()
	assert_int(probe.listen(0, "127.0.0.1")).is_equal(OK)
	var port := probe.get_local_port()
	probe.stop()
	return port


## The real backend, and a real game server that heartbeats to it and takes the tickets it signs.
func _start_stack() -> void:
	var port := _free_port()
	var env := {
		"HOST": "127.0.0.1",
		"PORT": str(port),
		"DISCORD_MODE": "off",
		"GUEST_SIGN_IN": "1",
		"NODE_ENV": "test",
		"LOG_LEVEL": "warn",
		"SESSION_SECRET": SESSION_SECRET,
		"TICKET_SECRET": TICKET_SECRET,
		"GAME_SERVER_SECRET": GAME_SERVER_SECRET,
	}
	for key: String in env:
		OS.set_environment(key, env[key])
	_pid = OS.create_process("node", [_backend_path() + "/src/main.ts"])
	for key: String in env:
		OS.unset_environment(key)
	assert_int(_pid).is_greater(0)
	_backend = "http://127.0.0.1:%d" % port
	var up := await _until(
		func() -> bool:
			var health := await HttpJson.send(self, "GET", _backend + "/health")
			return health["status"] == 200,
		90.0
	)
	assert_bool(up).is_true()
	var server_port := _free_port()
	_server = GameServer.new()
	_server.port = server_port
	_server.capacity = 4
	_server.server_id = SERVER_ID
	_server.public_url = "ws://127.0.0.1:%d" % server_port
	_server.backend_url = _backend
	_server.backend_secret = GAME_SERVER_SECRET
	_server.heartbeat_every = 0.4
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(TICKET_SECRET, SERVER_ID)
	_world().add_child(_server)
	var registered := await _until(
		func() -> bool:
			var ready := await HttpJson.send(self, "GET", _backend + "/ready")
			return ready["status"] == 200 and int(ready["json"].get("gameServers", 0)) >= 1,
		60.0
	)
	assert_bool(registered).is_true()


## A signed-in guest account of `level`: the backend pays it the XP that level begins at, as a game
## server's report does (the host's level is read from the stored profile).
func _account(player_name: String, level: int) -> TogetherApi:
	var api := TogetherApi.new(self, _backend)
	api.isolated = true
	var signed := await api.sign_in(player_name)
	assert_bool(signed["ok"]).is_true()
	if level > 1:
		var seat := {"userId": api.my_id(), "xp": LevelCurve.xp_for(level)}
		var sent := await HttpJson.send(
			self,
			"POST",
			"%s/internal/matches/seed-%s/report" % [_backend, player_name],
			{"Authorization": "Bearer " + GAME_SERVER_SECRET},
			{"kind": "night", "round": 0, "seats": [seat]}
		)
		assert_int(sent["status"]).is_equal(200)
	return api


## `api` takes its ticket for `lobby` and enters the night with it. Returns the night joined and
## the claims of the ticket as the backend signed it (read without spending it).
func _go_in(api: TogetherApi, lobby: Dictionary) -> Dictionary:
	var pass_to := await api.ticket(lobby)
	assert_bool(pass_to["ok"]).is_true()
	var claims := TicketVerifier.new(TICKET_SECRET, SERVER_ID).claims_of(
		pass_to["ticket"], int(Time.get_unix_time_from_system())
	)
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = pass_to["ticket"]
	var joined := await night.start_remote(pass_to["url"], Night.Mode.MANUAL, 60.0, link)
	assert_bool(joined).is_true()
	_nights.append(night)
	return {"night": night, "claims": claims}


func _rules_on(map_id: String) -> MatchSettings:
	var chosen := MatchSettings.new()
	chosen.map = map_id
	return chosen.clamped()


func test_a_level_3_host_has_the_lot_with_a_level_12_guest_over_the_real_backend(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _start_stack()
	var host := await _account("Low", 3)
	var guest := await _account("High", 12)
	var lobby: Dictionary = (await host.create_lobby())["lobby"]
	# The backend refuses the back rooms to this host: the picker's refusal and the server's agree.
	var refused := await host.set_settings(lobby, _rules_on(BACK_ROOMS))
	assert_bool(refused["ok"]).is_false()
	assert_str(refused["error"]).is_equal("bad_settings")
	var joined := await guest.join_code(lobby["code"])
	assert_bool(joined["ok"]).is_true()
	var started := await host.start(lobby)
	assert_bool(started["ok"]).is_true()
	lobby = started["lobby"]
	var guest_lobby: Dictionary = (await guest.refresh(joined["lobby"]))["lobby"]
	# The guest, level 12, goes in first: the order decides nothing, the host's level is in both.
	var guest_in := await _go_in(guest, guest_lobby)
	var host_in := await _go_in(host, lobby)
	assert_int(int(guest_in["claims"]["hostLevel"])).is_equal(3)
	assert_int(int(host_in["claims"]["hostLevel"])).is_equal(3)
	var room := _server.room_of_match(str(lobby["matchId"]))
	assert_object(room).is_not_null()
	assert_str(room.world.map_info.id).is_equal(MapRegistry.DEFAULT)
	assert_str((host_in["night"] as Night).world.map_info.id).is_equal(MapRegistry.DEFAULT)
	assert_str((guest_in["night"] as Night).world.map_info.id).is_equal(MapRegistry.DEFAULT)


func test_a_level_12_host_has_the_back_rooms_with_a_level_3_guest_over_the_real_backend(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _start_stack()
	var host := await _account("High", 12)
	var guest := await _account("Low", 3)
	var lobby: Dictionary = (await host.create_lobby())["lobby"]
	assert_bool((await host.set_settings(lobby, _rules_on(BACK_ROOMS)))["ok"]).is_true()
	var joined := await guest.join_code(lobby["code"])
	assert_bool(joined["ok"]).is_true()
	var started := await host.start(lobby)
	assert_bool(started["ok"]).is_true()
	lobby = started["lobby"]
	var guest_lobby: Dictionary = (await guest.refresh(joined["lobby"]))["lobby"]
	# The level-3 guest arrives first: a visitor on the host's map, whatever its own level.
	var guest_in := await _go_in(guest, guest_lobby)
	var host_in := await _go_in(host, lobby)
	assert_int(int(guest_in["claims"]["hostLevel"])).is_equal(12)
	assert_int(int(host_in["claims"]["hostLevel"])).is_equal(12)
	var room := _server.room_of_match(str(lobby["matchId"]))
	assert_object(room).is_not_null()
	assert_str(room.world.map_info.id).is_equal(BACK_ROOMS)
	assert_str(room.server.rules.settings.map).is_equal(BACK_ROOMS)
	assert_str((host_in["night"] as Night).world.map_info.id).is_equal(BACK_ROOMS)
	assert_str((guest_in["night"] as Night).world.map_info.id).is_equal(BACK_ROOMS)
