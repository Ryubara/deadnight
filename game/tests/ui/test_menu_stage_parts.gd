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


func test_the_governor_steps_down_once_per_slow_window_and_never_up() -> void:
	var governor := StageGovernor.new()
	for _i in StageGovernor.WARMUP + StageGovernor.WINDOW:
		governor.feed(1.0 / 60.0)
	assert_int(governor.level).is_equal(StageGovernor.Level.LIVE)
	var changed := false
	for _i in StageGovernor.WINDOW:
		changed = governor.feed(0.03) or changed
	assert_bool(changed).is_true()
	assert_int(governor.level).is_equal(StageGovernor.Level.HALF)
	for _i in StageGovernor.WINDOW:
		governor.feed(0.06)
	assert_int(governor.level).is_equal(StageGovernor.Level.STILL)
	for _i in StageGovernor.WINDOW:
		governor.feed(0.001)
	assert_int(governor.level).is_equal(StageGovernor.Level.STILL)


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
		governor.feed(0.5)
	for index in StageGovernor.WINDOW:
		governor.feed(5.0 if index == 10 else 1.0 / 60.0)
	assert_int(governor.level).is_equal(StageGovernor.Level.LIVE)


func test_the_settings_know_the_stage_and_the_showcase_weapon() -> void:
	assert_int(Settings.DEFAULTS[SettingsService.MENU_SCENE]).is_equal(0)
	assert_str(Settings.DEFAULTS[SettingsService.SHOWCASE_WEAPON]).is_equal("rifle")
	assert_array(MenuHero.available()).contains([&"rifle", &"shotgun"])
