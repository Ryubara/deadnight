# WebSocketLink measures time by its `clock` when it has one (game time in a test), by the real
# clock otherwise (#528).
extends GdUnitTestSuite

var _seconds := 0.0


func _fake_clock() -> float:
	return _seconds


func test_without_a_clock_it_reads_the_real_time() -> void:
	var link: WebSocketLink = auto_free(WebSocketLink.new())
	var before := Time.get_ticks_usec() / 1000000.0
	var now := link._now()
	assert_float(now).is_between(before, before + 1.0)
	assert_int(link._now_msec()).is_greater_equal(int(before * 1000.0))


func test_with_a_clock_every_reading_follows_it_and_not_the_wall() -> void:
	var link: WebSocketLink = auto_free(WebSocketLink.new())
	link.clock = _fake_clock
	_seconds = 12.5
	assert_float(link._now()).is_equal(12.5)
	assert_int(link._now_msec()).is_equal(12500)
	_seconds = 12.75
	assert_float(link._now()).is_equal(12.75)
	assert_int(link._now_msec()).is_equal(12750)
