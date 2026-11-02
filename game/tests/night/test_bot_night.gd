# Hosted bots in a real night (bots plan, phase 1): four seats on one server, the bots reading only
# what a client reads and sending only commands through `apply`. Scenarios 1 to 3 (a walker is shot
# after the reaction floor; one behind a wall is never believed; one from behind a car is believed
# only after the delay), 24 (a replay of a bot night gives the same state) and 26 (the cost of a
# decision with 46 zombies). The soak is in `test_bot_soak.gd`. Ticks are run by hand; nothing waits
# on the clock except the cost measurement, which is about time by definition.
extends GdUnitTestSuite

const STEP := Night.STEP
const TICKS_PER_SECOND := 60
## The floor of the first shot after the first clear ray, in ticks: 0.20 s and one tick.
const FLOOR_TICKS := 13
## A walker 14 m down the field from where the bot stands: open ground.
const AVENUE := Vector3(0.0, 0.0, -14.0)
## A spot 8 m to the side of home, behind the wall that stands 4.5 m from it.
const BEHIND_THE_WALL := Vector3(-8.0, 0.0, 0.0)
## Looking at the wall (yaw +90 degrees faces -x), and away from it.
const FACING_THE_WALL := PI / 2.0
const FACING_AWAY := -PI / 2.0
## Zombies on the lot at the top of the cost measurement: the alive cap at four players.
const CROWD := 46
const THINK_BUDGET_US := 500
## What `_reference_us` takes on the machine the budget was set on (microseconds, best of five).
## On a slower machine the budget grows by the same ratio: the budget is a statement about the
## bot's work, not about the runner.
const REFERENCE_US := 130
## Steps and spacing of the replay check.
const REPLAY_STEPS := 900
const REPLAY_EVERY := 100
const SEED := 4242


## A night with one bot at home and one zombie to a round.
func _lone(profile: BotProfile, bot_seed: int) -> SeatedNight:
	var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), 5)
	night.seat(1, profile, bot_seed)
	night.server.rules.apply(RulesAction.skip_break())
	night.server.body_of(1).teleport(Autopilot.HOME + Vector3(0.0, 0.1, 0.0))
	night.run(5)
	return night


func _home() -> Vector3:
	return Autopilot.HOME


## Whether a person standing where the bot does could see the zombie now: inside the view cone,
## inside the range and with a clear ray to its chest or head. The same question the bot's
## perception asks, asked from outside with the truth.
func _could_see(night: SeatedNight, bot: BotClient, zombie: ZombieBody) -> bool:
	var here := night.server.body_of(1).global_position
	var eye := here + Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)
	var offset := zombie.position - here
	var bearing := atan2(-offset.x, -offset.z)
	var half := deg_to_rad(bot.profile.view_degrees) * 0.5
	if absf(angle_difference(bot.motor.yaw, bearing)) > half:
		return false
	if Vector2(offset.x, offset.z).length() > night.level.view_range(zombie.position, 1):
		return false
	return (
		night.level.clear(eye, zombie.position + Vector3(0.0, BotLevel.CHEST_HEIGHT, 0.0))
		or night.level.clear(eye, zombie.position + Vector3(0.0, BotLevel.HEAD_HEIGHT, 0.0))
	)


func test_scenario_1_a_walker_is_shot_dead_and_not_before_the_reaction_floor() -> void:
	var night := await _lone(BotProfile.regular(), 17)
	var bot := night.host.bots[0]
	var shots: Array[int] = []
	var kills: Array[int] = []
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"shot_fired":
			shots.append(night.server.tick_count)
		elif event["type"] == &"zombie_removed" and event["cause"] == &"killed":
			kills.append(night.server.tick_count)
	var zombie := night.drop_zombie(_home() + AVENUE)
	assert_bool(_could_see(night, bot, zombie)).is_true()
	var first_clear := night.server.tick_count
	for _i in 20 * TICKS_PER_SECOND:
		night.tick()
		if not kills.is_empty():
			break
	assert_int(kills.size()).is_equal(1)
	assert_int(shots.size()).is_greater(0)
	assert_int(shots[0] - first_clear).is_greater_equal(FLOOR_TICKS)
	assert_float(night.frame["players"][1]["health"]).is_equal(100.0)
	night.on_event = Callable()
	night.dispose()


func test_scenario_2_a_walker_behind_a_wall_is_never_believed_or_aimed_at() -> void:
	for facing in [FACING_AWAY, FACING_THE_WALL]:
		var night := await _lone(BotProfile.veteran(), 18)
		var bot := night.host.bots[0]
		var zombie := night.drop_zombie(_home() + BEHIND_THE_WALL, 0.0)
		bot.motor.face(facing)
		# The premise: the wall really hides it, chest and head.
		var eye := _home() + Vector3(0.0, 0.1 + BotLevel.EYE_HEIGHT, 0.0)
		assert_bool(night.level.clear(eye, zombie.position + Vector3(0, 1.1, 0))).is_false()
		assert_bool(night.level.clear(eye, zombie.position + Vector3(0, 1.6, 0))).is_false()
		var aimed := 0
		var shots: Array[int] = []
		night.on_event = func(event: Dictionary) -> void:
			if event["type"] == &"shot_fired":
				shots.append(1)
		for _i in 600:
			night.tick()
			if bot.perception.beliefs.contacts.has(zombie.id) or bot.motor.target_id == zombie.id:
				aimed += 1
		assert_int(aimed).is_equal(0)
		assert_int(shots.size()).is_equal(0)
		night.on_event = Callable()
		night.dispose()


func test_scenario_3_a_walker_from_behind_cover_is_believed_only_after_the_delay() -> void:
	var night := await _lone(BotProfile.regular(), 19)
	var bot := night.host.bots[0]
	var zombie := night.drop_zombie(_home() + BEHIND_THE_WALL)
	bot.motor.face(FACING_THE_WALL)
	var first_clear := -1
	var believed := -1
	for _i in 30 * TICKS_PER_SECOND:
		night.tick()
		if first_clear < 0 and _could_see(night, bot, zombie):
			first_clear = night.server.tick_count
		var here := night.server.body_of(1).global_position
		if believed < 0 and not bot.perception.beliefs.targets(here).is_empty():
			believed = night.server.tick_count
		if believed >= 0:
			break
	assert_int(first_clear).is_greater(0)
	assert_int(believed).is_greater(0)
	assert_int(believed - first_clear).is_greater_equal(FLOOR_TICKS)
	# And before it was believed, it was not shot at.
	var contact := bot.perception.beliefs.contact(zombie.id)
	assert_float(contact["believed_at"] - contact["first_seen"]).is_greater_equal(0.2)
	night.dispose()


func test_scenario_24_a_replay_of_a_bot_night_gives_the_same_state() -> void:
	var live := await _four_standing_bots(true)
	live.hash_every = REPLAY_EVERY
	live.run(REPLAY_STEPS)
	var recorded := live.recorded
	var live_hashes := live.hashes
	var commands := recorded.size()
	var shots := 0
	for bot in live.host.bots:
		shots += bot.state.shots
	live.dispose()
	var replayed := await NightFixture.seat(self, 4, SeatedNight.brisk(), SEED)
	replayed.stage_the_dead = true
	replayed.gather()
	replayed.server.rules.apply(RulesAction.skip_break())
	var replay_hashes := replayed.replay(recorded, REPLAY_STEPS, REPLAY_EVERY)
	replayed.dispose()
	assert_int(commands).is_equal(4 * REPLAY_STEPS)
	# There was a fight in it: the hashes are about more than standing still.
	assert_int(shots).is_greater(10)
	assert_array(live_hashes).has_size(REPLAY_STEPS / REPLAY_EVERY)
	assert_array(replay_hashes).is_equal(live_hashes)


func _four_standing_bots(recording: bool) -> SeatedNight:
	var night := await NightFixture.seat(self, 4, SeatedNight.brisk(), SEED)
	night.recording = recording
	night.stage_the_dead = true
	# They stand and fight: a body that walks is moved by the physics engine, which does not repeat
	# to the last bit from one run to the next, and a fight amplifies a hair into a different night.
	var stand := BotProfile.regular()
	stand.retreat_margin = 0.0
	for id in range(1, 5):
		night.seat(id, stand, SEED + id)
	night.gather()
	night.server.rules.apply(RulesAction.skip_break())
	return night


func test_scenario_26_a_decision_with_the_whole_crowd_in_view_costs_under_half_a_millisecond(
) -> void:
	var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), 5)
	var bot := night.seat(1, BotProfile.regular(), 23)
	night.server.rules.apply(RulesAction.skip_break())
	night.server.body_of(1).teleport(_home() + Vector3(0.0, 0.1, 0.0))
	night.run(3)
	# 46 zombies that do not move, spread over the field around the bot, in view and out of it.
	var spread := RandomNumberGenerator.new()
	spread.seed = 5
	for id in range(1000, 1000 + CROWD):
		var around := spread.randf_range(-PI, PI)
		var distance := spread.randf_range(4.0, 22.0)
		var zombie := night.server.sim.spawn(
			id, 0.0, _home() + Vector3(-sin(around), 0.0, -cos(around)) * distance
		)
		zombie.enter(ZombieBody.Mode.CHASE)
	night.tick()
	assert_int(night.server.sim.zombies.size()).is_greater_equal(CROWD)
	# The frame the bots would get, fed again and again with the bot deciding on each: no server
	# step between, so the measurement is the bot's own work (the look and its rays, the thought,
	# the hands). The best of three batches, so a busy machine does not decide the result.
	var best := 1 << 30
	var frame := night.frame
	for _batch in 3:
		bot.telemetry = BotTelemetry.new()
		for _i in 3000:
			bot.hear([frame])
			bot.decide(STEP)
		best = mini(best, bot.telemetry.think_us(0.99))
		assert_int(bot.perception.rays_last).is_less_equal(bot.profile.rays_per_think)
	assert_int(bot.telemetry.counters[&"thinks"]).is_greater(300)
	var slower := maxf(float(_reference_us()) / float(REFERENCE_US), 1.0)
	(
		assert_float(float(best))
		. override_failure_message(
			(
				"a think at p99 took %d us, budget %d us (machine %.2f times the reference)"
				% [best, THINK_BUDGET_US * slower, slower]
			)
		)
		. is_less(float(THINK_BUDGET_US) * slower)
	)
	night.dispose()


## A fixed piece of plain GDScript (dictionaries of 46 entries read 20 times): how fast this
## machine runs the kind of work a think does. The best of five runs.
func _reference_us() -> int:
	var best := 1 << 30
	for _run in 5:
		var began := Time.get_ticks_usec()
		var table := {}
		for i in CROWD:
			table[i] = {"id": i, "position": Vector3(i, 0.0, -i), "mode": 1}
		var total := 0.0
		for _pass in 20:
			for id in table:
				var entry: Dictionary = table[id]
				var at: Vector3 = entry["position"]
				total += Vector2(at.x, at.z).length() + float(entry["mode"])
		assert_float(total).is_greater(0.0)
		best = mini(best, Time.get_ticks_usec() - began)
	return best
