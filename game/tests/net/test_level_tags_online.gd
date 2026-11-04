# The level and icon beside a name (#1077), over a real WebSocket on this machine: the ticket the
# backend signs gives a seat its level, the WELCOME and the `player_named` event carry it to every
# client (a late joiner too), a bot has none, no client message can change one, a level gained in
# the night reaches the tags, and the wire reads in both versions (16, and 15 which adds nothing a
# 15 client cannot skip). The ticket's claims are made as the backend makes them (`TicketMaker`).
extends GdUnitTestSuite

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"

var _server: GameServer
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
	if is_instance_valid(_server):
		_server.get_parent().queue_free()
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


func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _start() -> GameServer:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 4
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())
	return _server


func _url() -> String:
	return "ws://127.0.0.1:%d" % _server.listener.port()


## The claims the backend signs for an account at `level`: `level`, its icon and the raw XP.
func _claims(level: int, icon := -1) -> Dictionary:
	return {
		"level": level,
		"icon": "level_%02d" % (level if icon < 0 else icon),
		"xp": LevelCurve.xp_for(level),
	}


func _ticket(match_id: String, user: String, extra: Dictionary, settings := {}) -> String:
	return TicketMaker.make(SECRET, SERVER_ID, match_id, user, user, 60, settings, null, extra)


## A hand-driven client with a ticket that carries `extra` claims.
func _client(match_id: String, user: String, extra := {}, settings := {}) -> Night:
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = _ticket(match_id, user, extra, settings)
	assert_bool(await night.start_remote(_url(), Night.Mode.MANUAL, 60.0, link)).is_true()
	_nights.append(night)
	return night


## A bare socket that says hello as a client of `version` with `ticket`; its first answer (WELCOME
## or REFUSED) as a packet.
func _hello(ticket: String, version := NetWire.VERSION) -> PackedByteArray:
	var ws := WebSocketPeer.new()
	ws.connect_to_url(_url())
	_raw.append(ws)
	var got := {"packet": PackedByteArray(), "sent": false}
	await _until(
		func() -> bool:
			ws.poll()
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not got["sent"]:
				got["sent"] = true
				var hello := NetWire.hello(PackedByteArray(), ticket)
				hello[1] = version
				ws.send(hello, WebSocketPeer.WRITE_MODE_BINARY)
			while ws.get_available_packet_count() > 0:
				var packet := ws.get_packet()
				if packet[0] == NetWire.Type.WELCOME or packet[0] == NetWire.Type.REFUSED:
					got["packet"] = packet
			return not (got["packet"] as PackedByteArray).is_empty()
	)
	return got["packet"]


# --- The ticket ---


func test_the_ticket_gives_a_seat_its_level_and_the_icon_of_that_level() -> void:
	var verifier := TicketVerifier.new(SECRET, SERVER_ID)
	var now := int(Time.get_unix_time_from_system())
	var result := verifier.admit(_ticket("m", "ann", _claims(12)), now)
	assert_bool(result["ok"]).is_true()
	assert_int(result["level"]).is_equal(12)
	assert_int(result["icon"]).is_equal(12)
	# An icon the backend names apart from the level (a later frame) is read as sent.
	var other := verifier.admit(_ticket("m", "bo", _claims(12, 40)), now)
	assert_int(other["level"]).is_equal(12)
	assert_int(other["icon"]).is_equal(40)


func test_a_ticket_without_a_level_or_with_a_bad_one_shows_none() -> void:
	var verifier := TicketVerifier.new(SECRET, SERVER_ID)
	var now := int(Time.get_unix_time_from_system())
	var bad: Array[Dictionary] = [
		{},
		{"level": 0, "icon": "level_00"},
		{"level": 56, "icon": "level_56"},
		{"level": -3},
		{"level": 3.5},
		{"level": "12"},
		{"level": null},
		{"level": [12]},
	]
	for i in bad.size():
		var result := verifier.admit(_ticket("m", "u%d" % i, bad[i]), now)
		assert_bool(result["ok"]).is_true()
		assert_int(result["level"]).is_equal(0)
		assert_int(result["icon"]).is_equal(0)
	# An icon that is not a ladder icon follows the level.
	for icon in ["level_99", "level_", "sword", "level_1x", 7]:
		var result := verifier.admit(_ticket("m", "i%s" % icon, {"level": 9, "icon": icon}), now)
		assert_int(result["level"]).is_equal(9)
		assert_int(result["icon"]).is_equal(9)


func test_a_ticket_whose_level_was_changed_after_signing_is_refused() -> void:
	var verifier := TicketVerifier.new(SECRET, SERVER_ID)
	var now := int(Time.get_unix_time_from_system())
	var ticket := _ticket("m", "ann", _claims(3))
	var parts := ticket.split(".")
	var claims: Dictionary = JSON.parse_string(
		TicketVerifier._decode(parts[1]).get_string_from_utf8()
	)
	claims["level"] = 55
	claims["icon"] = "level_55"
	parts[1] = (
		Marshalls
		. raw_to_base64(JSON.stringify(claims).to_utf8_buffer())
		. replace("+", "-")
		. replace("/", "_")
		. trim_suffix("=")
		. trim_suffix("=")
	)
	var forged := verifier.admit(".".join(parts), now)
	assert_bool(forged["ok"]).is_false()
	assert_str(forged["reason"]).is_equal(TicketVerifier.BAD)


# --- The tags reach every client ---


func test_every_client_knows_every_level_and_a_late_joiner_too() -> void:
	await _start()
	var ann := await _client("tags", "ann", _claims(12))
	var bo := await _client("tags", "bo", _claims(30))
	var cy := await _client("tags", "cy", {})
	var room := _server.room_of_match("tags")
	await _ticks(10)
	assert_dict(room._welcome_snapshot()["levels"]).is_equal(
		{1: Vector2i(12, 12), 2: Vector2i(30, 30)}
	)
	# The first two heard each other's by the event; the third, who came last, by the WELCOME.
	for night in [ann, bo, cy]:
		assert_dict((night as Night).state.levels).is_equal(
			{1: Vector2i(12, 12), 2: Vector2i(30, 30)}
		)
	# A fourth who joins late, with a level of their own, sees all three seats' tags at once.
	var di := await _client("tags", "di", _claims(55))
	await _ticks(10)
	assert_dict(di.state.levels).is_equal(
		{1: Vector2i(12, 12), 2: Vector2i(30, 30), 4: Vector2i(55, 55)}
	)
	assert_dict(ann.state.levels).is_equal(di.state.levels)
	# The names came with them.
	assert_str(di.state.names[1]).is_equal("ann")


func test_a_player_who_comes_back_with_a_new_ticket_shows_the_level_it_has_now() -> void:
	await _start()
	var ann := await _client("back", "ann", _claims(12))
	var bo := await _client("back", "bo", _claims(5))
	var room := _server.room_of_match("back")
	room.resume_within = 30.0
	ann.link.close()
	assert_bool(await _until(func() -> bool: return room.player_count() == 1)).is_true()
	# The seat is held while Ann is away, and so is its tag.
	assert_dict(bo.state.levels).contains_keys([1, 2])
	var again := await _client("back", "ann", _claims(13))
	assert_int(again.state.player_id).is_equal(1)
	(
		assert_bool(await _until(func() -> bool: return bo.state.levels.get(1) == Vector2i(13, 13)))
		. is_true()
	)


func test_a_bot_has_no_level_and_the_seat_it_takes_over_loses_the_leavers() -> void:
	await _start()
	var settings := MatchSettings.new()
	settings.bots = MatchSettings.MAX_BOTS
	var dict := settings.to_dict()
	var ann := await _client("bots", "ann", _claims(12), dict)
	var bo := await _client("bots", "bo", _claims(20), dict)
	var room := _server.room_of_match("bots")
	await _ticks(20)
	assert_int(room.bots.count()).is_greater(0)
	# Only the two people have a level, in every client's table.
	assert_array(ann.state.levels.keys()).contains_exactly_in_any_order([1, 2])
	assert_int(ann.state.names.size()).is_greater(2)
	# Bo leaves: a bot takes the seat, and the seat shows no level (the person's went with them).
	bo.link.close()
	assert_bool(await _until(func() -> bool: return room.player_count() == 1)).is_true()
	assert_bool(await _until(func() -> bool: return not ann.state.levels.has(2))).is_true()
	assert_vector(room.level_of(2)).is_equal(Vector2i.ZERO)
	assert_array(ann.state.levels.keys()).is_equal([1])
	# A level set on a bot's seat is refused, whoever asks.
	room.set_level(2, 40)
	assert_vector(room.level_of(2)).is_equal(Vector2i.ZERO)


func test_a_client_cannot_give_itself_a_level_whatever_it_sends() -> void:
	await _start()
	var ann := await _client("forge", "ann", _claims(3))
	var bo := await _client("forge", "bo", {})
	var room := _server.room_of_match("forge")
	await _ticks(10)
	# Everything a client can say that the server reads is a fixed layout of numbers; try the ways in
	# that a level could ride: the events a server sends, sent up; a hello that says it again; a
	# command with the field in it; a look; garbage of every type byte.
	var claims := {"type": &"player_leveled", "player_id": 2, "level": 55, "icon": 55}
	var forged: Array[PackedByteArray] = [
		NetWire.tick(
			1, [claims, {"type": &"player_named", "player_id": 1, "name": "x", "level": 55}]
		),
		NetWire.welcome(
			1, 60, PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]), {"levels": {1: Vector2i(55, 55)}}
		),
		NetWire.hello(PackedByteArray(), _ticket("forge", "ann", _claims(55))),
		PackedByteArray([NetWire.Type.PLATFORM, 1, 55, 55]),
		PackedByteArray([NetWire.Type.MARK, 55, 55, 55]),
		PackedByteArray([NetWire.Type.COMMAND, 55, 55, 55, 55]),
		LookWire.look(CharacterLook.new()),
	]
	for type in [0, 5, 8, 9, 14, 255]:
		forged.append(PackedByteArray([type, 55, 55, 55, 55, 55, 55, 55]))
	# A client that sends junk is struck and, at a hundred points, hung up on (`PeerLimits`): a few
	# at a time, with the forgiving seconds between, keeps the connection to see the levels stand.
	var link := ann.link as WebSocketLink
	for i in forged.size():
		link._put(forged[i])
		if i % 3 == 2:
			await _ticks(60)
	await _ticks(20)
	assert_vector(room.level_of(1)).is_equal(Vector2i(3, 3))
	assert_vector(room.level_of(2)).is_equal(Vector2i.ZERO)
	assert_dict(bo.state.levels).is_equal({1: Vector2i(3, 3)})


func test_a_level_gained_in_the_night_reaches_every_tag_once() -> void:
	await _start()
	var ann := await _client("gain", "ann", _claims(4))
	var bo := await _client("gain", "bo", _claims(9))
	var room := _server.room_of_match("gain")
	await _ticks(10)
	var heard: Array[Dictionary] = []
	bo.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == &"player_leveled":
				heard.append(event)
	)
	room.set_level(1, 5)
	room.set_level(1, 5)
	(
		assert_bool(await _until(func() -> bool: return bo.state.levels.get(1) == Vector2i(5, 5)))
		. is_true()
	)
	await _ticks(10)
	assert_int(heard.size()).is_equal(1)
	assert_dict(ann.state.levels).is_equal({1: Vector2i(5, 5), 2: Vector2i(9, 9)})
	# Nobody sits in seat 3, and 0 is no level.
	room.set_level(3, 5)
	room.set_level(1, 0)
	assert_vector(room.level_of(3)).is_equal(Vector2i.ZERO)
	assert_vector(room.level_of(1)).is_equal(Vector2i(5, 5))


# --- The wire in both versions ---


func test_the_protocol_is_16_and_takes_a_15_client_that_cannot_read_levels() -> void:
	assert_int(NetWire.VERSION).is_equal(16)
	assert_bool(NetWire.accepts(16)).is_true()
	assert_bool(NetWire.accepts(15)).is_true()
	assert_bool(NetWire.accepts(14)).is_false()
	assert_bool(NetWire.accepts(17)).is_false()
	await _start()
	var first := await _client("old", "ann", _claims(12))
	assert_int(first.state.player_id).is_equal(1)
	# A client of 16 reads the levels from the WELCOME; one of 15, who reads the layout the same
	# and only the keys it knew, gets the same WELCOME and finds its names where it left them.
	for version in [16, 15]:
		var ticket := _ticket("old", "bo%d" % version, _claims(7))
		var welcome := NetWire.read_welcome(await _hello(ticket, version))
		assert_bool(welcome.is_empty()).is_false()
		assert_int(welcome["version"]).is_equal(NetWire.VERSION)
		var snapshot: Dictionary = welcome["snapshot"]
		assert_str(snapshot["names"][1]).is_equal("ann")
		assert_str(snapshot["names"][welcome["player_id"]]).is_equal("bo%d" % version)
		assert_bool(snapshot.has("round")).is_true()
		var tags: Dictionary = snapshot["levels"]
		assert_vector(tags[1]).is_equal(Vector2i(12, 12))
		assert_vector(tags[welcome["player_id"]]).is_equal(Vector2i(7, 7))
	# A client of 14 is turned away, as it has been.
	var refused := await _hello(_ticket("old", "cy", {}), 14)
	assert_int(refused[0]).is_equal(NetWire.Type.REFUSED)
	assert_int(refused[1]).is_equal(NetWire.Refusal.VERSION)


func test_a_snapshot_of_a_server_of_15_leaves_the_tags_bare_and_keeps_the_names() -> void:
	# What a 16 client makes of a WELCOME from a server that sends no `levels` (an older deploy).
	var state := ClientState.new()
	state.load_names({"names": {1: "ann", 2: "bo"}})
	assert_dict(state.names).is_equal({1: "ann", 2: "bo"})
	assert_dict(state.levels).is_empty()
	var hud_state := HudState.new()
	hud_state.load_snapshot({"names": {1: "ann"}, "players": {1: {}}})
	assert_vector(hud_state.level_of(hud_state.team[1])).is_equal(Vector2i.ZERO)
	# And a player_named event of 15, with no level, names the seat and shows none.
	hud_state.apply_event({"type": &"player_named", "player_id": 1, "name": "ann"})
	assert_vector(hud_state.level_of(hud_state.team[1])).is_equal(Vector2i.ZERO)


# --- What a join costs ---


func test_what_the_levels_add_to_a_join_is_a_few_dozen_bytes_a_seat() -> void:
	await _start()
	for i in 4:
		await _client("cost", "player%d" % i, _claims(12 + i * 10))
	var room := _server.room_of_match("cost")
	await _ticks(10)
	# The WELCOME a fifth player would get, with the levels and without the key (the real snapshot,
	# packed and compressed the way it goes), and the `player_named` the others hear.
	var tagged := room._welcome_snapshot()
	var plain := tagged.duplicate()
	plain.erase("levels")
	var token := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	var without := NetWire.welcome(5, 60, token, plain).size()
	var with := NetWire.welcome(5, 60, token, tagged).size()
	var named := {"type": &"player_named", "player_id": 5, "name": "player4"}
	var event_plain := NetWire.tick(1, [named]).size()
	named["level"] = 42
	named["icon"] = 42
	var event_tagged := NetWire.tick(1, [named]).size()
	print(
		(
			"LEVELBYTES welcome, 4 levelled seats: %d -> %d (+%d); player_named: %d -> %d (+%d)"
			% [without, with, with - without, event_plain, event_tagged, event_tagged - event_plain]
		)
	)
	assert_int(with - without).is_greater(0)
	assert_int(with - without).is_less(24 * 4)
	assert_int(event_tagged - event_plain).is_less(48)
