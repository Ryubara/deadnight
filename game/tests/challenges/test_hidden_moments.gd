extends GdUnitTestSuite
## The stats of the hidden challenges (`HiddenMoments`, #1172), one event at a time: a break held
## whole at the stand, a round reached with the second door shut, a death in the first round and a
## night that ends with the people it began with. What counts, what does not, and the edges.

## Inside the stand (`data/areas.json`) and a point on the field outside it.
const AT_STAND := Vector3(2.0, 0.2, 3.0)
const IN_FIELD := Vector3(2.0, 0.2, -12.0)
const SECOND := &"door_booth"

var _b: MomentsBench


func before_test() -> void:
	_b = MomentsBench.new()


## A round ends and its break begins, as the rules say them.
func _round_over(round_number: int) -> void:
	_b.finish(round_number, [1, 2])
	_b.begin_break(round_number + 1)


# --- Intermission: a whole break at the stand ---


func test_a_break_spent_at_the_stand_from_its_start_to_its_end_is_counted() -> void:
	_b.join(1)
	_b.positions = {1: AT_STAND}
	_b.start(1)
	_b.wait(1.0)
	_round_over(1)
	_b.wait(5.0)
	_b.wait(5.0)
	_b.start(2)
	assert_int(_b.n(1, ChallengeStats.BREAKS_STAND)).is_equal(1)
	# The next break is another: counted once for each.
	_round_over(2)
	_b.wait(3.0)
	_b.start(3)
	assert_int(_b.n(1, ChallengeStats.BREAKS_STAND)).is_equal(2)


func test_one_step_out_of_the_stand_in_the_break_spoils_it_for_that_player_only() -> void:
	_b.join(1)
	_b.join(2)
	_b.join(3)
	_b.positions = {1: AT_STAND, 2: AT_STAND, 3: IN_FIELD}
	_b.start(1)
	_b.wait(1.0)
	_round_over(1)
	_b.wait(2.0)
	# Player 2 steps out for a moment and comes back; 3 comes in late.
	_b.positions[2] = IN_FIELD
	_b.wait(1.0)
	_b.positions[2] = AT_STAND
	_b.positions[3] = AT_STAND
	_b.wait(5.0)
	_b.start(2)
	assert_int(_b.n(1, ChallengeStats.BREAKS_STAND)).is_equal(1)
	assert_int(_b.n(2, ChallengeStats.BREAKS_STAND)).is_equal(0)
	assert_int(_b.n(3, ChallengeStats.BREAKS_STAND)).is_equal(0)


func test_the_wait_before_the_first_round_is_no_break_between_rounds() -> void:
	_b.join(1)
	_b.positions = {1: AT_STAND}
	_b.wait(1.0)
	_b.begin_break(1, 20.0)
	_b.wait(10.0)
	_b.start(1)
	assert_int(_b.n(1, ChallengeStats.BREAKS_STAND)).is_equal(0)


func test_a_break_the_night_ends_in_is_no_whole_break() -> void:
	_b.join(1)
	_b.positions = {1: AT_STAND}
	_b.start(1)
	_b.wait(1.0)
	_round_over(1)
	_b.wait(4.0)
	_b.game_over(1, &"no_players")
	_b.start(2)
	assert_int(_b.n(1, ChallengeStats.BREAKS_STAND)).is_equal(0)


func test_a_break_with_no_frame_in_it_and_a_player_who_left_count_nothing() -> void:
	_b.join(1)
	_b.join(2)
	_b.positions = {1: AT_STAND, 2: AT_STAND}
	_b.start(1)
	_b.wait(1.0)
	_round_over(1)
	_b.start(2)
	assert_int(_b.n(1, ChallengeStats.BREAKS_STAND)).is_equal(0)
	_round_over(2)
	_b.wait(2.0)
	_b.leave(2)
	_b.positions.erase(2)
	_b.wait(2.0)
	_b.start(3)
	assert_int(_b.n(1, ChallengeStats.BREAKS_STAND)).is_equal(1)
	assert_int(_b.n(2, ChallengeStats.BREAKS_STAND)).is_equal(0)


func test_a_map_with_no_stand_counts_no_break() -> void:
	_b.tally.know(RulesFixture.tuning(), "small_indoor")
	_b.join(1)
	_b.positions = {1: AT_STAND}
	_b.start(1)
	_b.wait(1.0)
	_round_over(1)
	_b.wait(5.0)
	_b.start(2)
	assert_int(_b.n(1, ChallengeStats.BREAKS_STAND)).is_equal(0)


# --- The long way round: a round reached with the second door shut ---


func test_each_round_started_with_the_second_door_shut_is_a_round_reached_the_long_way() -> void:
	_b.join(1)
	_b.join(2)
	for round_number in range(1, 9):
		_b.start(round_number)
	assert_int(_b.n(1, ChallengeStats.ROUND_LONG_WAY)).is_equal(8)
	assert_int(_b.n(2, ChallengeStats.ROUND_LONG_WAY)).is_equal(8)


func test_the_second_door_opening_stops_the_count_for_everyone_and_another_door_does_not() -> void:
	_b.join(1)
	_b.join(2)
	_b.start(1)
	_b.open_door(&"door_concession")
	_b.open_door(&"door_yard")
	_b.start(2)
	_b.start(3)
	assert_int(_b.n(1, ChallengeStats.ROUND_LONG_WAY)).is_equal(3)
	_b.open_door(SECOND)
	for round_number in range(4, 10):
		_b.start(round_number)
	assert_int(_b.n(1, ChallengeStats.ROUND_LONG_WAY)).is_equal(3)
	assert_int(_b.n(2, ChallengeStats.ROUND_LONG_WAY)).is_equal(3)


func test_a_frame_that_lists_the_door_open_counts_for_a_client_that_missed_the_event() -> void:
	_b.join(1)
	_b.start(1)
	_b.feed({"type": &"frame", "tick": 10, "players": {}, "doors": [&"door_concession", SECOND]})
	_b.start(2)
	assert_int(_b.n(1, ChallengeStats.ROUND_LONG_WAY)).is_equal(1)


func test_a_map_with_no_second_door_counts_no_round() -> void:
	_b.tally.know(RulesFixture.tuning(), "small_indoor")
	_b.join(1)
	_b.start(1)
	_b.start(2)
	assert_int(_b.n(1, ChallengeStats.ROUND_LONG_WAY)).is_equal(0)


# --- Dead on arrival: a death in the first round ---


func test_a_bleed_out_in_the_first_round_is_a_death_and_in_the_second_is_not() -> void:
	_b.join(1)
	_b.join(2)
	_b.start(1)
	_b.died(1)
	_b.died(1)
	assert_int(_b.n(1, ChallengeStats.DEATHS_ROUND_ONE)).is_equal(1)
	_b.finish(1, [2])
	_b.start(2)
	_b.died(2)
	assert_int(_b.n(2, ChallengeStats.DEATHS_ROUND_ONE)).is_equal(0)


func test_a_night_that_ends_in_the_first_round_with_everyone_down_is_a_death_for_each_once(
) -> void:
	_b.join(1)
	_b.join(2)
	_b.start(1)
	_b.died(1)
	_b.game_over(1)
	assert_int(_b.n(1, ChallengeStats.DEATHS_ROUND_ONE)).is_equal(1)
	assert_int(_b.n(2, ChallengeStats.DEATHS_ROUND_ONE)).is_equal(1)


func test_a_night_that_ends_later_or_for_no_player_left_is_no_death() -> void:
	_b.join(1)
	_b.start(1)
	_b.game_over(1, &"no_players")
	assert_int(_b.n(1, ChallengeStats.DEATHS_ROUND_ONE)).is_equal(0)
	var later := MomentsBench.new()
	later.join(1)
	later.start(1)
	later.start(2)
	later.game_over(2)
	assert_int(later.n(1, ChallengeStats.DEATHS_ROUND_ONE)).is_equal(0)


# --- Standing room only: the same four from the first round to the end ---


func _lot(ids: Array) -> void:
	for id: int in ids:
		_b.join(id)


func test_four_people_who_stay_from_the_first_round_to_the_end_fill_the_house() -> void:
	_lot([1, 2, 3, 4])
	_b.start(1)
	_b.start(2)
	_b.game_over(2)
	for id in [1, 2, 3, 4]:
		assert_int(_b.n(id, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(1)


func test_more_than_four_people_who_all_stay_fill_it_too() -> void:
	_lot([1, 2, 3, 4, 5])
	_b.start(1)
	_b.game_over(1)
	assert_int(_b.n(5, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(1)


func test_three_people_or_a_bot_among_four_do_not() -> void:
	_lot([1, 2, 3])
	_b.start(1)
	_b.game_over(1)
	assert_int(_b.n(1, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(0)
	var with_bot := MomentsBench.new()
	for id in [1, 2, 3, 4]:
		with_bot.join(id, id == 4)
	with_bot.start(1)
	with_bot.game_over(1)
	assert_int(with_bot.n(1, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(0)


func test_one_who_leaves_or_one_who_comes_in_or_a_seat_a_bot_takes_over_spoils_it() -> void:
	_lot([1, 2, 3, 4])
	_b.start(1)
	_b.leave(4)
	_b.game_over(2)
	assert_int(_b.n(1, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(0)
	# A fifth comes in after the first round began: not the same people.
	var late := MomentsBench.new()
	for id in [1, 2, 3, 4]:
		late.join(id)
	late.start(1)
	late.join(5)
	late.game_over(2)
	assert_int(late.n(1, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(0)
	# A bot takes the seat of a person who left.
	var swapped := MomentsBench.new()
	for id in [1, 2, 3, 4]:
		swapped.join(id)
	swapped.start(1)
	swapped.feed({"type": &"bot_seated", "player_id": 3})
	swapped.game_over(2)
	assert_int(swapped.n(1, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(0)


func test_one_who_left_and_came_back_before_the_end_is_still_the_same_four() -> void:
	_lot([1, 2, 3, 4])
	_b.start(1)
	_b.leave(4)
	_b.wait(1.0)
	_b.join(4)
	_b.game_over(3)
	assert_int(_b.n(4, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(1)


func test_a_new_night_forgets_the_last_ones_four() -> void:
	_lot([1, 2, 3, 4])
	_b.start(1)
	_b.tally.reset()
	_lot([1, 2, 3, 4])
	# No first round was heard in this night: nothing to compare the end with.
	_b.game_over(1)
	assert_int(_b.n(1, ChallengeStats.NIGHTS_FULL_LOT)).is_equal(0)
