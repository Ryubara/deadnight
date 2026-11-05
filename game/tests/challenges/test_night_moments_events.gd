extends GdUnitTestSuite
## The odd and together stats (`NightMoments`, #1074) of blasts, boards, doors, downs and the
## crowbar's crawlers: what counts, what does not, and the windows of time that run out.

var _b: MomentsBench


func before_test() -> void:
	_b = MomentsBench.new()


# --- Blasts, boards, doors, downs, crawlers ---


func test_the_most_dead_one_blast_left_is_a_best() -> void:
	_b.join(1)
	_b.start(1)
	for kills in [0, 2, 3, 1]:
		_b.feed({"type": &"blast_resolved", "player_id": 1, "kills": kills, "hits": kills + 1})
	assert_int(_b.n(1, ChallengeStats.BLAST_BEST)).is_equal(3)


func test_three_boards_on_one_window_in_ten_seconds_is_a_rush_and_slower_is_not() -> void:
	_b.join(1)
	_b.wait(1.0)
	_b.board(1)
	_b.wait(4.0)
	_b.board(1)
	_b.wait(4.0)
	_b.board(1)
	assert_int(_b.n(1, ChallengeStats.BOARD_RUSHES)).is_equal(1)
	# Three more, but each pair ten seconds apart: the window slides past the first.
	_b.wait(11.0)
	_b.board(1)
	_b.wait(6.0)
	_b.board(1)
	_b.wait(6.0)
	_b.board(1)
	assert_int(_b.n(1, ChallengeStats.BOARD_RUSHES)).is_equal(1)


func test_boards_on_three_windows_or_by_three_players_are_no_rush() -> void:
	_b.join(1)
	_b.join(2)
	_b.join(3)
	_b.wait(1.0)
	_b.board(1, &"w1")
	_b.board(1, &"w2")
	_b.board(1, &"w3")
	_b.board(1, &"w1")
	_b.board(2, &"w1")
	_b.board(3, &"w1")
	assert_int(_b.n(1, ChallengeStats.BOARD_RUSHES)).is_equal(0)
	assert_int(_b.n(2, ChallengeStats.BOARD_RUSHES)).is_equal(0)


func test_a_board_beside_a_teammates_on_the_same_window_in_six_seconds_is_shared() -> void:
	_b.join(1)
	_b.join(2)
	_b.wait(1.0)
	_b.board(1)
	assert_int(_b.n(1, ChallengeStats.BOARDS_SHARED)).is_equal(0)
	_b.wait(2.0)
	_b.board(2)
	assert_int(_b.n(2, ChallengeStats.BOARDS_SHARED)).is_equal(1)
	assert_int(_b.n(1, ChallengeStats.BOARDS_SHARED)).is_equal(0)
	_b.wait(2.0)
	_b.board(1)
	assert_int(_b.n(1, ChallengeStats.BOARDS_SHARED)).is_equal(1)


func test_a_board_alone_or_late_or_on_another_window_is_not_shared() -> void:
	_b.join(1)
	_b.join(2)
	_b.wait(1.0)
	_b.board(1)
	_b.wait(1.0)
	_b.board(1)
	_b.board(2, &"w2")
	_b.wait(8.0)
	_b.board(2)
	assert_int(_b.n(1, ChallengeStats.BOARDS_SHARED)).is_equal(0)
	assert_int(_b.n(2, ChallengeStats.BOARDS_SHARED)).is_equal(0)


func test_a_door_in_the_first_thirty_seconds_of_the_night_is_early() -> void:
	_b.join(1)
	_b.wait(29.0)
	_b.buy(1, &"door_concession", 350)
	assert_int(_b.n(1, ChallengeStats.DOORS_EARLY)).is_equal(1)
	_b.wait(2.0)
	_b.buy(1, &"door_yard", 500)
	assert_int(_b.n(1, ChallengeStats.DOORS_EARLY)).is_equal(1)
	# Not a door.
	_b.buy(1, &"weapon_shotgun", 900)
	assert_int(_b.n(1, ChallengeStats.DOORS_EARLY)).is_equal(1)


func test_every_way_through_open_before_round_five_is_counted_for_the_whole_lot_once() -> void:
	var doors: Array[StringName] = []
	for item in RulesFixture.tuning().economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			doors.append(item.id)
	assert_int(doors.size()).is_greater(2)
	_b.join(1)
	_b.join(2)
	_b.start(1)
	for i in doors.size():
		assert_int(_b.n(1, ChallengeStats.DOORS_ALL_EARLY)).is_equal(0)
		_b.buy(1 + (i % 2), doors[i], 100)
	assert_int(_b.n(1, ChallengeStats.DOORS_ALL_EARLY)).is_equal(1)
	assert_int(_b.n(2, ChallengeStats.DOORS_ALL_EARLY)).is_equal(1)


func test_the_last_way_through_in_round_five_or_after_is_too_late() -> void:
	var doors: Array[StringName] = []
	for item in RulesFixture.tuning().economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			doors.append(item.id)
	_b.join(1)
	for round_number in range(1, 6):
		_b.start(round_number)
	for door in doors:
		_b.buy(1, door, 100)
	assert_int(_b.n(1, ChallengeStats.DOORS_ALL_EARLY)).is_equal(0)


func test_a_frame_that_lists_the_open_doors_tells_those_opened_before_it_was_listening() -> void:
	var doors: Array[StringName] = []
	for item in RulesFixture.tuning().economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			doors.append(item.id)
	_b.join(1)
	_b.feed({"type": &"frame", "tick": 1, "round": 2, "doors": doors.slice(1), "players": {}})
	_b.buy(1, doors[0], 100)
	assert_int(_b.n(1, ChallengeStats.DOORS_ALL_EARLY)).is_equal(1)


func test_downed_in_the_first_five_seconds_of_a_round_counts_and_later_or_between_rounds_not(
) -> void:
	_b.join(1)
	_b.join(2)
	_b.join(3)
	_b.wait(1.0)
	_b.down(3)
	_b.start(1)
	_b.wait(4.0)
	_b.down(1)
	_b.wait(2.0)
	_b.down(2)
	assert_int(_b.n(1, ChallengeStats.DOWNS_EARLY)).is_equal(1)
	assert_int(_b.n(2, ChallengeStats.DOWNS_EARLY)).is_equal(0)
	assert_int(_b.n(3, ChallengeStats.DOWNS_EARLY)).is_equal(0)
	assert_int(_b.n(2, ChallengeStats.DOWNS)).is_equal(1)
	_b.finish(1, [3])
	_b.down(3)
	assert_int(_b.n(3, ChallengeStats.DOWNS_EARLY)).is_equal(0)


func test_five_crawlers_with_the_crowbar_in_thirty_seconds_is_a_run() -> void:
	_b.join(1)
	_b.hold(1, &"crowbar")
	for _i in 4:
		_b.wait(5.0)
		_b.kill(1, &"crawler", true)
	assert_int(_b.n(1, ChallengeStats.CRAWLER_RUNS)).is_equal(0)
	_b.wait(5.0)
	_b.kill(1, &"crawler", true)
	assert_int(_b.n(1, ChallengeStats.CRAWLER_RUNS)).is_equal(1)
	# A run is used up: the next needs five more.
	for _i in 4:
		_b.wait(1.0)
		_b.kill(1, &"crawler", true)
	assert_int(_b.n(1, ChallengeStats.CRAWLER_RUNS)).is_equal(1)
	_b.kill(1, &"crawler", true)
	assert_int(_b.n(1, ChallengeStats.CRAWLER_RUNS)).is_equal(2)


func test_a_run_that_takes_more_than_thirty_seconds_the_wrong_weapon_or_kind_is_none() -> void:
	_b.join(1)
	_b.hold(1, &"crowbar")
	for _i in 5:
		_b.wait(8.0)
		_b.kill(1, &"crawler", true)
	assert_int(_b.n(1, ChallengeStats.CRAWLER_RUNS)).is_equal(0)
	# Walkers with the crowbar.
	for _i in 5:
		_b.kill(1, &"walker", true)
	assert_int(_b.n(1, ChallengeStats.CRAWLER_RUNS)).is_equal(0)
	# Crawlers with a gun, or with the quick melee while a gun is in hand.
	_b.hold(1, &"pistol")
	for _i in 5:
		_b.kill(1, &"crawler", false)
		_b.kill(1, &"crawler", true)
	assert_int(_b.n(1, ChallengeStats.CRAWLER_RUNS)).is_equal(0)
