extends GdUnitTestSuite
## A finished poster set on the night report (#1073), over a real game server and its WebSocket: a
## four-player night where the seat that kills finishes a poster set, every client hears
## `poster_set_done` once, and only that seat's report names the set, with its title and prize. The
## solo case (the rules run here, no server) is in `test_poster_sets`.

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-test"
const MATCH := "match-poster-report"
const DAY := 20401
const SET_TEXT := (
	'{"sets": [{"id": "small", "title": "Small Feature", "short": "Small", "lines": ["A"], '
	+ '"palette": "teal", "motif": "bolt", '
	+ '"challenges": ["p1", "p2", "p3", "p4", "p5", "p6"], '
	+ '"grants": ["card:fifty_foot_feature", "emblem:live_wire"]}]}'
)

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


func _until(condition: Callable, seconds: float = 30.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


## Six feats finished by one, one, two, two, three and three kills.
func _catalog() -> ChallengeCatalog:
	var catalog := ChallengeFixture.quick_catalog()
	var targets := [1, 1, 2, 2, 3, 3]
	var records: Array = []
	for n in targets.size():
		var target: int = targets[n]
		records.append(
			{
				"id": "p%d" % (n + 1),
				"text": "Put down %d" % target,
				"stat": "kills",
				"target": target
			}
		)
	catalog.add_all(records, ChallengeDef.Family.FEAT)
	return catalog


func _start() -> void:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 2
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_server.challenge_catalog = _catalog()
	_server.poster_sets = PosterSets.from_text(SET_TEXT)
	_server.challenge_clock = ChallengeFixture.clock_on(DAY)
	_server.report_sender = func(_path: String, _body: Dictionary) -> int: return 200
	_server.board_reader = func(_user: String) -> Dictionary:
		return {"status": 404, "json": ChallengeAward.NO_BOARD}
	_world().add_child(_server)
	await _until(func() -> bool: return _server.listener.is_listening())


func _client(user: String) -> Night:
	var night := Night.new()
	_world().add_child(night)
	var link := WebSocketLink.new()
	var chosen := MatchSettings.new()
	chosen.count_multiplier = 5.0
	chosen.break_seconds = 1.0
	link.ticket = TicketMaker.make(
		SECRET, SERVER_ID, MATCH, user, user.capitalize(), 60, chosen.to_dict(), null, {"xp": 0}
	)
	var url := "ws://127.0.0.1:%d" % _server.listener.port()
	assert_bool(await night.start_remote(url, Night.Mode.MANUAL, 60.0, link)).is_true()
	_nights.append(night)
	return night


func _hear(night: Night) -> Array[Dictionary]:
	var heard: Array[Dictionary] = []
	night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == PosterSets.DONE:
				heard.append(event)
	)
	return heard


func test_the_seat_that_finished_a_set_has_it_on_its_report_and_the_others_do_not() -> void:
	await _start()
	var ann := await _client("ann")
	var bo := await _client("bo")
	var cy := await _client("cy")
	var di := await _client("di")
	var heard := [ann, bo, cy, di].map(func(n: Night) -> Array[Dictionary]: return _hear(n))
	(
		assert_bool(
			await _until(
				func() -> bool: return _server.room_of_match(MATCH).server.challenges.follows(4)
			)
		)
		. is_true()
	)
	# Ann alone kills: three kills finish the six feats, and the set with the last.
	var rules := _server.room_of_match(MATCH).server.rules
	rules.apply(RulesAction.skip_break())
	var kills := 0
	var began := Time.get_ticks_msec()
	while kills < 6 and Time.get_ticks_msec() - began < 60000:
		await get_tree().physics_frame
		for zombie_id in rules.zombie_ids():
			if kills < 6:
				RulesFixture.kill(rules, 1, zombie_id, RulesAction.ZONE_HEAD)
				kills += 1
	assert_int(kills).is_equal(6)
	assert_bool(await _until(func() -> bool: return not (heard[0] as Array).is_empty())).is_true()
	# Every client heard it, once, for seat 1.
	for told: Array[Dictionary] in heard:
		assert_int(told.size()).is_equal(1)
		assert_int(told[0]["player_id"]).is_equal(1)
		assert_str(told[0]["id"]).is_equal("small")
	# Ann's report names it with its title and its prize; the others' reports do not.
	var sets: Array = ann.report.model()["sets"]
	assert_int(sets.size()).is_equal(1)
	assert_str(sets[0]["title"]).is_equal("Small Feature")
	assert_str(sets[0]["card"]).is_equal("fifty_foot_feature")
	assert_str(sets[0]["emblem"]).is_equal("live_wire")
	for other: Night in [bo, cy, di]:
		assert_array(other.report.model()["sets"]).is_empty()
	# The card says it.
	var card := HudNightReport.new()
	add_child(card)
	card.show_report(ann.report.model())
	assert_array(card.sets_text).is_equal(
		[["SMALL FEATURE", "WON: FIFTY-FOOT FEATURE + LIVE WIRE"]]
	)
	card.free()
