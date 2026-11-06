extends GdUnitTestSuite
## TEMPORARY probe for #1348: what the runner's virtual display does with the window.


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func test_probe() -> void:
	print(
		(
			"PROBE display=%s screen=%s usable=%s window=%s mode=%s content=%s"
			% [
				DisplayServer.get_name(),
				DisplayServer.screen_get_size(),
				DisplayServer.screen_get_usable_rect(),
				DisplayServer.window_get_size(),
				DisplayServer.window_get_mode(),
				get_window().content_scale_factor,
			]
		)
	)
	for size in [
		Vector2i(1688, 780),
		Vector2i(1920, 1080),
		Vector2i(2340, 1080),
		Vector2i(2560, 1080),
		Vector2i(2880, 1620)
	]:
		get_window().size = size
		await _frames(3)
		print(
			(
				"PROBE set %s got window=%s display=%s root=%s"
				% [size, get_window().size, DisplayServer.window_get_size(), get_tree().root.size]
			)
		)
	get_window().size = Vector2i(1152, 648)
	await _frames(3)
	var drawn := Engine.get_frames_drawn()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	await _frames(2)
	print("PROBE after minimize: mode=%s" % DisplayServer.window_get_mode())
	var before := Engine.get_frames_drawn()
	await _frames(30)
	print(
		(
			"PROBE minimized: drawn %d -> %d (frames before the call %d)"
			% [before, Engine.get_frames_drawn(), drawn]
		)
	)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await _frames(5)
	print(
		(
			"PROBE restored: mode=%s drawn=%d"
			% [DisplayServer.window_get_mode(), Engine.get_frames_drawn()]
		)
	)
	var out: Array = []
	OS.execute(
		"sh",
		["-c", "echo DISPLAY=$DISPLAY; ps -e -o comm | sort | uniq -c | sort -rn | head -20"],
		out
	)
	print("PROBE env\n", "\n".join(out))
	assert_bool(true).is_true()
