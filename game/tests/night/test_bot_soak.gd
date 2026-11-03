# The soak (bots plan, phase 1): four hosted bots, one of each profile and the old autopilot, play
# a whole night through three rounds without dying, and none of them loses its brain. Ticks are
# run by hand; nothing waits on the clock.
extends GdUnitTestSuite

const STEP := Night.STEP
const ROUNDS_SURVIVED := 3
## Game seconds after which the soak gives up (the bots stopped advancing).
const GIVE_UP_SECONDS := 1200.0

## Game seconds each seeded night of the movement soak runs, and the seeds. The twenty-minute soak
## is `tests/captures/bots_move_soak.tscn`, a local or nightly measurement.
const MOVE_SECONDS := 45
const MOVE_SEEDS := [11, 12]
## A person's tour of the field for the bots to follow (offsets from the field's home).
const TOUR := [
	Vector3(-20.0, 0.0, 0.0),
	Vector3(-20.0, 0.0, 14.0),
	Vector3(20.0, 0.0, 14.0),
	Vector3(20.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 0.0),
]
## What the short soak holds the bots to: looser than the twenty-minute gates (a short run is a
## sample of a few episodes): stuck time under this share of walking time, no episode this long, and
## at least this share of the time within `NEAR` metres of the person (who walks the tour without
## stopping, at a run: harder than a person fighting).
const STUCK_SHARE := 0.05
const LONGEST_STUCK := 6.0
const SHARE_NEAR := 0.65
const NEAR := 12.0


func test_the_soak_four_hosted_bots_survive_three_rounds() -> void:
	var night := await NightFixture.seat(self, 4, null, 7)
	night.seat(1, BotProfile.rookie(), 101)
	night.seat(2, BotProfile.regular(), 102)
	night.seat(3, BotProfile.veteran(), 103)
	night.seat(4, BotProfile.autopilot(), 104, true)
	night.server.rules.apply(RulesAction.skip_break())
	var ticks := 0
	var limit := int(GIVE_UP_SECONDS / STEP)
	while (
		night.server.rules.round_number <= ROUNDS_SURVIVED
		and night.server.rules.phase != GameRules.Phase.OVER
		and ticks < limit
	):
		night.tick()
		ticks += 1
	assert_int(night.server.rules.phase).is_not_equal(GameRules.Phase.OVER)
	assert_int(night.server.rules.round_number).is_greater(ROUNDS_SURVIVED)
	var killed := 0
	for bot in night.host.bots:
		killed += night.frame["players"][bot.state.player_id]["kills"]
		assert_int(bot.telemetry.counters[&"ticks"]).is_equal(ticks)
		assert_bool(bot.telemetry.has_event(BotClient.BRAIN_DISABLED)).is_false()
	assert_int(killed).is_greater_equal(RulesFixture.round_count(1, 4))
	night.dispose()


func test_the_movement_soak_three_bots_follow_a_person_round_the_field() -> void:
	for seed_value: int in MOVE_SEEDS:
		var tuning := RulesFixture.tuning()
		# The person does not fight and must outlast the soak: health is not what is measured.
		tuning.health.max_health = 100000.0
		var night := await NightFixture.seat(self, 4, tuning, seed_value)
		var walker := night.human(1)
		night.seat(2, BotProfile.regular(), seed_value * 10 + 2)
		night.seat(3, BotProfile.veteran(), seed_value * 10 + 3)
		night.seat(4, BotProfile.rookie(), seed_value * 10 + 4)
		var catcher := ErrorCatcher.new()
		catcher.start()
		night.gather()
		night.server.rules.apply(RulesAction.skip_break())
		# Follow is the stance this measures (the default is to roam).
		night.give_order(BotOrders.FOLLOW, 1, walker.position())
		var leg := 0
		walker.goto(Autopilot.HOME + TOUR[0])
		var near := 0
		var sampled := 0
		for _tick in MOVE_SECONDS * 60:
			night.tick()
			if walker.arrived():
				leg = (leg + 1) % TOUR.size()
				walker.goto(Autopilot.HOME + TOUR[leg])
			for bot in night.host.bots:
				var apart := Vector2(
					(
						night.server.body_of(bot.state.player_id).global_position.x
						- walker.position().x
					),
					(
						night.server.body_of(bot.state.player_id).global_position.z
						- walker.position().z
					)
				)
				sampled += 1
				near += 1 if apart.length() <= NEAR else 0
		catcher.stop()
		assert_array(catcher.lines).is_empty()
		assert_float(float(near) / float(sampled)).is_greater(SHARE_NEAR)
		for bot in night.host.bots:
			var stuck := bot.legs.stuck
			var label := "seed %d seat %d" % [seed_value, bot.state.player_id]
			assert_float(stuck.longest()).override_failure_message(label).is_less(LONGEST_STUCK)
			assert_float(stuck.stuck_seconds).override_failure_message(label).is_less(
				STUCK_SHARE * maxf(stuck.walking_seconds, 1.0)
			)
			(
				assert_bool(bot.telemetry.has_event(&"bot_stuck"))
				. override_failure_message(label)
				. is_false()
			)
			assert_int(bot.legs.path.empty_answers).is_equal(0)
			# At most three path questions a second.
			assert_int(bot.legs.path.queries).is_less_equal(MOVE_SECONDS * 3)
			assert_bool(bot.telemetry.has_event(BotClient.BRAIN_DISABLED)).is_false()
		night.dispose()
