# The bots of a game server's rooms (#230), over a real WebSocket on this machine: the room's skill
# names and dresses them, the operator's cap, budget and kill-switch hold whatever the host asked
# for, a limit that changes while a night runs seats or sends away bots without ending it, and a
# person who leaves takes only their own body (a bot holds no seat of the people's, #1179).
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


func _start(limits: BotLimits = null) -> GameServer:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 4
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	if limits != null:
		_server.bot_limits = limits
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())
	return _server


## A hand-driven client of `match_id` whose host asked for `bots` bots of `skill`.
func _client(match_id: String, user: String, bots: int, skill: int = 1) -> Night:
	var settings := {
		"count_multiplier": 1.0,
		"max_alive": 0,
		"break_seconds": 0.0,
		"bots": bots,
		"bot_skill": skill,
	}
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = TicketMaker.make(SECRET, SERVER_ID, match_id, user, user, 60, settings)
	var url := "ws://127.0.0.1:%d" % _server.listener.port()
	assert_bool(await night.start_remote(url, Night.Mode.MANUAL, 60.0, link)).is_true()
	_nights.append(night)
	return night


func _look_key(night: Night, player_id: int) -> String:
	var held: CharacterLook = night.looks.looks.get(player_id)
	return held.key() if held != null else ""


func _bots_of(room: NightHost) -> Array:
	var seats: Array = []
	for id: int in room.server.rules.players:
		if (room.server.rules.players[id] as PlayerState).bot:
			seats.append(id)
	seats.sort()
	return seats


func test_the_rooms_skill_names_dresses_and_drives_its_bots() -> void:
	await _start()
	var ann := await _client("skill", "Ann", 3, MatchSettings.SKILL_VETERAN)
	var room := _server.room_of_match("skill")
	await _ticks(20)
	assert_array(_bots_of(room)).is_equal([101, 102, 103])
	for bot in room.bots.host.bots:
		assert_str(bot.profile.title).is_equal("Veteran")
	# Every bot's name reaches the client, in the skill's cast.
	assert_str(ann.state.names[101]).is_equal(BotRoster.name_for(MatchSettings.SKILL_VETERAN, 1))
	assert_str(ann.state.names[102]).is_equal(BotRoster.name_for(MatchSettings.SKILL_VETERAN, 2))
	# Their looks reach the client's table as the server holds them.
	var wanted := BotRoster.look_for(MatchSettings.SKILL_VETERAN, 3).key()
	assert_bool(await _until(func() -> bool: return _look_key(ann, 103) == wanted)).is_true()
	# The roster API marks them (the snapshot a WELCOME carries); a person's seat is no bot's.
	var players: Dictionary = room.server.rules.to_dict()["players"]
	assert_bool(bool(players[101]["bot"])).is_true()
	assert_bool(bool(players[1]["bot"])).is_false()


func test_a_cap_per_room_holds_whatever_the_host_asked_for() -> void:
	var limits := BotLimits.new()
	limits.per_room = 1
	await _start(limits)
	await _client("cap", "Ann", 3)
	var room := _server.room_of_match("cap")
	await _ticks(20)
	assert_array(_bots_of(room)).is_equal([101])
	assert_int(room.server.rules.settings.bots).is_equal(3)


func test_the_kill_switch_seats_no_bot() -> void:
	var limits := BotLimits.new()
	limits.off = true
	await _start(limits)
	await _client("off", "Ann", 3)
	var room := _server.room_of_match("off")
	await _ticks(20)
	assert_int(room.bots.count()).is_equal(0)
	assert_int(room.server.rules.players.size()).is_equal(1)


func test_the_kill_switch_thrown_mid_night_sends_the_bots_away_and_lifting_it_brings_them_back(
) -> void:
	await _start()
	var ann := await _client("live", "Ann", 2)
	var room := _server.room_of_match("live")
	await _ticks(20)
	assert_array(_bots_of(room)).is_equal([101, 102])
	var round_before := room.server.rules.round_number
	var nights_before := room.nights
	var off := BotLimits.new()
	off.off = true
	_server.set_bot_limits(off)
	await _ticks(10)
	assert_int(room.bots.count()).is_equal(0)
	assert_array(_bots_of(room)).is_empty()
	# The person still plays the same night, and the client's frame no longer holds the seats.
	assert_int(room.nights).is_equal(nights_before)
	assert_int(room.server.rules.round_number).is_equal(round_before)
	(
		assert_bool(await _until(func() -> bool: return not ann.state.frame["players"].has(102)))
		. is_true()
	)
	_server.set_bot_limits(BotLimits.new())
	await _ticks(10)
	assert_array(_bots_of(room)).is_equal([101, 102])
	assert_int(room.nights).is_equal(nights_before)


func test_the_budget_is_shared_by_the_open_rooms() -> void:
	var limits := BotLimits.new()
	limits.budget = 4
	await _start(limits)
	await _client("one", "Ann", 3)
	var first := _server.room_of_match("one")
	await _ticks(20)
	assert_int(first.bots.count()).is_equal(3)
	# A second room opens: each room gets half the budget, and the first sends a bot away.
	await _client("two", "Bo", 3)
	var second := _server.room_of_match("two")
	await _ticks(20)
	assert_int(first.bots.count()).is_equal(2)
	assert_int(second.bots.count()).is_equal(2)
	assert_int(first.bot_limit).is_equal(2)


func test_a_person_who_leaves_takes_only_their_own_body_and_the_bots_stand_as_they_were() -> void:
	await _start()
	var ann := await _client("leave", "Ann", MatchSettings.MAX_BOTS, MatchSettings.SKILL_VETERAN)
	var bo := await _client("leave", "Bo", MatchSettings.MAX_BOTS, MatchSettings.SKILL_VETERAN)
	var room := _server.room_of_match("leave")
	await _ticks(20)
	# Two people and all seven bots: the bots take none of the eight places.
	assert_array(_bots_of(room)).is_equal([101, 102, 103, 104, 105, 106, 107])
	room.server.rules.apply(RulesAction.skip_break())
	room.server.rules.apply(RulesAction.grant_points(101, 4321))
	var bot_body := room.server.body_of(101)
	var bot_points: int = room.server.rules.players[101].points
	var round_before := room.server.rules.round_number
	var nights_before := room.nights
	bo.link.close()
	assert_bool(await _until(func() -> bool: return room.player_count() == 1)).is_true()
	await _ticks(20)
	# Bo's body is gone; no bot took it, and every bot stands as it was.
	assert_bool(room.server.rules.players.has(2)).is_false()
	assert_array(_bots_of(room)).is_equal([101, 102, 103, 104, 105, 106, 107])
	assert_object(room.server.body_of(101)).is_same(bot_body)
	assert_int(room.server.rules.players[101].points).is_equal(bot_points)
	assert_int(room.server.rules.round_number).is_equal(round_before)
	assert_int(room.nights).is_equal(nights_before)
	assert_str(ann.state.names[101]).is_equal(BotRoster.name_for(MatchSettings.SKILL_VETERAN, 1))
	assert_int(room.bots.count()).is_equal(MatchSettings.MAX_BOTS)
	assert_str(room.bots.host.bots[0].profile.title).is_equal("Veteran")
	# A third person takes the lowest free person's id, in a body of their own.
	var cy := await _client("leave", "Cy", MatchSettings.MAX_BOTS, MatchSettings.SKILL_VETERAN)
	await _ticks(20)
	assert_int(cy.state.player_id).is_equal(2)
	assert_bool(room.server.rules.players[2].bot).is_false()
	assert_object(room.server.body_of(101)).is_same(bot_body)
