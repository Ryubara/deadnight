# The pre-game lobby over real sockets on this machine (#515): the platform backend is the real one
# (`spikes/backend`, run by Node on a free port with memory storage and guest sign-in), the game
# server is a real `GameServer` heartbeating to it, and every player is a `TogetherApi` with a
# session of its own plus a `Night` that joined with the backend's own ticket.
#
# Two players meet in a lobby and see each other, a guest cannot start, the host starts and both
# enter the same night, a third reads "Night in progress, round N" from the code, joins mid-match,
# and the others hear it (the notices of the night say "JOINED" and "LEFT"); a full night turns the
# next player away; the host who leaves before the start hands the role on.
#
# It needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without them the
# suite is skipped with a line saying so.
extends GdUnitTestSuite

const BACKEND_DIR := "res://../spikes/backend"
const SERVER_ID := "gs-lobby"
const SESSION_SECRET := "session-secret-of-at-least-32-characters-a"
const TICKET_SECRET := "ticket-secret-of-at-least-32-characters-b"
const GAME_SERVER_SECRET := "server-secret-of-at-least-32-characters-c"

var _pid := 0
var _backend := ""
var _server: GameServer
var _nights: Array[Night] = []
var _watches: Array[LobbyWatch] = []


func before_test() -> void:
	await _start_stack()


func after_test() -> void:
	for watch in _watches:
		if is_instance_valid(watch):
			watch.stop()
	_watches.clear()
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


## Why this machine cannot run the suite ("" when it can).
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
	var watch: LobbyWatch
	var heard: Array = []
	var night: Night


func _guest(player_name: String) -> Guest:
	var player := Guest.new()
	player.name = player_name
	player.api = TogetherApi.new(self, _backend)
	player.api.isolated = true
	var signed := await player.api.sign_in(player_name)
	assert_bool(signed["ok"]).is_true()
	return player


func _watch(player: Guest) -> void:
	player.watch = LobbyWatch.new()
	add_child(player.watch)
	player.watch.every = 3600.0
	player.watch.watch(player.api, player.lobby, player.api.my_id())
	player.watch.happened.connect(func(events: Array) -> void: player.heard.append_array(events))
	_watches.append(player.watch)


func _names(player: Guest) -> Array:
	return player.watch.lobby["members"].map(func(m: Dictionary) -> String: return m["name"])


## The player enters the night of its lobby with the backend's own ticket.
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


# --- The tests ---


func test_two_players_meet_the_host_starts_and_a_third_joins_mid_match(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")

	# Ann makes a lobby: she is the host and the night has not started.
	var made := await ann.api.create_lobby()
	assert_bool(made["ok"]).is_true()
	ann.lobby = made["lobby"]
	assert_str(ann.lobby["state"]).is_equal("open")
	assert_str(ann.lobby["hostId"]).is_equal(ann.api.my_id())
	var code: String = ann.lobby["code"]
	_watch(ann)

	# Bo looks at the code (joined to nothing) and then joins: each sees the other.
	var seen := await bo.api.preview(code)
	assert_str(LobbyScreen.preview_text(seen["preview"])).is_equal(
		"Waiting room. Ann is hosting, 1 of 4 here."
	)
	assert_array(_names(ann)).is_equal(["Ann"])
	var joined := await bo.api.join_code(code)
	assert_bool(joined["ok"]).is_true()
	bo.lobby = joined["lobby"]
	_watch(bo)
	(
		assert_array(bo.lobby["members"].map(func(m: Dictionary) -> String: return m["name"]))
		. is_equal(["Ann", "Bo"])
	)
	await ann.watch.poll()
	assert_array(_names(ann)).is_equal(["Ann", "Bo"])
	(
		assert_array(ann.heard.map(func(e: Dictionary) -> String: return e["kind"]))
		. is_equal(["joined"])
	)
	assert_str(LobbyScreen.event_text(ann.heard[0])).is_equal("Bo joined.")

	# Nobody has a night yet; the guest cannot start one.
	assert_str((await bo.api.ticket(bo.lobby))["error"]).is_equal("not_started")
	assert_str((await bo.api.start(bo.lobby))["error"]).is_equal("not_host")

	# The host starts: Bo's poll sees it, and both enter the same night.
	var started := await ann.api.start(ann.lobby)
	assert_bool(started["ok"]).is_true()
	ann.lobby = started["lobby"]
	assert_str(ann.lobby["state"]).is_equal("started")
	await bo.watch.poll()
	assert_str(bo.watch.lobby["state"]).is_equal("started")
	assert_str(LobbyScreen.status_text(bo.watch.lobby, bo.api.my_id())).is_equal(
		"Ann started the night. Press Play."
	)
	bo.lobby = bo.watch.lobby
	var ann_night := await _go_in(ann)
	var bo_night := await _go_in(bo)
	var match_id: String = ann.lobby["matchId"]
	var room := _server.room_of_match(match_id)
	assert_object(room).is_not_null()
	assert_int(room.player_count()).is_equal(2)
	assert_int(ann_night.state.player_id).is_equal(1)
	assert_int(bo_night.state.player_id).is_equal(2)

	# The night's notices hear a join and a leave.
	var hud_state := HudState.new()
	var notices := HudFeed.new()
	notices.kind = HudFeed.Kind.NOTICES
	add_child(notices)
	notices.bind(hud_state)
	ann_night.state.event_received.connect(
		func(event: Dictionary) -> void: hud_state.apply_events([event])
	)
	hud_state.local_player_id = 1

	# The game server says the round; a late joiner reads it from the code before joining.
	# (The rules are moved to round 3 directly: a real night takes minutes to get there.)
	room.server.rules.round_number = 3
	var read := [{}]
	var heard := await _until(
		func() -> bool:
			read[0] = (await cy.api.preview(code))["preview"]
			return read[0].get("round") == 3
	)
	assert_bool(heard).is_true()
	var in_progress: Dictionary = read[0]
	assert_str(LobbyScreen.preview_text(in_progress)).is_equal(
		"Night in progress, round 3. 2 of 4 here."
	)
	assert_bool(in_progress["full"]).is_false()

	# Cy presses Join: straight into the same night, as player 3, and the others are told.
	var cy_joined := await cy.api.join_code(code)
	assert_bool(cy_joined["ok"]).is_true()
	cy.lobby = cy_joined["lobby"]
	assert_str(cy.lobby["state"]).is_equal("started")
	var cy_night := await _go_in(cy)
	assert_int(cy_night.state.player_id).is_equal(3)
	assert_int(room.player_count()).is_equal(3)
	# (The label's own reveal animation scrambles the letters for a moment: wait for the settled text.)
	var told := await _until(func() -> bool: return notices.texts().has("CY JOINED"))
	assert_bool(told).is_true()
	# The lobby the others poll lists all three, and the round the night is in.
	await ann.watch.poll()
	assert_array(_names(ann)).is_equal(["Ann", "Bo", "Cy"])
	assert_int(int(ann.watch.lobby["round"])).is_equal(3)

	# Cy leaves the night: the others read it.
	cy_night.link.close()
	var left := await _until(func() -> bool: return notices.texts().has("CY LEFT"))
	assert_bool(left).is_true()


func test_the_rules_the_host_sets_while_waiting_reach_the_guest_the_ticket_and_the_room(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	var made := await ann.api.create_lobby()
	ann.lobby = made["lobby"]
	var code: String = ann.lobby["code"]
	assert_object(ann.lobby["settings"]).is_null()
	var joined := await bo.api.join_code(code)
	bo.lobby = joined["lobby"]
	_watch(bo)

	# The host moves the rules; the guest reads them on a poll, as the lobby screen does.
	var chosen := MatchSettings.new()
	chosen.count_multiplier = 3.0
	chosen.max_alive = 12
	chosen.break_seconds = 11.0
	var changed := await ann.api.set_settings(ann.lobby, chosen)
	assert_bool(changed["ok"]).is_true()
	await bo.watch.poll()
	assert_dict(MatchSettings.from_json(bo.watch.lobby["settings"]).to_dict()).is_equal(
		chosen.to_dict()
	)
	# The guest cannot change them.
	var refused := await bo.api.set_settings(bo.lobby, MatchSettings.new())
	assert_str(refused["error"]).is_equal("not_host")
	(
		assert_array(bo.watch.lobby["members"].map(func(m: Dictionary) -> String: return m["name"]))
		. is_equal(["Ann", "Bo"])
	)

	# The start with the panel's rules (the same ones): both nights run with them.
	var started := await ann.api.start(ann.lobby, chosen)
	assert_bool(started["ok"]).is_true()
	ann.lobby = started["lobby"]
	await bo.watch.poll()
	bo.lobby = bo.watch.lobby
	var ann_night := await _go_in(ann)
	var bo_night := await _go_in(bo)
	var room := _server.room_of_match(str(ann.lobby["matchId"]))
	assert_dict(room.server.rules.settings.to_dict()).is_equal(chosen.to_dict())
	assert_dict(ann_night.match_settings.to_dict()).is_equal(chosen.to_dict())
	assert_dict(bo_night.match_settings.to_dict()).is_equal(chosen.to_dict())
	# Fixed from the start on.
	var late := await ann.api.set_settings(ann.lobby, MatchSettings.new())
	assert_str(late["error"]).is_equal("already_started")


func test_a_full_night_turns_the_next_player_away_with_the_room_it_has(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	var host := await _guest("Host")
	var made := await host.api.create_lobby()
	host.lobby = made["lobby"]
	var code: String = host.lobby["code"]
	var guests: Array[Guest] = []
	for guest_name in ["G1", "G2", "G3"]:
		var guest := await _guest(guest_name)
		var joined := await guest.api.join_code(code)
		assert_bool(joined["ok"]).is_true()
		guest.lobby = joined["lobby"]
		guests.append(guest)
	var late := await _guest("Late")
	var full := await late.api.preview(code)
	assert_bool(full["preview"]["full"]).is_true()
	assert_str(LobbyScreen.preview_text(full["preview"])).is_equal("That night is full (4 of 4).")
	var refused := await late.api.join_code(code)
	assert_bool(refused["ok"]).is_false()
	assert_str(refused["error"]).is_equal("full")
	assert_str(refused["text"]).is_equal("That night is full (4 of 4).")
	# A seat that frees up is taken.
	await guests[2].api.leave(guests[2].lobby)
	assert_bool((await late.api.join_code(code))["ok"]).is_true()


func test_the_host_who_leaves_before_the_start_hands_the_role_to_the_next_seat(
	_do_skip := _why_not() != "", _skip_reason := "needs node 24 and npm ci in spikes/backend"
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	ann.lobby = (await ann.api.create_lobby())["lobby"]
	bo.lobby = (await bo.api.join_code(ann.lobby["code"]))["lobby"]
	_watch(bo)
	assert_bool((await ann.api.leave(ann.lobby))["ok"]).is_true()
	await bo.watch.poll()
	assert_str(bo.watch.lobby["hostId"]).is_equal(bo.api.my_id())
	assert_array(_names(bo)).is_equal(["Bo"])
	var kinds := bo.heard.map(func(e: Dictionary) -> String: return e["kind"])
	assert_array(kinds).is_equal(["left", "host"])
	assert_str(LobbyScreen.event_text(bo.heard[1])).is_equal("You are the host now.")
	# Bo can start it, and Ann is not a member any more.
	assert_str((await ann.api.refresh(ann.lobby))["error"]).is_equal("not_member")
	assert_bool((await bo.api.start(bo.lobby))["ok"]).is_true()
