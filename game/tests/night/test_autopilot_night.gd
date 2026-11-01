# The autopilot plays whole rounds headless: nothing errors, rounds advance, points are earned
# and spent. It sends the same commands a person does, through the loopback to the server.
extends GdUnitTestSuite

## Ticks run in each physics frame, so the run takes seconds, not minutes.
const TICKS_PER_FRAME := 40
## A door the bot can afford in round two, so spending shows without a long run.
const CHEAP_DOOR := 250
const ROUNDS := 3
## Game seconds after which a run gives up (a bot that stops advancing fails the test).
const GIVE_UP_SECONDS := 900.0


func test_the_bot_plays_rounds_earns_and_spends() -> void:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.economy.item(&"door_concession").price = CHEAP_DOOR
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT, tuning)
	night.ticks_per_frame = TICKS_PER_FRAME
	var state := night.state
	var ticks := 0
	while state.rounds_started < ROUNDS and not state.over and ticks < GIVE_UP_SECONDS / Night.STEP:
		await get_tree().physics_frame
		ticks = night.server.tick_count
	assert_bool(state.over).is_false()
	assert_int(state.rounds_started).is_greater_equal(ROUNDS)
	assert_int(state.kills).is_greater(10)
	assert_int(state.points_earned).is_greater(200)
	assert_int(state.points_spent).is_greater_equal(CHEAP_DOOR)
	assert_int(state.doors_bought).is_greater_equal(1)
	assert_bool(night.server.rules.is_door_open(&"door_concession")).is_true()
	night.queue_free()
