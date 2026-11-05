extends GdUnitTestSuite
## The odd and together stats (`NightMoments`, #1074), each worked from events made the way the
## rules and the server make them: a round's stats (no shot, no kill, the whole crew), the empty
## gun, the circuits and the booth. The same stats from a real server and real clients are
## `tests/net/test_challenge_moments_online.gd`.

var _b: MomentsBench


func before_test() -> void:
	_b = MomentsBench.new()


# --- Rounds ---


func test_a_round_ended_on_their_feet_without_a_gun_fired_counts_and_melee_and_downs_do_not(
) -> void:
	_b.join(1)
	_b.join(2)
	_b.join(3)
	_b.start(1)
	_b.shot(1, &"pistol")
	_b.shot(2, &"crowbar")
	_b.finish(1, [1, 2])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_UNFIRED)).is_equal(0)
	# A swing is no shot, a body on the ground did not clear anything.
	assert_int(_b.n(2, ChallengeStats.ROUNDS_UNFIRED)).is_equal(1)
	assert_int(_b.n(3, ChallengeStats.ROUNDS_UNFIRED)).is_equal(0)
	# The next round starts again from nothing fired.
	_b.start(2)
	_b.finish(2, [1, 2, 3])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_UNFIRED)).is_equal(1)
	assert_int(_b.n(3, ChallengeStats.ROUNDS_UNFIRED)).is_equal(1)


func test_a_player_who_came_during_the_round_is_not_counted_for_it() -> void:
	_b.join(1)
	_b.start(1)
	_b.join(2)
	_b.finish(1, [1, 2])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_UNFIRED)).is_equal(1)
	assert_int(_b.n(2, ChallengeStats.ROUNDS_UNFIRED)).is_equal(0)
	assert_int(_b.n(2, ChallengeStats.ROUNDS_NO_KILLS)).is_equal(0)


func test_a_round_with_no_kill_of_theirs_counts_and_a_blast_kill_is_a_kill() -> void:
	_b.join(1)
	_b.join(2)
	_b.join(3)
	_b.start(1)
	_b.kill(1)
	(
		_b
		. feed(
			{
				"type": &"zombie_removed",
				"zombie_id": 2,
				"zombie_type": &"walker",
				"boss": false,
				"cause": &"killed",
				"killer_id": 2,
				"zone": RulesAction.ZONE_BLAST,
				"melee": false,
				"shattered": false,
			}
		)
	)
	# A zombie that left on its own is nobody's kill.
	(
		_b
		. feed(
			{
				"type": &"zombie_removed",
				"zombie_id": 3,
				"zombie_type": &"walker",
				"boss": false,
				"cause": &"gone",
				"killer_id": -1,
				"zone": &"",
				"melee": false,
				"shattered": false,
			}
		)
	)
	_b.finish(1, [1, 2, 3])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_NO_KILLS)).is_equal(0)
	assert_int(_b.n(2, ChallengeStats.ROUNDS_NO_KILLS)).is_equal(0)
	assert_int(_b.n(3, ChallengeStats.ROUNDS_NO_KILLS)).is_equal(1)


func test_a_whole_crew_is_two_or_more_in_the_round_all_on_their_feet() -> void:
	_b.join(1)
	_b.start(1)
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_WHOLE)).is_equal(0)
	_b.join(2)
	_b.start(2)
	_b.finish(2, [1, 2])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_WHOLE)).is_equal(1)
	assert_int(_b.n(2, ChallengeStats.ROUNDS_WHOLE)).is_equal(1)
	_b.start(3)
	_b.finish(3, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_WHOLE)).is_equal(1)
	# One who left in the round leaves one alone, and one is no crew.
	_b.start(4)
	_b.feed({"type": &"player_removed", "player_id": 2})
	_b.finish(4, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_WHOLE)).is_equal(1)
	_b.join(2)
	_b.join(3)
	_b.start(5)
	_b.finish(5, [1, 2, 3])
	assert_int(_b.n(3, ChallengeStats.ROUNDS_WHOLE)).is_equal(1)


# --- Ammunition ---


func test_a_round_ended_with_the_last_bullet_fired_counts() -> void:
	_b.join(1)
	_b.hold(1, &"pistol")
	_b.start(1)
	_b.shot(1, &"pistol", 0, 0)
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_DRY)).is_equal(1)


func test_rounds_left_in_the_magazine_or_in_reserve_are_not_dry() -> void:
	_b.join(1)
	_b.join(2)
	_b.hold(1, &"pistol")
	_b.hold(2, &"pistol")
	_b.start(1)
	_b.shot(1, &"pistol", 0, 12)
	_b.shot(2, &"pistol", 3, 0)
	_b.finish(1, [1, 2])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_DRY)).is_equal(0)
	assert_int(_b.n(2, ChallengeStats.ROUNDS_DRY)).is_equal(0)


func test_a_melee_weapon_in_hand_is_never_dry_and_a_player_who_never_shot_is_not_either() -> void:
	_b.join(1)
	_b.join(2)
	_b.hold(1, &"crowbar")
	_b.hold(2, &"pistol")
	_b.start(1)
	# The frame reads a crowbar's magazine as nothing: that is no empty gun.
	_b.feed({"type": &"frame", "tick": 1, "players": {1: {"ammo": 0, "reserve": 0}}})
	_b.finish(1, [1, 2])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_DRY)).is_equal(0)
	assert_int(_b.n(2, ChallengeStats.ROUNDS_DRY)).is_equal(0)


func test_the_frame_tells_the_ammunition_after_a_reload_or_a_purchase() -> void:
	_b.join(1)
	_b.hold(1, &"pistol")
	_b.start(1)
	_b.shot(1, &"pistol", 0, 0)
	# Ammunition bought: the frame's reserve is no longer nothing.
	_b.feed({"type": &"frame", "tick": 2, "players": {1: {"reserve": 20}}})
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_DRY)).is_equal(0)


# --- Circuits ---


func test_a_round_cleared_with_every_circuit_off_counts_as_that_round_in_the_dark() -> void:
	_b.join(1)
	_b.circuits = {&"field": false, &"booth": false}
	_b.wait(1.0)
	_b.start(3)
	_b.wait(5.0)
	_b.finish(3, [1])
	assert_int(_b.n(1, ChallengeStats.ROUND_DARK)).is_equal(3)


func test_a_circuit_lit_at_the_start_or_during_the_round_ends_the_dark() -> void:
	_b.join(1)
	_b.circuits = {&"field": true, &"booth": false}
	_b.wait(1.0)
	_b.start(1)
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUND_DARK)).is_equal(0)
	_b.circuits = {&"field": false, &"booth": false}
	_b.wait(1.0)
	_b.start(2)
	_b.feed({"type": &"circuit_changed", "circuit_id": &"booth", "on": true})
	_b.finish(2, [1])
	assert_int(_b.n(1, ChallengeStats.ROUND_DARK)).is_equal(0)
	# The event is the same as a frame that shows it.
	_b.circuits = {&"field": false, &"booth": false}
	_b.wait(1.0)
	_b.start(3)
	_b.circuits = {&"field": true, &"booth": false}
	_b.wait(1.0)
	_b.finish(3, [1])
	assert_int(_b.n(1, ChallengeStats.ROUND_DARK)).is_equal(0)


func test_a_night_that_never_said_its_circuits_is_not_dark() -> void:
	_b.join(1)
	_b.start(1)
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUND_DARK)).is_equal(0)


func test_the_dark_is_credited_to_those_on_their_feet_only() -> void:
	_b.join(1)
	_b.join(2)
	_b.circuits = {&"field": false}
	_b.wait(1.0)
	_b.start(2)
	_b.finish(2, [1])
	assert_int(_b.n(1, ChallengeStats.ROUND_DARK)).is_equal(2)
	assert_int(_b.n(2, ChallengeStats.ROUND_DARK)).is_equal(0)


# --- The booth ---


func test_a_round_spent_whole_in_the_booth_counts_and_a_step_out_does_not() -> void:
	_b.join(1)
	_b.join(2)
	_b.positions = {1: Vector3(0, 0, 27), 2: Vector3(-5, 0, 23)}
	_b.wait(1.0)
	_b.start(1)
	_b.wait(10.0)
	_b.positions = {1: Vector3(0, 0, 27), 2: Vector3(-5, 0, 21.5)}
	_b.wait(1.0)
	_b.positions = {1: Vector3(0, 0, 27), 2: Vector3(-5, 0, 23)}
	_b.wait(1.0)
	_b.finish(1, [1, 2])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_BOOTH)).is_equal(1)
	assert_int(_b.n(2, ChallengeStats.ROUNDS_BOOTH)).is_equal(0)


func test_a_player_who_walks_in_after_the_round_began_does_not_count() -> void:
	_b.join(1)
	_b.positions = {1: Vector3(0, 0, 40)}
	_b.wait(1.0)
	_b.start(1)
	_b.positions = {1: Vector3(0, 0, 27)}
	_b.wait(1.0)
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_BOOTH)).is_equal(0)


func test_a_still_player_stays_where_the_last_frame_put_them() -> void:
	_b.join(1)
	_b.positions = {1: Vector3(1, 0, 25)}
	_b.wait(1.0)
	_b.start(1)
	# A delta frame leaves out a position that did not change.
	_b.feed({"type": &"frame", "tick": 999, "players": {1: {"health": 90.0}}})
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_BOOTH)).is_equal(1)


func test_a_map_without_a_booth_has_no_booth_rounds() -> void:
	_b.tally = NightTally.new()
	_b.tally.know(RulesFixture.tuning(), "small_indoor")
	_b.join(1)
	_b.positions = {1: Vector3(0, 0, 27)}
	_b.wait(1.0)
	_b.start(1)
	_b.finish(1, [1])
	assert_int(_b.n(1, ChallengeStats.ROUNDS_BOOTH)).is_equal(0)
