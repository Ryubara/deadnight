# The predicting client's body: small differences are taken back a share at a time, big ones snap,
# and no difference costs nothing.
extends GdUnitTestSuite


func test_a_server_that_agrees_asks_for_nothing() -> void:
	var reconciler := Reconciler.new()
	reconciler.record(1, Vector3(1, 0, 0))
	reconciler.record(2, Vector3(2, 0, 0))
	assert_vector(reconciler.correction(2, Vector3(2.01, 0, 0))).is_equal(Vector3.ZERO)
	assert_int(reconciler.corrections).is_equal(0)


func test_a_small_error_is_taken_back_by_a_share() -> void:
	var reconciler := Reconciler.new()
	reconciler.record(5, Vector3(0, 0, 0))
	var shift := reconciler.correction(5, Vector3(0.4, 0, 0))
	assert_float(shift.x).is_equal_approx(0.4 * Reconciler.CATCH_UP, 0.0001)
	assert_int(reconciler.corrections).is_equal(1)


func test_a_big_error_snaps() -> void:
	var reconciler := Reconciler.new()
	reconciler.record(5, Vector3(0, 0, 0))
	var shift := reconciler.correction(5, Vector3(0, 0, 6))
	assert_vector(shift).is_equal(Vector3(0, 0, 6))
	assert_float(reconciler.worst_error).is_equal_approx(6.0, 0.0001)


func test_an_answer_for_a_command_never_sent_is_ignored_and_old_ones_are_forgotten() -> void:
	var reconciler := Reconciler.new()
	reconciler.record(1, Vector3.ZERO)
	reconciler.record(2, Vector3.ZERO)
	reconciler.record(3, Vector3.ZERO)
	assert_vector(reconciler.correction(99, Vector3(1, 0, 0))).is_equal(Vector3.ZERO)
	reconciler.correction(2, Vector3.ZERO)
	# 1 and 2 are answered and gone; asking again about 2 finds nothing.
	assert_vector(reconciler.correction(2, Vector3(1, 0, 0))).is_equal(Vector3.ZERO)
	assert_vector(reconciler.correction(3, Vector3(1, 0, 0))).is_not_equal(Vector3.ZERO)


func test_a_correction_shifts_the_commands_still_unanswered_with_it() -> void:
	var reconciler := Reconciler.new()
	for seq in range(1, 6):
		reconciler.record(seq, Vector3(seq, 0, 0))
	# The server is half a metre ahead of the client at command 1: a share of it is taken back.
	var shift := reconciler.correction(1, Vector3(1.5, 0, 0))
	assert_float(shift.x).is_equal_approx(0.5 * Reconciler.CATCH_UP, 0.0001)
	# The body moved by it, so command 3 left it where it was plus the shift: a server that is
	# where the first answer said, one metre on, has nothing more to correct beyond what is left.
	var again := reconciler.correction(3, Vector3(3.5, 0, 0))
	assert_float(again.x).is_equal_approx((0.5 - shift.x) * Reconciler.CATCH_UP, 0.0001)


func test_a_big_snap_is_not_repeated_by_the_answers_that_follow() -> void:
	var reconciler := Reconciler.new()
	for seq in range(1, 9):
		reconciler.record(seq, Vector3(0, 0, 0))
	var snap := reconciler.correction(1, Vector3(0, 0, 8))
	assert_vector(snap).is_equal(Vector3(0, 0, 8))
	# The answers to commands 2 to 8 say the same place; the body is there now.
	for seq in range(2, 9):
		assert_vector(reconciler.correction(seq, Vector3(0, 0, 8))).is_equal(Vector3.ZERO)


func test_a_body_far_from_the_server_with_no_answer_to_judge_it_by_is_put_where_it_says() -> void:
	var reconciler := Reconciler.new()
	var body := Vector3(40, 0, 0)
	var shift := reconciler.correction(77, Vector3(2, 0, 0), body)
	assert_vector(shift).is_equal(Vector3(-38, 0, 0))
	# Near the server, an answer about nothing is still ignored.
	assert_vector(reconciler.correction(78, Vector3(2, 0, 0), Vector3(2.5, 0, 0))).is_equal(
		Vector3.ZERO
	)


func test_reset_forgets_every_command() -> void:
	var reconciler := Reconciler.new()
	reconciler.record(1, Vector3.ZERO)
	reconciler.reset()
	assert_vector(reconciler.correction(1, Vector3(3, 0, 0))).is_equal(Vector3.ZERO)
