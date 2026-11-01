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
