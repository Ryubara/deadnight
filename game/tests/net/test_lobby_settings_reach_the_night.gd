# gdlint:disable=max-public-methods
# Every setting the host's lobby offers reaches the night that starts from it (Deadnight #944): the
# map, the intensity, the most alive, the break, the bots and their skill. The host is the real
# `LobbyScreen` with its real `MatchSettingsPanel` asking through a real `TogetherApi`; the backend
# is the real one (`spikes/backend`, run by Node on a free port); the game server is a real
# `GameServer` that heartbeats to it; and the players enter the night the screen hands them
# (`NightScreen.join_*`) with `Night.start_remote`. What each case reads back is the RUNNING night:
# the room's own rules, the lot it built, the bots it seated and the lot the client built from
# the WELCOME.
#
# Each setting has two cases: the host moves it after the lobby is open and waits for it to be sent
# (the guest's poll reads it from the backend before the start), and the host moves it and presses
# Start at once (the change still waiting goes with the start). A third case starts the lobby with
# no rules in the body, so the night has what the backend kept from the changes sent while waiting.
# A test fails when `MatchSettings` has a setting with no case here, so a setting added later is
# proved to reach the night before it ships.
#
# It needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without them the
# suite is skipped with a line saying so.
extends GdUnitTestSuite

const BACKEND_DIR := "res://../spikes/backend"
const SERVER_ID := "gs-lobby-settings"
const SESSION_SECRET := "session-secret-of-at-least-32-characters-a"
const TICKET_SECRET := "ticket-secret-of-at-least-32-characters-b"
const GAME_SERVER_SECRET := "server-secret-of-at-least-32-characters-c"
const SECOND_MAP := "small_indoor"
const SKIP := "needs node 24 and npm ci in spikes/backend"

var _pid := 0
var _backend := ""
var _server: GameServer
var _nights: Array[Night] = []
var _screens: Array[LobbyScreen] = []


func before_test() -> void:
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	NightScreen.join_map = ""
	await _start_stack()


func after_test() -> void:
	LobbyScreen.opener = Callable()
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	NightScreen.join_map = ""
	for screen in _screens:
		if is_instance_valid(screen):
			screen.free()
	_screens.clear()
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


# --- The players ---


func _guest(player_name: String, level_10 := false) -> TogetherApi:
	var api := TogetherApi.new(self, _backend)
	api.isolated = true
	var signed := await api.sign_in(player_name)
	assert_bool(signed["ok"]).is_true()
	if level_10:
		await _reach_level_10(api)
	return api


## The backend pays the signed-in account the XP of level 10, as a game server's report does (the
## back rooms open to a host from that level; the backend refuses the map to a lower one, #1098).
func _reach_level_10(api: TogetherApi) -> void:
	var sent := await HttpJson.send(
		self,
		"POST",
		"%s/internal/matches/seed-level-10/report" % _backend,
		{"Authorization": "Bearer " + GAME_SERVER_SECRET},
		{"kind": "night", "round": 0, "seats": [{"userId": api.my_id(), "xp": 1000}]}
	)
	assert_int(sent["status"]).is_equal(200)


## The host's real lobby screen over a lobby the real backend made.
func _host_screen(api: TogetherApi) -> LobbyScreen:
	var made := await api.create_lobby()
	assert_bool(made["ok"]).is_true()
	await RouterFixture.clear(get_tree())
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"api": api, "lobby": made["lobby"]}
	add_child(screen)
	_screens.append(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	assert_bool(screen.rules_editable()).is_true()
	# A new lobby is the usual night.
	assert_bool(screen.rules.settings().same_as(MatchSettings.new())).is_true()
	return screen


## A guest who joined the host's lobby and reads it on each poll, as its screen does.
func _guest_in(screen: LobbyScreen) -> Dictionary:
	var api := await _guest("Bo")
	var joined := await api.join_code(str(screen.lobby["code"]))
	assert_bool(joined["ok"]).is_true()
	return {"api": api, "lobby": joined["lobby"]}


## What the guest's poll says the host chose.
func _guest_reads(guest: Dictionary) -> MatchSettings:
	var seen := await (guest["api"] as TogetherApi).refresh(guest["lobby"])
	assert_bool(seen["ok"]).is_true()
	guest["lobby"] = seen["lobby"]
	return MatchSettings.from_json(seen["lobby"].get("settings"))


## The host presses Start on the screen and the night opens as the lobby screen opens it: the ticket
## and the lot go to `NightScreen`, and the player joins the room the way that screen does.
func _start_on_screen(screen: LobbyScreen) -> Night:
	var opened := [false]
	LobbyScreen.opener = func() -> void: opened[0] = true
	await screen.start()
	assert_bool(opened[0]).is_true()
	return await _enter_with_screen_hand_off()


func _enter_with_screen_hand_off() -> Night:
	var night := Night.new()
	night.map_id = NightScreen.join_map
	var link := WebSocketLink.new()
	link.ticket = NightScreen.join_ticket
	var url := NightScreen.join_url
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	NightScreen.join_map = ""
	_world().add_child(night)
	var joined := await night.start_remote(url, Night.Mode.MANUAL, 60.0, link)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


## A player enters the started lobby with the ticket the backend gives.
func _enter(api: TogetherApi, lobby: Dictionary) -> Night:
	var pass_to := await api.ticket(lobby)
	assert_bool(pass_to["ok"]).is_true()
	var night := Night.new()
	night.map_id = MapRegistry.of_lobby(lobby).id
	var link := WebSocketLink.new()
	link.ticket = pass_to["ticket"]
	_world().add_child(night)
	var joined := await night.start_remote(pass_to["url"], Night.Mode.MANUAL, 60.0, link)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


# --- What the running night says ---


## The room the server built for the lobby's match.
func _room(lobby: Dictionary) -> NightHost:
	var room := _server.room_of_match(str(lobby["matchId"]))
	assert_object(room).is_not_null()
	return room


## Every setting as the running night shows it, key by key: from the room's rules, the lot the room
## built, the bots it seated and the profile they play, never from the settings that were sent.
func _observed(room: NightHost) -> Dictionary:
	var rules := room.server.rules
	var skills := {}
	for bot in room.bots.host.bots:
		skills[bot.profile.title] = true
	var out := {
		"map": room.world.map_info.id,
		"count_multiplier": rules.settings.scaled_count(8) / 8.0,
		"max_alive": rules.settings.alive_cap(rules.tuning.rounds, 1, 1),
		"break_seconds": rules.settings.break_for(rules.tuning.rounds),
		"bots": room.bots.count(),
		"bot_skill": -1,
		"perk_limit":
		(
			MatchSettings.PERKS_UNLIMITED
			if rules.settings.tonic_limit(rules.tuning.economy) == MatchSettings.UNLIMITED_PERKS
			else MatchSettings.PERKS_DEFAULT
		),
	}
	for skill in [
		MatchSettings.SKILL_ROOKIE, MatchSettings.SKILL_REGULAR, MatchSettings.SKILL_VETERAN
	]:
		if skills.size() == 1 and skills.has(BotProfile.for_skill(skill).title):
			out["bot_skill"] = skill
	return out


## What `_observed` must read for `wanted`.
func _expected(room: NightHost, wanted: MatchSettings) -> Dictionary:
	var rules := room.server.rules
	var cap := wanted.alive_cap(rules.tuning.rounds, 1, 1)
	return {
		"map": wanted.map,
		"count_multiplier": roundi(8.0 * wanted.count_multiplier) / 8.0,
		"max_alive": cap,
		"break_seconds": wanted.break_for(rules.tuning.rounds),
		"bots": wanted.bots,
		"bot_skill": wanted.bot_skill if wanted.bots > 0 else -1,
		"perk_limit": wanted.perk_limit,
	}


## Fails on the first setting the night does not hold, naming it.
func _check_night(room: NightHost, client: Night, wanted: MatchSettings) -> void:
	(
		assert_bool(await _until(func() -> bool: return room.bots.count() == wanted.bots, 20.0))
		. is_true()
	)
	var seen := _observed(room)
	var expected := _expected(room, wanted)
	for key: String in MatchSettings.KEYS:
		(
			assert_that(seen[key])
			. override_failure_message(
				"the night's %s is %s, the host chose %s" % [key, seen[key], expected[key]]
			)
			. is_equal(expected[key])
		)
	# The rules the room runs are the host's, whole.
	assert_dict(room.server.rules.settings.to_dict()).is_equal(wanted.to_dict())
	# The client that joined has the same rules and built the same lot from the WELCOME.
	assert_dict(client.match_settings.to_dict()).is_equal(wanted.to_dict())
	assert_str(client.world.map_info.id).is_equal(wanted.map)
	if wanted.bots > 0:
		assert_int(client.state.names.size()).is_greater_equal(wanted.bots)


# --- The cases: one panel control each ---


## The non-default value of each setting and the control of the panel that moves it, by the
## setting's key. `bot_skill` has no one to play it without bots, so its case asks for two.
func _move(panel: MatchSettingsPanel, key: String) -> MatchSettings:
	match key:
		"map":
			panel.map_picker.card_for(SECOND_MAP).pressed.emit()
		"count_multiplier":
			panel.count_selector.select(2, true)
		"max_alive":
			panel.alive_slider.value = 12
		"break_seconds":
			panel.break_slider.value = 11
		"bots":
			panel.bots_selector.select(3, true)
		"bot_skill":
			panel.bots_selector.select(2, true)
			panel.skill_selector.select(MatchSettings.SKILL_VETERAN, true)
		"perk_limit":
			panel.perk_selector.select(MatchSettings.PERKS_UNLIMITED, true)
		_:
			fail("the setting '%s' has no control in this test: add its case" % key)
	return panel.settings()


func _moved_and_sent_then_started(key: String) -> void:
	var host := await _guest("Ann", true)
	var screen := await _host_screen(host)
	var guest := await _guest_in(screen)
	var wanted := _move(screen.rules, key)
	(
		assert_bool(wanted.same_as(MatchSettings.new()))
		. override_failure_message("moving '%s' on the panel changed nothing" % key)
		. is_false()
	)
	# The host stops moving; the change goes to the backend and the guest reads it before the start.
	await screen.send_rules()
	var read := await _guest_reads(guest)
	(
		assert_object(read)
		. override_failure_message(
			"the guest read no rules for '%s' after the host sent them" % key
		)
		. is_not_null()
	)
	assert_dict(read.to_dict()).is_equal(wanted.to_dict())
	var client := await _start_on_screen(screen)
	var started := (
		(await (guest["api"] as TogetherApi).refresh(guest["lobby"]))["lobby"] as Dictionary
	)
	var room := _room(started)
	await _check_night(room, client, wanted)
	# The guest enters the same night with the same rules.
	var other := await _enter(guest["api"], started)
	assert_dict(other.match_settings.to_dict()).is_equal(wanted.to_dict())
	assert_str(other.world.map_info.id).is_equal(wanted.map)


func _moved_and_started_at_once(key: String) -> void:
	var host := await _guest("Ann", true)
	var screen := await _host_screen(host)
	var wanted := _move(screen.rules, key)
	# Nothing was sent yet: the change is still waiting when Start is pressed.
	var client := await _start_on_screen(screen)
	var room := _room(screen.lobby)
	await _check_night(room, client, wanted)


# --- One case per setting, each both ways ---


func test_the_map_the_host_picks_after_the_lobby_is_open_is_the_map_of_the_night(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_sent_then_started("map")


func test_the_map_the_host_picks_as_they_press_start_is_the_map_of_the_night(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_started_at_once("map")


func test_the_intensity_the_host_sets_after_the_lobby_is_open_is_the_nights(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_sent_then_started("count_multiplier")


func test_the_intensity_the_host_sets_as_they_press_start_is_the_nights(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_started_at_once("count_multiplier")


func test_the_alive_cap_the_host_sets_after_the_lobby_is_open_is_the_nights(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_sent_then_started("max_alive")


func test_the_alive_cap_the_host_sets_as_they_press_start_is_the_nights(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_started_at_once("max_alive")


func test_the_break_the_host_sets_after_the_lobby_is_open_is_the_nights(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_sent_then_started("break_seconds")


func test_the_break_the_host_sets_as_they_press_start_is_the_nights(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_started_at_once("break_seconds")


func test_the_bots_the_host_adds_after_the_lobby_is_open_sit_in_the_night(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_sent_then_started("bots")


func test_the_bots_the_host_adds_as_they_press_start_sit_in_the_night(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_started_at_once("bots")


func test_the_skill_the_host_picks_after_the_lobby_is_open_is_the_bots_in_the_night(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_sent_then_started("bot_skill")


func test_the_skill_the_host_picks_as_they_press_start_is_the_bots_in_the_night(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_started_at_once("bot_skill")


func test_the_perk_limit_the_host_picks_after_the_lobby_is_open_is_the_nights(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_sent_then_started("perk_limit")


func test_the_perk_limit_the_host_picks_as_they_press_start_is_the_nights(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	await _moved_and_started_at_once("perk_limit")


# --- The rest of the path ---


func test_every_setting_the_host_moves_together_and_changes_again_ends_as_the_last_change(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Ann", true)
	var screen := await _host_screen(host)
	# A first choice, sent; then a second one over it, sent; the night has the second.
	screen.rules.map_picker.card_for(SECOND_MAP).pressed.emit()
	screen.rules.bots_selector.select(5, true)
	screen.rules.count_selector.select(1, true)
	await screen.send_rules()
	screen.rules.map_picker.card_for(MapRegistry.DEFAULT).pressed.emit()
	screen.rules.bots_selector.select(2, true)
	screen.rules.skill_selector.select(MatchSettings.SKILL_ROOKIE, true)
	screen.rules.count_selector.select(2, true)
	screen.rules.alive_slider.value = 9
	screen.rules.break_slider.value = 7
	await screen.send_rules()
	var wanted := screen.rules.settings()
	var client := await _start_on_screen(screen)
	await _check_night(_room(screen.lobby), client, wanted)


func test_a_start_with_no_rules_in_it_keeps_what_the_host_sent_while_waiting(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Ann", true)
	var screen := await _host_screen(host)
	var wanted := MatchSettings.new()
	wanted.map = SECOND_MAP
	wanted.count_multiplier = 3.0
	wanted.max_alive = 12
	wanted.break_seconds = 11.0
	wanted.bots = 3
	wanted.bot_skill = MatchSettings.SKILL_ROOKIE
	wanted.perk_limit = MatchSettings.PERKS_UNLIMITED
	var changed := await host.set_settings(screen.lobby, wanted)
	assert_bool(changed["ok"]).is_true()
	var started := await host.start(screen.lobby)
	assert_bool(started["ok"]).is_true()
	var client := await _enter(host, started["lobby"])
	await _check_night(_room(started["lobby"]), client, wanted)


func test_every_setting_has_a_case_in_this_suite() -> void:
	var cased := [
		"map", "count_multiplier", "max_alive", "break_seconds", "bots", "bot_skill", "perk_limit"
	]
	for key: String in MatchSettings.KEYS:
		(
			assert_bool(cased.has(key))
			. override_failure_message(
				"MatchSettings has '%s' and the lobby suite has no case for it" % key
			)
			. is_true()
		)
	for key: String in cased:
		assert_bool(MatchSettings.KEYS.has(key)).is_true()
	# Each has a row on the panel the host moves.
	assert_array(auto_free(MatchSettingsPanel.new()).missing_keys()).is_empty()


func test_the_backend_takes_exactly_the_settings_the_game_has(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	# A key the game sends that the backend lacks is refused (or, in a backend from before it,
	# lost); a key the backend takes that the game lacks is a setting nobody can set. Both ways.
	var health := await HttpJson.send(self, "GET", _backend + "/health")
	assert_int(health["status"]).is_equal(200)
	var taken: Array = health["json"]["settingsKeys"]
	taken.sort()
	var ours: Array = MatchSettings.KEYS.keys()
	ours.sort()
	assert_array(taken).is_equal(ours)


func test_a_setting_the_backend_does_not_know_is_an_error_the_host_reads(
	_do_skip := _why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Ann", true)
	var made := await host.create_lobby()
	var asked := MatchSettings.new().to_dict()
	asked["a_modifier"] = true
	var answer := await host._call("PUT", "/lobbies/%s/settings" % made["lobby"]["id"], asked)
	assert_bool(answer["ok"]).is_false()
	assert_str(answer["error"]).is_equal("bad_settings")
	assert_str(answer["text"]).contains("unknown setting a_modifier")


func test_a_backend_with_no_route_for_the_rules_is_told_to_the_host_as_out_of_date() -> void:
	# The framework's own 404 of a backend from before the rules (a lobby that is gone says
	# `not_found`): the host is not told to try again.
	var old := TogetherApi.rules_answer({"ok": false, "error": "Not Found", "text": "x"})
	assert_str(old["error"]).is_equal("rules_unsupported")
	assert_str(old["text"]).contains("out of date")
	var gone := TogetherApi.rules_answer({"ok": false, "error": "not_found", "text": "gone"})
	assert_str(gone["error"]).is_equal("not_found")
	assert_bool(TogetherApi.rules_answer({"ok": true, "id": "l"})["ok"]).is_true()
