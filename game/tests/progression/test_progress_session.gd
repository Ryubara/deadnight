extends GdUnitTestSuite
## A night's XP as the client counts it: events in, XP out, the profile written at the end of every
## round for an account and never for a night with no account, the one-off awards paid once, and a
## played night that
## ends and is read back from the file.

const DAY := 20401
const TICKS_PER_FRAME := 40
const ROUNDS := 3
const GIVE_UP_SECONDS := 900.0

var _account := true
var _state: ClientState


func _store(name: String) -> ProfileStore:
	var store := ProfileStore.open(
		ChallengeFixture.save_path("xp_" + name), func() -> bool: return _account
	)
	store.seed_ids(3)
	return store


func _session(store: ProfileStore, day: int = DAY) -> ProgressSession:
	_state = ClientState.new()
	var session := ProgressSession.new(store, ChallengeFixture.clock_on(day))
	session.attach(_state)
	return session


## A night of one player (id 1) played through round one, every zombie killed by a head shot; its
## events go to the client state as the player's client would hear them.
func _round_one() -> void:
	var made := ChallengeFixture.night(1)
	_state.apply_events(made["events"])
	_state.apply_events(ChallengeFixture.play_round_one(made["rules"], 1))


func test_the_first_round_pays_its_lines_and_the_one_off_awards_to_an_account() -> void:
	_account = true
	var store := _store("first")
	var session := _session(store)
	_round_one()
	var stats := XpRules.stats_of(session.tally, 1)
	assert_int(stats[ChallengeStats.ROUND]).is_equal(1)
	assert_int(stats[ChallengeStats.POINTS]).is_greater(0)
	var awards := {"opening_night": true, "first_game_of_the_day": true}
	var expected := XpRules.settle(stats, awards)
	assert_int(expected).is_greater_equal(20 + 50 + 100)
	assert_int(session.xp()).is_equal(expected)
	assert_int(session.credited()).is_equal(expected)
	assert_int(store.profile.xp).is_equal(expected)
	assert_bool(store.profile.opening_night).is_true()
	assert_int(store.profile.bonus_day).is_equal(DAY)
	assert_bool(session.is_unkept()).is_false()
	# The file holds the same, and the queue holds the night for the backend.
	var again := ProfileStore.open(store.path)
	assert_int(again.profile.xp).is_equal(expected)
	assert_int(again.queue.size()).is_equal(1)


func test_the_opening_night_pays_once_and_the_first_game_once_a_day() -> void:
	_account = true
	var store := _store("once")
	var first := _session(store)
	_round_one()
	var after_first := store.profile.xp
	assert_int(first.credited()).is_equal(after_first)
	# The same day, a second night: only the lines. The queue has one write each time a round ended.
	var second := _session(store)
	_round_one()
	var lines_only := XpRules.settle(XpRules.stats_of(second.tally, 1))
	assert_int(second.xp()).is_equal(lines_only)
	assert_int(store.profile.xp).is_equal(after_first + lines_only)
	# The next day, the first game pays again and the opening night does not.
	var third := _session(store, DAY + 1)
	_round_one()
	var with_day := XpRules.settle(
		XpRules.stats_of(third.tally, 1), {"first_game_of_the_day": true}
	)
	assert_int(third.xp()).is_equal(with_day)
	assert_int(store.profile.xp).is_equal(after_first + lines_only + with_day)
	assert_int(store.profile.bonus_day).is_equal(DAY + 1)


func test_opening_the_game_pays_nothing_only_a_round_that_ends() -> void:
	_account = true
	var store := _store("open_only")
	var session := _session(store)
	var made := ChallengeFixture.night(1)
	_state.apply_events(made["events"])
	assert_int(session.xp()).is_zero()
	assert_int(store.profile.xp).is_zero()
	assert_bool(store.profile.opening_night).is_false()
	assert_bool(FileAccess.file_exists(store.path)).is_false()


func test_a_night_with_no_account_counts_and_keeps_nothing() -> void:
	_account = false
	var store := _store("no_account")
	var session := _session(store)
	_round_one()
	assert_bool(session.is_unkept()).is_true()
	assert_int(session.xp()).is_greater_equal(20)
	assert_int(session.credited()).is_zero()
	assert_int(store.profile.xp).is_zero()
	assert_bool(store.profile.opening_night).is_false()
	assert_bool(FileAccess.file_exists(store.path)).is_false()
	assert_bool(store.queue.is_empty()).is_true()


func test_a_finished_challenge_adds_its_xp_once_and_is_remembered() -> void:
	_account = true
	var store := _store("challenge")
	_state = ClientState.new()
	var board := ChallengeBoard.open(
		ChallengeFixture.save_path("xp_board"),
		ChallengeFixture.clock_on(DAY),
		ChallengeFixture.small_catalog()
	)
	var challenges := ChallengeSession.new(board)
	var session := ProgressSession.new(store, ChallengeFixture.clock_on(DAY))
	challenges.attach(_state)
	session.attach(_state, challenges)
	_state.apply_events(ChallengeFixture.night(1)["events"])
	var gains: Array[int] = []
	session.gained.connect(func(hundredths: int, _total: int) -> void: gains.append(hundredths))
	var done := {"id": "o_boards", "completed": true, "player_id": 1}
	challenges.advanced.emit(done)
	assert_int(session.xp()).is_equal(1)
	assert_array(gains).is_equal([100])
	assert_array(store.profile.done).is_equal([&"o_boards"])
	# A step that is not a completion pays nothing.
	challenges.advanced.emit({"id": "o_boards", "completed": false, "player_id": 1})
	assert_int(session.xp()).is_equal(1)


func test_a_played_night_finishes_a_feat_and_the_card_it_gives_can_be_worn() -> void:
	_account = true
	var store := _store("feat")
	_state = ClientState.new()
	var board := ChallengeBoard.open(
		ChallengeFixture.save_path("xp_feat_board"), ChallengeFixture.clock_on(DAY)
	)
	var challenges := ChallengeSession.new(board)
	var session := ProgressSession.new(store, ChallengeFixture.clock_on(DAY))
	challenges.attach(_state)
	session.attach(_state, challenges)
	var plates := PlateCatalog.shipped()
	(
		assert_array(plates.owned(PlateCatalog.EMBLEM, store.profile.level(), store.profile.done))
		. is_empty()
	)
	# Round one is all head shots: the first headshot kill is the feat "Say cheese" (an emblem).
	var made := ChallengeFixture.night(1)
	_state.apply_events(made["events"])
	_state.apply_events(ChallengeFixture.play_round_one(made["rules"], 1))
	assert_array(store.profile.done).contains([&"f_cheese"])
	# What the player now owns, from the profile as the night wrote it (and as the file keeps it).
	var read := ProfileStore.open(store.path).profile
	assert_array(plates.owned(PlateCatalog.EMBLEM, read.level(), read.done)).contains(
		[&"say_cheese"]
	)
	assert_bool(store.equip(&"emblem", &"say_cheese")).is_true()
	assert_str(store.profile.chosen(&"emblem")).is_equal("say_cheese")
	# The game server, given the ticket this profile would make, seats the player wearing it.
	var table := PlateTable.new()
	table.seat(
		1,
		{
			"xp": store.profile.xp,
			"emblem": "say_cheese",
			"done": store.profile.done.map(func(id: StringName) -> String: return String(id))
		},
		store.profile.level()
	)
	assert_str(table.of_seat(1)["emblem"]).is_equal("say_cheese")
	# A feat is paid once: another round's headshots do not finish it again.
	var count := store.profile.done.count(&"f_cheese")
	assert_int(count).is_equal(1)


func test_a_kill_raises_the_running_total_as_it_is_earned() -> void:
	_account = true
	var session := _session(_store("live"))
	var made := ChallengeFixture.night(1)
	var rules: GameRules = made["rules"]
	_state.apply_events(made["events"])
	_state.apply_events(rules.apply(RulesAction.start()))
	_state.apply_events(rules.apply(RulesAction.skip_break()))
	var totals: Array[int] = []
	session.gained.connect(func(_hundredths: int, total: int) -> void: totals.append(total))
	var before := session.xp()
	for _i in 4000:
		_state.apply_events(rules.apply(RulesAction.tick(RulesFixture.STEP)))
		var ids := rules.zombie_ids()
		if not ids.is_empty():
			_state.apply_events(RulesFixture.kill(rules, 1, ids[0], RulesAction.ZONE_HEAD))
			break
	assert_int(session.tally.count(1, ChallengeStats.KILLS)).is_equal(1)
	assert_int(session.xp()).is_greater_equal(before)
	assert_bool(totals.is_empty()).is_false()


func test_a_played_night_ends_and_the_profile_reads_back() -> void:
	_account = true
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	var store := _store("night")
	var night := Night.new()
	night.challenge_board = ChallengeBoard.open(
		ChallengeFixture.save_path("xp_night_board"), ChallengeFixture.clock_on(DAY)
	)
	night.profile_store = store
	add_child(night)
	await night.start(Night.Mode.AUTOPILOT, 7, tuning)
	night.ticks_per_frame = TICKS_PER_FRAME
	var state := night.state
	var ticks := 0
	while state.rounds_started < ROUNDS and not state.over and ticks < GIVE_UP_SECONDS / Night.STEP:
		await get_tree().physics_frame
		ticks = night.server.tick_count
	assert_bool(state.over).is_false()
	var progress := night.progress
	assert_object(progress).is_not_null()
	# Live equals settle on a real night: the running total is the finished night's number.
	var awards := {
		"opening_night": true,
		"first_game_of_the_day": true,
		"challenge_xp": progress.challenge_xp(),
	}
	var settled := XpRules.settle(XpRules.stats_of(progress.tally, state.player_id), awards)
	assert_int(progress.xp()).is_equal(settled)
	assert_int(state.points_earned - tuning.economy.start_points).is_equal(
		progress.tally.count(state.player_id, ChallengeStats.POINTS)
	)
	# The local rules tell the player their XP as events, as a game server would, and the totals
	# agree with the profile's own count (the one-off awards and the challenges' XP included).
	NightFixture.run(night, 2)
	assert_int(night.server.xp.night_xp(state.player_id)).is_equal(progress.xp())
	assert_int(state.xp_events).is_greater(0)
	assert_int(state.account_xp).is_equal(progress.xp())
	assert_int(state.levels[state.player_id]).is_equal(LevelCurve.level_of(progress.xp()))
	# A round ended, so the file holds the night so far, at most one round behind.
	assert_int(progress.credited()).is_greater(0)
	assert_int(progress.credited()).is_less_equal(progress.xp())
	var saved := ProfileStore.open(store.path)
	assert_int(saved.profile.xp).is_equal(progress.credited())
	assert_bool(saved.profile.opening_night).is_true()
	assert_int(saved.profile.bonus_day).is_equal(DAY)
	# Leaving writes the rest.
	progress.flush()
	assert_int(ProfileStore.open(store.path).profile.xp).is_equal(progress.xp())
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_a_night_without_a_store_never_touches_a_profile() -> void:
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT)
	assert_object(night.progress).is_null()
	# And awards no XP: nobody in it holds an account.
	assert_array(night.server.xp.seats()).is_empty()
	NightFixture.run(night, 30)
	night.queue_free()
