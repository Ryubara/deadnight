# One game-server process, several nights: a `GameServer` over a real WebSocket on this machine
# gives each match of the backend's tickets a night of its own (own physics, own players, own
# zombies), refuses tickets that are forged, used, expired or another server's, frees a night
# when its players are gone, and takes a returning player back by token or by user.
extends GdUnitTestSuite

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"

var _server: GameServer
var _nights: Array[Night] = []
var _raw: Array[WebSocketPeer] = []
var _commands: Dictionary = {}


func after_test() -> void:
	for ws in _raw:
		ws.close()
	_raw.clear()
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_commands.clear()
	if is_instance_valid(_server):
		_server.get_parent().queue_free()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _start(capacity: int = 4) -> GameServer:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = capacity
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())
	return _server


func _url() -> String:
	return "ws://127.0.0.1:%d" % _server.listener.port()


func _ticket(match_id: String, user: String, name := "Tester", settings := {}) -> String:
	return TicketMaker.make(SECRET, SERVER_ID, match_id, user, name, 60, settings)


## A hand-driven client with a ticket (MANUAL): it sends `_commands[night]` every tick.
func _client(match_id: String, user: String, name := "Tester", settings := {}) -> Night:
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = _ticket(match_id, user, name, settings)
	var joined := await night.start_remote(_url(), Night.Mode.MANUAL, 60.0, link)
	assert_bool(joined).is_true()
	_nights.append(night)
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void:
			var command: NightCommand = _commands[night]
			command.seq += 1
			night.link.send(command.to_dict())
	)
	return night


## A bare socket that says hello with `ticket`; its first answer (WELCOME or REFUSED) as a packet.
func _hello(ticket: String, token := PackedByteArray()) -> Dictionary:
	var ws := WebSocketPeer.new()
	ws.connect_to_url(_url())
	_raw.append(ws)
	var got := {"packet": PackedByteArray(), "sent": false}
	await _until(
		func() -> bool:
			ws.poll()
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not got["sent"]:
				got["sent"] = true
				ws.send(NetWire.hello(token, ticket), WebSocketPeer.WRITE_MODE_BINARY)
			while ws.get_available_packet_count() > 0:
				var packet := ws.get_packet()
				if packet[0] == NetWire.Type.WELCOME or packet[0] == NetWire.Type.REFUSED:
					got["packet"] = packet
			return not (got["packet"] as PackedByteArray).is_empty()
	)
	return got


func test_two_matches_are_two_nights_that_know_nothing_of_each_other() -> void:
	await _start()
	var ann := await _client("match-a", "ann")
	var bo := await _client("match-a", "bo")
	var cy := await _client("match-b", "cy")
	# Everyone is player 1 or 2 of their own night.
	assert_int(ann.state.player_id).is_equal(1)
	assert_int(bo.state.player_id).is_equal(2)
	assert_int(cy.state.player_id).is_equal(1)
	assert_array(_server.match_ids()).contains_exactly_in_any_order(["match-a", "match-b"])
	assert_int(_server.room_of_match("match-a").player_count()).is_equal(2)
	assert_int(_server.room_of_match("match-b").player_count()).is_equal(1)
	(
		assert_bool(await _until(func() -> bool: return ann.state.frame.get("players", {}).has(2)))
		. is_true()
	)
	# Each night has its own world and its own server.
	(
		assert_bool(
			_server.room_of_match("match-a").server != _server.room_of_match("match-b").server
		)
		. is_true()
	)
	(
		assert_bool(
			_server.room_of_match("match-a").world != _server.room_of_match("match-b").world
		)
		. is_true()
	)
	# Cy walks in night B; nothing of it reaches night A.
	var cy_start: Vector3 = cy.state.frame["players"][1]["pos"]
	var ann_start: Vector3 = ann.state.frame["players"][1]["pos"]
	(_commands[cy] as NightCommand).motion.move = Vector2(0.0, -1.0)
	for _i in 90:
		await get_tree().physics_frame
	assert_float((cy.state.frame["players"][1]["pos"] as Vector3).distance_to(cy_start)).is_greater(
		2.0
	)
	assert_float((ann.state.frame["players"][1]["pos"] as Vector3).distance_to(ann_start)).is_less(
		0.5
	)
	assert_bool((cy.state.frame["players"] as Dictionary).has(2)).is_false()
	assert_bool((ann.state.frame["players"] as Dictionary).has(2)).is_true()


func test_rooms_put_their_crowds_steps_on_alternate_ticks() -> void:
	await _start()
	for index in 4:
		await _client("match-%d" % index, "user-%d" % index)
	var rooms: Array[NightHost] = []
	var lures: Array[ZombieLure] = []
	var parities := [0, 0]
	for match_id in _server.match_ids():
		var room := _server.room_of_match(match_id)
		rooms.append(room)
		parities[room.heavy_parity] += 1
		# A lure counts down by one step each time the room's zombies step, nothing else.
		var lure := ZombieLure.new(1, Vector3.ZERO, 1.0, 1000.0)
		room.server.sim.lures.append(lure)
		lures.append(lure)
	assert_array(parities).is_equal([2, 2])
	await get_tree().physics_frame
	var before: Array[float] = []
	for lure in lures:
		before.append(lure.left)
	var stepping: Array[int] = []
	for _frame in 20:
		await get_tree().physics_frame
		var count := 0
		for index in lures.size():
			if lures[index].left < before[index]:
				count += 1
			before[index] = lures[index].left
		stepping.append(count)
	# Two of the four rooms step their zombies in every frame, never all four or none.
	assert_array(stepping).is_equal([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2])


func test_rooms_share_the_processes_alive_budget() -> void:
	await _start()
	_server.alive_budget = 100
	await _client("match-a", "ann")
	var first := _server.room_of_match("match-a")
	# A lone room of a desktop client stands the budget (its own ceiling is 120).
	(
		assert_bool(await _until(func() -> bool: return first.server.rules.crowd_ceiling == 100))
		. is_true()
	)
	await _client("match-b", "bo")
	var second := _server.room_of_match("match-b")
	for room in [first, second]:
		(
			assert_bool(
				await _until(
					func() -> bool: return (room as NightHost).server.rules.crowd_ceiling == 50
				)
			)
			. is_true()
		)
		assert_int((room as NightHost).server.sim.tuning.hard_cap).is_equal(50)
	# The operator's cap still holds when it is the smaller.
	first.max_alive = 30
	first.set_alive_share(first.alive_share)
	assert_int(first.server.rules.crowd_ceiling).is_equal(30)
	# A room freed gives its share back.
	_server._end_room("match-a")
	(
		assert_bool(await _until(func() -> bool: return second.server.rules.crowd_ceiling == 100))
		. is_true()
	)


func test_the_server_takes_three_rooms_and_a_budget_of_120_unless_told() -> void:
	var config := ServerConfig.from_environment(func(_key: String) -> String: return "")
	assert_int(config.capacity).is_equal(3)
	assert_int(config.alive_budget).is_equal(120)
	var env := {"ALIVE_BUDGET": "90"}
	var set_up := ServerConfig.from_environment(
		func(key: String) -> String: return env.get(key, "")
	)
	assert_int(set_up.alive_budget).is_equal(90)
	env["ALIVE_BUDGET"] = "0"
	var off := ServerConfig.from_environment(func(key: String) -> String: return env.get(key, ""))
	assert_int(off.alive_budget).is_equal(0)
	env["ALIVE_BUDGET"] = "lots"
	var junk := ServerConfig.from_environment(func(key: String) -> String: return env.get(key, ""))
	assert_int(junk.alive_budget).is_equal(120)


func test_a_ticket_that_is_not_good_is_turned_away() -> void:
	await _start()
	var good := _ticket("m", "ann")
	var forged := TicketMaker.make("another-secret-of-at-least-32-chars!!", SERVER_ID, "m", "x")
	var elsewhere := TicketMaker.make(SECRET, "gs-other", "m", "x")
	var expired := TicketMaker.make(SECRET, SERVER_ID, "m", "x", "x", -5)
	for ticket in [forged, elsewhere, expired, "", "not a ticket", good.left(40)]:
		var answer := await _hello(ticket)
		var packet: PackedByteArray = answer["packet"]
		assert_int(packet[0]).is_equal(NetWire.Type.REFUSED)
		assert_int(packet[1]).is_equal(NetWire.Refusal.DENIED)
	assert_array(_server.match_ids()).is_empty()
	# The good one is admitted once and refused the second time.
	var first := await _hello(good)
	assert_int((first["packet"] as PackedByteArray)[0]).is_equal(NetWire.Type.WELCOME)
	var again := await _hello(good)
	assert_int((again["packet"] as PackedByteArray)[0]).is_equal(NetWire.Type.REFUSED)


func test_the_rules_the_host_chose_ride_the_ticket_into_the_room_and_every_welcome() -> void:
	await _start()
	var chosen := {"count_multiplier": 3.0, "max_alive": 9, "break_seconds": 11.0}
	# The first ticket of the match opens the room with the host's rules; the JSON the backend signs
	# gives numbers as floats, and a whole one still fits `max_alive`.
	var ann := await _client("rules-a", "ann", "Tester", chosen)
	var room := _server.room_of_match("rules-a")
	# A ticket from before the bot count (no `bots`) asks for none.
	var held := chosen.merged({"bots": 0, "bot_skill": MatchSettings.DEFAULT_SKILL})
	assert_dict(room.server.rules.settings.to_dict()).is_equal(held)
	assert_dict(ann.match_settings.to_dict()).is_equal(held)
	# A friend's ticket carries the same rules (and even one without them changes nothing): the
	# WELCOME reads what the room has.
	var bo := await _client("rules-a", "bo")
	assert_dict(bo.match_settings.to_dict()).is_equal(held)
	# Another match on the same server has its own rules: none chosen is today's game.
	var cy := await _client("rules-b", "cy")
	assert_bool(cy.match_settings.is_default()).is_true()
	assert_bool(_server.room_of_match("rules-b").server.rules.settings.is_default()).is_true()


func test_a_ticket_with_rules_out_of_bounds_is_turned_away_and_no_room_opens() -> void:
	await _start()
	for settings in [
		{"count_multiplier": 9.0, "max_alive": 9, "break_seconds": 11.0},
		{"count_multiplier": 2.0, "max_alive": 9},
		{"count_multiplier": 2.0, "max_alive": 3.5, "break_seconds": 0.0},
	]:
		var answer := await _hello(_ticket("bad-rules", "ann", "Ann", settings))
		var packet: PackedByteArray = answer["packet"]
		assert_int(packet[0]).is_equal(NetWire.Type.REFUSED)
		assert_int(packet[1]).is_equal(NetWire.Refusal.DENIED)
	assert_array(_server.match_ids()).is_empty()


func test_every_client_shows_the_same_names_and_a_duplicate_gets_a_number() -> void:
	await _start()
	var ann := await _client("names-a", "u1", "Ann")
	var bo := await _client("names-a", "u2", "ann")
	# The ticket's name is the seat's; the second Ann is told apart from the first.
	var expected := {1: "Ann", 2: "ann (2)"}
	assert_dict(_server.room_of_match("names-a")._names).is_equal(expected)
	assert_bool(await _until(func() -> bool: return ann.state.names == expected)).is_true()
	assert_dict(bo.state.names).is_equal(expected)
	# A late joiner gets everyone's name in its WELCOME, and the others hear its own.
	var cy := await _client("names-a", "u3", "Cy")
	var everyone := {1: "Ann", 2: "ann (2)", 3: "Cy"}
	assert_dict(cy.state.names).is_equal(everyone)
	assert_bool(await _until(func() -> bool: return ann.state.names == everyone)).is_true()
	assert_bool(await _until(func() -> bool: return bo.state.names == everyone)).is_true()
	# Another night does not know them.
	var dee := await _client("names-b", "u4", "Ann")
	assert_dict(dee.state.names).is_equal({1: "Ann"})


func test_a_server_with_no_room_left_turns_a_new_match_away() -> void:
	await _start(1)
	var first := await _client("m1", "ann")
	assert_object(first).is_not_null()
	var answer := await _hello(_ticket("m2", "bo"))
	var packet: PackedByteArray = answer["packet"]
	assert_int(packet[0]).is_equal(NetWire.Type.REFUSED)
	assert_int(packet[1]).is_equal(NetWire.Refusal.FULL)
	# But a second player of the first match still gets in.
	var second := await _hello(_ticket("m1", "bo"))
	assert_int((second["packet"] as PackedByteArray)[0]).is_equal(NetWire.Type.WELCOME)


func test_a_night_is_freed_when_its_players_have_left() -> void:
	await _start()
	var ann := await _client("gone", "ann")
	assert_array(_server.match_ids()).is_equal(["gone"])
	var closed := {"match": ""}
	_server.room_closed.connect(func(id: String) -> void: closed["match"] = id)
	ann.link.close()
	assert_bool(await _until(func() -> bool: return closed["match"] == "gone")).is_true()
	assert_array(_server.match_ids()).is_empty()
	# The same match can be opened again (a new night) and the room count is back.
	var again := await _client("gone", "bo")
	assert_int(again.state.player_id).is_equal(1)


func test_a_player_with_a_new_ticket_takes_their_own_seat_back() -> void:
	await _start()
	var first := await _client("m", "ann")
	var body := _server.room_of_match("m").server.body_of(1)
	# The same user opens the night again (another tab, a reload): one seat, the old socket is cut.
	var second := await _client("m", "ann")
	assert_int(second.state.player_id).is_equal(1)
	assert_int(_server.room_of_match("m").player_count()).is_equal(1)
	assert_bool(_server.room_of_match("m").server.body_of(1) == body).is_true()
	assert_bool(await _until(func() -> bool: return not first.link.is_open())).is_true()


func test_a_dropped_player_comes_back_by_token_into_the_right_night() -> void:
	await _start()
	var ann := await _client("m1", "ann")
	var cy := await _client("m2", "cy")
	var link: WebSocketLink = ann.link
	link.retry_every = 0.2
	var resumed := {"count": 0}
	ann.connection_resumed.connect(func() -> void: resumed["count"] += 1)
	link.drop()
	assert_bool(await _until(func() -> bool: return resumed["count"] == 1, 20.0)).is_true()
	assert_int(link.player_id).is_equal(1)
	assert_int(_server.room_of_match("m1").player_count()).is_equal(1)
	assert_int(_server.room_of_match("m2").player_count()).is_equal(1)
	assert_object(cy).is_not_null()


func test_a_connection_that_never_says_hello_is_dropped() -> void:
	await _start()
	_server.hello_within = 0.4
	var ws := WebSocketPeer.new()
	ws.connect_to_url(_url())
	_raw.append(ws)
	var closed := await _until(
		func() -> bool:
			ws.poll()
			return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED
	)
	assert_bool(closed).is_true()


func test_the_server_is_set_up_from_its_environment() -> void:
	var env := {
		"BACKEND_URL": "https://backend.example/",
		"GAME_SERVER_SECRET": "g".repeat(40),
		"TICKET_SECRET": "t".repeat(40),
		"RAILWAY_SERVICE_ID": "abcdef0123456789",
		"RAILWAY_PUBLIC_DOMAIN": "gs.example.app",
		"ROOM_CAPACITY": "6",
		"MAX_ALIVE": "60",
	}
	var config := ServerConfig.from_environment(
		func(key: String) -> String: return env.get(key, "")
	)
	assert_bool(config.uses_backend()).is_true()
	assert_str(config.backend_url).is_equal("https://backend.example")
	assert_str(config.server_id).is_equal("gs-abcdef012345")
	assert_str(config.public_url).is_equal("wss://gs.example.app")
	assert_str(config.activity_path).is_equal("/server")
	assert_int(config.capacity).is_equal(6)
	assert_int(config.max_alive).is_equal(60)
	# Unset, or not a number, is no cap.
	env["MAX_ALIVE"] = "lots"
	var unset := ServerConfig.from_environment(func(key: String) -> String: return env.get(key, ""))
	assert_int(unset.max_alive).is_equal(0)
	var alone := ServerConfig.from_environment(func(_key: String) -> String: return "")
	assert_bool(alone.uses_backend()).is_false()
	assert_str(alone.problem()).is_equal("")
	env["TICKET_SECRET"] = "short"
	var broken := ServerConfig.from_environment(
		func(key: String) -> String: return env.get(key, "")
	)
	assert_str(broken.problem()).contains("TICKET_SECRET")
