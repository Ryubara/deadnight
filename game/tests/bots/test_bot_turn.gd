# The errand turn (bots plan, phase 5): one bot at a time goes, the turn lapses a second after it
# was last taken, and a bot that has held it for a long slice while another waits rests before it
# may take it back.
extends GdUnitTestSuite


func test_the_first_to_ask_goes_and_the_others_wait() -> void:
	var turn := BotTurn.new()
	assert_bool(turn.may_go(2, 0.0)).is_true()
	turn.took(2, 0.0)
	assert_bool(turn.may_go(3, 0.1)).is_false()
	assert_bool(turn.may_go(2, 0.1)).is_true()
	assert_int(turn.holder).is_equal(2)


func test_the_turn_lapses_when_it_is_not_taken_again() -> void:
	var turn := BotTurn.new()
	turn.took(2, 0.0)
	assert_bool(turn.may_go(3, BotTurn.LEASE - 0.1)).is_false()
	assert_bool(turn.may_go(3, BotTurn.LEASE + 0.1)).is_true()
	turn.took(3, BotTurn.LEASE + 0.1)
	assert_int(turn.holder).is_equal(3)


func test_taking_it_every_think_keeps_it() -> void:
	var turn := BotTurn.new()
	var now := 0.0
	while now < 10.0:
		assert_bool(turn.may_go(2, now)).is_true()
		turn.took(2, now)
		assert_bool(turn.may_go(3, now + 0.05)).is_false()
		now += 0.125


func test_a_long_slice_with_another_waiting_passes_the_turn_on_and_rests() -> void:
	var turn := BotTurn.new()
	var now := 0.0
	var passed_at := -1.0
	while now < BotTurn.SLICE + 20.0:
		turn.may_go(3, now)
		if turn.may_go(2, now):
			turn.took(2, now)
		else:
			passed_at = now
			break
		now += 0.125
	assert_float(passed_at).is_greater(BotTurn.SLICE)
	assert_float(passed_at).is_less(BotTurn.SLICE + 1.0)
	# The waiting bot got it the moment the first one gave it up.
	assert_bool(turn.may_go(3, passed_at + 0.2)).is_true()
	turn.took(3, passed_at + 0.2)
	assert_bool(turn.may_go(2, passed_at + 0.3)).is_false()


func test_a_long_slice_with_nobody_waiting_is_kept() -> void:
	var turn := BotTurn.new()
	var now := 0.0
	while now < BotTurn.SLICE + 20.0:
		assert_bool(turn.may_go(2, now)).is_true()
		turn.took(2, now)
		now += 0.125


func test_a_bot_that_leaves_gives_the_turn_up_at_once() -> void:
	var turn := BotTurn.new()
	turn.took(2, 0.0)
	turn.release(2)
	assert_bool(turn.may_go(3, 0.1)).is_true()
