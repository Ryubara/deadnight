# A room with bots (#643), over a real WebSocket on this machine: the host's Bots setting seats
# that many bots in ids of their own (101 and up), and they take no seat of the 8 people (#1179): a
# person who joins takes the next free person's seat while the round goes on and every bot stays
# as it is, 8 people and 7 bots hold one night together, and a person who leaves takes only their
# own body away. The server and its clients each live in their own SubViewport world.
extends GdUnitTestSuite

const STEP := Night.STEP
## The points the test puts in a bot's pocket, to find them still there after the people come.
const POCKET := 4321

var _host: NightHost
var _nights: Array[Night] = []
var _raw: Array[WebSocketPeer] = []


func after_test() -> void:
	for ws in _raw:
		ws.close()
	_raw.clear()
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


## A room whose host asked for `bots` bots.
func _server(bots: int) -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	var settings := MatchSettings.new()
	settings.bots = bots
	_host.match_settings = settings
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var joined := await night.start_remote(
		"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.MANUAL, 30.0
	)
	assert_bool(joined).is_true()
	_nights.append(night)
	return night


## The seats bots hold, from the server's rules, lowest first.
func _bot_seats() -> Array:
	var seats: Array = []
	for id: int in _host.server.rules.players:
		if (_host.server.rules.players[id] as PlayerState).bot:
			seats.append(id)
	seats.sort()
	return seats


func _people_seats() -> Array:
	var seats: Array = []
	for id: int in _host.server.rules.players:
		if not (_host.server.rules.players[id] as PlayerState).bot:
			seats.append(id)
	seats.sort()
	return seats


func test_a_room_with_two_people_and_seven_bots_asked_seats_all_seven() -> void:
	await _server(MatchSettings.MAX_BOTS)
	await _client()
	await _client()
	await _ticks(10)
	assert_array(_people_seats()).is_equal([1, 2])
	assert_array(_bot_seats()).is_equal([101, 102, 103, 104, 105, 106, 107])
	assert_int(_host.bots.count()).is_equal(MatchSettings.MAX_BOTS)


func test_a_lone_person_gets_the_bots_asked_for_and_the_night_has_started() -> void:
	await _server(3)
	var first := await _client()
	await _ticks(10)
	assert_array(_bot_seats()).is_equal([101, 102, 103])
	assert_int(_host.server.rules.phase).is_not_equal(GameRules.Phase.IDLE)
	# The client's roster of the room shows them as bots, by name.
	assert_int(first.state.names.size()).is_greater_equal(3)


func test_no_bots_asked_for_seats_none() -> void:
	await _server(0)
	await _client()
	await _ticks(10)
	assert_int(_host.bots.count()).is_equal(0)
	assert_int(_host.server.rules.players.size()).is_equal(1)


func test_a_second_person_takes_their_own_seat_and_no_bot_moves() -> void:
	await _server(MatchSettings.MAX_BOTS)
	await _client()
	await _ticks(10)
	assert_array(_bot_seats()).is_equal([101, 102, 103, 104, 105, 106, 107])
	# The night is on: round 1 has begun and the first bot holds something of its own.
	_host.server.rules.apply(RulesAction.skip_break())
	_host.server.rules.apply(RulesAction.grant_points(101, POCKET))
	var round_before := _host.server.rules.round_number
	var phase_before := _host.server.rules.phase
	var nights_before := _host.nights
	var body_before := _host.server.body_of(101)
	var second := await _client()
	await _ticks(20)
	# The person is at seat 2, in a body of their own; all seven bots are where they were.
	assert_int(second.state.player_id).is_equal(2)
	assert_array(_people_seats()).is_equal([1, 2])
	assert_array(_bot_seats()).is_equal([101, 102, 103, 104, 105, 106, 107])
	assert_int(_host.bots.count()).is_equal(MatchSettings.MAX_BOTS)
	assert_object(_host.server.body_of(101)).is_same(body_before)
	assert_bool(_host.server.rules.players[101].points >= POCKET).is_true()
	assert_bool((_host.server.rules.players[2] as PlayerState).bot).is_false()
	# The round did not end and the night was not rebuilt.
	assert_int(_host.server.rules.round_number).is_equal(round_before)
	assert_int(_host.server.rules.phase).is_equal(phase_before)
	assert_int(_host.nights).is_equal(nights_before)
	assert_int(_host.server.rules.phase).is_not_equal(GameRules.Phase.OVER)
	# Every client heard it: both people and the bot are in the frame.
	for night in _nights:
		var players: Dictionary = night.state.frame.get("players", {})
		assert_bool(players.has(2)).is_true()
		assert_bool(players.has(101)).is_true()


func test_eight_people_and_seven_bots_hold_one_night_and_a_ninth_person_is_turned_away() -> void:
	await _server(MatchSettings.MAX_BOTS)
	for _i in NightHost.MAX_PLAYERS:
		await _client()
	await _ticks(10)
	# No bot gave way for a person: the cap of 8 is people alone.
	assert_int(_host.bots.count()).is_equal(MatchSettings.MAX_BOTS)
	assert_array(_people_seats()).is_equal(range(1, NightHost.MAX_PLAYERS + 1))
	assert_int(_host.server.rules.players.size()).is_equal(NightHost.MAX_SEATS)
	assert_int(_host.people_count()).is_equal(NightHost.MAX_PLAYERS)
	assert_int(_host.player_count()).is_equal(NightHost.MAX_PLAYERS)
	# Every client sees the whole room, the people and the bots.
	for night in _nights:
		assert_int((night.state.frame["players"] as Dictionary).size()).is_equal(
			NightHost.MAX_SEATS
		)
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % _host.listener.port())
	_raw.append(ws)
	var refusal := {"reason": 0, "sent": false}
	await _until(
		func() -> bool:
			ws.poll()
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not refusal["sent"]:
				refusal["sent"] = true
				ws.send(NetWire.hello(PackedByteArray()), WebSocketPeer.WRITE_MODE_BINARY)
			while ws.get_available_packet_count() > 0:
				var packet := ws.get_packet()
				if packet[0] == NetWire.Type.REFUSED:
					refusal["reason"] = packet[1]
			return refusal["reason"] != 0
	)
	assert_int(refusal["reason"]).is_equal(NetWire.Refusal.FULL)


func test_a_person_who_leaves_takes_only_their_own_body_and_the_bots_stay() -> void:
	await _server(MatchSettings.MAX_BOTS)
	await _client()
	var second := await _client()
	await _ticks(10)
	assert_array(_bot_seats()).is_equal([101, 102, 103, 104, 105, 106, 107])
	second.link.close()
	await _until(func() -> bool: return _host.player_count() == 1, 10.0)
	await _ticks(10)
	assert_array(_people_seats()).is_equal([1])
	assert_array(_bot_seats()).is_equal([101, 102, 103, 104, 105, 106, 107])
	assert_int(_host.people_count()).is_equal(1)


func test_bots_play_the_night_they_are_seated_in() -> void:
	await _server(2)
	await _client()
	await _ticks(10)
	_host.server.rules.apply(RulesAction.skip_break())
	# Bots send commands every step: their telemetry counts them.
	await _ticks(120)
	var sent := 0
	for bot in _host.bots.host.bots:
		sent += bot.telemetry.commands
	assert_int(sent).is_greater(200)
