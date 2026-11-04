# The autopilot walks to the re-cut bench in the booth and the soda fountain in the stand when it
# can pay, and uses them through the same `use` a person presses (docs/design/upgrades.md).
extends GdUnitTestSuite

const TICKS_PER_FRAME := 40
## Points the bot starts with: enough for the concession, the booth and both machines at once.
const PURSE := 6000
const CHEAP := 300
const GIVE_UP_SECONDS := 1500.0
## The doors past the booth. The autopilot buys every door it can pay for before it shops, so with
## a purse of 6000 it spent the rest on the yard and the road (2000), walked out to the road and
## could not walk back: its way home runs through a boarded fence breach (#995). The machines are
## in the concession and the booth; these stay out of the purse's reach.
const FAR_DOORS: Array[StringName] = [&"door_back_lot", &"door_yard", &"door_road"]
const OUT_OF_REACH := 1000000


func test_the_bot_re_cuts_its_weapon_and_drinks_the_hearty_tonic() -> void:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.economy.start_points = PURSE
	tuning.economy.item(&"upgrade_weapon").price = CHEAP
	tuning.economy.item(&"tonic_hearty").price = CHEAP
	for door in FAR_DOORS:
		tuning.economy.item(door).price = OUT_OF_REACH
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT, tuning, 7)
	night.ticks_per_frame = TICKS_PER_FRAME
	var state := night.state
	var ticks := 0
	while not _done(night) and not state.over and ticks < GIVE_UP_SECONDS / Night.STEP:
		await get_tree().physics_frame
		ticks = night.server.tick_count
	assert_bool(state.over).is_false()
	assert_int(state.bought.get(&"upgrade_weapon", 0)).is_equal(1)
	assert_int(state.bought.get(&"tonic_hearty", 0)).is_equal(1)
	var rules := night.server.rules
	assert_int(rules.players[1].upgraded.size()).is_equal(1)
	assert_float(rules.max_health_of(1)).is_equal(100.0 + 50.0)
	var weapon: StringName = rules.players[1].upgraded[0]
	assert_int(night.server.combat.state_of(1, weapon).tier()).is_equal(1)
	night.queue_free()


func _done(night: Night) -> bool:
	return (
		night.state.bought.get(&"upgrade_weapon", 0) > 0
		and night.state.bought.get(&"tonic_hearty", 0) > 0
	)
