extends GdUnitTestSuite
## The arrival by helicopter in a night played alone (#1057), on both maps: the show begins when the
## night is ready, the server shields the player and keeps them out of it while it plays, the
## player's
## own presses do nothing meanwhile, a press skips it, and the body is theirs again when it ends
## (the
## view, the HUD, the roof). A test, a capture and a bot never see it unless they ask.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const MAPS: Array[String] = ["drive_in", "small_indoor"]

var _night: Night
var _tuning: RulesTuning


func before_test() -> void:
	NightArrival.reset()
	_tuning = RulesFixture.tuning()
	_tuning.rounds.intro_seconds = 60.0
	_tuning.rounds.first_spawn_delay = 600.0
	_tuning.arrival.night_seconds = 2.5
	_tuning.arrival.skip_after = 0.4


func after_test() -> void:
	for action in [&"fire", &"move_forward", &"jump"]:
		Input.action_release(action)
	if is_instance_valid(_night):
		_night.queue_free()
	await get_tree().process_frame
	Audio.stop_all()
	await RouterFixture.clear(get_tree())
	NightScreen.arrival_enabled = DisplayServer.get_name() != "headless"


func after() -> void:
	await Audio.wait_for_mixer()


func _start(map_id: String, arrival := true) -> Night:
	_night = Night.new()
	_night.arrival = arrival
	_night.match_settings.map = map_id
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, _tuning)
	var player := _night.player()
	player.local_input = false
	player.capture_mouse = false
	return _night


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _state() -> PlayerState:
	return _night.server.rules.players[Night.PLAYER_ID]


func _press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	_night.arrival_show._input(event)


func _model_shown() -> bool:
	return (_night.player().get_node("Model") as Node3D).visible


func test_the_show_begins_with_the_night_and_the_server_shields_the_player() -> void:
	for map_id in MAPS:
		await _start(map_id)
		assert_object(_night.arrival_show).is_not_null()
		assert_bool(_night.is_arriving()).is_true()
		await _ticks(4)
		assert_bool(_state().is_dropping()).is_true()
		assert_bool(_night.server.is_dropping(Night.PLAYER_ID)).is_true()
		assert_bool(_night.state.frame["players"][Night.PLAYER_ID]["dropping"]).is_true()
		# The body is the show's: not drawn, and the picture is the show's camera.
		assert_bool(_model_shown()).is_false()
		assert_object(get_viewport().get_camera_3d()).is_not_same(
			_night.player().camera_rig.camera()
		)
		_night.queue_free()
		await get_tree().process_frame


func test_nothing_the_player_presses_reaches_the_night_while_it_plays() -> void:
	await _start("drive_in")
	var start := _night.server.body_of(Night.PLAYER_ID).global_position
	var shots := [0]
	_night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == &"shot_fired":
				shots[0] += 1
	)
	Input.action_press(&"move_forward")
	Input.action_press(&"fire")
	Input.action_press(&"jump")
	await _ticks(45)
	assert_float(_night.server.body_of(Night.PLAYER_ID).global_position.distance_to(start)).is_less(
		0.05
	)
	assert_int(shots[0]).is_equal(0)


func test_nothing_in_the_night_can_hurt_them_meanwhile() -> void:
	await _start("drive_in")
	await _ticks(4)
	var health := _night.server.health_of(Night.PLAYER_ID)
	_night.server.rules.apply(RulesAction.skip_break())
	_night.server.rules.apply(RulesAction.blow(Night.PLAYER_ID, 60.0))
	_night.server._on_player_struck(Night.PLAYER_ID, 1, 60.0)
	_night.server._blast_player(Night.PLAYER_ID, 60.0, Vector3.ZERO, &"grenade", Night.PLAYER_ID)
	assert_float(_night.server.health_of(Night.PLAYER_ID)).is_equal(health)
	# And the dead have nobody to turn to.
	assert_bool(_night.server._chase_targets().has(Night.PLAYER_ID)).is_false()


func test_a_press_skips_it_and_the_body_is_theirs_again() -> void:
	for map_id in MAPS:
		await _start(map_id)
		var roof := _night.world.greybox.get_node_or_null("Ceilings") as Node3D
		if roof != null:
			assert_bool(roof.visible).is_false()
		await _ticks(10)
		_press_key(KEY_SPACE)
		assert_bool(_night.arrival_show.is_over()).is_false()
		await _ticks(40)
		_press_key(KEY_SPACE)
		await _ticks(40)
		assert_bool(_night.is_arriving()).is_false()
		assert_bool(_model_shown()).is_true()
		assert_object(get_viewport().get_camera_3d()).is_same(_night.player().camera_rig.camera())
		if roof != null:
			assert_bool(roof.visible).is_true()
		# The server heard the landing: still shielded for the grace, then not.
		await _ticks(4)
		assert_bool(_state().is_dropping()).is_false()
		assert_bool(_state().dropped).is_true()
		await _ticks(ceili((_tuning.arrival.grace_seconds + 0.3) * 60.0))
		assert_bool(_state().is_shielded()).is_false()
		assert_bool(_night.player().look_locked).is_false()
		_night.queue_free()
		await get_tree().process_frame


func test_a_night_that_ends_under_the_show_ends_the_show_and_the_end_camera_is_the_view() -> void:
	await _start("drive_in")
	await _ticks(5)
	assert_bool(_night.is_arriving()).is_true()
	_night.night_over.emit(3)
	await _ticks(3)
	assert_bool(_night.is_arriving()).is_false()
	assert_object(_night.end_camera).is_not_null()
	assert_object(get_viewport().get_camera_3d()).is_not_same(_night.player().camera_rig.camera())


func test_it_plays_to_its_end_on_its_own() -> void:
	await _start("drive_in")
	await _ticks(ceili(_tuning.arrival.night_seconds * 60.0) + 10)
	assert_bool(_night.is_arriving()).is_false()
	assert_bool(_state().dropped).is_true()


func test_a_test_or_a_bot_never_sees_it_unless_it_asks() -> void:
	await _start("drive_in", false)
	assert_object(_night.arrival_show).is_null()
	assert_bool(_night.is_arriving()).is_false()
	await _ticks(4)
	assert_bool(_state().dropped).is_false()
	assert_bool(_model_shown()).is_true()


func test_a_tuning_that_turns_it_off_or_plays_it_once_a_session() -> void:
	_tuning.arrival.enabled = false
	await _start("drive_in")
	assert_object(_night.arrival_show).is_null()
	_night.queue_free()
	await get_tree().process_frame
	_tuning.arrival.enabled = true
	_tuning.arrival.repeat = ArrivalTuning.Repeat.FIRST_PER_SESSION
	await _start("drive_in")
	assert_object(_night.arrival_show).is_not_null()
	_night.queue_free()
	await get_tree().process_frame
	await _start("drive_in")
	assert_object(_night.arrival_show).is_null()
	_night.queue_free()
	await get_tree().process_frame
	_tuning.arrival.repeat = ArrivalTuning.Repeat.ALWAYS
	await _start("drive_in")
	assert_object(_night.arrival_show).is_not_null()


func test_the_screen_gives_way_to_the_show_and_comes_back() -> void:
	NightScreen.arrival_enabled = true
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	await _ticks(3)
	_night = screen.night
	assert_bool(_night.is_arriving()).is_true()
	var hud := screen.find_children("*", "Hud", true, false)[0] as Hud
	assert_bool(hud.visible).is_false()
	assert_bool(hud.reticle.is_visible_in_tree()).is_false()
	# The screen plays the shipped table: a press counts after its `skip_after`.
	await _ticks(ceili((_night.rules_tuning.arrival.skip_after + 0.2) * 60.0))
	_press_key(KEY_SPACE)
	await _ticks(60)
	assert_bool(_night.is_arriving()).is_false()
	assert_bool(hud.visible).is_true()
	assert_bool(hud.reticle.is_visible_in_tree()).is_true()
	assert_bool(_night.player().controls_enabled()).is_true()
