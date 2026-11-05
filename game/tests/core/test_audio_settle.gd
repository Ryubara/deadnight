extends GdUnitTestSuite
## `AudioSettle.until_idle` leaves nothing for the `Audio` service to do in the frames that follow:
## a count of objects taken across them does not move (Deadnight #1102).

## Frames the engine is given to make what it keeps, and frames counted after them.
const WARM_FRAMES := 5
const FRAMES := 30
## Objects the count may move by (a frame of the engine's own).
const JITTER := 2
## Sounds an earlier suite is taken to have left playing on the `Audio` autoload.
const LEFTOVER_SOUNDS := 12


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


## Starts sounds on the autoload and leaves them: what a night run by the suite before leaves
## playing (its zombies' voices, a sting) while the next suite starts.
func _leave_sounds_playing() -> void:
	var started := 0
	for id: StringName in SoundCatalog.ids_for_night():
		if started >= LEFTOVER_SOUNDS:
			break
		var def := SoundCatalog.get_def(id)
		if not def.loop and not def.deferred and Audio.play(id) != null:
			started += 1


func test_a_background_load_that_is_under_way_does_not_move_a_count_after_the_settle() -> void:
	# The suite before may have left sounds playing, each one's playback freed in a frame of its
	# own as it ends: objects that fall during the count (5 and 8 on two pull requests, #1134).
	# That is the suite before's motion, not the load's, so it is brought to a standstill first.
	_leave_sounds_playing()
	assert_bool(await QuietCount.settle(get_tree())).is_true()
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
