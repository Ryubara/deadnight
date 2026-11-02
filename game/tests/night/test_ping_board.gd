extends GdUnitTestSuite
## The pings' bookkeeping: one mark a player, a gap between two, and the end of a mark.


func test_a_mark_is_put_up_and_runs_out() -> void:
	var board := PingBoard.new()
	board.seconds = 2.0
	var event := board.place(3, PingBoard.HERE, Vector3(1, 0, 2), 0)
	assert_str(event["type"]).is_equal("ping_placed")
	assert_int(event["player_id"]).is_equal(3)
	assert_dict(board.marks()).contains_keys([3])
	assert_array(board.step(1.0)).is_empty()
	var ended := board.step(1.5)
	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0]["type"]).is_equal("ping_cleared")
	assert_dict(board.marks()).is_empty()


func test_a_new_mark_replaces_the_last_of_the_same_player() -> void:
	var board := PingBoard.new()
	board.place(1, PingBoard.HERE, Vector3.ZERO, 0)
	board.place(1, PingBoard.ENEMY, Vector3(4, 0, 0), 9)
	assert_int(board.marks().size()).is_equal(1)
	assert_str(board.marks()[1]["kind"]).is_equal("enemy")
	assert_int(board.marks()[1]["subject"]).is_equal(9)


func test_the_gap_between_two_marks_is_per_player() -> void:
	var board := PingBoard.new()
	board.gap = 1.0
	board.place(1, PingBoard.HERE, Vector3.ZERO, 0)
	assert_bool(board.ready_for(1)).is_false()
	assert_bool(board.ready_for(2)).is_true()
	board.step(1.1)
	assert_bool(board.ready_for(1)).is_true()


func test_a_player_who_leaves_takes_the_mark_down() -> void:
	var board := PingBoard.new()
	board.place(1, PingBoard.HERE, Vector3.ZERO, 0)
	board.forget(1)
	assert_dict(board.marks()).is_empty()
	assert_bool(board.ready_for(1)).is_true()
