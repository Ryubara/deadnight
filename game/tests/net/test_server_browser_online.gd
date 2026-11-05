# The Server Browser's data and the cap of 8 PEOPLE (Deadnight #1179), over the real stack: the real
# backend (`spikes/backend`, run by Node on a free port), a real `GameServer` that heartbeats to it,
# and players who sign in, list the nights, join by a row's code and enter the night with the ticket
# they are given (`TogetherApi`, `Night.start_remote`). What each case reads back is the running
# night (the room's own players and bots, what every client holds) and what the backend lists.
#
# It needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without them the
# suite is skipped with a line saying so.
extends GdUnitTestSuite

const SERVER_ID := "gs-server-browser"
const SKIP := "needs node 24 and npm ci in spikes/backend"
const SETTLE_SECONDS := 30.0

var _backend := BackendFixture.new()
var _server: GameServer
var _nights: Array[Night] = []


func before_test() -> void:
	if BackendFixture.why_not() != "":
		return
	var up := await _backend.start(self)
	assert_bool(up).is_true()
	var server_port := _free_port()
	_server = GameServer.new()
	_server.port = server_port
	_server.capacity = 4
	_server.server_id = SERVER_ID
	_server.public_url = "ws://127.0.0.1:%d" % server_port
	_server.backend_url = _backend.url
	_server.backend_secret = BackendFixture.GAME_SERVER_SECRET
	_server.heartbeat_every = 0.4
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(BackendFixture.TICKET_SECRET, SERVER_ID)
	_world().add_child(_server)
	var registered := await _until(
		func() -> bool:
			var ready := await HttpJson.send(self, "GET", _backend.url + "/ready")
			return ready["status"] == 200 and int(ready["json"].get("gameServers", 0)) >= 1,
		60.0
	)
	assert_bool(registered).is_true()


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	if is_instance_valid(_server):
		_server.get_parent().queue_free()
	_backend.stop()
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


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


func _until(condition: Callable, seconds: float = SETTLE_SECONDS) -> bool:
	var began := Time.get_ticks_msec()
	while not await condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().create_timer(0.05).timeout
	return true


func _guest(player_name: String) -> TogetherApi:
	var api := TogetherApi.new(self, _backend.url)
	api.isolated = true
	var signed := await api.sign_in(player_name)
	assert_bool(signed["ok"]).is_true()
	return api


## A night the host started with `bots` bots, and its row as the Server Browser lists it.
func _host_night(host: TogetherApi, bots: int) -> Dictionary:
	var made := await host.create_lobby()
	assert_bool(made["ok"]).is_true()
	var settings := MatchSettings.new()
	settings.bots = bots
	var ruled := await host.set_settings(made["lobby"], settings)
	assert_bool(ruled["ok"]).is_true()
	var started := await host.start(ruled["lobby"])
	assert_bool(started["ok"]).is_true()
	return started["lobby"]


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


## The row of the night with `code` in the list `api` reads, or {}.
func _row(api: TogetherApi, code: String) -> Dictionary:
	var listed := await api.list_nights()
	assert_bool(listed["ok"]).is_true()
	for row: Dictionary in listed["nights"]:
		if row["code"] == code:
			return row
	return {}


## Waits until `condition` holds for the row of `code` ({} when it is not listed), asking the list
## every 0.7 s: the backend answers a polled list at most 20 times in 10 seconds per account.
func _until_listed(code: String, api: TogetherApi, condition: Callable) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call(await _row(api, code)):
		if (Time.get_ticks_msec() - began) / 1000.0 > SETTLE_SECONDS:
			return false
		await get_tree().create_timer(0.7).timeout
	return true


func _room(lobby: Dictionary) -> NightHost:
	var room := _server.room_of_match(str(lobby["matchId"]))
	assert_object(room).is_not_null()
	return room


func test_eight_people_and_seven_bots_share_one_night_the_list_counts_people_only(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Host")
	var lobby := await _host_night(host, MatchSettings.MAX_BOTS)
	var looker := await _guest("Looker")
	# The row a Server Browser would draw: the map, people out of the cap, the bots the host set, and
	# that the night is on. The code in it is all the looker needs to join.
	var row := await _row(looker, str(lobby["code"]))
	assert_bool(row.is_empty()).is_false()
	assert_str(row["map"]).is_equal("drive_in")
	assert_str(row["hostName"]).is_equal("Host")
	assert_int(int(row["maxPlayers"])).is_equal(NightHost.MAX_PLAYERS)
	assert_int(int(row["bots"])).is_equal(MatchSettings.MAX_BOTS)
	assert_str(row["state"]).is_equal("started")
	var people: Array[TogetherApi] = [host, looker]
	var nights: Array[Night] = [await _enter(host, lobby)]
	# Seven more people, each joining by the code of the row.
	for i in range(1, NightHost.MAX_PLAYERS):
		if i > 1:
			people.append(await _guest("P%d" % i))
		var joined := await people[i].join_code(str(row["code"]))
		assert_bool(joined["ok"]).is_true()
		nights.append(await _enter(people[i], joined["lobby"]))
	var room := _room(lobby)
	# Eight people and seven bots, one night: no bot gave way, the room holds 15 bodies.
	assert_int(room.people_count()).is_equal(NightHost.MAX_PLAYERS)
	assert_int(room.bots.count()).is_equal(MatchSettings.MAX_BOTS)
	assert_int(room.server.rules.players.size()).is_equal(NightHost.MAX_SEATS)
	assert_array(room.bots.seats()).is_equal([101, 102, 103, 104, 105, 106, 107])
	for night in nights:
		var all := await _until(
			func() -> bool:
				return (night.state.frame["players"] as Dictionary).size() == NightHost.MAX_SEATS
		)
		assert_bool(all).is_true()
	# The game server's heartbeat tells the backend 8, not 15, and the row says full on people.
	var full := await _until_listed(
		str(lobby["code"]),
		looker,
		func(now: Dictionary) -> bool:
			return int(now.get("players", 0)) == NightHost.MAX_PLAYERS and now.get("full", false)
	)
	assert_bool(full).is_true()
	var seen := await _row(looker, str(lobby["code"]))
	assert_int(int(seen["players"])).is_equal(NightHost.MAX_PLAYERS)
	assert_int(int(seen["bots"])).is_equal(MatchSettings.MAX_BOTS)
	# The ninth person is turned away by the backend: the night is full on people alone.
	var ninth := await _guest("Ninth")
	var refused := await ninth.join_code(str(row["code"]))
	assert_bool(refused["ok"]).is_false()
	assert_str(refused["error"]).is_equal("full")
	# One person leaves the night: the count falls to 7 and the ninth is let in.
	nights[1].link.close()
	var room_left := await _until_listed(
		str(lobby["code"]),
		looker,
		func(now: Dictionary) -> bool:
			return int(now.get("players", 0)) == NightHost.MAX_PLAYERS - 1 and not now["full"]
	)
	assert_bool(room_left).is_true()
	assert_int(room.bots.count()).is_equal(MatchSettings.MAX_BOTS)
	var late := await ninth.join_code(str(row["code"]))
	assert_bool(late["ok"]).is_true()
	await _enter(ninth, late["lobby"])
	assert_int(room.people_count()).is_equal(NightHost.MAX_PLAYERS)
	assert_int(room.bots.count()).is_equal(MatchSettings.MAX_BOTS)


func test_a_private_night_is_not_listed_and_its_code_still_joins(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Host")
	var lobby := await _host_night(host, 2)
	var looker := await _guest("Looker")
	assert_bool((await _row(looker, str(lobby["code"]))).is_empty()).is_false()
	var hidden := await host.set_visibility(lobby, false)
	assert_bool(hidden["ok"]).is_true()
	assert_str(hidden["lobby"]["visibility"]).is_equal("private")
	assert_bool((await _row(looker, str(lobby["code"]))).is_empty()).is_true()
	# Only the host moves it.
	var refused := await looker.set_visibility(lobby, true)
	assert_bool(refused["ok"]).is_false()
	# A friend with the code is let in, and gets a ticket.
	var friend := await looker.join_code(str(lobby["code"]))
	assert_bool(friend["ok"]).is_true()
	assert_bool((await looker.ticket(friend["lobby"]))["ok"]).is_true()
	var shown := await host.set_visibility(lobby, true)
	assert_bool(shown["ok"]).is_true()
	assert_bool((await _row(looker, str(lobby["code"]))).is_empty()).is_false()


func test_a_night_the_last_person_left_is_gone_from_the_list_with_its_bots_standing(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Host")
	var lobby := await _host_night(host, 3)
	var looker := await _guest("Looker")
	var night := await _enter(host, lobby)
	var room := _room(lobby)
	assert_int(room.bots.count()).is_equal(3)
	assert_bool((await _row(looker, str(lobby["code"]))).is_empty()).is_false()
	# The only person leaves: the room ends (bots are no one to keep it for) and the backend drops
	# the night from the list on the game server's word.
	night.link.close()
	var gone := await _until_listed(
		str(lobby["code"]), looker, func(now: Dictionary) -> bool: return now.is_empty()
	)
	assert_bool(gone).is_true()
	assert_object(_server.room_of_match(str(lobby["matchId"]))).is_null()


func test_the_list_shows_a_waiting_lobby_and_a_match_in_progress_and_a_row_joins_the_match(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	# A match in progress: started, entered, past its first break, so a round is running.
	var host := await _guest("Host")
	var match_lobby := await _host_night(host, 2)
	var host_night := await _enter(host, match_lobby)
	var room := _room(match_lobby)
	room.server.rules.apply(RulesAction.skip_break())
	var nights_built := room.nights
	var round_before := room.round_number()
	assert_int(round_before).is_greater(0)
	# A lobby that still waits for its host.
	var waiting_host := await _guest("Waiting")
	var made := await waiting_host.create_lobby()
	assert_bool(made["ok"]).is_true()
	var looker := await _guest("Looker")
	# Both are rows, and each says which it is: the match with its round, the lobby waiting.
	var seen := await _until_listed(
		str(match_lobby["code"]),
		looker,
		func(row: Dictionary) -> bool: return int(row.get("round", 0)) == round_before
	)
	assert_bool(seen).is_true()
	var match_row := await _row(looker, str(match_lobby["code"]))
	assert_str(match_row["kind"]).is_equal("match")
	assert_str(match_row["state"]).is_equal("started")
	assert_int(int(match_row["players"])).is_equal(1)
	var lobby_row := await _row(looker, str(made["lobby"]["code"]))
	assert_str(lobby_row["kind"]).is_equal("lobby")
	assert_str(lobby_row["state"]).is_equal("open")
	assert_bool(lobby_row["round"] == null).is_true()
	# One press on the match's row: the looker is in that night, mid-round, in a body of their own.
	var joined := await looker.join_code(str(match_row["code"]))
	assert_bool(joined["ok"]).is_true()
	var guest_night := await _enter(looker, joined["lobby"])
	assert_int(guest_night.state.player_id).is_equal(2)
	assert_int(room.nights).is_equal(nights_built)
	assert_int(room.round_number()).is_greater_equal(round_before)
	assert_int(room.people_count()).is_equal(2)
	assert_int(room.bots.count()).is_equal(2)
	var host_sees := await _until(
		func() -> bool: return (host_night.state.frame["players"] as Dictionary).has(2)
	)
	(
		assert_bool(host_sees)
		. override_failure_message("the first player never saw the newcomer")
		. is_true()
	)
	assert_int(guest_night.state.round_number()).is_equal(room.round_number())
