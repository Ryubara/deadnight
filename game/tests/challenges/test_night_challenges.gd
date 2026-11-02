extends GdUnitTestSuite
## A real night counts into the player's challenges as it plays: a bot plays through the loopback
## to the server, and what the tracker counted from the events a client hears is checked against
## what the client state counted on its own, and against what reached the save.

const TICKS_PER_FRAME := 40
const ROUNDS := 3
const GIVE_UP_SECONDS := 900.0
const CHEAP_DOOR := 250
const DAY := 20401


func test_a_played_night_is_counted_saved_and_agrees_with_the_client() -> void:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.economy.item(&"door_concession").price = CHEAP_DOOR
	var path := ChallengeFixture.save_path("night")
	var board := ChallengeBoard.open(path, ChallengeFixture.clock_on(DAY))
	var night := Night.new()
	night.challenge_board = board
	add_child(night)
	await night.start(Night.Mode.AUTOPILOT, 7, tuning)
	night.ticks_per_frame = TICKS_PER_FRAME
	var state := night.state
	var advances: Array[Dictionary] = []
	night.challenges.advanced.connect(func(advance: Dictionary) -> void: advances.append(advance))
	var ticks := 0
	while state.rounds_started < ROUNDS and not state.over and ticks < GIVE_UP_SECONDS / Night.STEP:
		await get_tree().physics_frame
		ticks = night.server.tick_count
	assert_bool(state.over).is_false()
	var tally := night.challenges.tracker.tally
	var me := state.player_id
	assert_int(tally.count(me, ChallengeStats.KILLS)).is_equal(state.kills)
	assert_int(state.kills).is_greater_equal(RulesFixture.round_count(1))
	assert_int(tally.count(me, ChallengeStats.DOORS)).is_equal(state.doors_bought)
	assert_int(tally.count(me, ChallengeStats.BUYS)).is_equal(
		state.bought.values().reduce(func(sum: int, n: int) -> int: return sum + n, 0)
	)
	assert_int(tally.count(me, ChallengeStats.POINTS)).is_equal(
		state.points_earned - tuning.economy.start_points
	)
	assert_int(tally.count(me, ChallengeStats.ROUND)).is_equal(state.rounds_started)
	# Every kill is the work of one weapon or of a grenade.
	var by_weapon := 0
	for weapon in WeaponCatalog.IDS:
		by_weapon += tally.count(me, ChallengeStats.weapon_kills(weapon))
	assert_int(by_weapon + tally.count(me, ChallengeStats.KILLS_BLAST)).is_equal(state.kills)
	# It reached the profile and the screen's prompt, not only the tally.
	var profile := board.profile
	assert_int(int(profile.lifetime[&"kills"])).is_equal(state.kills)
	(
		assert_bool(
			advances.any(func(a: Dictionary) -> bool: return a["checkpoint"] > 0 or a["rung"] > 0)
		)
		. is_true()
	)
	# A round ended, so the save holds the night so far, at most one round behind.
	var saved: ChallengeProfile = ChallengeSave.read(path)["profile"]
	assert_int(int(saved.lifetime[&"kills"])).is_greater(0)
	assert_int(int(saved.lifetime[&"kills"])).is_less_equal(state.kills)
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_a_night_without_a_board_never_touches_a_save() -> void:
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT)
	assert_object(night.challenges).is_null()
	NightFixture.run(night, 30)
	night.queue_free()


func test_leaving_a_night_early_still_saves_what_was_counted() -> void:
	var path := ChallengeFixture.save_path("left")
	var board := ChallengeBoard.open(path, ChallengeFixture.clock_on(DAY))
	var night := Night.new()
	night.challenge_board = board
	add_child(night)
	await night.start(Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.skip_break())
	night.state.apply_events(night.server.rules.apply(RulesAction.buy(1, &"door_concession")))
	night.state.apply_events(night.server.rules.apply(RulesAction.grant_points(1, 1000)))
	night.state.apply_events(night.server.rules.apply(RulesAction.buy(1, &"door_concession")))
	assert_int(int(board.profile.lifetime.get(&"doors_bought", 0))).is_equal(1)
	await NightFixture.settle_bake(night)
	remove_child(night)
	night.free()
	var saved: ChallengeProfile = ChallengeSave.read(path)["profile"]
	assert_int(int(saved.lifetime.get(&"doors_bought", 0))).is_equal(1)
