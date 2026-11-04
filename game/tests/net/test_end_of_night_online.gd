# The end of a night over real sockets on this machine (Deadnight #973): the platform backend is the
# real one (`spikes/backend`, run by Node), the game server a real `GameServer` heartbeating to it,
# and every player a `TogetherApi` with a session of its own plus a `Night` that joined with the
# backend's own ticket.
#
# The night ends (everyone down): every client reads the server's clock in step and the night is
# closed for all of them at the same moment; a player who leaves during the intermission does not
# break the others' return; the backend then opens the lobby again for the people who were there,
# with its code, host and the host's rules (map, bots, rules); the host starts the next night
# there and the room runs those rules. Through the real screens: the night screen of a player ends
# on the lobby screen of the reopened lobby.
#
# It needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without them the suite
# is skipped with a line saying so.
extends GdUnitTestSuite

const BACKEND_DIR := "res://../spikes/backend"
const SERVER_ID := "gs-end"
const SESSION_SECRET := "session-secret-of-at-least-32-characters-a"
const TICKET_SECRET := "ticket-secret-of-at-least-32-characters-b"
const GAME_SERVER_SECRET := "server-secret-of-at-least-32-characters-c"
## The intermission a test waits for (the shipped one is 15 s).
const SECONDS := 3.0

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
	# A machine that cannot run the suite skips at once: no node, no 90 s wait for a backend (#1049).
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


## The host's rules: the second map, two bots, a heavier night and a short break.
func _rules() -> MatchSettings:
	var chosen := MatchSettings.new()
	chosen.map = "small_indoor"
	chosen.bots = 2
	chosen.bot_skill = 2
	chosen.count_multiplier = 2.0
	chosen.break_seconds = 9.0
	return chosen.clamped()


## Ann hosts a lobby with the rules, Bo and Cy join it, the host starts it and all three are in the
## night. Returns the match's id.
func _night_of_three(ann: Guest, bo: Guest, cy: Guest) -> String:
	ann.lobby = (await ann.api.create_lobby())["lobby"]
	assert_bool((await ann.api.set_settings(ann.lobby, _rules()))["ok"]).is_true()
	bo.lobby = (await bo.api.join_code(ann.lobby["code"]))["lobby"]
	cy.lobby = (await cy.api.join_code(ann.lobby["code"]))["lobby"]
	var started := await ann.api.start(ann.lobby)
	assert_bool(started["ok"]).is_true()
	ann.lobby = started["lobby"]
	bo.lobby = (await bo.api.refresh(bo.lobby))["lobby"]
	cy.lobby = (await cy.api.refresh(cy.lobby))["lobby"]
	for guest: Guest in [ann, bo, cy]:
		await _go_in(guest)
	return str(ann.lobby["matchId"])


## Everyone in the room goes down: the night is over, as the server's own rules say.
func _end(room: NightHost) -> void:
	var rules := room.server.rules
	room._collect(rules.apply(RulesAction.skip_break()))
	for id: int in rules.players.keys():
		room._collect(rules.apply(RulesAction.set_downed(id, true)))


func _names(held: Dictionary) -> Array:
	return held["members"].map(func(m: Dictionary) -> String: return m["name"])


# --- The tests ---


func test_the_night_ends_on_the_servers_clock_a_leaver_breaks_nothing_and_the_lobby_returns(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")
	var match_id := await _night_of_three(ann, bo, cy)
	var room := _server.room_of_match(match_id)
	assert_object(room).is_not_null()
	# The room runs the host's rules: the second map, two bots.
	assert_str(room.match_settings.map).is_equal("small_indoor")
	assert_int(room.server.rules.settings.bots).is_equal(2)
	room.server.end_seconds = SECONDS
	assert_int(room.player_count()).is_equal(3)

	# The night ends. Every client reads it over the socket, and the clock the same seconds.
	_end(room)
	var all_over := await _until(
		func() -> bool: return ann.night.state.over and bo.night.state.over and cy.night.state.over
	)
	assert_bool(all_over).is_true()
	assert_object(ann.night.end_camera).is_not_null()
	var first_left: int = ann.night.state.over_left()
	assert_int(first_left).is_between(int(SECONDS) - 1, int(SECONDS))
	# Nobody was sent away: the three are still in the room.
	assert_int(room.player_count()).is_equal(3)

	# Cy leaves in the middle of it; the room frees the seat and the others go on.
	cy.night.link.close()
	var freed := await _until(func() -> bool: return room.player_count() == 2)
	assert_bool(freed).is_true()
	assert_bool(ann.night.state.closed).is_false()
	assert_bool(bo.night.state.closed).is_false()

	# The two read the clock go down in step (never more than a second apart) to the close.
	var worst := 0
	var seen := {}
	var closed := await _until(
		func() -> bool:
			var a: int = ann.night.state.over_left()
			var b: int = bo.night.state.over_left()
			worst = maxi(worst, absi(a - b))
			seen[a] = true
			return ann.night.state.closed and bo.night.state.closed,
		20.0
	)
	assert_bool(closed).is_true()
	assert_int(worst).is_less_equal(1)
	assert_int(ann.night.state.over_left()).is_equal(0)
	# Both left the seat at once; the room is empty and the match is over.
	var gone := await _until(func() -> bool: return _server.room_of_match(match_id) == null)
	assert_bool(gone).is_true()

	# The backend opened the lobby again: the same code and host, the two who were there, the rules.
	var held := [{}]
	var open := await _until(
		func() -> bool:
			var answer := await ann.api.refresh(ann.lobby)
			if answer["ok"]:
				held[0] = answer["lobby"]
			return answer["ok"] and held[0].get("state") == "open"
	)
	assert_bool(open).is_true()
	var reopened: Dictionary = held[0]
	assert_str(reopened["code"]).is_equal(ann.lobby["code"])
	assert_str(reopened["hostId"]).is_equal(ann.api.my_id())
	assert_array(_names(reopened)).is_equal(["Ann", "Bo"])
	assert_dict(MatchSettings.from_json(reopened["settings"]).to_dict()).is_equal(
		_rules().to_dict()
	)
	# Cy left the night, so Cy is not in the lobby; Bo reads the same lobby.
	assert_str((await cy.api.refresh(cy.lobby))["error"]).is_equal("not_member")
	var bo_view := await bo.api.refresh(bo.lobby)
	assert_str(bo_view["lobby"]["state"]).is_equal("open")

	# Ann starts the next night there: the room runs the same rules.
	var again := await ann.api.start(ann.lobby)
	assert_bool(again["ok"]).is_true()
	ann.lobby = again["lobby"]
	await _go_in(ann)
	var next_room := _server.room_of_match(str(ann.lobby["matchId"]))
	assert_object(next_room).is_not_null()
	assert_str(next_room.match_settings.map).is_equal("small_indoor")
	assert_int(next_room.match_settings.bots).is_equal(2)
	assert_float(next_room.match_settings.count_multiplier).is_equal(2.0)
	assert_float(next_room.match_settings.break_seconds).is_equal(9.0)


func test_the_host_who_leaves_during_the_intermission_hands_the_reopened_lobby_on(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")
	var match_id := await _night_of_three(ann, bo, cy)
	var room := _server.room_of_match(match_id)
	room.server.end_seconds = SECONDS
	_end(room)
	assert_bool(await _until(func() -> bool: return ann.night.state.over)).is_true()
	# The host presses Leave (the screen closes the link and leaves the lobby).
	ann.night.link.close()
	assert_bool((await ann.api.leave(ann.lobby))["ok"]).is_true()
	var closed := await _until(
		func() -> bool: return bo.night.state.closed and cy.night.state.closed, 20.0
	)
	assert_bool(closed).is_true()
	var held := [{}]
	var last := [{}]
	var open := await _until(
		func() -> bool:
			var answer := await bo.api.refresh(bo.lobby)
			last[0] = answer
			if answer["ok"]:
				held[0] = answer["lobby"]
			return answer["ok"] and held[0].get("state") == "open"
	)
	assert_bool(open).override_failure_message("the last answer: %s" % [last[0]]).is_true()
	var reopened: Dictionary = held[0]
	assert_str(reopened["hostId"]).is_equal(bo.api.my_id())
	assert_array(_names(reopened)).is_equal(["Bo", "Cy"])


func test_a_night_everyone_left_does_not_reopen_the_lobby(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")
	var match_id := await _night_of_three(ann, bo, cy)
	var room := _server.room_of_match(match_id)
	room.server.end_seconds = 30.0
	_end(room)
	assert_bool(await _until(func() -> bool: return ann.night.state.over)).is_true()
	for guest: Guest in [ann, bo, cy]:
		guest.night.link.close()
	var gone := await _until(func() -> bool: return _server.room_of_match(match_id) == null)
	assert_bool(gone).is_true()
	var dropped := await _until(
		func() -> bool: return (await ann.api.refresh(ann.lobby)).get("error") == "not_found"
	)
	assert_bool(dropped).is_true()


func test_the_night_screen_of_a_player_ends_on_the_lobby_screen_of_the_reopened_lobby(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	ann.lobby = (await ann.api.create_lobby())["lobby"]
	assert_bool((await ann.api.set_settings(ann.lobby, _rules()))["ok"]).is_true()
	bo.lobby = (await bo.api.join_code(ann.lobby["code"]))["lobby"]
	ann.lobby = (await ann.api.start(ann.lobby))["lobby"]
	bo.lobby = (await bo.api.refresh(bo.lobby))["lobby"]
	await _go_in(bo)
	# Ann plays through the real night screen, entered as the lobby screen enters it.
	var pass_to := await ann.api.ticket(ann.lobby)
	NightScreen.join_url = pass_to["url"]
	NightScreen.join_ticket = pass_to["ticket"]
	NightScreen.join_map = "small_indoor"
	NightScreen.remember_lobby(ann.api, ann.lobby, get_tree().root)
	UIRouter.push("res://ui/screens/night_screen.tscn", UITransition.Kind.CUT)
	var room := _server.room_of_match(str(ann.lobby["matchId"]))
	(
		assert_bool(await _until(func() -> bool: return room != null and room.player_count() == 2))
		. is_true()
	)
	var screen := UIRouter.top() as NightScreen
	assert_object(screen).is_not_null()
	room.server.end_seconds = SECONDS
	_end(room)
	assert_bool(await _until(func() -> bool: return screen.night.state.over)).is_true()
	await get_tree().process_frame
	# The board is up over the camera's flight, with every player and the server's seconds.
	var board: HudEndBoard = screen.get_node("EndBoard")
	assert_bool(board.visible).is_true()
	assert_bool(screen._hud.visible).is_false()
	assert_int(board.row_ids.size()).is_greater_equal(2)
	assert_str(board.leave_button.text).is_equal("Leave")
	assert_str(board.countdown_text).is_not_empty()
	# At the end of the clock the screen is replaced by the lobby's: open, the same code, the rules.
	var back := await _until(
		func() -> bool: return UIRouter.top() is LobbyScreen and not UIRouter.busy, 30.0
	)
	assert_bool(back).is_true()
	var lobby_screen := UIRouter.top() as LobbyScreen
	assert_str(lobby_screen.lobby["state"]).is_equal("open")
	assert_str(lobby_screen.lobby["code"]).is_equal(ann.lobby["code"])
	assert_bool(lobby_screen.is_host()).is_true()
	assert_str(lobby_screen.rules_text()).is_not_empty()
	assert_str(lobby_screen.lobby_rules().map).is_equal("small_indoor")
	assert_int(lobby_screen.lobby_rules().bots).is_equal(2)
