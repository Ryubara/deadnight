# The level and icon beside a name (#1077), over a real WebSocket on this machine: the XP the ticket
# says gives a seat its level (`XpAward`, #1114), the WELCOME and the `account_seated`, `level_up`
# and `account_left` events carry it to every client (a late joiner too) and into each client's
# HUD, a bot has none, and no client message can change one. The ticket's claims are made as the
# backend makes them (`TicketMaker`).
extends GdUnitTestSuite

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"

var _server: GameServer
var _nights: Array[Night] = []


func after_test() -> void:
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


## The progression the backend signs for an account at `level`: the raw XP its level starts at.
func _account(level: int) -> Dictionary:
	return {"xp": LevelCurve.xp_for(level)}


func _ticket(match_id: String, user: String, account: Dictionary, settings := {}) -> String:
	return TicketMaker.make(SECRET, SERVER_ID, match_id, user, user, 60, settings, null, account)


## A hand-driven client with a ticket that carries `account`; with a `hud` it feeds that HUD too.
func _client(
	match_id: String, user: String, account := {}, settings := {}, hud: Hud = null
) -> Night:
	var night := Night.new()
	night.hud = hud
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = _ticket(match_id, user, account, settings)
	assert_bool(await night.start_remote(_url(), Night.Mode.MANUAL, 60.0, link)).is_true()
	_nights.append(night)
	return night


# --- The tags reach every client ---


func test_every_client_knows_every_level_and_a_late_joiner_too() -> void:
	await _start()
	var ann := await _client("tags", "ann", _account(12))
	var bo := await _client("tags", "bo", _account(30))
	var cy := await _client("tags", "cy", {})
	var room := _server.room_of_match("tags")
	await _ticks(10)
	# A ticket with no XP is an account at level 1 (#1114).
	var seats := {1: 12, 2: 30, 3: 1}
	assert_dict(room._welcome_snapshot()["levels"]).is_equal(seats)
	# The first two heard the others by `account_seated`; the last, who came last, by the WELCOME.
	for night in [ann, bo, cy]:
		assert_dict((night as Night).state.levels).is_equal(seats)
	var di := await _client("tags", "di", _account(55))
	await _ticks(10)
	assert_dict(di.state.levels).is_equal({1: 12, 2: 30, 3: 1, 4: 55})
	assert_dict(ann.state.levels).is_equal(di.state.levels)
	assert_str(di.state.names[1]).is_equal("ann")


func test_every_clients_hud_shows_each_level_and_the_icon_of_that_level() -> void:
	await _start()
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	var ann := await _client("hud", "ann", _account(12), {}, hud)
	var bo := await _client("hud", "bo", _account(30))
	await _client("hud", "cy", _account(7))
	await _ticks(10)
	var state := hud.state
	var ids: Array[int] = [ann.state.player_id, bo.state.player_id, 3]
	var expected: Array[int] = [12, 30, 7]
	for i in ids.size():
		var shown := state.level_of(state.team[ids[i]])
		assert_vector(shown).is_equal(Vector2i(expected[i], expected[i]))
	# The viewer turns levels off: the data stays, nothing shows.
	state.show_levels = false
	assert_vector(state.level_of(state.team[ann.state.player_id])).is_equal(Vector2i.ZERO)
	state.show_levels = true
	# A level crossed in the night reaches the viewer's tag by `level_up`.
	var room := _server.room_of_match("hud")
	room.server.xp.add_xp(bo.state.player_id, 100000, &"test")
	room._collect(room.server.xp.end_tick(true))
	(
		assert_bool(
			await _until(
				func() -> bool: return state.level_of(state.team[bo.state.player_id]).x > 30
			)
		)
		. is_true()
	)
	layer.queue_free()


func test_a_player_who_comes_back_with_a_new_ticket_shows_the_level_it_has_now() -> void:
	await _start()
	var ann := await _client("back", "ann", _account(12))
	var bo := await _client("back", "bo", _account(5))
	var room := _server.room_of_match("back")
	room.resume_within = 30.0
	ann.link.close()
	assert_bool(await _until(func() -> bool: return room.player_count() == 1)).is_true()
	# While Ann is away her account is not in the night (the tally releases it), so her tag goes.
	assert_bool(await _until(func() -> bool: return not bo.state.levels.has(1))).is_true()
	assert_dict(bo.state.levels).contains_keys([2])
	var again := await _client("back", "ann", _account(13))
	assert_int(again.state.player_id).is_equal(1)
	assert_bool(await _until(func() -> bool: return bo.state.levels.get(1) == 13)).is_true()


func test_a_bot_has_no_level_and_the_seat_it_takes_over_loses_the_leavers() -> void:
	await _start()
	var settings := MatchSettings.new()
	settings.bots = MatchSettings.MAX_BOTS
	var dict := settings.to_dict()
	var ann := await _client("bots", "ann", _account(12), dict)
	var bo := await _client("bots", "bo", _account(20), dict)
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
	assert_array(ann.state.levels.keys()).is_equal([1])


func test_a_client_cannot_give_itself_a_level_whatever_it_sends() -> void:
	await _start()
	var ann := await _client("forge", "ann", _account(3))
	var bo := await _client("forge", "bo", _account(1))
	var room := _server.room_of_match("forge")
	await _ticks(10)
	# Everything a client can say that the server reads is a fixed layout of numbers; try the ways in
	# that a level could ride: the events a server sends, sent up; a hello that says it again; a
	# command with the field in it; a look; garbage of every type byte.
	var claims := {"type": &"level_up", "player_id": 2, "level": 55, "total": 99999}
	var forged: Array[PackedByteArray] = [
		NetWire.tick(1, [claims, {"type": &"account_seated", "player_id": 1, "level": 55}]),
		NetWire.welcome(1, 60, PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]), {"levels": {1: 55}}),
		NetWire.hello(PackedByteArray(), _ticket("forge", "ann", {"xp": 99999999})),
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
	assert_int(room.server.xp.levels()[1]).is_equal(3)
	assert_int(room.server.xp.levels()[2]).is_equal(1)
	assert_dict(bo.state.levels).is_equal({1: 3, 2: 1})
