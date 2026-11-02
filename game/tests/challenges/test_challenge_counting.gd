extends GdUnitTestSuite
## Counting on a profile: quarter marks, totals against best nights, ladders, the high-water mark.

const DAY := 20401

var _profile: ChallengeProfile


func before_test() -> void:
	_profile = ChallengeProfile.fresh(5)


# --- Counting ---


func test_checkpoints_are_the_quarter_marks_for_a_target_of_four_or_more() -> void:
	assert_int(ChallengeProfile.checkpoint_crossed(0, 1, 8)).is_equal(0)
	assert_int(ChallengeProfile.checkpoint_crossed(0, 2, 8)).is_equal(25)
	assert_int(ChallengeProfile.checkpoint_crossed(2, 3, 8)).is_equal(0)
	assert_int(ChallengeProfile.checkpoint_crossed(3, 4, 8)).is_equal(50)
	assert_int(ChallengeProfile.checkpoint_crossed(5, 6, 8)).is_equal(75)
	assert_int(ChallengeProfile.checkpoint_crossed(7, 8, 8)).is_equal(100)
	# A jump over two marks reports the highest.
	assert_int(ChallengeProfile.checkpoint_crossed(0, 7, 8)).is_equal(75)
	assert_int(ChallengeProfile.checkpoint_crossed(0, 100, 8)).is_equal(100)
	# Nothing passed, nothing said.
	assert_int(ChallengeProfile.checkpoint_crossed(4, 4, 8)).is_equal(0)


func test_a_target_under_four_is_only_said_when_done() -> void:
	assert_int(ChallengeProfile.checkpoint_crossed(0, 1, 3)).is_equal(0)
	assert_int(ChallengeProfile.checkpoint_crossed(1, 2, 3)).is_equal(0)
	assert_int(ChallengeProfile.checkpoint_crossed(2, 3, 3)).is_equal(100)


func test_a_total_challenge_adds_up_across_nights() -> void:
	var catalog := ChallengeFixture.small_catalog()
	_profile.refresh(catalog, DAY)
	_profile.apply(catalog, &"kills", 5, 5)
	# A second night starts its own count at zero, and the challenge keeps adding.
	_profile.apply(catalog, &"kills", 2, 2)
	assert_int(_entry(&"d_kills")["progress"]).is_equal(7)


func test_a_one_night_challenge_takes_the_best_night_not_the_sum() -> void:
	var catalog := ChallengeFixture.small_catalog()
	_profile.orders = [{"id": &"o_doors", "progress": 0}]
	# Night one buys a door; night two buys two; night three buys one: the best night is two.
	_profile.apply(catalog, &"doors_bought", 1, 1)
	_profile.apply(catalog, &"doors_bought", 1, 1)
	assert_int(_profile.orders[0]["progress"]).is_equal(1)
	_profile.apply(catalog, &"doors_bought", 2, 1)
	assert_int(_profile.orders[0]["progress"]).is_equal(2)


func test_a_finished_challenge_stops_counting_and_is_counted_once() -> void:
	var catalog := ChallengeFixture.small_catalog()
	_profile.refresh(catalog, DAY)
	_profile.apply(catalog, &"kills:head", 4, 4)
	_profile.apply(catalog, &"kills:head", 9, 5)
	assert_int(_entry(&"d_head")["progress"]).is_equal(4)
	assert_int(_profile.finished["daily"]).is_equal(1)


func test_apply_answers_what_moved_for_the_prompt() -> void:
	var catalog := ChallengeFixture.small_catalog()
	_profile.refresh(catalog, DAY)
	var moved := _profile.apply(catalog, &"kills", 2, 2)
	var daily: Dictionary = moved.filter(func(m: Dictionary) -> bool: return m["id"] == &"d_kills")[0]
	assert_int(daily["before"]).is_equal(0)
	assert_int(daily["after"]).is_equal(2)
	assert_int(daily["target"]).is_equal(8)
	assert_int(daily["checkpoint"]).is_equal(25)
	assert_bool(daily["completed"]).is_false()
	assert_str(daily["text"]).is_equal("Do kills 8")


func test_an_unrelated_stat_moves_nothing_but_the_lifetime() -> void:
	var catalog := ChallengeFixture.small_catalog()
	_profile.refresh(catalog, DAY)
	assert_array(_profile.apply(catalog, &"buys", 1, 1)).is_empty()
	assert_int(_profile.lifetime[&"buys"]).is_equal(1)


func test_a_ladder_says_each_step_once_and_the_last_completes_it() -> void:
	var catalog := ChallengeFixture.small_catalog()
	var said: Array[int] = []
	var total := 0
	for _i in 60:
		total += 1
		for move in _profile.apply(catalog, &"kills", total, 1):
			if move["id"] == &"m_kills":
				said.append(move["rung"])
				assert_int(move["rungs"]).is_equal(3)
				assert_int(move["target"]).is_equal([5, 20, 50][move["rung"] - 1])
				assert_bool(move["completed"]).is_equal(move["rung"] == 3)
	assert_array(said).is_equal([1, 2, 3])


func test_the_best_round_is_kept_as_a_high_water_mark() -> void:
	var catalog := ChallengeFixture.small_catalog()
	_profile.apply(catalog, &"round", 3, 3)
	_profile.apply(catalog, &"round", 1, 1)
	assert_int(_profile.lifetime[&"round"]).is_equal(3)
	var moved := _profile.apply(catalog, &"round", 4, 1)
	(
		assert_array(moved.filter(func(m: Dictionary) -> bool: return m["id"] == &"m_round"))
		. has_size(1)
	)
	assert_int(_profile.lifetime[&"round"]).is_equal(4)


func test_a_stat_that_did_not_move_says_nothing() -> void:
	var catalog := ChallengeFixture.small_catalog()
	_profile.refresh(catalog, DAY)
	_profile.apply(catalog, &"round", 2, 2)
	assert_array(_profile.apply(catalog, &"round", 2, 0)).is_empty()


func _entry(id: StringName) -> Dictionary:
	for entry in _profile.dailies:
		if entry["id"] == id:
			return entry
	return {}


func _order(id: StringName) -> Dictionary:
	for entry in _profile.orders:
		if entry["id"] == id:
			return entry
	return {}
