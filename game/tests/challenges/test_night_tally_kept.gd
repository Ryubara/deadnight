extends GdUnitTestSuite
## `NightTally` counting only what pays (the XP award's way), forgetting a seat, and being told who
## is here without a frame.


func _kill(zone: StringName = &"head", boss := false) -> Dictionary:
	return {
		"type": &"zombie_removed",
		"killer_id": 1,
		"cause": &"killed",
		"zombie_type": &"walker",
		"boss": boss,
		"zone": zone,
		"melee": false,
	}


func test_counting_only_what_pays_skips_the_rest_of_a_kill() -> void:
	var tally := NightTally.new()
	tally.keep_only([ChallengeStats.KILLS_BOSS, ChallengeStats.POINTS])
	tally.observe(_kill())
	assert_int(tally.count(1, ChallengeStats.KILLS)).is_equal(0)
	assert_int(tally.count(1, ChallengeStats.KILLS_HEAD)).is_equal(0)
	var changes := tally.observe(_kill(&"body", true))
	assert_int(changes.size()).is_equal(1)
	assert_str(changes[0]["stat"]).is_equal(ChallengeStats.KILLS_BOSS)
	tally.observe({"type": &"points_changed", "player_id": 1, "delta": 70, "reason": &"kill"})
	assert_int(tally.count(1, ChallengeStats.POINTS)).is_equal(70)
	# Without the filter the same kill counts everything again.
	tally.keep_only([])
	tally.observe(_kill())
	assert_int(tally.count(1, ChallengeStats.KILLS)).is_equal(1)


func test_a_forgotten_seat_starts_again_and_presence_needs_no_frame() -> void:
	var tally := NightTally.new()
	tally.set_present(2)
	assert_bool(tally.is_present(2)).is_true()
	tally.observe({"type": &"round_started", "round": 3})
	assert_int(tally.count(2, ChallengeStats.ROUND)).is_equal(3)
	tally.forget(2)
	assert_int(tally.count(2, ChallengeStats.ROUND)).is_equal(0)
	assert_bool(tally.is_present(2)).is_true()
	tally.set_present(2, false)
	tally.observe({"type": &"round_started", "round": 4})
	assert_int(tally.count(2, ChallengeStats.ROUND)).is_equal(0)
