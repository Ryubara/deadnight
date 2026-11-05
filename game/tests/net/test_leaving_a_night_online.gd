# Leaving a night, over real sockets on this machine (Deadnight #1177): the platform backend is the
# real one (`spikes/backend`, run by Node), the game server a real `GameServer` heartbeating to it,
# and every player a `TogetherApi` with a session of its own plus a `Night` that joined with the
# backend's own ticket.
#
# The maintainer: "when players leave a match and they try joining another, it says they're already
# in an existing night", and "why aren't lobbies immediately disbanded and player state cleared
# whenever the lobby is empty? The lobby I left had bots in it". Every way out of a night is run
# here, with bots in the room, and each ends with the same check: the player creates, joins and
# quick-joins another night at once, and the lobby they left is gone when no person is in it.
#
# It needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without them the suite
# is skipped with a line saying so.
extends GdUnitTestSuite

const BACKEND_DIR := "res://../spikes/backend"
const SERVER_ID := "gs-leaving"
const SESSION_SECRET := "session-secret-of-at-least-32-characters-a"
const TICKET_SECRET := "ticket-secret-of-at-least-32-characters-b"
const GAME_SERVER_SECRET := "server-secret-of-at-least-32-characters-c"
## The intermission a test waits for (the shipped one is 15 s).
const SECONDS := 2.0
const SKIP := "needs node 24 and npm ci in spikes/backend"
## The next thing a player does after leaving, one for each of three players.
const NEXT := ["create", "join", "quick"]

var _pid := 0
var _backend := ""
var _server: GameServer
var _nights: Array[Night] = []


func before_test() -> void:
	await _start_stack()


func after_test() -> void:
	await RouterFixture.clear(get_tree())
	NightScreen.join_url = ""
	NightScreen.return_lobby = {}
	NightScreen.return_api = null
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	if is_instance_valid(_server):
		_server.get_parent().queue_free()
	if _pid != 0:
		OS.kill(_pid)
		_pid = 0
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


# --- The stack ---


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
		await get_tree().create_timer(0.05).timeout
	return true


func _start_stack() -> void:
	if _why_not() != "":
		return
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


# --- Players ---


class Guest:
	extends RefCounted
	var api: TogetherApi
	var name := ""
	var lobby := {}
	var night: Night


func _guest(player_name: String) -> Guest:
	var player := Guest.new()
	player.name = player_name
	player.api = TogetherApi.new(self, _backend)
	player.api.isolated = true
	var signed := await player.api.sign_in(player_name)
	assert_bool(signed["ok"]).is_true()
	return player


func _go_in(player: Guest) -> Night:
	var pass_to := await player.api.ticket(player.lobby)
	assert_bool(pass_to["ok"]).is_true()
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = pass_to["ticket"]
	var joined := await night.start_remote(pass_to["url"], Night.Mode.MANUAL, 60.0, link)
	assert_bool(joined).is_true()
	_nights.append(night)
	player.night = night
	return night


## Three bots, as a host picks them on the lobby screen.
func _with_bots() -> MatchSettings:
	var chosen := MatchSettings.new()
	chosen.bots = 3
	return chosen.clamped()


## The player hosts a lobby with bots, starts it and is in the night. Returns the room.
func _night_with_bots(player: Guest) -> NightHost:
	player.lobby = (await player.api.create_lobby())["lobby"]
	assert_bool((await player.api.set_settings(player.lobby, _with_bots()))["ok"]).is_true()
	var started := await player.api.start(player.lobby)
	assert_bool(started["ok"]).is_true()
	player.lobby = started["lobby"]
	await _go_in(player)
	var room := _server.room_of_match(str(player.lobby["matchId"]))
	assert_object(room).is_not_null()
	# The bots took the seats the person did not (the scenario the maintainer left).
	var seated := await _until(func() -> bool: return room.bots.count() > 0)
	assert_bool(seated).is_true()
	return room


## Whether the lobby with this code still exists (any signed-in player may look at a code).
func _exists(looker: Guest, code: String) -> bool:
	return (await looker.api.preview(code))["ok"]


## The next thing a player does, straight after leaving: one of three, each a move, none refused.
## `target` is a waiting lobby another player has open.
func _next(player: Guest, kind: String, target: Dictionary) -> Dictionary:
	match kind:
		"create":
			return await player.api.create_lobby()
		"join":
			return await player.api.join_code(target["code"])
		_:
			return await player.api.quick()


## Everyone in the room goes down: the night is over, as the server's own rules say.
func _end(room: NightHost) -> void:
	var rules := room.server.rules
	room._collect(rules.apply(RulesAction.skip_break()))
	for id: int in rules.players.keys():
		room._collect(rules.apply(RulesAction.set_downed(id, true)))


# --- The ways out of a night ---


## Three players, each alone in a night of their own with bots, leave the same way and each does a
## different next thing at once: create, join a waiting lobby, quick join. The lobby each left is
## gone when no person is in it, and its room is over.
func _leave_with_bots_then_move(how: String) -> void:
	var watcher := await _guest("Watcher")
	var waiting: Dictionary = (await watcher.api.create_lobby())["lobby"]
	var players: Array[Guest] = []
	for kind in NEXT:
		var player := await _guest("P_" + kind)
		await _night_with_bots(player)
		players.append(player)
	var rooms: Array[String] = []
	for player in players:
		rooms.append(str(player.lobby["matchId"]))
	for player in players:
		if how == "button":
			# What the night screen's Leave does: say so to the backend, then close the socket.
			assert_bool((await player.api.leave(player.lobby))["ok"]).is_true()
		player.night.link.close()
	for i in players.size():
		var answer := await _next(players[i], NEXT[i], waiting)
		(
			assert_bool(answer["ok"])
			. override_failure_message("%s then %s: %s" % [how, NEXT[i], answer.get("error", "")])
			. is_true()
		)
	for i in players.size():
		var code: String = players[i].lobby["code"]
		var gone := await _until(func() -> bool: return not await _exists(watcher, code), 10.0)
		(
			assert_bool(gone)
			. override_failure_message("%s: the lobby %s is still there" % [how, code])
			. is_true()
		)
		var ended := await _until(
			func() -> bool: return _server.room_of_match(rooms[i]) == null, 10.0
		)
		assert_bool(ended).override_failure_message("%s: the room is still up" % how).is_true()


func test_leaving_with_the_button_with_bots_in_the_room_frees_the_player_and_ends_the_lobby(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _leave_with_bots_then_move("button")


func test_closing_the_tab_with_bots_in_the_room_frees_the_player_and_ends_the_lobby(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _leave_with_bots_then_move("tab")


func test_a_night_that_ended_and_reopened_for_a_player_who_went_to_the_menu_holds_nobody(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	var ann := await _guest("Ann")
	var watcher := await _guest("Watcher")
	var room := await _night_with_bots(ann)
	var code: String = ann.lobby["code"]
	room.server.end_seconds = SECONDS
	_end(room)
	# The intermission runs out and the room closes. Ann's screen waited for the lobby, gave up and
	# went to the menu (or her tab is closed): she never polls it, and never says leave.
	var open := await _until(
		func() -> bool:
			var seen := await watcher.api.preview(code)
			return seen["ok"] and seen["preview"]["state"] == "open",
		30.0
	)
	assert_bool(open).override_failure_message("the lobby never reopened").is_true()
	var made := await ann.api.create_lobby()
	assert_bool(made["ok"]).override_failure_message(str(made.get("error", ""))).is_true()


func test_the_menus_leave_night_leaves_the_lobby_too(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	ann.lobby = (await ann.api.create_lobby())["lobby"]
	bo.lobby = (await bo.api.join_code(ann.lobby["code"]))["lobby"]
	ann.lobby = (await ann.api.start(ann.lobby))["lobby"]
	bo.lobby = (await bo.api.refresh(bo.lobby))["lobby"]
	await _go_in(bo)
	var pass_to := await ann.api.ticket(ann.lobby)
	NightScreen.join_url = pass_to["url"]
	NightScreen.join_ticket = pass_to["ticket"]
	NightScreen.join_map = "drive_in"
	NightScreen.remember_lobby(ann.api, ann.lobby, get_tree().root)
	UIRouter.push("res://ui/screens/night_screen.tscn", UITransition.Kind.CUT)
	var room := _server.room_of_match(str(ann.lobby["matchId"]))
	(
		assert_bool(await _until(func() -> bool: return room != null and room.player_count() == 2))
		. is_true()
	)
	var screen := UIRouter.top() as NightScreen
	assert_object(screen).is_not_null()
	# Esc, then "Leave night".
	screen._leave()
	var told := await _until(
		func() -> bool: return (await ann.api.refresh(ann.lobby)).get("error", "") == "not_member"
	)
	assert_bool(told).is_true()
	# Bo, who stays, sees one person in the night, not two.
	var seen := await bo.api.refresh(bo.lobby)
	(
		assert_array(seen["lobby"]["members"].map(func(m: Dictionary) -> String: return m["name"]))
		. is_equal(["Bo"])
	)


func test_a_player_who_drops_out_of_a_night_with_others_in_it_is_no_longer_in_its_lobby(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	ann.lobby = (await ann.api.create_lobby())["lobby"]
	assert_bool((await ann.api.set_settings(ann.lobby, _with_bots()))["ok"]).is_true()
	bo.lobby = (await bo.api.join_code(ann.lobby["code"]))["lobby"]
	ann.lobby = (await ann.api.start(ann.lobby))["lobby"]
	bo.lobby = (await bo.api.refresh(bo.lobby))["lobby"]
	await _go_in(ann)
	await _go_in(bo)
	# Ann's tab is closed.
	ann.night.link.close()
	var listed := await _until(
		func() -> bool:
			var seen := await bo.api.refresh(bo.lobby)
			return seen["ok"] and seen["lobby"]["members"].size() == 1,
		10.0
	)
	assert_bool(listed).is_true()
	# Bo is the host now and the night goes on with him.
	var seen := await bo.api.refresh(bo.lobby)
	assert_str(seen["lobby"]["hostId"]).is_equal(bo.api.my_id())
	# Ann joins a night straight away.
	assert_bool((await ann.api.quick())["ok"]).is_true()
