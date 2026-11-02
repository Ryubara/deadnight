extends GdUnitTestSuite
## The tracker turns a night's events into progress for the players it follows: each player on
## their own profile, the same for one player or four, with the quarter marks reported as they pass.

const DAY := 20401

var _catalog: ChallengeCatalog
var _profiles := {}


func before_test() -> void:
	_catalog = ChallengeFixture.small_catalog()
	_profiles = {}


func _tracker(ids: Array[int]) -> ChallengeTracker:
	return ChallengeFixture.tracker_for(_catalog, DAY, ids, _profiles)


func _progress(player_id: int, id: StringName) -> int:
	for entry in (_profiles[player_id] as ChallengeProfile).dailies:
		if entry["id"] == id:
			return entry["progress"]
	return -1


func _kill(tracker: ChallengeTracker, killer: int, zone: StringName = &"body") -> Array[Dictionary]:
	return (
		tracker
		. observe(
			{
				"type": &"zombie_removed",
				"zombie_id": 1,
				"zombie_type": &"walker",
				"boss": false,
				"cause": &"killed",
				"killer_id": killer,
				"zone": zone,
				"melee": false,
			}
		)
	)


func test_a_followed_player_is_dealt_the_days_challenges_on_following() -> void:
	_tracker([1])
	var profile: ChallengeProfile = _profiles[1]
	assert_int(profile.dealt_day).is_equal(DAY)
	assert_int(profile.dailies.size()).is_equal(3)
	assert_int(profile.orders.size()).is_equal(3)


func test_a_real_round_advances_the_dailies_and_milestones_of_the_killer() -> void:
	var made := ChallengeFixture.night(1)
	var tracker := _tracker([1])
	ChallengeFixture.feed(tracker, made["events"])
	var moved := ChallengeFixture.feed(tracker, ChallengeFixture.play_round_one(made["rules"], 1))
	var kills := RulesFixture.round_count(1)
	assert_int(_progress(1, &"d_kills")).is_equal(mini(kills, 8))
	assert_int(_progress(1, &"d_head")).is_equal(mini(kills, 4))
	assert_int(_progress(1, &"d_round")).is_equal(1)
	assert_int((_profiles[1] as ChallengeProfile).lifetime[&"kills"]).is_equal(kills)
	# The small catalogue's first kill milestone is 5 kills; round one's zombies may not reach it.
	var said := moved.any(func(m: Dictionary) -> bool: return m["id"] == &"m_kills")
	assert_bool(said).is_equal(kills >= 5)
	assert_bool(moved.any(func(m: Dictionary) -> bool: return m["id"] == &"d_kills")).is_true()
	for move in moved:
		assert_int(move["player_id"]).is_equal(1)


func test_each_player_has_their_own_progress_in_a_team() -> void:
	var tracker := _tracker([1, 2])
	for _i in 3:
		_kill(tracker, 1, &"head")
	_kill(tracker, 2)
	assert_int(_progress(1, &"d_kills")).is_equal(3)
	assert_int(_progress(1, &"d_head")).is_equal(3)
	assert_int(_progress(2, &"d_kills")).is_equal(1)
	assert_int(_progress(2, &"d_head")).is_equal(0)


func test_a_player_nobody_follows_is_counted_and_costs_no_progress() -> void:
	var tracker := _tracker([1])
	assert_array(_kill(tracker, 4)).is_empty()
	assert_int(tracker.tally.count(4, ChallengeStats.KILLS)).is_equal(1)
	assert_object(tracker.profile_of(4)).is_null()
	assert_int(_progress(1, &"d_kills")).is_equal(0)


func test_one_players_kills_the_same_alone_or_with_three_others() -> void:
	var solo := _tracker([1])
	var solo_progress := []
	for _i in 5:
		_kill(solo, 1, &"head")
	solo_progress.append(_progress(1, &"d_kills"))
	solo_progress.append(_progress(1, &"d_head"))
	var team_profiles := {}
	var team := ChallengeFixture.tracker_for(_catalog, DAY, [1, 2, 3, 4], team_profiles)
	for _i in 5:
		_kill(team, 1, &"head")
		_kill(team, 3)
	var mine: ChallengeProfile = team_profiles[1]
	var by_id := {}
	for entry in mine.dailies:
		by_id[entry["id"]] = entry["progress"]
	assert_array([by_id[&"d_kills"], by_id[&"d_head"]]).is_equal(solo_progress)


func test_the_quarter_marks_come_as_the_count_passes_them() -> void:
	var tracker := _tracker([1])
	var marks := []
	for _i in 8:
		for move in _kill(tracker, 1):
			if move["id"] == &"d_kills":
				marks.append(move["checkpoint"])
	# A target of 8: 25 percent at 2, 50 at 4, 75 at 6 and done at 8; the others say nothing.
	assert_array(marks).is_equal([0, 25, 0, 50, 0, 75, 0, 100])


func test_the_advance_is_also_a_signal() -> void:
	var tracker := _tracker([1])
	var heard: Array[Dictionary] = []
	tracker.advanced.connect(func(advance: Dictionary) -> void: heard.append(advance))
	_kill(tracker, 1)
	assert_bool(heard.any(func(a: Dictionary) -> bool: return a["id"] == &"d_kills")).is_true()
	assert_int(heard[0]["player_id"]).is_equal(1)


func test_the_night_ending_replaces_the_orders_that_were_finished() -> void:
	var made := ChallengeFixture.night(1)
	var tracker := _tracker([1])
	var profile: ChallengeProfile = _profiles[1]
	var finished: StringName = profile.orders[0]["id"]
	profile.orders[0]["progress"] = _catalog.get_def(finished).target
	ChallengeFixture.feed(tracker, made["events"])
	(
		assert_array(profile.orders.map(func(e: Dictionary) -> StringName: return e["id"]))
		. contains([finished])
	)
	tracker.observe({"type": &"game_over", "reason": &"all_down", "round_reached": 2})
	(
		assert_array(profile.orders.map(func(e: Dictionary) -> StringName: return e["id"]))
		. not_contains([finished])
	)
	assert_int(profile.orders.size()).is_equal(3)


func test_a_night_across_midnight_counts_on_the_new_days_challenges() -> void:
	var now := [float(DAY) * ChallengeClock.DAY_SECONDS + 86400.0 - 60.0]
	var clock := ChallengeClock.from_source(func() -> float: return now[0])
	var tracker := ChallengeTracker.new(_catalog, clock)
	var profile := ChallengeProfile.fresh(2)
	tracker.follow(1, profile)
	assert_int(profile.dealt_day).is_equal(DAY)
	_kill(tracker, 1)
	now[0] += 120.0
	_kill(tracker, 1)
	assert_int(profile.dealt_day).is_equal(DAY + 1)
	# Yesterday's kill expired with the day; the one after midnight counts on the new day's daily
	# (the small catalogue deals the same three every day, so it is the same id, from zero).
	var kills := profile.dailies.filter(func(e: Dictionary) -> bool: return e["id"] == &"d_kills")
	assert_int(profile.dailies.size()).is_equal(3)
	assert_int(kills[0]["progress"]).is_equal(1)
