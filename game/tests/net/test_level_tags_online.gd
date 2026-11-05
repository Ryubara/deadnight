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
var _layers: Array[CanvasLayer] = []


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	for layer in _layers:
		if is_instance_valid(layer):
			layer.queue_free()
	_layers.clear()
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


# --- A level crossed in the night follows the tally to every tag (#1116) ---


## The XP a seat needs to cross to `level` from where it is: the tally pays it as a challenge's
## reward is paid (`add_xp`), and the room's own tick tells every client (`XpAward.end_tick`).
func _pay_up_to(room: NightHost, player_id: int, level: int) -> void:
	var need := LevelCurve.xp_for(level) - room.server.xp.total_of(player_id)
	room.server.xp.add_xp(player_id, need, &"test")


## A client with a HUD of its own, seated with `account`.
func _viewer(match_id: String, user: String, account := {}) -> Array:
	var layer := CanvasLayer.new()
	add_child(layer)
	_layers.append(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	var night := await _client(match_id, user, account, {}, hud)
	return [night, hud]


## The scoreboard of each viewer held up, the way a player holds the key.
func _hold_boards(viewers: Array) -> void:
	Input.action_press(Hud.SCOREBOARD_ACTION)
	for pair: Array in viewers:
		(pair[1] as Hud).scoreboard.set_shown(true)


## What one client's screen shows for a seat, `{state, tag, box, board}` (0: no level shown). The
## nameplate is the marker over the seat's head (never your own), the box is the bottom-left
## one, the board the scoreboard's row.
func _screen(night: Night, hud: Hud, id: int) -> Dictionary:
	var shown := {
		"state": hud.state.level_of(hud.state.team[id]).x, "tag": -1, "box": 0, "board": 0
	}
	for marker in night.markers.markers():
		if marker["id"] == StringName("player_%d" % id):
			shown["tag"] = int(marker["level"])
	var box := hud.points.box_of(id)
	if box != null:
		shown["box"] = box.shown_level.x
	hud.scoreboard.refresh()
	var at := hud.scoreboard.row_ids.find(id)
	if at >= 0:
		shown["board"] = hud.scoreboard.row_levels[at]
	return shown


## Whether `id` shows `level` everywhere on this client's screen (the tag only where it can be
## seen: not over your own head).
func _shows(night: Night, hud: Hud, id: int, level: int) -> bool:
	var shown := _screen(night, hud, id)
	var tag_ok: bool = int(shown["tag"]) == level or id == night.state.player_id
	return shown["state"] == level and shown["box"] == level and shown["board"] == level and tag_ok


func test_a_level_paid_in_the_night_reaches_the_tag_the_box_and_the_board_of_every_client() -> void:
	await _start()
	var one := await _viewer("pay", "ann", _account(4))
	var two := await _viewer("pay", "bo", _account(9))
	var room := _server.room_of_match("pay")
	var ann: Night = one[0]
	var bo: Night = two[0]
	Input.action_press(Hud.SCOREBOARD_ACTION)
	for pair: Array in [one, two]:
		(pair[1] as Hud).scoreboard.set_shown(true)
	var ids: Array[int] = [ann.state.player_id, bo.state.player_id]
	for pair: Array in [one, two]:
		for i in ids.size():
			var settled := func() -> bool: return _shows(pair[0], pair[1], ids[i], [4, 9][i])
			assert_bool(await _until(settled)).override_failure_message("before %d" % i).is_true()
	# Ann crosses three levels in one tick (one of them gives a card, an emblem and a colour), Bo one.
	_pay_up_to(room, ids[0], 7)
	_pay_up_to(room, ids[1], 10)
	for pair: Array in [one, two]:
		for i in ids.size():
			var seen := func() -> bool: return _shows(pair[0], pair[1], ids[i], [7, 10][i])
			(
				assert_bool(await _until(seen))
				. override_failure_message(
					(
						"client %d, seat %d: %s"
						% [pair[0].state.player_id, ids[i], _screen(pair[0], pair[1], ids[i])]
					)
				)
				. is_true()
			)
	Input.action_release(Hud.SCOREBOARD_ACTION)


func test_a_level_that_gives_an_item_moves_the_tags_like_one_that_gives_none() -> void:
	await _start()
	var one := await _viewer("items", "ann", _account(1))
	var two := await _viewer("items", "bo", _account(1))
	var room := _server.room_of_match("items")
	var ann: Night = one[0]
	var bo: Night = two[0]
	var heard: Array[StringName] = []
	bo.state.event_received.connect(func(e: Dictionary) -> void: heard.append(e["type"]))
	Input.action_press(Hud.SCOREBOARD_ACTION)
	for pair: Array in [one, two]:
		(pair[1] as Hud).scoreboard.set_shown(true)
	var table := LadderUnlocks.shipped()
	# 2: a calling card and an emblem; 3: a colour; 5: a tier (its card, emblem and a colour); 10
	# jumps five levels (a tier, a map, a hat...). Each says `unlock_earned` and `tier_up` beside
	# `level_up`, the events the voice cheers differently.
	var before := 1
	var slots := {}
	for level in [2, 3, 5, 10]:
		heard.clear()
		_pay_up_to(room, ann.state.player_id, level)
		for pair: Array in [one, two]:
			var done := func() -> bool: return _shows(pair[0], pair[1], ann.state.player_id, level)
			(
				assert_bool(await _until(done))
				. override_failure_message(
					"level %d: %s" % [level, _screen(pair[0], pair[1], ann.state.player_id)]
				)
				. is_true()
			)
		# The levels crossed gave their items by their own events beside `level_up`.
		var items := 0
		var tiers := 0
		for crossed in range(before + 1, level + 1):
			items += table.earned_at(crossed).size()
			tiers += 1 if LevelCurve.tier_of(crossed) > LevelCurve.tier_of(crossed - 1) else 0
			for row: Dictionary in table.earned_at(crossed):
				slots[row["slot"]] = true
		assert_int(heard.count(&"level_up")).is_equal(level - before)
		assert_int(heard.count(&"unlock_earned")).is_equal(items)
		assert_int(heard.count(&"tier_up")).is_equal(tiers)
		before = level
	# The four steps gave a calling card, an emblem, a colour and a tier's card.
	assert_array(slots.keys()).contains([&"calling_cards", &"emblem", &"colour", &"tier_card"])
	# Bo was never paid: its tag stayed where it began on both screens.
	assert_bool(_shows(bo, two[1], bo.state.player_id, 1)).is_true()
	assert_bool(_shows(ann, one[1], bo.state.player_id, 1)).is_true()
	Input.action_release(Hud.SCOREBOARD_ACTION)


func test_a_late_joiner_shows_the_levels_paid_before_it_came_and_the_next_one_too() -> void:
	await _start()
	var one := await _viewer("late", "ann", _account(3))
	var room := _server.room_of_match("late")
	var ann: Night = one[0]
	_pay_up_to(room, ann.state.player_id, 11)
	(
		assert_bool(
			await _until(func() -> bool: return room.server.xp.levels()[ann.state.player_id] == 11)
		)
		. is_true()
	)
	var two := await _viewer("late", "bo", _account(8))
	var bo: Night = two[0]
	Input.action_press(Hud.SCOREBOARD_ACTION)
	(two[1] as Hud).scoreboard.set_shown(true)
	# Bo's WELCOME carried Ann's level now (11), not the one she joined with (3).
	var arrived := func() -> bool: return _shows(bo, two[1], ann.state.player_id, 11)
	(
		assert_bool(await _until(arrived))
		. override_failure_message(str(_screen(bo, two[1], ann.state.player_id)))
		. is_true()
	)
	# And a level paid after it came reaches Bo's own box and Ann's view of it.
	(one[1] as Hud).scoreboard.set_shown(true)
	_pay_up_to(room, bo.state.player_id, 12)
	for pair: Array in [one, two]:
		var next := func() -> bool: return _shows(pair[0], pair[1], bo.state.player_id, 12)
		assert_bool(await _until(next)).is_true()
	Input.action_release(Hud.SCOREBOARD_ACTION)


func test_a_seat_with_no_account_has_no_level_and_is_paid_nothing() -> void:
	await _start()
	var one := await _viewer("bare", "ann", _account(5))
	var two := await _viewer("bare", "", {})
	var room := _server.room_of_match("bare")
	var ann: Night = one[0]
	var bare: Night = two[0]
	_hold_boards([one, two])
	assert_bool(room.server.xp.has_seat(bare.state.player_id)).is_false()
	# The tally pays no seat without an account, so its XP is not asked for and nothing is told.
	_pay_up_to(room, bare.state.player_id, 9)
	_pay_up_to(room, ann.state.player_id, 6)
	for pair: Array in [one, two]:
		var next := func() -> bool: return _shows(pair[0], pair[1], ann.state.player_id, 6)
		(
			assert_bool(await _until(next, 3.0))
			. override_failure_message(str(_screen(pair[0], pair[1], ann.state.player_id)))
			. is_true()
		)
	for pair: Array in [one, two]:
		assert_bool(_shows(pair[0], pair[1], bare.state.player_id, 0)).is_true()
		assert_dict(pair[0].state.levels).is_equal({ann.state.player_id: 6})


func test_a_level_paid_to_a_seat_that_left_in_the_same_tick_is_not_an_error() -> void:
	await _start()
	var one := await _viewer("gone", "ann", _account(5))
	var two := await _viewer("gone", "bo", _account(5))
	var room := _server.room_of_match("gone")
	var ann: Night = one[0]
	var bo: Night = two[0]
	var gone := bo.state.player_id
	_hold_boards([one, two])
	_pay_up_to(room, gone, 9)
	_pay_up_to(room, ann.state.player_id, 8)
	# Bo is released before the room's tick tells anyone of the 9 it was paid.
	room.server.xp.release(gone)
	room._collect([{"type": &"account_left", "player_id": gone}])
	var next := func() -> bool: return _shows(ann, one[1], ann.state.player_id, 8)
	(
		assert_bool(await _until(next, 3.0))
		. override_failure_message(str(_screen(ann, one[1], ann.state.player_id)))
		. is_true()
	)
	assert_dict(ann.state.levels).is_equal({ann.state.player_id: 8})
	assert_vector(one[1].state.level_of(one[1].state.team[gone])).is_equal(Vector2i.ZERO)
