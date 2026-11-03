# Bots as a team (bots plan, phase 5), in the real lot with the real server: the callouts reach the
# feed's event (a `bot_say`) and name only a zombie the bot made out, and the errands go one bot at
# a time. Ticks are run by hand.
extends GdUnitTestSuite

const STEP := Night.STEP
const TICKS_PER_SECOND := 60
const SEED := 53
## A break longer than any test.
const LONG_BREAK := 3000.0
## Physics frames the navigation server is given to take the mesh in (twelve was not always enough
## on a busy machine: a bot that finds no way to a stand leaves it alone for three minutes).
const SETTLE_FRAMES := 60
## Where the boss is put, in metres from the bot, and how fast it walks (m/s).
const BOSS_DISTANCE := 13.0
const BOSS_SPEED := 0.5

var _catcher := ErrorCatcher.new()
var _said: Array[Dictionary] = []


func after_test() -> void:
	_catcher.stop()


func _home() -> Vector3:
	return Autopilot.HOME


func _bot(night: SeatedNight, id: int) -> BotClient:
	for candidate in night.host.bots:
		if candidate.state.player_id == id:
			return candidate
	return null


# --- The callouts ---


## A night with one bot at home that does not walk, one zombie to a round, past the first break;
## the lines the bot says are kept in `_said`.
func _lone() -> SeatedNight:
	var profile := BotProfile.regular()
	profile.follows = false
	profile.retreat_margin = 0.0
	profile.boss_keep = 0.0
	var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), SEED)
	night.seat(1, profile, SEED + 1)
	night.start_round()
	night.server.body_of(1).teleport(_home() + Vector3(0.0, 0.1, 0.0))
	_said.clear()
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"bot_say":
			_said.append(event)
	night.run(5)
	_catcher.start()
	return night


## The headliner, as the roster makes it, `BOSS_DISTANCE` metres from the bot toward `side` (-1 in
## front of it, 1 behind), walking slowly.
func _put_the_boss(night: SeatedNight, side: float) -> ZombieBody:
	var at := _home() + Vector3(0.0, 0.0, side * BOSS_DISTANCE)
	var boss := night.drop_zombie(at, BOSS_SPEED)
	var type := night.server.rules.tuning.roster.type_of(&"headliner")
	boss.profile = ZombieProfile.from_type(type, &"headliner", night.server.sim.tuning)
	boss.speed = BOSS_SPEED
	return boss


func test_a_bot_calls_out_the_boss_it_sees_and_names_it() -> void:
	var night := await _lone()
	night.hold_fire = true
	var boss := _put_the_boss(night, -1.0)
	night.run(5 * TICKS_PER_SECOND)
	var lines := _said.filter(func(e: Dictionary) -> bool: return e["line"] == &"boss_coming")
	assert_int(lines.size()).is_equal(1)
	assert_int(lines[0]["subject"]).is_equal(boss.id)
	assert_int(lines[0]["player_id"]).is_equal(1)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_bot_does_not_name_a_boss_behind_it_that_it_has_not_made_out() -> void:
	var night := await _lone()
	night.hold_fire = true
	_put_the_boss(night, 1.0)
	night.run(8 * TICKS_PER_SECOND)
	(
		assert_array(_said.filter(func(e: Dictionary) -> bool: return e["line"] == &"boss_coming"))
		. is_empty()
	)
	for event in _said:
		assert_bool(BotSay.ABOUT_A_ZOMBIE.has(event["line"])).is_false()
	night.dispose()


func test_every_line_of_a_busy_night_is_in_the_set_and_none_comes_twice_in_four_seconds() -> void:
	var night := await NightFixture.seat(self, 4, SeatedNight.brisk(), SEED)
	for id in range(1, 5):
		night.seat(id, BotProfile.regular(), SEED + id)
	night.gather()
	_said.clear()
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"bot_say":
			_said.append(event)
	night.start_round()
	_catcher.start()
	var ticks := 120 * TICKS_PER_SECOND
	var last := {}
	var worst_gap := INF
	for _i in ticks:
		night.tick()
		for event in night.last_events:
			if event["type"] != &"bot_say":
				continue
			var who: int = event["player_id"]
			if last.has(who):
				worst_gap = minf(worst_gap, float(night.server.tick_count - last[who]) / 60.0)
			last[who] = night.server.tick_count
	for event in _said:
		assert_bool(BotSay.is_line(event["line"])).is_true()
		assert_str(BotSay.text_of(event["line"])).is_not_empty()
	assert_float(worst_gap).is_greater_equal(BotCallouts.GAP_URGENT - 0.1)
	# Under a line per bot per ten seconds.
	assert_float(float(_said.size()) / (4.0 * 120.0 / 10.0)).is_less(1.0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_the_server_refuses_a_line_that_is_not_in_the_set() -> void:
	var night := await _lone()
	(
		assert_bool(night.server.say(1, {"line": &"insult", "subject": -1, "pos": Vector3.ZERO}))
		. is_false()
	)
	(
		assert_bool(night.server.say(9, {"line": &"thanks", "subject": -1, "pos": Vector3.ZERO}))
		. is_false()
	)
	(
		assert_bool(night.server.say(1, {"line": &"thanks", "subject": -1, "pos": Vector3.ZERO}))
		. is_true()
	)
	night.dispose()


# --- One bot at a time on an errand ---


func test_the_errands_go_one_bot_at_a_time_and_the_others_still_get_their_turn() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, 3, tuning, SEED, true)
	for id in range(1, 4):
		night.seat(id, BotProfile.regular(), SEED + id)
		night.server.rules.players[id].points = 3000
	night.gather()
	await night.settle(SETTLE_FRAMES)
	_catcher.start()
	var most := 0
	var seen: Dictionary = {}
	for _i in 90 * TICKS_PER_SECOND:
		night.tick()
		var on := 0
		for bot in night.host.bots:
			if (bot.brain as BotFightBrain).on_errand:
				on += 1
				seen[bot.state.player_id] = true
		most = maxi(most, on)
	assert_int(most).is_equal(1)
	assert_int(seen.size()).is_greater_equal(2)
	var spent := 0
	for id in range(1, 4):
		spent += night.server.rules.players[id].points_spent
	assert_int(spent).is_greater(0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- A person's ping ---


func test_a_person_marks_a_place_and_the_nearest_bot_goes_and_holds_it() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = LONG_BREAK
	var night := await NightFixture.seat(self, 3, tuning, SEED)
	night.human(1)
	night.seat(2, BotProfile.regular(), SEED + 2)
	night.seat(3, BotProfile.regular(), SEED + 3)
	night.start_round()
	night.server.body_of(1).teleport(_home() + Vector3(0.0, 0.1, 0.0))
	night.server.body_of(2).teleport(_home() + Vector3(-3.0, 0.1, -2.0))
	night.server.body_of(3).teleport(_home() + Vector3(9.0, 0.1, 4.0))
	await night.settle(SETTLE_FRAMES)
	night.run(30)
	_catcher.start()
	var spot := NavigationServer3D.map_get_closest_point(
		night.world.map(), _home() + Vector3(-9.0, 0.0, -12.0)
	)
	var answer := night.server.ping(1, {"kind": PingBoard.HERE, "pos": spot, "subject": 0})
	assert_str(answer).is_equal("")
	night.run(14 * TICKS_PER_SECOND)
	var first := night.server.body_of(2).global_position
	var second := night.server.body_of(3).global_position
	assert_float(Vector2(first.x - spot.x, first.z - spot.z).length()).is_less(4.0)
	assert_float(Vector2(second.x - spot.x, second.z - spot.z).length()).is_greater(6.0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- Roles ---


func test_with_a_person_and_three_bots_one_bot_flanks_and_the_others_stay_with_the_person() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, 4, tuning, SEED)
	night.human(1)
	for id in range(2, 5):
		var profile := BotProfile.regular()
		profile.errands = false
		night.seat(id, profile, SEED + id)
	night.gather()
	await night.settle(SETTLE_FRAMES)
	_catcher.start()
	# The roles are Follow's: the person gives that order (the default is to roam).
	night.give_order(BotOrders.FOLLOW, 1, night.server.body_of(1).global_position)
	night.run(25 * TICKS_PER_SECOND)
	var flanks: Array[int] = []
	for bot in night.host.bots:
		if (bot.brain as BotFightBrain).role == BotRoles.Role.FLANK:
			flanks.append(bot.state.player_id)
	assert_int(flanks.size()).is_equal(1)
	var person := night.server.body_of(1).global_position
	for bot in night.host.bots:
		var at := night.server.body_of(bot.state.player_id).global_position
		var apart := Vector2(at.x - person.x, at.z - person.z).length()
		if flanks.has(bot.state.player_id):
			assert_float(apart).is_between(5.0, 18.0)
		else:
			assert_float(apart).is_less(12.0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()
