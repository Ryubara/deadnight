# The soak (bots plan, phase 1): four hosted bots, one of each profile and the old autopilot, play
# a whole night through three rounds without dying, and none of them loses its brain. Ticks are
# run by hand; nothing waits on the clock.
extends GdUnitTestSuite

const STEP := Night.STEP
const ROUNDS_SURVIVED := 3
## Game seconds after which the soak gives up (the bots stopped advancing).
const GIVE_UP_SECONDS := 1200.0


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
