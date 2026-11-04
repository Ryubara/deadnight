extends GdUnitTestSuite
## The reports of what a night earned wait in order for the backend: one goes at a time, one not
## taken is sent again unchanged after a pause, one the backend refuses for good is dropped and
## counted, and a backend that never answers cannot grow the queue without end.


func _queue() -> XpReportQueue:
	var queue := XpReportQueue.new()
	queue.push("/r/1", {"round": 1})
	queue.push("/r/2", {"round": 2})
	return queue


func test_reports_go_one_at_a_time_in_the_order_they_were_made() -> void:
	var queue := _queue()
	var first := queue.next(0.0)
	assert_str(first["path"]).is_equal("/r/1")
	# Another is not given while the first is in flight.
	assert_dict(queue.next(0.0)).is_empty()
	queue.answered(200, 0.0)
	assert_int(queue.taken).is_equal(1)
	assert_str(queue.next(0.0)["path"]).is_equal("/r/2")
	queue.answered(204, 0.0)
	assert_bool(queue.is_idle()).is_true()
	assert_int(queue.made).is_equal(2)


func test_a_report_not_taken_is_sent_again_unchanged_after_a_pause() -> void:
	var queue := _queue()
	var body: Dictionary = queue.next(0.0)["body"].duplicate()
	queue.answered(0, 10.0)
	# Not before the pause is up, and the one behind it waits for it.
	assert_dict(queue.next(11.0)).is_empty()
	var again := queue.next(12.5)
	assert_str(again["path"]).is_equal("/r/1")
	assert_dict(again["body"]).is_equal(body)
	queue.answered(503, 12.5)
	# The pause grows with each try.
	assert_dict(queue.next(12.5 + 4.0)).is_empty()
	assert_str(queue.next(12.5 + 5.0)["path"]).is_equal("/r/1")
	queue.answered(200, 20.0)
	assert_str(queue.next(20.0)["path"]).is_equal("/r/2")
	assert_int(queue.refused).is_equal(0)


func test_a_report_the_backend_refuses_for_good_is_dropped_and_counted() -> void:
	var queue := _queue()
	queue.next(0.0)
	queue.answered(422, 0.0)
	assert_int(queue.refused).is_equal(1)
	assert_str(queue.next(0.0)["path"]).is_equal("/r/2")
	# A busy backend (429, 408) is not a refusal.
	queue.answered(429, 0.0)
	assert_int(queue.refused).is_equal(1)
	assert_int(queue.waiting.size()).is_equal(1)


func test_a_backend_that_never_answers_cannot_grow_the_queue_without_end() -> void:
	var queue := XpReportQueue.new()
	for round_number in XpReportQueue.MAX_WAITING + 25:
		queue.push("/r/%d" % round_number, {})
	assert_int(queue.waiting.size()).is_equal(XpReportQueue.MAX_WAITING)
	assert_int(queue.dropped).is_equal(25)
	# The newest are kept.
	assert_str(queue.next(0.0)["path"]).is_equal("/r/25")
