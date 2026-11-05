extends GdUnitTestSuite
## The hidden challenges from a real game server and real clients (#1172): signed-in seats over a
## real WebSocket, the shipped challenges, a night the rules play and the clients watch. Each stat
## is counted by the server from the events and the frames it makes (`HiddenMoments`), told to every
## client as `challenge_done`, and written in the seat's board. The rare ones are reached the way a
## night reaches them (a break held at the stand, eight rounds with a door shut, a bleed-out in the
## first round, four who stay), by the rules' own actions and the players' own commands, not by
## saying a count. The pattern is `test_challenge_moments_online.gd`'s.

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"
const MATCH := "match-moments"
const DAY := 20401
## The stand of the lot (`data/areas.json`) and a point on the field outside it.
const AT_STAND := Vector3(0.0, 0.2, 2.0)
const IN_FIELD := Vector3(0.0, 0.2, -12.0)

var _server: GameServer
var _nights: Array[Night] = []
var _commands: Dictionary = {}
## Per client, every event but frames, in the order heard.
var _heard: Dictionary = {}
var _tuning: RulesTuning
var _map := "drive_in"
## How many dead a round brings: a quarter, so a round is a few of them, unless a test says more.
var _count := MatchSettings.MIN_COUNT_MULTIPLIER
## The level of the host the tickets name (the back rooms open at 10).
var _host_level := 12


## The shipped tuning with the dead coming at once: a round is a few seconds of waiting, not a
## dozen. Nothing the stats read (the events, the frames, the windows of time) changes with it.
func _fast_tuning() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 0.1
	tuning.rounds.spawn_interval_start = 0.1
	tuning.rounds.spawn_interval_min = 0.05
	return tuning


func before_test() -> void:
	_tuning = _fast_tuning()
	_count = MatchSettings.MIN_COUNT_MULTIPLIER
	_map = "drive_in"


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_commands.clear()
	_heard.clear()
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


func _until(condition: Callable, seconds: float = 30.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


## A game server on the shipped challenges; the dead come few at a time and the breaks are short.
func _start(map := "drive_in") -> GameServer:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 4
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.rules_tuning = _tuning
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_server.challenge_catalog = ChallengeCatalog.load_default()
	_server.challenge_clock = ChallengeFixture.clock_on(DAY)
	_server.report_sender = func(_path: String, _body: Dictionary) -> int: return 200
	_server.board_reader = func(_user: String) -> Dictionary:
		return {"status": 404, "json": ChallengeAward.NO_BOARD}
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())
	_map = map
	return _server


func _settings() -> Dictionary:
	var chosen := MatchSettings.new()
	chosen.count_multiplier = _count
	chosen.break_seconds = 1.0
	chosen.map = _map
	return chosen.to_dict()


## A signed-in client that sends the command held for it every tick.
func _client(user: String) -> Night:
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	link.ticket = TicketMaker.make(
		SECRET, SERVER_ID, MATCH, user, user.capitalize(), 60, _settings(), _host_level, {"xp": 0}
	)
	var joined := await night.start_remote(
		"ws://127.0.0.1:%d" % _server.listener.port(), Night.Mode.MANUAL, 60.0, link
	)
	assert_bool(joined).is_true()
	_nights.append(night)
	var heard: Array[Dictionary] = []
	_heard[night] = heard
	night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] != &"frame":
				heard.append(event)
	)
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void:
			var command: NightCommand = _commands.get(night)
			if command != null:
				night.link.send(command.to_dict())
	)
	return night


## Signed-in clients in the order of `users`, each followed by the server (seats 1, 2, ...).
func _crew(users: Array[String]) -> Array[Night]:
	var crew: Array[Night] = []
	for user in users:
		crew.append(await _client(user))
	for seat in users.size():
		(
			assert_bool(
				await _until(func() -> bool: return _room().server.challenges.follows(seat + 1))
			)
			. is_true()
		)
	return crew


func _room() -> NightHost:
	return _server.room_of_match(MATCH)


func _rules() -> GameRules:
	return _room().server.rules


## An action of the server's own (a kill, a purchase, a blow), whose events go on to every client
## as the game server sends the rules' answers between two steps.
func _act(action: Dictionary) -> Array[Dictionary]:
	var events := _rules().apply(action)
	_room()._collect(events)
	return events


func _kill(killer: int, zombie_id: int, melee := false) -> void:
	_act(
		RulesAction.hit(
			killer, zombie_id, RulesAction.ZONE_BODY, RulesFixture.KILLING_DAMAGE, melee
		)
	)


## The board the server keeps for this account.
func _board(user: String) -> ChallengeProfile:
	return _room().server.challenges.profile_of(user)


func _stat(user: String, stat: StringName) -> int:
	return int(_board(user).lifetime.get(stat, 0))


## The ids of the challenges the server told this client were done for `seat`.
func _done(night: Night, seat: int) -> Array:
	var ids: Array = []
	for event: Dictionary in _heard[night]:
		if event["type"] == ChallengeAward.DONE and event["player_id"] == seat:
			ids.append(event["id"])
	return ids


## How many events of `type` this client has heard; of one `field` equal to `value` when given.
func _heard_count(night: Night, type: StringName, field := &"", value := 0) -> int:
	var found := 0
	for event: Dictionary in _heard[night]:
		if event["type"] == type and (field == &"" or event.get(field, 0) == value):
			found += 1
	return found


## Starts the round and ticks until it is over, killing the dead as they stand; `kill_with` is
## called with each zombie id and answers the killer's seat.
func _clear_round(killer: Callable, on_start := Callable()) -> void:
	var rules := _rules()
	var round_before := rules.round_number
	_act(RulesAction.skip_break())
	if on_start.is_valid():
		await on_start.call()
	var began := Time.get_ticks_msec()
	while (
		rules.round_number == round_before + 1
		and (rules.phase == GameRules.Phase.ACTIVE or rules.phase == GameRules.Phase.IDLE)
	):
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			_kill(killer.call(zombie_id), zombie_id)
		if Time.get_ticks_msec() - began > 120000:
			break
	assert_int(rules.phase).is_equal(GameRules.Phase.BREAK)


## One frame of the server, so the tallies have heard what the last action did.
func _settle(frames := 3) -> void:
	for _i in frames:
		await get_tree().physics_frame


## Whether the server has told every client this challenge is done for `seat`.
func _all_told(crew: Array[Night], seat: int, id: StringName) -> bool:
	for night in crew:
		if not _done(night, seat).has(id):
			return false
	return true


# --- Intermission: a whole break at the stand ---


func test_a_break_held_at_the_stand_is_snack_break_and_one_who_leaves_or_comes_late_is_not(
) -> void:
	await _start()
	var crew := await _crew(["ann", "bo", "cy"])
	var server := _room().server
	# Ann and bo are at the stand when the round ends; cy is on the field.
	await _clear_round(
		func(_zombie: int) -> int: return 1,
		func() -> void:
			server.body_of(1).teleport(AT_STAND)
			server.body_of(2).teleport(AT_STAND)
			await _settle(4)
	)
	var rules := _rules()
	assert_int(rules.phase).is_equal(GameRules.Phase.BREAK)
	assert_int(rules.round_number).is_equal(1)
	# Bo steps out in the break; cy comes in late. Ann stays.
	await _settle(15)
	server.body_of(2).teleport(IN_FIELD)
	server.body_of(3).teleport(AT_STAND)
	assert_bool(await _until(func() -> bool: return rules.round_number == 2)).is_true()
	var counted := func() -> bool: return _stat("ann", ChallengeStats.BREAKS_STAND) == 1
	assert_bool(await _until(counted)).is_true()
	assert_int(_stat("bo", ChallengeStats.BREAKS_STAND)).is_equal(0)
	assert_int(_stat("cy", ChallengeStats.BREAKS_STAND)).is_equal(0)
	for night in crew:
		(
			assert_bool(await _until(func() -> bool: return _done(night, 1).has(&"f_snack_break")))
			. is_true()
		)
		assert_array(_done(night, 2)).not_contains([&"f_snack_break"])
		assert_array(_done(night, 3)).not_contains([&"f_snack_break"])


# --- The long way round: eight rounds with the second door shut ---


func test_eight_rounds_with_the_second_door_shut_finish_the_long_way_round() -> void:
	await _start()
	var crew := await _crew(["ann", "bo"])
	var rules := _rules()
	var second := ChallengeAreas.second_door("drive_in")
	# The first door is opened (it is no matter), the second never.
	_act(RulesAction.grant_points(1, 1000))
	_act(RulesAction.buy(1, &"door_concession"))
	assert_bool(rules.doors_open.has(&"door_concession")).is_true()
	for _round in 7:
		await _clear_round(func(_zombie: int) -> int: return 1)
	assert_int(rules.round_number).is_equal(7)
	var seven := func() -> bool: return _stat("bo", ChallengeStats.ROUND_LONG_WAY) == 7
	assert_bool(await _until(seven)).is_true()
	assert_bool(rules.doors_open.has(second)).is_false()
	for night in crew:
		assert_array(_done(night, 1)).not_contains([&"f_long_way_round"])
	_act(RulesAction.skip_break())
	var eight := func() -> bool: return _stat("ann", ChallengeStats.ROUND_LONG_WAY) == 8
	assert_bool(await _until(eight)).is_true()
	assert_int(_stat("bo", ChallengeStats.ROUND_LONG_WAY)).is_equal(8)
	var told := func() -> bool:
		return _all_told(crew, 1, &"f_long_way_round") and _all_told(crew, 2, &"f_long_way_round")
	assert_bool(await _until(told)).is_true()
	assert_int(int(_board("ann").feats[&"f_long_way_round"])).is_equal(8)


func test_opening_the_second_door_stops_the_count_for_the_whole_lot() -> void:
	await _start()
	var crew := await _crew(["ann", "bo"])
	var rules := _rules()
	_act(RulesAction.grant_points(1, 6000))
	_act(RulesAction.buy(1, &"door_concession"))
	for _round in 2:
		await _clear_round(func(_zombie: int) -> int: return 1)
	var two := func() -> bool: return _stat("bo", ChallengeStats.ROUND_LONG_WAY) == 2
	assert_bool(await _until(two)).is_true()
	# Ann buys the second door in the break; rounds three and four start behind it.
	var events := _act(RulesAction.buy(1, ChallengeAreas.second_door("drive_in")))
	assert_bool(RulesFixture.first(events, &"door_opened").is_empty()).is_false()
	for _round in 2:
		await _clear_round(func(_zombie: int) -> int: return 1)
	assert_int(rules.round_number).is_equal(4)
	var heard_four := func() -> bool: return _heard_count(crew[1], &"round_started") == 4
	assert_bool(await _until(heard_four)).is_true()
	await _settle(4)
	assert_int(_stat("ann", ChallengeStats.ROUND_LONG_WAY)).is_equal(2)
	assert_int(_stat("bo", ChallengeStats.ROUND_LONG_WAY)).is_equal(2)


# --- Dead on arrival: a death in round one ---


func test_a_bleed_out_in_round_one_and_the_night_ending_in_it_are_both_a_death_on_arrival() -> void:
	_tuning = _fast_tuning()
	_tuning.revive.bleed_out_seconds = 1.0
	await _start()
	var crew := await _crew(["ann", "bo"])
	var rules := _rules()
	_act(RulesAction.skip_break())
	_act(RulesAction.blow(2, 99999.0))
	# Nobody holds the revive: bo bleeds out in a second, with ann on her feet.
	assert_bool(await _until(func() -> bool: return rules.players[2].dead, 20.0)).is_true()
	var bo_counted := func() -> bool: return _stat("bo", ChallengeStats.DEATHS_ROUND_ONE) == 1
	assert_bool(await _until(bo_counted)).is_true()
	assert_int(_stat("ann", ChallengeStats.DEATHS_ROUND_ONE)).is_equal(0)
	assert_int(rules.round_number).is_equal(1)
	# Then ann goes down: the night ends in round one with everyone down, and she is dead too.
	_act(RulesAction.blow(1, 99999.0))
	assert_bool(await _until(func() -> bool: return rules.phase == GameRules.Phase.OVER)).is_true()
	var ann_counted := func() -> bool: return _stat("ann", ChallengeStats.DEATHS_ROUND_ONE) == 1
	assert_bool(await _until(ann_counted)).is_true()
	await _settle(4)
	# Bo's death was counted once, not again by the night's end.
	assert_int(_stat("bo", ChallengeStats.DEATHS_ROUND_ONE)).is_equal(1)
	var told := func() -> bool:
		return _all_told(crew, 1, &"f_dead_on_arrival") and _all_told(crew, 2, &"f_dead_on_arrival")
	assert_bool(await _until(told)).is_true()


func test_a_death_in_round_two_and_a_night_that_ends_in_it_are_no_death_on_arrival() -> void:
	_tuning = _fast_tuning()
	_tuning.revive.bleed_out_seconds = 1.0
	await _start()
	var crew := await _crew(["ann", "bo"])
	var rules := _rules()
	await _clear_round(func(_zombie: int) -> int: return 1)
	_act(RulesAction.skip_break())
	assert_int(rules.round_number).is_equal(2)
	_act(RulesAction.blow(2, 99999.0))
	assert_bool(await _until(func() -> bool: return rules.players[2].dead, 20.0)).is_true()
	_act(RulesAction.blow(1, 99999.0))
	assert_bool(await _until(func() -> bool: return rules.phase == GameRules.Phase.OVER)).is_true()
	var ended := func() -> bool: return _stat("ann", ChallengeStats.NIGHTS) == 1
	assert_bool(await _until(ended)).is_true()
	assert_int(_stat("bo", ChallengeStats.DEATHS_ROUND_ONE)).is_equal(0)
	assert_int(_stat("ann", ChallengeStats.DEATHS_ROUND_ONE)).is_equal(0)
	for night in crew:
		assert_array(_done(night, 1)).not_contains([&"f_dead_on_arrival"])
		assert_array(_done(night, 2)).not_contains([&"f_dead_on_arrival"])


# --- Standing room only: the same four from the first round to the end ---


func test_four_people_who_stay_to_the_end_are_standing_room_only() -> void:
	await _start()
	var crew := await _crew(["ann", "bo", "cy", "di"])
	var rules := _rules()
	assert_int(rules.players.size()).is_equal(4)
	_act(RulesAction.skip_break())
	for seat in [1, 2, 3, 4]:
		_act(RulesAction.blow(seat, 99999.0))
	assert_bool(await _until(func() -> bool: return rules.phase == GameRules.Phase.OVER)).is_true()
	for user in ["ann", "bo", "cy", "di"]:
		var full := func() -> bool: return _stat(user, ChallengeStats.NIGHTS_FULL_LOT) == 1
		assert_bool(await _until(full)).is_true()
	for seat in [1, 2, 3, 4]:
		var told := func() -> bool: return _all_told(crew, seat, &"f_standing_room_only")
		assert_bool(await _until(told)).is_true()


func test_a_fourth_who_leaves_in_the_night_spoils_it_for_the_other_three() -> void:
	await _start()
	var crew := await _crew(["ann", "bo", "cy", "di"])
	var rules := _rules()
	_act(RulesAction.skip_break())
	await _settle(4)
	(crew[3].link as WebSocketLink).close()
	assert_bool(await _until(func() -> bool: return rules.players.size() == 3)).is_true()
	for seat in [1, 2, 3]:
		_act(RulesAction.blow(seat, 99999.0))
	assert_bool(await _until(func() -> bool: return rules.phase == GameRules.Phase.OVER)).is_true()
	var ended := func() -> bool: return _stat("ann", ChallengeStats.NIGHTS) == 1
	assert_bool(await _until(ended)).is_true()
	for user in ["ann", "bo", "cy"]:
		assert_int(_stat(user, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(0)
	assert_array(_done(crew[0], 1)).not_contains([&"f_standing_room_only"])
