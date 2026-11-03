# The bot host (bots plan, phase 1, scenario 27): a brain that fails is switched off and the motor
# goes on alone, the raw zombie list stays behind the perception filter, the thinks follow the
# profile's rate and are spread over the seats, and the telemetry keeps the last decisions.
extends GdUnitTestSuite

const SECONDS := 10
const TICKS_PER_SECOND := 60


## A brain whose thought comes back empty, as the answer of a function that hit a script error does.
class EmptyBrain:
	extends BotBrain

	func think(_beliefs: BotBeliefs, _state: ClientState) -> BotIntent:
		return null


## A brain that wants the bot to walk to a place that is not a number.
class BrokenBrain:
	extends BotBrain

	func think(_beliefs: BotBeliefs, _state: ClientState) -> BotIntent:
		var intent := BotIntent.new()
		intent.wish = Vector3(NAN, 0.0, 0.0)
		return intent


func _thinks(rig: BotRig) -> int:
	return rig.bot.telemetry.counters.get(&"thinks", 0)


func test_a_brain_that_fails_is_switched_off_and_the_motor_goes_on_alone() -> void:
	var rig := BotRig.new(BotProfile.regular(), 3)
	rig.bot.brain = EmptyBrain.new()
	rig.put_zombie(1, Vector3(0, 0, -12))
	rig.run(180)
	assert_bool(rig.bot.brain_enabled).is_false()
	var names := rig.bot.telemetry.events.map(
		func(entry: Dictionary) -> StringName: return entry["name"]
	)
	assert_array(names).is_equal([BotClient.BRAIN_FAILED, BotClient.BRAIN_DISABLED])
	# The motor holds where it stands and follows the zombie it can see: it still shoots it.
	assert_int(rig.shot_ticks.size()).is_greater(0)
	for action in rig.sent:
		assert_vector(action["motion"]["move"]).is_equal(Vector2.ZERO)
	# And the failure is not repeated every think.
	assert_int(rig.bot.telemetry.counters[BotClient.BRAIN_FAILED]).is_equal(1)


func test_a_nonsense_answer_counts_as_a_failure_and_the_limit_is_the_profiles() -> void:
	var profile := BotProfile.regular()
	profile.brain_failure_limit = 3
	var rig := BotRig.new(profile, 3)
	rig.bot.brain = BrokenBrain.new()
	rig.run(10)
	assert_bool(rig.bot.brain_enabled).is_true()
	rig.run(170)
	assert_bool(rig.bot.brain_enabled).is_false()
	assert_int(rig.bot.telemetry.counters[BotClient.BRAIN_FAILED]).is_equal(3)
	assert_bool(rig.bot.telemetry.has_event(BotClient.BRAIN_DISABLED)).is_true()
	for action in rig.sent:
		assert_bool(Vector3(action["motion"]["move"].x, 0, 0).is_finite()).is_true()


func test_the_raw_zombie_list_is_gone_once_the_perception_has_looked() -> void:
	var rig := BotRig.new()
	rig.put_zombie(1, Vector3(0, 0, -10))
	rig.put_zombie(2, Vector3(2, 0, -12))
	rig.run(3)
	assert_array(rig.bot.state.zombies).is_empty()
	assert_int(rig.bot.state.frame["zombies"].size()).is_equal(0)


func test_the_brain_thinks_at_the_profiles_rate() -> void:
	for profile in [BotProfile.rookie(), BotProfile.regular(), BotProfile.veteran()]:
		var rig := BotRig.new(profile, 2)
		rig.run(SECONDS * TICKS_PER_SECOND)
		var expected := float(profile.think_hz * SECONDS)
		assert_float(float(_thinks(rig))).is_between(expected * 0.9, expected * 1.1)
		# The motor runs every tick.
		assert_int(rig.sent.size()).is_equal(SECONDS * TICKS_PER_SECOND)


func test_two_seats_do_not_think_on_the_same_tick() -> void:
	var first := BotRig.new(BotProfile.regular(), 2)
	var second := BotRig.new(BotProfile.regular(), 2)
	first.bot.slot = 0
	second.bot.slot = 1
	var together := 0
	for _i in 200:
		var before_first := _thinks(first)
		var before_second := _thinks(second)
		first.step()
		second.step()
		if _thinks(first) > before_first and _thinks(second) > before_second:
			together += 1
	assert_int(together).is_equal(0)
	assert_int(_thinks(first)).is_greater(0)
	assert_int(_thinks(second)).is_greater(0)


func test_the_ring_buffer_keeps_the_last_decisions_oldest_first() -> void:
	var rig := BotRig.new(BotProfile.veteran(), 2)
	rig.run(60 * 40)
	var recent := rig.bot.telemetry.recent()
	assert_int(_thinks(rig)).is_greater(BotTelemetry.RING_SIZE)
	assert_int(recent.size()).is_equal(BotTelemetry.RING_SIZE)
	for i in range(1, recent.size()):
		assert_int(recent[i]["tick"]).is_greater(recent[i - 1]["tick"])
	assert_int(recent.back()["tick"]).is_greater(60 * 39)
	# What it believed and wanted is there to read.
	assert_bool(recent[0].has("intent")).is_true()
	assert_bool(recent[0].has("contacts")).is_true()


func test_the_report_is_one_line_of_json_with_the_think_times() -> void:
	var rig := BotRig.new()
	rig.put_zombie(1, Vector3(0, 0, -10))
	rig.run(240)
	var parsed: Variant = JSON.parse_string(rig.bot.telemetry.report({"rounds_reached": 3}))
	assert_bool(parsed is Dictionary).is_true()
	assert_float(parsed["commands"]).is_equal(240.0)
	assert_float(parsed["rounds_reached"]).is_equal(3.0)
	assert_bool(parsed.has("think_us_p99")).is_true()
	assert_int(rig.bot.telemetry.think_us(0.99)).is_greater_equal(rig.bot.telemetry.think_us(0.5))


func test_the_marquee_of_a_break_is_remembered_until_the_round_starts() -> void:
	var rig := BotRig.new(BotProfile.rookie(), 3)
	assert_bool(rig.bot.perception.beliefs.special_coming).is_false()
	rig.step([{"type": &"special_round_announced", "round": 5, "special_id": &"double_feature"}])
	assert_bool(rig.bot.perception.beliefs.special_coming).is_true()
	rig.step([{"type": &"round_started", "round": 5, "special_id": &"double_feature"}])
	assert_bool(rig.bot.perception.beliefs.special_coming).is_false()
	assert_str(String(rig.bot.perception.beliefs.special)).is_equal("double_feature")


func test_a_downed_bot_sends_a_command_that_does_nothing() -> void:
	var rig := BotRig.new()
	rig.put_zombie(1, Vector3(0, 0, -6))
	rig.run(60)
	rig.downed = true
	for _i in 30:
		var command := rig.step()
		assert_bool(command.fire).is_false()
		assert_vector(command.motion.move).is_equal(Vector2.ZERO)
		assert_bool(command.reload or command.use or command.swap).is_false()
