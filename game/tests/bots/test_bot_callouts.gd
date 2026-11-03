# What a bot says (bots plan, phase 5): the lines are an enumerated set with cooldowns of 20 to 60
# seconds, a bot has one gap between two lines, a line about a zombie is refused unless the bot
# believes in that zombie, and however long the trouble lasts the bot says less than one line in ten
# seconds. The server's gate (`SayBoard`) refuses a line that is not in the set.
extends GdUnitTestSuite

const HERE := Vector3.ZERO
const STEP := 0.125


func _zombie(
	beliefs: BotBeliefs, id: int, at: Vector3, look: StringName, believed_at := 0.0
) -> void:
	beliefs.contacts[id] = {
		"id": id,
		"position": at,
		"velocity": Vector3.ZERO,
		"mode": ZombieBody.Mode.CHASE,
		"look": look,
		"believed_at": believed_at,
		"last_seen": 0.0,
		"visible": true,
	}


func _me(health := 100.0) -> Dictionary:
	return {"pos": HERE, "health": health, "arms": {&"pistol": [10, 60, 0]}}


func test_every_line_has_words_and_a_cooldown_of_twenty_to_sixty_seconds() -> void:
	assert_int(BotSay.LINES.size()).is_greater_equal(10)
	for line: StringName in BotSay.LINES:
		assert_str(BotSay.text_of(line)).is_not_empty()
		assert_float(BotSay.cooldown_of(line)).is_between(20.0, 60.0)
	for line in BotSay.ABOUT_A_ZOMBIE:
		assert_bool(BotSay.is_line(line)).is_true()
	assert_bool(BotSay.is_line(&"insult")).is_false()


func test_a_line_waits_its_cooldown_and_any_line_waits_the_gap() -> void:
	var callouts := BotCallouts.new()
	assert_bool(callouts.say(BotSay.RELOADING, 0.0, []).is_empty()).is_false()
	assert_bool(callouts.say(BotSay.RELOADING, 29.0, []).is_empty()).is_true()
	assert_bool(callouts.say(BotSay.RELOADING, 31.0, []).is_empty()).is_false()
	# A different line right after is held back by the gap.
	assert_bool(callouts.say(BotSay.DOOR_BOUGHT, 32.0, []).is_empty()).is_true()
	var fresh := BotCallouts.new()
	fresh.say(BotSay.DOOR_BOUGHT, 0.0, [])
	assert_bool(fresh.say(BotSay.THANKS, BotCallouts.GAP - 1.0, []).is_empty()).is_true()
	assert_bool(fresh.say(BotSay.THANKS, BotCallouts.GAP + 0.1, []).is_empty()).is_false()


func test_an_urgent_line_waits_a_shorter_gap() -> void:
	var callouts := BotCallouts.new()
	callouts.say(BotSay.DOOR_BOUGHT, 0.0, [])
	var soon := BotCallouts.GAP_URGENT + 0.1
	assert_bool(callouts.say(BotSay.COVER_ME, soon, []).is_empty()).is_false()


func test_no_more_than_two_lines_in_a_window_whatever_the_gaps() -> void:
	var callouts := BotCallouts.new()
	var spoken := 0
	for line in [BotSay.COVER_ME, BotSay.TRAPPED, BotSay.REVIVING, BotSay.HELP]:
		var at := float(spoken) * 6.0
		if not callouts.say(line, at, []).is_empty():
			spoken += 1
	assert_int(spoken).is_equal(BotCallouts.WINDOW_LINES)
	assert_bool(callouts.say(BotSay.THANKS, BotCallouts.WINDOW + 1.0, []).is_empty()).is_false()


func test_a_line_about_a_zombie_is_refused_unless_the_bot_believes_in_it() -> void:
	var callouts := BotCallouts.new()
	assert_bool(callouts.say(BotSay.BOSS_COMING, 0.0, [4, 5], 9).is_empty()).is_true()
	assert_int(callouts.refused_unseen).is_equal(1)
	var action := callouts.say(BotSay.BOSS_COMING, 1.0, [4, 5, 9], 9)
	assert_int(action["subject"]).is_equal(9)
	assert_int(callouts.refused_unseen).is_equal(1)


func test_a_boss_still_in_its_reaction_time_is_not_called() -> void:
	var beliefs := BotBeliefs.new()
	beliefs.now = 1.0
	_zombie(beliefs, 7, Vector3(0, 0, -15), &"headliner", 1.4)
	var callouts := BotCallouts.new()
	var profile := BotProfile.regular()
	assert_bool(callouts.plan(beliefs, _me(), profile, false, false, true).is_empty()).is_true()
	beliefs.now = 1.5
	var action := callouts.plan(beliefs, _me(), profile, false, false, true)
	assert_str(action["line"]).is_equal("boss_coming")
	assert_int(action["subject"]).is_equal(7)


func test_three_runners_in_sight_are_called_with_the_nearest_named() -> void:
	var beliefs := BotBeliefs.new()
	beliefs.now = 1.0
	for i in 3:
		_zombie(beliefs, 10 + i, Vector3(0, 0, -20 + float(i) * 3.0), &"runner")
	var action := BotCallouts.new().plan(beliefs, _me(), BotProfile.regular(), false, false, true)
	assert_str(action["line"]).is_equal("runners")
	assert_int(action["subject"]).is_equal(12)


func test_moments_become_lines_and_are_used_up() -> void:
	var beliefs := BotBeliefs.new()
	beliefs.now = 5.0
	beliefs.moments.append({"kind": &"revived"})
	var callouts := BotCallouts.new()
	var action := callouts.plan(beliefs, _me(), BotProfile.regular(), false, false, true)
	assert_str(action["line"]).is_equal("thanks")
	assert_array(beliefs.moments).is_empty()
	# Only the bot that speaks for the team talks about the generator.
	beliefs.now = 40.0
	beliefs.moments.append({"kind": &"fuel_low"})
	(
		assert_bool(
			callouts.plan(beliefs, _me(), BotProfile.regular(), false, false, false).is_empty()
		)
		. is_true()
	)
	beliefs.moments.append({"kind": &"fuel_low"})
	(
		assert_str(callouts.plan(beliefs, _me(), BotProfile.regular(), false, false, true)["line"])
		. is_equal("low_fuel")
	)


func test_a_downed_bot_calls_for_help_once() -> void:
	var beliefs := BotBeliefs.new()
	beliefs.now = 3.0
	var callouts := BotCallouts.new()
	assert_str(callouts.downed(beliefs, _me())["line"]).is_equal("help")
	beliefs.now = 10.0
	assert_bool(callouts.downed(beliefs, _me()).is_empty()).is_true()
	callouts.up()
	beliefs.now = 100.0
	assert_bool(callouts.downed(beliefs, _me()).is_empty()).is_false()


func test_under_every_kind_of_trouble_a_bot_says_less_than_a_line_in_ten_seconds() -> void:
	var beliefs := BotBeliefs.new()
	var callouts := BotCallouts.new()
	var profile := BotProfile.regular()
	for i in 4:
		_zombie(beliefs, 20 + i, Vector3(0, 0, -10 + float(i)), &"runner")
	_zombie(beliefs, 30, Vector3(0, 0, -12), &"headliner")
	for i in 3:
		_zombie(beliefs, 40 + i, Vector3(0.5 * float(i), 0, -1.5), &"walker")
	var now := 0.0
	var seconds := 900.0
	var times: Array[float] = []
	while now < seconds:
		beliefs.now = now
		beliefs.moments.append({"kind": &"door_bought"})
		beliefs.moments.append({"kind": &"breach_open"})
		beliefs.moments.append({"kind": &"revived"})
		var action := callouts.plan(beliefs, _me(40.0), profile, int(now) % 7 == 0, true, true)
		if not action.is_empty():
			times.append(now)
		now += STEP
	assert_int(times.size()).is_greater(10)
	assert_float(float(times.size()) / (seconds / 10.0)).is_less(1.0)
	for i in range(1, times.size()):
		assert_float(times[i] - times[i - 1]).is_greater_equal(BotCallouts.GAP_URGENT - 0.001)


func test_the_server_refuses_a_line_that_is_not_in_the_set_and_one_that_comes_too_soon() -> void:
	var board := SayBoard.new()
	assert_bool(board.say(2, &"insult", -1, HERE).is_empty()).is_true()
	var event := board.say(2, BotSay.RELOADING, -1, HERE)
	assert_str(event["type"]).is_equal("bot_say")
	assert_bool(board.say(2, BotSay.THANKS, -1, HERE).is_empty()).is_true()
	assert_bool(board.say(3, BotSay.THANKS, -1, HERE).is_empty()).is_false()
	board.step(board.gap + 0.1)
	assert_bool(board.say(2, BotSay.THANKS, -1, HERE).is_empty()).is_false()
	assert_bool(board.say(4, BotSay.THANKS, -1, Vector3(INF, 0, 0)).is_empty()).is_true()
