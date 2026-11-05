extends GdUnitTestSuite
## The server's tracker against a client's, over a night that is really played (#1076): a bot plays
## three rounds on the real rules and the real combat; the board a client counts on its own from the
## events it hears is the board the server counted from the events it made, and what the server said
## finished is what the client's tracker finished, with the reward, in the same order.

const TICKS_PER_FRAME := 40
const ROUNDS := 3
const GIVE_UP_SECONDS := 900.0
const CHEAP_DOOR := 250
const DAY := 20401
const USER := "played"


func test_the_server_finishes_what_the_clients_tracker_finishes_in_a_played_night() -> void:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.economy.item(&"door_concession").price = CHEAP_DOOR
	var catalog := ChallengeFixture.quick_catalog()
	var board := ChallengeBoard.open(
		ChallengeFixture.save_path("award_night"), ChallengeFixture.clock_on(DAY), catalog
	)
	var night := Night.new()
	night.challenge_board = board
	add_child(night)
	await night.start(Night.Mode.AUTOPILOT, 7, tuning)
	night.ticks_per_frame = TICKS_PER_FRAME
	var state := night.state
	# The server follows the player's account as a game server does: a board it never read, fresh.
	var award := night.server.challenges
	award.catalog = catalog
	award.clock = ChallengeFixture.clock_on(DAY)
	night.server.xp.register(state.player_id, USER, 0, 0)
	assert_bool(award.seat(state.player_id, USER)).is_true()
	award.arrived(USER, 404, ChallengeAward.NO_BOARD)
	var told: Array[Dictionary] = []
	state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == ChallengeAward.DONE:
				told.append(event)
	)
	var theirs: Array[Dictionary] = []
	night.challenges.advanced.connect(
		func(advance: Dictionary) -> void:
			if advance["completed"]:
				theirs.append(advance)
	)
	var ticks := 0
	while state.rounds_started < ROUNDS and not state.over and ticks < GIVE_UP_SECONDS / Night.STEP:
		await get_tree().physics_frame
		ticks = night.server.tick_count
	assert_bool(state.over).is_false()
	assert_int(state.kills).is_greater_equal(RulesFixture.round_count(1))
	# Something finished, and it is the same somethings in the same order.
	assert_int(theirs.size()).is_greater(1)
	(
		assert_array(told.map(func(e: Dictionary) -> StringName: return e["id"]))
		. is_equal(theirs.map(func(a: Dictionary) -> StringName: return a["id"]))
	)
	for event in told:
		assert_int(int(event["reward"]["xp"])).is_equal(5)
		assert_int(event["player_id"]).is_equal(state.player_id)
	# And the whole board is the same, down to the kills of each weapon and each kind of dead.
	var served := award.profile_of(USER)
	assert_dict(served.lifetime).is_equal(board.profile.lifetime)
	assert_array(served.dailies).is_equal(board.profile.dailies)
	assert_array(served.orders).is_equal(board.profile.orders)
	await NightFixture.settle_bake(night)
	night.queue_free()
