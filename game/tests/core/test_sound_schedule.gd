extends GdUnitTestSuite
## The sound schedule runs things on the clock its owner moves: in order, once, and never from
## the wall clock.


func test_an_item_runs_when_the_clock_reaches_it_and_not_before() -> void:
	var schedule := SoundSchedule.new()
	var ran: Array[float] = []
	schedule.add(0.5, func() -> void: ran.append(schedule.now()))
	schedule.advance(0.4)
	assert_array(ran).is_empty()
	schedule.advance(0.1)
	assert_array(ran).has_size(1)
	schedule.advance(5.0)
	assert_array(ran).has_size(1)


func test_items_run_in_time_order_whatever_the_order_they_were_added() -> void:
	var schedule := SoundSchedule.new()
	var order: Array[int] = []
	schedule.add(0.3, func() -> void: order.append(3))
	schedule.add(0.1, func() -> void: order.append(1))
	schedule.add(0.2, func() -> void: order.append(2))
	schedule.advance(1.0)
	assert_array(order).is_equal([1, 2, 3])


func test_a_chain_counts_from_the_item_that_added_it_not_from_the_step() -> void:
	var schedule := SoundSchedule.new()
	var count := [0]
	var chain := [Callable()]
	chain[0] = func() -> void:
		count[0] += 1
		if count[0] < 4:
			schedule.add(0.1, chain[0])
	schedule.add(0.1, chain[0])
	# One big step still runs the whole chain: each link is 0.1 s after the one before.
	schedule.advance(0.45)
	assert_int(count[0]).is_equal(4)


func test_cancel_drops_only_the_tagged_items() -> void:
	var schedule := SoundSchedule.new()
	var ran: Array[String] = []
	schedule.add(0.1, func() -> void: ran.append("a"), &"one")
	schedule.add(0.1, func() -> void: ran.append("b"), &"two")
	assert_int(schedule.cancel(&"one")).is_equal(1)
	schedule.advance(1.0)
	assert_array(ran).is_equal(["b"])
