# What a bot does about a person's ping (bots plan, phase 5): only people's marks count, "hold here"
# sends the one nearest bot, "enemy" names the first target, "downed" names who to raise first.
extends GdUnitTestSuite

const HERE := Vector3.ZERO


func _frame(marks: Dictionary) -> Dictionary:
	return {"pings": marks}


func _mark(kind: StringName, pos := Vector3.ZERO, subject: Variant = 0) -> Dictionary:
	return {"kind": kind, "pos": pos, "subject": subject, "left": 15.0}


func _crew() -> Dictionary:
	return {
		1: {"bot": false},
		2: {"bot": true},
		3: {"bot": true},
	}


func _bot_at(id: int, at: Vector3) -> Dictionary:
	return {"id": id, "pos": at, "bot": true}


func test_only_the_marks_of_people_are_read() -> void:
	var found := BotPings.marks(
		_frame({1: _mark(PingBoard.HERE, Vector3(5, 0, 0)), 2: _mark(PingBoard.HERE)}), _crew()
	)
	assert_int(found.size()).is_equal(1)
	assert_int(found[0]["from"]).is_equal(1)
	assert_array(BotPings.marks({}, _crew())).is_empty()


func test_the_nearest_bot_is_sent_to_hold_a_place_and_the_others_are_not() -> void:
	var found := BotPings.marks(_frame({1: _mark(PingBoard.HERE, Vector3(0, 0, -12))}), _crew())
	var mate: Array[Dictionary] = [_bot_at(3, Vector3(8, 0, 0))]
	var other: Array[Dictionary] = [_bot_at(2, Vector3(0, 0, -10))]
	assert_vector(BotPings.hold_place(found, 2, HERE, mate)).is_equal(Vector3(0, 0, -12))
	assert_vector(BotPings.hold_place(found, 3, Vector3(8, 0, 0), other)).is_equal(Vector3.INF)


func test_a_tie_goes_to_the_lowest_seat_and_a_bot_already_there_stays() -> void:
	var found := BotPings.marks(_frame({1: _mark(PingBoard.HERE, Vector3(0, 0, -12))}), _crew())
	var there := Vector3(0, 0, -11)
	var third: Array[Dictionary] = [_bot_at(3, there)]
	assert_vector(BotPings.hold_place(found, 2, there, third)).is_equal(Vector3.INF)
	var far := Vector3(0, 0, 6)
	var tied: Array[Dictionary] = [_bot_at(3, far)]
	assert_vector(BotPings.hold_place(found, 2, far, tied)).is_equal(Vector3(0, 0, -12))
	var second: Array[Dictionary] = [_bot_at(2, far)]
	assert_vector(BotPings.hold_place(found, 3, far, second)).is_equal(Vector3.INF)


func test_an_enemy_mark_names_the_zombie_only_when_it_is_in_sight() -> void:
	var found := BotPings.marks(_frame({1: _mark(PingBoard.ENEMY, Vector3.ZERO, 14)}), _crew())
	var in_sight: Array[Dictionary] = [{"id": 3}, {"id": 14}]
	var not_in_sight: Array[Dictionary] = [{"id": 3}]
	assert_int(BotPings.enemy(found, in_sight)).is_equal(14)
	assert_int(BotPings.enemy(found, not_in_sight)).is_equal(-1)


func test_a_downed_mark_names_who_to_raise() -> void:
	var found := BotPings.marks(_frame({1: _mark(PingBoard.DOWNED, Vector3.ZERO, 5)}), _crew())
	assert_int(BotPings.downed(found)).is_equal(5)
	assert_int(BotPings.downed(BotPings.marks({}, _crew()))).is_equal(0)


func test_a_pinged_body_is_raised_before_one_that_needs_it_more() -> void:
	var team := BotTeam.new()
	var revive := BotRevive.new(BotProfile.regular())
	revive.team = team
	revive.rounds = RoundTuning.new()
	var beliefs := BotBeliefs.new()
	beliefs.me = 2
	beliefs.now = 1.0
	beliefs.teammates = {
		2: {"id": 2, "pos": HERE, "downed": false, "dead": false, "bot": true, "health": 100.0},
		5: _body(5, Vector3(0, 0, -6), 40.0),
		6: _body(6, Vector3(0, 0, -8), 20.0),
	}
	var me: Dictionary = beliefs.teammates[2]
	var intent := BotIntent.new()
	revive.run(intent, beliefs, me, WeaponCatalog.get_def(&"pistol"), 1, 0.1)
	assert_int(revive.victim).is_equal(6)
	revive.reset()
	team.claims.release(2)
	revive.pinged = 5
	intent = BotIntent.new()
	revive.run(intent, beliefs, me, WeaponCatalog.get_def(&"pistol"), 1, 0.1)
	assert_int(revive.victim).is_equal(5)


func _body(id: int, at: Vector3, bleed: float) -> Dictionary:
	return {
		"id": id,
		"pos": at,
		"downed": true,
		"dead": false,
		"bot": false,
		"health": 0.0,
		"bleed": bleed,
		"reviver": 0,
		"revive": 0.0,
	}
