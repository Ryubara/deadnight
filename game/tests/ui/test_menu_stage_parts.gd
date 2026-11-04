extends GdUnitTestSuite
## The pure parts of the menu's stage: the tabs, the poses, the camera's moves, the wander path and
## the governor that gives the stage up on a slow machine.


func test_tab_neighbours_wrap_round_the_bar() -> void:
	assert_int(MenuTab.neighbour(MenuTab.Id.PLAY, 1)).is_equal(MenuTab.Id.LOADOUT)
	assert_int(MenuTab.neighbour(MenuTab.Id.MORE, 1)).is_equal(MenuTab.Id.PLAY)
	assert_int(MenuTab.neighbour(MenuTab.Id.PLAY, -1)).is_equal(MenuTab.Id.MORE)
	assert_int(MenuTab.ORDER.size()).is_equal(5)
	for tab in MenuTab.ORDER:
		assert_str(MenuTab.label(tab)).is_not_empty()


func test_a_pose_puts_the_focus_where_its_frame_x_says() -> void:
	for tab in MenuTab.ORDER:
		var pose := StagePose.for_tab(tab)
		var placed := pose.place(16.0 / 9.0)
		var camera := Camera3D.new()
		camera.fov = pose.fov
		add_child(camera)
		camera.look_at_from_position(placed[0], placed[1])
		var size := Vector2(1920.0, 1080.0)
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		# Project the focus by hand: the camera is not in a viewport of this size.
		var local := camera.global_transform.affine_inverse() * pose.focus
		var half_height := -local.z * tan(deg_to_rad(pose.fov) * 0.5)
		var across := 0.5 + local.x / (2.0 * half_height * (size.x / size.y))
		assert_float(across).is_equal_approx(pose.frame_x, 0.005)
		camera.free()


func test_a_wider_window_keeps_the_16_by_9_framing() -> void:
	var pose := StagePose.for_tab(MenuTab.Id.CHALLENGES)
	var wide := pose.place(21.0 / 9.0)
	var standard := pose.place(16.0 / 9.0)
	assert_vector(wide[0]).is_equal_approx(standard[0], Vector3.ONE * 0.0001)
	var narrow := pose.place(4.0 / 3.0)
	assert_float(narrow[0].distance_to(standard[0])).is_greater(0.1)


func test_the_rig_arrives_without_overshoot_at_any_frame_rate() -> void:
	var finals: Array[Vector3] = []
	for rate in [30.0, 60.0, 144.0]:
		var camera := Camera3D.new()
		add_child(camera)
		var rig := StageCameraRig.new(camera)
		rig.go_to(MenuTab.Id.PLAY, true)
		rig.step(0.0)
		rig.go_to(MenuTab.Id.LOADOUT)
		var goal: Vector3 = StagePose.for_tab(MenuTab.Id.LOADOUT).place(16.0 / 9.0)[0]
		var worst := 0.0
		var start: Vector3 = StagePose.for_tab(MenuTab.Id.PLAY).place(16.0 / 9.0)[0]
		for _i in int(2.0 * rate):
			rig.step(1.0 / rate)
		# Critically damped: it never passes the goal along the line from the start.
		worst = (camera.position - start).dot((goal - start).normalized())
		assert_bool(rig.arrived()).is_true()
		assert_float(worst).is_less(goal.distance_to(start) + 0.15)
		finals.append(camera.position)
		camera.free()
	assert_float(finals[0].distance_to(finals[2])).is_less(0.1)


func test_reduced_motion_cuts_the_camera() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	var rig := StageCameraRig.new(camera)
	rig.set_reduced(true)
	rig.go_to(MenuTab.Id.MORE)
	assert_bool(rig.arrived()).is_true()
	rig.step(0.016)
	var goal: Vector3 = StagePose.for_tab(MenuTab.Id.MORE).place(16.0 / 9.0)[0]
	assert_vector(camera.position).is_equal_approx(goal, Vector3.ONE * 0.0001)
	camera.free()


func test_a_wander_path_is_a_function_of_time() -> void:
	var loop: Array[Vector3] = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 5)]
	var path := WanderPath.new(loop, 1.0)
	assert_float(path.lap_time()).is_equal_approx(10.0 + 5.0 + sqrt(125.0), 0.001)
	assert_vector(path.position_at(0.0)).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	assert_vector(path.position_at(5.0)).is_equal_approx(Vector3(5, 0, 0), Vector3.ONE * 0.001)
	assert_vector(path.heading_at(5.0)).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.001)
	assert_vector(path.position_at(path.lap_time() + 5.0)).is_equal_approx(
		path.position_at(5.0), Vector3.ONE * 0.001
	)


## Feeds the governor `seconds` of frames of `frame` seconds; returns how many times the level
## changed.
func _run(governor: StageGovernor, seconds: float, frame: float) -> int:
	var changes := 0
	var elapsed := 0.0
	while elapsed < seconds:
		if governor.feed(frame):
			changes += 1
		elapsed += frame
	return changes


func _warmed() -> StageGovernor:
	var governor := StageGovernor.new()
	_run(governor, StageGovernor.WARMUP_SECONDS, 1.0 / 60.0)
	return governor


func test_the_governor_steps_down_after_two_slow_windows_and_not_one() -> void:
	var governor := _warmed()
	assert_int(governor.level).is_equal(StageGovernor.Level.LIVE)
	# One slow window (a busy second at launch) is not a trend.
	_run(governor, StageGovernor.WINDOW_SECONDS + 0.2, 0.03)
	assert_int(governor.level).is_equal(StageGovernor.Level.LIVE)
	_run(governor, StageGovernor.WINDOW_SECONDS * 2.0, 1.0 / 60.0)
	assert_int(governor.level).is_equal(StageGovernor.Level.LIVE)
	# Two in a row are.
	var changed := _run(governor, StageGovernor.WINDOW_SECONDS * 3.0, 0.03)
	assert_int(changed).is_equal(1)
	assert_int(governor.level).is_equal(StageGovernor.Level.HALF)
	# At half, too slow again for two windows: the still.
	_run(governor, StageGovernor.WINDOW_SECONDS * 3.0, 0.06)
	assert_int(governor.level).is_equal(StageGovernor.Level.STILL)
	_run(governor, 10.0, 0.001)
	assert_int(governor.level).is_equal(StageGovernor.Level.STILL)


func test_the_stage_climbs_back_to_live_when_frames_recover() -> void:
	var governor := _warmed()
	_run(governor, 5.0, 0.03)
	assert_int(governor.level).is_equal(StageGovernor.Level.HALF)
	# A 60 Hz display held at half resolution for a few windows: back to live, once.
	var seconds := governor.seconds_to_climb() + StageGovernor.WINDOW_SECONDS * 4.0
	var changed := _run(governor, seconds, 1.0 / 60.0)
	assert_int(changed).is_equal(1)
	assert_int(governor.level).is_equal(StageGovernor.Level.LIVE)
	assert_int(governor.failed_climbs).is_equal(0)


func test_a_fast_display_does_not_hurry_the_climb() -> void:
	var governor := _warmed()
	_run(governor, 5.0, 0.03)
	assert_int(governor.level).is_equal(StageGovernor.Level.HALF)
	# 240 frames a second fill a window of 90 frames in 0.4 s: the wait is in seconds.
	_run(governor, StageGovernor.RECOVER_SECONDS - 2.0, 1.0 / 240.0)
	assert_int(governor.level).is_equal(StageGovernor.Level.HALF)
	_run(governor, 3.0, 1.0 / 240.0)
	assert_int(governor.level).is_equal(StageGovernor.Level.LIVE)


func test_a_stage_that_is_only_just_holding_does_not_climb() -> void:
	var governor := _warmed()
	_run(governor, 5.0, 0.03)
	assert_int(governor.level).is_equal(StageGovernor.Level.HALF)
	# 30 frames a second at half: fine to stay, nothing to say live would hold.
	_run(governor, 60.0, 0.033)
	assert_int(governor.level).is_equal(StageGovernor.Level.HALF)


func test_a_climb_that_fails_waits_longer_and_stops_after_two() -> void:
	var governor := _warmed()
	var climbs_needed := []
	var drops := 0
	var climbs := 0
	for _round in 3:
		# Slow until it is at half.
		var guard := 0.0
		while governor.level == StageGovernor.Level.LIVE and guard < 30.0:
			governor.feed(0.03)
			guard += 0.03
		if governor.level != StageGovernor.Level.HALF:
			break
		drops += 1
		climbs_needed.append(governor.seconds_to_climb())
		# Fast until it climbs, if it will.
		guard = 0.0
		while governor.level == StageGovernor.Level.HALF and guard < 200.0:
			if governor.feed(1.0 / 60.0):
				climbs += 1
			guard += 1.0 / 60.0
	# The wait doubles after each failed climb; after two failures the stage stays at half.
	assert_array(climbs_needed).is_equal([4.5, 9.0, 18.0])
	assert_int(governor.failed_climbs).is_equal(StageGovernor.MAX_FAILED_CLIMBS)
	assert_bool(governor.can_climb()).is_false()
	# Good frames for as long as it likes: it stays at half, the look does not flicker.
	_run(governor, 120.0, 1.0 / 60.0)
	assert_int(governor.level).is_equal(StageGovernor.Level.HALF)
	assert_int(climbs).is_equal(2)
	assert_int(drops).is_equal(3)


func test_a_drop_long_after_a_climb_is_not_a_failed_climb() -> void:
	var governor := _warmed()
	_run(governor, 5.0, 0.03)
	_run(governor, 30.0, 1.0 / 60.0)
	assert_int(governor.level).is_equal(StageGovernor.Level.LIVE)
	# A minute of good frames, then another program starts: that is not the stage's fault.
	_run(governor, StageGovernor.PROBATION_SECONDS + 5.0, 1.0 / 60.0)
	_run(governor, 5.0, 0.03)
	assert_int(governor.level).is_equal(StageGovernor.Level.HALF)
	assert_int(governor.failed_climbs).is_equal(0)


func test_a_machine_that_draws_a_few_frames_a_second_goes_straight_to_the_still() -> void:
	var governor := StageGovernor.new()
	var frames := 0
	while governor.level == StageGovernor.Level.LIVE and frames < 100:
		governor.feed(0.38)
		frames += 1
	assert_int(governor.level).is_equal(StageGovernor.Level.STILL)
	# Judged in a few seconds of its own slow time, not after a minute of frames.
	assert_int(frames).is_less(StageGovernor.WARMUP + StageGovernor.MIN_FRAMES + 2)


func test_one_long_frame_is_not_a_trend() -> void:
	var governor := StageGovernor.new()
	for _i in StageGovernor.WARMUP:
		governor.feed(0.2)
	for index in StageGovernor.WINDOW * 3:
		governor.feed(5.0 if index == 10 else 1.0 / 60.0)
	assert_int(governor.level).is_equal(StageGovernor.Level.LIVE)


func test_the_stage_is_drawn_in_the_windows_own_pixels_and_4x() -> void:
	# A 2560 x 1440 window has a 1920 x 1080 control (the canvas stretch) scaled by 4/3.
	assert_vector(MenuStageView.render_size_for(Vector2(1920, 1080), 4.0 / 3.0, false)).is_equal(
		Vector2i(2560, 1440)
	)
	assert_vector(MenuStageView.render_size_for(Vector2(1920, 1080), 1.0, true)).is_equal(
		Vector2i(960, 540)
	)
	# A phone page (1688 x 780 pixels) has a 2337 x 1080 control scaled by 0.722: its own pixels.
	(
		assert_vector(MenuStageView.render_size_for(Vector2(2337, 1080), 780.0 / 1080.0, false))
		. is_equal(Vector2i(1688, 780))
	)
	# A 4K window is drawn at 1440p.
	assert_vector(MenuStageView.render_size_for(Vector2(1920, 1080), 2.0, false)).is_equal(
		Vector2i(2560, 1440)
	)
	assert_int(MenuStageView.MSAA).is_equal(Viewport.MSAA_4X)


func test_the_settings_know_the_stage_and_the_showcase_weapon() -> void:
	assert_int(Settings.DEFAULTS[SettingsService.MENU_SCENE]).is_equal(0)
	assert_str(Settings.DEFAULTS[SettingsService.SHOWCASE_WEAPON]).is_equal("rifle")
	assert_array(MenuHero.available()).contains([&"rifle", &"shotgun"])


func test_a_cpu_renderer_is_told_by_its_name() -> void:
	for name in [
		"ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero)), SwiftShader driver)",
		"llvmpipe (LLVM 15.0.7, 256 bits)",
		"Microsoft Basic Render Driver",
	]:
		assert_bool(StageGovernor.is_software(name)).is_true()
	for name in [
		"ANGLE (NVIDIA, NVIDIA GeForce RTX 5080 Direct3D11 vs_5_0 ps_5_0)", "Adreno (TM) 650", ""
	]:
		assert_bool(StageGovernor.is_software(name)).is_false()


func test_the_warm_up_ends_after_a_few_seconds_when_the_frames_are_long() -> void:
	var governor := StageGovernor.new()
	var frames := 0
	# One frame a second: twelve of them would be twelve seconds of warm-up; four are enough.
	while governor.level == StageGovernor.Level.LIVE and frames < 100:
		governor.feed(1.0)
		frames += 1
	assert_int(governor.level).is_equal(StageGovernor.Level.STILL)
	assert_int(frames).is_less_equal(
		int(StageGovernor.WARMUP_SECONDS) + StageGovernor.MIN_FRAMES + 1
	)
