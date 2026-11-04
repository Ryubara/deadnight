extends GdUnitTestSuite
## `AudioSettle.until_idle` leaves nothing for the `Audio` service to do in the frames that follow:
## a count of objects taken across them does not move (Deadnight #1102).

## Frames the engine is given to make what it keeps, and frames counted after them.
const WARM_FRAMES := 5
const FRAMES := 30
## Objects the count may move by (a frame of the engine's own).
const JITTER := 2


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func test_a_background_load_that_is_under_way_does_not_move_a_count_after_the_settle() -> void:
	var service: AudioService = auto_free(AudioService.new())
	add_child(service)
	service.start_background_preload()
	# A frame long enough to be past the first second's wait: it loads and decodes a slice of the
	# sounds (the menu's load, in the frames of the suite that runs next).
	service._process(2.0)
	var under_way := service.background_preloading()
	await AudioSettle.until_idle(get_tree(), service)
	# The frames right after any step of the engine's own make a few objects that stay.
	for _i in WARM_FRAMES:
		await get_tree().process_frame
	var before := _objects()
	for _i in FRAMES:
		await get_tree().process_frame
	var after := _objects()
	assert_bool(under_way).override_failure_message("the load was not under way").is_true()
	assert_bool(service.background_preloading()).is_false()
	(
		assert_int(absi(after - before))
		. override_failure_message("objects %d -> %d over %d frames" % [before, after, FRAMES])
		. is_less_equal(JITTER)
	)
