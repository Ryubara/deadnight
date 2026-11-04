extends GdUnitTestSuite
## The challenge boards a game server follows (#1076): a seat's board is asked for once and never
## waited for, a seat without one is not followed or written, a finished challenge is said once with
## its reward and paid once, the server counts a night exactly as a client's tracker does, and a
## board that moved goes into the next report.

const DAY := 20401
const FUEL: Array[StringName] = [&"fuel_can"]

var _rules: GameRules
var _xp: XpAward
var _award: ChallengeAward
var _told: Array[Dictionary] = []
var _kills_made := 0


## A night of `players` (ids 1..n), the first `accounts` of which hold one.
func _night(players: int, accounts: Array[int]) -> void:
	_told = []
	_kills_made = 0
	_rules = RulesFixture.make_rules(players)
	_xp = XpAward.new(FUEL, ChallengeFixture.clock_on(DAY))
	_award = ChallengeAward.new(_xp, FUEL)
	_award.catalog = ChallengeFixture.quick_catalog()
	_award.clock = ChallengeFixture.clock_on(DAY)
	_rules.event_emitted.connect(_xp.observe)
	_rules.event_emitted.connect(_award.observe)
	for id in accounts:
		_xp.register(id, "user-%d" % id, 0, 0)
		assert_bool(_award.seat(id, "user-%d" % id)).is_true()


func _with_board(id: int) -> void:
	_award.arrived("user-%d" % id, 404, ChallengeAward.NO_BOARD)


func _say() -> Array[Dictionary]:
	var said := _award.take_events()
	_told.append_array(said)
	return said


func _of(type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in _told:
		if event["type"] == type:
			found.append(event)
	return found


## Plays the night on, `killer` shooting each zombie in the head, until `count` are dead (rounds
## are skipped through).
## The hundredths of XP the challenges paid since this was last asked, as the seat is told them.
func _challenge_hundredths() -> int:
	var total := 0
	for event in _xp.end_tick(true):
		total += int((event["sources"] as Dictionary).get(XpAward.CHALLENGE, 0))
	return total


func _head_kills(killer: int, count: int) -> void:
	if _rules.phase == GameRules.Phase.IDLE:
		RulesFixture.into_round_one(_rules)
	var made := _kills_made
	for _i in 6000:
		if _rules.phase == GameRules.Phase.BREAK:
			_rules.apply(RulesAction.skip_break())
		_rules.apply(RulesAction.tick(RulesFixture.STEP))
		for zombie_id in _rules.zombie_ids():
			if made < _kills_made + count:
				RulesFixture.kill(_rules, killer, zombie_id, RulesAction.ZONE_HEAD)
				made += 1
		if made >= _kills_made + count:
			break
	_kills_made = made


func test_a_seats_board_is_asked_for_once_and_the_seat_is_not_followed_until_it_comes() -> void:
	_night(2, [1])
	assert_bool(_award.follows(1)).is_false()
	# Sitting down again, or the same account in another seat, asks for nothing more.
	assert_bool(_award.seat(1, "user-1")).is_false()
	_head_kills(1, 4)
	assert_array(_say()).is_empty()
	var none: Array[Dictionary] = []
	_award.fill_report(none)
	assert_array(none).is_empty()
	_with_board(1)
	assert_bool(_award.follows(1)).is_true()
	assert_bool(_award.seat(1, "user-1")).is_false()


func test_a_seat_whose_board_did_not_come_is_never_followed_or_written() -> void:
	_night(1, [1])
	# No answer in time, the backend down, a board a newer game wrote: the night goes on without it.
	_award.arrived("user-1", 0, null)
	_award.arrived("user-1", 500, null)
	_award.arrived("user-1", 200, {"revision": 3, "schemaVersion": 9, "data": {}})
	_award.arrived("user-1", 200, {"revision": 3, "schemaVersion": 1, "data": "damaged"})
	# A 404 that is not the backend's "no board yet": a backend from before the route, a wrong
	# address. It must not start a fresh board that a report would write over the real one.
	_award.arrived("user-1", 404, null)
	_award.arrived(
		"user-1",
		404,
		{"message": "Route GET:/x not found", "error": "Not Found", "statusCode": 404}
	)
	assert_bool(_award.follows(1)).is_false()
	_head_kills(1, 8)
	assert_array(_say()).is_empty()
	var entries: Array[Dictionary] = []
	_award.fill_report(entries)
	assert_array(entries).is_empty()
	# It is not asked for again this night: the account stays unfollowed.
	assert_bool(_award.seat(1, "user-1")).is_false()


func test_a_board_the_backend_holds_is_followed_from_where_it_was() -> void:
	_night(1, [1])
	var held := ChallengeProfile.fresh()
	held.refresh(_award.catalog, DAY)
	held.apply(_award.catalog, ChallengeStats.KILLS, 3, 3)
	var envelope: Dictionary = JSON.parse_string(ChallengeSave.to_json(held))
	_award.arrived("user-1", 200, envelope)
	_head_kills(1, 1)
	_say()
	# Three kills held plus one more: the daily of four is done.
	var ids := _of(ChallengeAward.DONE).map(func(e: Dictionary) -> StringName: return e["id"])
	assert_array(ids).contains([&"d_kills"])


func test_progress_is_said_at_quarter_marks_and_a_finish_once_with_its_reward() -> void:
	_night(1, [1])
	_with_board(1)
	_head_kills(1, 8)
	_say()
	var kills := _of(ChallengeAward.PROGRESS).filter(
		func(e: Dictionary) -> bool: return e["id"] == &"d_kills"
	)
	# Four kills of a daily of four: the marks are 25, 50, 75 and 100 percent, and the fifth to eighth
	# kill say nothing about it.
	(
		assert_array(kills.map(func(e: Dictionary) -> int: return e["checkpoint"]))
		. is_equal([25, 50, 75, 100])
	)
	var done := _of(ChallengeAward.DONE).filter(
		func(e: Dictionary) -> bool: return e["id"] == &"d_kills"
	)
	assert_int(done.size()).is_equal(1)
	assert_int(done[0]["player_id"]).is_equal(1)
	assert_int(int(done[0]["reward"]["xp"])).is_equal(5)
	assert_int(done[0]["target"]).is_equal(4)
	# The ladder's last step is a finish too, its first only a step.
	var rungs := _of(ChallengeAward.PROGRESS).filter(
		func(e: Dictionary) -> bool: return e["id"] == &"m_kills"
	)
	assert_array(rungs.map(func(e: Dictionary) -> int: return e["rung"])).is_equal([1, 2])
	var finished_ids := _of(ChallengeAward.DONE).map(
		func(e: Dictionary) -> StringName: return e["id"]
	)
	assert_array(finished_ids).contains_exactly_in_any_order(
		[&"d_kills", &"d_head", &"d_round", &"m_kills", &"o_points"]
	)
	# Each reward is the seat's XP, from a source of its own.
	var gained := _xp.end_tick()
	var sources: Dictionary = gained[0]["sources"]
	assert_int(int(sources[XpAward.CHALLENGE])).is_equal(5 * 5 * XpRules.HUNDREDTHS)
	# More kills say nothing more about any of it.
	_told.clear()
	_head_kills(1, 2)
	_say()
	assert_array(_of(ChallengeAward.DONE)).is_empty()
	(
		assert_array(
			_of(ChallengeAward.PROGRESS).filter(
				func(e: Dictionary) -> bool: return e["id"] == &"d_kills"
			)
		)
		. is_empty()
	)


func test_the_server_finishes_what_a_clients_tracker_finishes_for_the_same_night() -> void:
	_night(2, [1, 2])
	_with_board(1)
	_with_board(2)
	# The client's tracker: the same catalogue, the same day, fresh boards, the events in order.
	var client := ChallengeTracker.new(_award.catalog, ChallengeFixture.clock_on(DAY))
	var profiles := {}
	for id in [1, 2]:
		profiles[id] = ChallengeProfile.fresh()
		client.follow(id, profiles[id])
		client.observe({"type": &"player_added", "player_id": id})
	var heard: Array[Dictionary] = []
	_rules.event_emitted.connect(
		func(event: Dictionary) -> void: heard.append_array(client.observe(event))
	)
	RulesFixture.into_round_one(_rules)
	for _i in 6000:
		_rules.apply(RulesAction.tick(RulesFixture.STEP))
		for zombie_id in _rules.zombie_ids():
			RulesFixture.kill(_rules, 1 + (zombie_id % 2), zombie_id, RulesAction.ZONE_HEAD)
		if _rules.phase == GameRules.Phase.BREAK:
			break
	_say()
	var theirs: Array[String] = []
	for advance in heard:
		if advance["completed"]:
			theirs.append("%d:%s" % [advance["player_id"], advance["id"]])
	var ours: Array[String] = []
	for event in _of(ChallengeAward.DONE):
		ours.append("%d:%s" % [event["player_id"], event["id"]])
	assert_int(ours.size()).is_greater(0)
	assert_array(ours).is_equal(theirs)
	# And the boards are the same boards.
	for id in [1, 2]:
		assert_dict(_award.profile_of("user-%d" % id).to_dict()).is_equal(profiles[id].to_dict())


func test_a_seat_that_leaves_and_comes_back_is_not_told_or_paid_twice() -> void:
	_night(3, [1])
	_with_board(1)
	_head_kills(1, 8)
	_say()
	var paid := _challenge_hundredths()
	var said := _of(ChallengeAward.DONE).size()
	assert_int(said).is_greater(0)
	_award.release(1)
	assert_bool(_award.follows(1)).is_false()
	# Back in another seat: the board of the night is kept, so nothing is read and nothing is said
	# again.
	assert_bool(_award.seat(3, "user-1")).is_false()
	assert_bool(_award.follows(3)).is_true()
	_head_kills(3, 2)
	_say()
	assert_int(_of(ChallengeAward.DONE).size()).is_equal(said)
	assert_int(_challenge_hundredths()).is_equal(0)
	assert_int(paid).is_greater(0)


func test_a_board_that_moved_goes_into_the_next_report_once() -> void:
	_night(2, [1, 2])
	_with_board(1)
	_with_board(2)
	_head_kills(1, 8)
	_say()
	# Seat 1 earned XP, seat 2 did nothing: the report is XpAward's entries with the boards on.
	var entries := _xp.take_report(true)
	_award.fill_report(entries)
	var mine: Dictionary = entries.filter(func(e: Dictionary) -> bool: return e["user"] == "user-1")[0]
	assert_array(mine["done"]).contains(["d_kills"])
	assert_int(int(mine["board"]["schemaVersion"])).is_equal(ChallengeSave.SCHEMA_VERSION)
	var data: Dictionary = mine["board"]["data"]
	assert_int(int(data["lifetime"]["kills"])).is_equal(8)
	assert_int(int(data["dealt_day"])).is_equal(DAY)
	# A board the backend can read back as the board it was.
	var back := ChallengeSave.from_envelope(mine["board"])
	assert_object(back["profile"]).is_not_null()
	# Taking it again says nothing: it has not moved.
	var again := _xp.take_report(true)
	_award.fill_report(again)
	(
		assert_array(
			again.filter(
				func(e: Dictionary) -> bool: return e.has("board") and e["user"] == "user-1"
			)
		)
		. is_empty()
	)


func test_a_board_that_moved_without_earning_xp_has_an_entry_of_its_own() -> void:
	_night(1, [1])
	_with_board(1)
	# Nothing earned yet, but the board was dealt for the day: it has to reach the backend.
	var entries: Array[Dictionary] = []
	_award.fill_report(entries)
	assert_int(entries.size()).is_equal(1)
	assert_str(entries[0]["user"]).is_equal("user-1")
	assert_int(entries[0]["xp"]).is_equal(0)
	assert_int(entries[0]["board"]["data"]["dealt_day"]).is_equal(DAY)
	entries.clear()
	_award.fill_report(entries)
	assert_array(entries).is_empty()


func test_a_seat_with_no_account_is_never_followed() -> void:
	_night(2, [1])
	assert_bool(_award.seat(2, "")).is_false()
	assert_bool(_award.follows(2)).is_false()
	assert_bool(_award.enabled).is_true()
	_award.enabled = false
	assert_bool(_award.seat(2, "user-2")).is_false()
