# gdlint:disable=max-public-methods
# The touch controls driven by real touch events: each finger has one job, and the game's own
# input actions follow.
extends GdUnitTestSuite

var _fixture: TouchFixture


func before_test() -> void:
	_fixture = TouchFixture.make(self)


func after_test() -> void:
	_fixture.free_all()


func _move() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


func test_the_stick_floats_under_the_thumb_and_moves_right() -> void:
	var start := Vector2(300.0, 700.0)
	await _fixture.touch(0, start)
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	assert_float(_move().length()).is_equal(0.0)
	await _fixture.drag(0, start + Vector2(90.0, 0.0), Vector2(90.0, 0.0))
	assert_float(_move().x).is_greater(0.6)
	assert_float(absf(_move().y)).is_less(0.05)
	await _fixture.lift(0)
	assert_float(_move().length()).is_equal(0.0)
	assert_bool(_fixture.controls.is_stick_down()).is_false()


func test_pushing_the_stick_up_walks_forward_and_past_the_edge_sprints() -> void:
	var start := Vector2(300.0, 800.0)
	var edge := _fixture.controls.stick_radius()
	await _fixture.touch(0, start)
	await _fixture.drag(0, start + Vector2(0.0, -60.0), Vector2(0.0, -60.0))
	assert_float(Input.get_action_strength(&"move_forward")).is_greater(0.3)
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()
	# The edge itself is a full walk, not a sprint (#1276).
	await _fixture.drag(0, start + Vector2(0.0, -edge), Vector2(0.0, 60.0 - edge))
	assert_float(Input.get_action_strength(&"move_forward")).is_equal_approx(1.0, 0.001)
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()
	var past := edge + _fixture.controls.sprint_margin() + 5.0
	await _fixture.drag(0, start + Vector2(0.0, -past), Vector2(0.0, edge - past))
	assert_bool(_fixture.controls.is_sprinting()).is_true()
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	# Easing back no longer ends it: only the lift does.
	await _fixture.drag(0, start + Vector2(0.0, -60.0), Vector2(0.0, past - 60.0))
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	await _fixture.lift(0)
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()


func test_a_thumb_past_the_rim_drags_the_stick_base_along() -> void:
	var start := Vector2(300.0, 800.0)
	await _fixture.touch(0, start)
	await _fixture.drag(0, start + Vector2(400.0, 0.0), Vector2(400.0, 0.0))
	assert_float(_fixture.controls.stick_vector().x).is_equal_approx(1.0, 0.01)
	await _fixture.drag(0, start + Vector2(300.0, 0.0), Vector2(-100.0, 0.0))
	# The base followed to one radius behind the finger, so a short pull back already slows.
	assert_float(_fixture.controls.stick_vector().x).is_less(0.85)
	await _fixture.lift(0)


func test_a_drag_on_the_right_looks_in_proportion_to_the_screen_height() -> void:
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	await _fixture.touch(0, Vector2(1700.0, 300.0))
	await _fixture.drag(0, Vector2(1800.0, 300.0), Vector2(100.0, 0.0))
	await _fixture.drag(0, Vector2(1800.0, 360.0), Vector2(0.0, 60.0))
	assert_int(looks.size()).is_equal(2)
	assert_float(looks[0].x).is_greater(0.0)
	assert_float(looks[0].y).is_equal(0.0)
	assert_float(looks[1].y).is_greater(0.0)
	# 100 units of a 1080 tall canvas, at 3.2 rad per height, in mouse pixels.
	var turn := TouchLook.tuning.radians_per_height * 100.0 / 1080.0
	assert_float(looks[0].x).is_equal_approx(turn / TouchLook.mouse_radians_per_pixel, 0.01)
	await _fixture.lift(0)


func test_a_fast_flick_turns_further_than_a_slow_drag() -> void:
	var slow := TouchLook.mouse_equivalent(Vector2(100.0, 0.0), 200.0, 1080.0)
	var fast := TouchLook.mouse_equivalent(Vector2(100.0, 0.0), 3000.0, 1080.0)
	assert_float(fast.x / slow.x).is_equal_approx(TouchLook.tuning.max_gain, 0.001)


func test_the_same_swipe_turns_the_same_on_any_screen_height() -> void:
	var phone := TouchLook.mouse_equivalent(Vector2(0.0, 108.0), 0.0, 1080.0)
	var tablet := TouchLook.mouse_equivalent(Vector2(0.0, 144.0), 0.0, 1440.0)
	assert_float(phone.y).is_equal_approx(tablet.y, 0.001)


func test_fire_is_held_while_the_thumb_is_on_it_and_a_drag_from_it_looks() -> void:
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	var fire := _fixture.at(TouchLayout.FIRE)
	await _fixture.touch(0, fire)
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	await _fixture.drag(0, fire + Vector2(40.0, 0.0), Vector2(40.0, 0.0))
	assert_int(looks.size()).is_equal(1)
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	await _fixture.lift(0)
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"fire")).is_false()


func test_a_quick_tap_still_lasts_long_enough_for_a_physics_tick_to_see() -> void:
	var jump := _fixture.at(TouchLayout.JUMP)
	await _fixture.tap(jump)
	# Lifted in the same frame, but held for the minimum so the next physics tick sees it.
	assert_bool(Input.is_action_pressed(&"jump")).is_true()
	await await_millis(300)
	assert_bool(Input.is_action_pressed(&"jump")).is_false()


func test_each_button_presses_its_action() -> void:
	var ids: Array[StringName] = [TouchLayout.AIM, TouchLayout.RELOAD]
	for id in ids:
		var point := _fixture.at(id)
		await _fixture.touch(0, point)
		assert_bool(Input.is_action_pressed(id)).override_failure_message(str(id)).is_true()
		await _fixture.lift(0, point)
		await await_millis(250)
		assert_bool(Input.is_action_pressed(id)).is_false()


func test_aim_is_held_while_the_thumb_is_on_it_with_auto_fire_on() -> void:
	var aim := _fixture.at(TouchLayout.AIM)
	await _fixture.touch(0, aim)
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	await _fixture.lift(0, aim)
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"aim")).is_false()


func test_aim_is_a_toggle_with_auto_fire_off() -> void:
	_fixture.auto_fire(false)
	var aim := _fixture.at(TouchLayout.AIM)
	await _fixture.touch(0, aim)
	await _fixture.lift(0, aim)
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	assert_bool(_fixture.controls.is_aim_latched()).is_true()
	await _fixture.touch(0, aim)
	await _fixture.lift(0, aim)
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"aim")).is_false()
	assert_bool(_fixture.controls.is_aim_latched()).is_false()


func test_fire_shoots_with_aim_toggled_on_and_from_the_hip_and_leaves_the_aim_alone() -> void:
	_fixture.auto_fire(false)
	var fire := _fixture.at(TouchLayout.FIRE)
	await _fixture.touch(0, fire)
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	assert_bool(Input.is_action_pressed(&"aim")).is_false()
	await _fixture.lift(0, fire)
	await await_millis(250)
	var aim := _fixture.at(TouchLayout.AIM)
	await _fixture.tap(aim)
	await await_millis(250)
	await _fixture.touch(1, fire)
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	await _fixture.lift(1, fire)
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	await _fixture.tap(aim)
	await await_millis(250)


func test_fire_shoots_while_aim_is_held_with_auto_fire_on() -> void:
	await _fixture.touch(0, _fixture.at(TouchLayout.AIM))
	await _fixture.touch(1, _fixture.at(TouchLayout.FIRE))
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	await _fixture.lift(1)
	await _fixture.lift(0)


func test_changing_auto_fire_or_hiding_the_layer_lets_go_of_a_toggled_aim() -> void:
	_fixture.auto_fire(false)
	await _fixture.tap(_fixture.at(TouchLayout.AIM))
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	_fixture.auto_fire(true)
	assert_bool(Input.is_action_pressed(&"aim")).is_false()
	_fixture.auto_fire(false)
	await _fixture.tap(_fixture.at(TouchLayout.AIM))
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	_fixture.controls.live = false
	assert_bool(Input.is_action_pressed(&"aim")).is_false()
	_fixture.controls.live = true


func test_stick_look_and_fire_work_together_with_three_fingers() -> void:
	await _fixture.touch(0, Vector2(300.0, 800.0))
	await _fixture.drag(0, Vector2(380.0, 800.0), Vector2(80.0, 0.0))
	await _fixture.touch(1, _fixture.at(TouchLayout.FIRE))
	await _fixture.touch(2, Vector2(1500.0, 250.0))
	assert_float(Input.get_action_strength(&"move_right")).is_greater(0.3)
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	await _fixture.drag(2, Vector2(1560.0, 250.0), Vector2(60.0, 0.0))
	assert_int(looks.size()).is_equal(1)
	# Lifting the look finger leaves the others alone.
	await _fixture.lift(2)
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	assert_float(Input.get_action_strength(&"move_right")).is_greater(0.3)
	await _fixture.lift(1)
	await _fixture.lift(0)


func test_interact_shows_only_next_to_something_usable_and_names_it() -> void:
	var state := HudState.new()
	_fixture.free_all()
	_fixture = TouchFixture.make(self, TouchFixture.PHONE, state)
	await get_tree().process_frame
	assert_str(_fixture.controls.interact_verb()).is_equal("")
	# Hidden, so a touch where it would be is a look, not a use.
	await _fixture.touch(0, _fixture.at(TouchLayout.INTERACT))
	await await_millis(150)
	assert_bool(Input.is_action_pressed(&"interact")).is_false()
	await _fixture.lift(0)
	state.set_prompt(&"repair", "Boarded window", 0)
	await get_tree().process_frame
	assert_str(_fixture.controls.interact_verb()).is_equal("HOLD")
	await _fixture.touch(0, _fixture.at(TouchLayout.INTERACT))
	assert_bool(Input.is_action_pressed(&"interact")).is_true()
	await _fixture.lift(0)
	state.set_prompt(&"buy_door", "Projection booth door", 750)
	await get_tree().process_frame
	assert_str(_fixture.controls.interact_verb()).is_equal("OPEN")
	state.clear_prompt()
	await get_tree().process_frame
	assert_str(_fixture.controls.interact_verb()).is_equal("")


func test_interact_lets_go_if_the_prompt_goes_while_held() -> void:
	var state := HudState.new()
	_fixture.free_all()
	_fixture = TouchFixture.make(self, TouchFixture.PHONE, state)
	state.set_prompt(&"buy_ammo", "Ammo", 100)
	await get_tree().process_frame
	await _fixture.touch(0, _fixture.at(TouchLayout.INTERACT))
	assert_bool(Input.is_action_pressed(&"interact")).is_true()
	state.clear_prompt()
	await await_millis(300)
	assert_bool(Input.is_action_pressed(&"interact")).is_false()


func test_the_pause_button_sends_the_pause_action() -> void:
	var spy := PauseSpy.new()
	add_child(spy)
	await _fixture.touch(0, _fixture.at(TouchLayout.PAUSE))
	await _fixture.lift(0)
	await get_tree().process_frame
	assert_int(spy.pressed).is_equal(1)
	spy.free()


func test_touches_do_nothing_while_the_layer_is_off() -> void:
	TouchMode.device_is_touch = false
	_fixture.controls.refresh()
	assert_bool(_fixture.controls.is_active()).is_false()
	assert_bool(Input.emulate_mouse_from_touch).is_true()
	await _fixture.touch(0, _fixture.at(TouchLayout.FIRE))
	assert_bool(Input.is_action_pressed(&"fire")).is_false()


func test_a_menu_up_hides_the_layer_lets_go_and_gives_the_mouse_emulation_back() -> void:
	await _fixture.touch(0, _fixture.at(TouchLayout.FIRE))
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	assert_bool(Input.emulate_mouse_from_touch).is_false()
	_fixture.controls.live = false
	assert_bool(Input.is_action_pressed(&"fire")).is_false()
	assert_bool(Input.emulate_mouse_from_touch).is_true()
	assert_bool(_fixture.controls.visible).is_false()
	_fixture.controls.live = true
	assert_bool(_fixture.controls.is_active()).is_true()


func test_freeing_the_fixture_lets_go_of_a_mouse_button_a_finger_left_down() -> void:
	# A finger down on a layer that is off is the engine's emulated left mouse button, and a test
	# can end with the finger still down: the night's trigger of a later suite would read it
	# (`test_night_pad_pause`, when it ran after this suite).
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	assert_bool(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)).is_true()
	_fixture.free_all()
	assert_bool(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)).is_false()


func test_held_upright_the_layer_waits_for_landscape() -> void:
	_fixture.free_all()
	_fixture = TouchFixture.make(self, Vector2(1080.0, 1920.0))
	assert_bool(_fixture.controls.is_portrait()).is_true()
	assert_bool(_fixture.controls.is_active()).is_false()


func test_the_setting_forces_the_controls_on_or_off() -> void:
	var settings: SettingsService = get_tree().root.get_node("Settings")
	var before: Variant = settings.get_value(SettingsService.TOUCH_CONTROLS)
	TouchMode.device_is_touch = false
	settings.set_value(SettingsService.TOUCH_CONTROLS, TouchMode.Choice.ON)
	assert_bool(TouchMode.wanted(get_tree())).is_true()
	settings.set_value(SettingsService.TOUCH_CONTROLS, TouchMode.Choice.AUTO)
	assert_bool(TouchMode.wanted(get_tree())).is_false()
	TouchMode.device_is_touch = true
	assert_bool(TouchMode.wanted(get_tree())).is_true()
	settings.set_value(SettingsService.TOUCH_CONTROLS, TouchMode.Choice.OFF)
	assert_bool(TouchMode.wanted(get_tree())).is_false()
	settings.set_value(SettingsService.TOUCH_CONTROLS, before)


# --- The shoulder button and the left hand ---


func test_the_shoulder_button_presses_swap_shoulder_and_a_quick_tap_still_lasts() -> void:
	await _fixture.touch(0, _fixture.at(TouchLayout.SHOULDER))
	assert_bool(Input.is_action_pressed(&"swap_shoulder")).is_true()
	await _fixture.lift(0)
	await _fixture.tap(_fixture.at(TouchLayout.SHOULDER))
	assert_bool(Input.is_action_pressed(&"swap_shoulder")).is_true()
	await await_millis(200)
	assert_bool(Input.is_action_pressed(&"swap_shoulder")).is_false()


# --- The right thumb's buttons (#1277): every one looks while it drags ---


## The buttons whose finger looks while it drags, less Interact (it needs a prompt).
func _looking_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for row in TouchLayout.BUTTONS:
		var id: StringName = row[0]
		if id != TouchLayout.INTERACT and TouchLayout.looks_when_dragged(id):
			found.append(id)
	return found


func test_a_finger_on_any_right_button_also_looks_while_it_drags() -> void:
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	for id in _looking_ids():
		looks.clear()
		var point := _fixture.at(id)
		await _fixture.touch(0, point)
		await _fixture.drag(0, point + Vector2(-40.0, 0.0), Vector2(-40.0, 0.0))
		await _fixture.drag(0, point + Vector2(-40.0, 30.0), Vector2(0.0, 30.0))
		(
			assert_int(looks.size())
			. override_failure_message("a drag from %s did not look" % id)
			. is_equal(2)
		)
		assert_float(looks[0].x).is_less(0.0)
		assert_float(looks[1].y).is_greater(0.0)
		await _fixture.lift(0)
		await await_millis(250)


func test_a_drag_from_the_bot_wheel_picks_an_order_and_does_not_look() -> void:
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	var point := _fixture.at(TouchLayout.BOT_WHEEL)
	await _fixture.touch(0, point)
	await _fixture.drag(0, point + Vector2(-40.0, 0.0), Vector2(-40.0, 0.0))
	assert_int(looks.size()).is_equal(0)
	assert_bool(_fixture.controls.has_wheel_finger()).is_true()
	await _fixture.lift(0)


func test_interact_looks_while_it_drags_too() -> void:
	var state := HudState.new()
	_fixture.free_all()
	_fixture = TouchFixture.make(self, TouchFixture.PHONE, state)
	state.set_prompt(&"repair", "Boarded window", 0)
	await get_tree().process_frame
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	var point := _fixture.at(TouchLayout.INTERACT)
	await _fixture.touch(0, point)
	await _fixture.drag(0, point + Vector2(0.0, -40.0), Vector2(0.0, -40.0))
	assert_int(looks.size()).is_equal(1)
	assert_bool(Input.is_action_pressed(&"interact")).is_true()
	await _fixture.lift(0)


func test_reload_and_jump_fire_on_the_press_and_hand_the_rest_of_the_drag_to_the_look() -> void:
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	for id: StringName in [TouchLayout.RELOAD, TouchLayout.JUMP]:
		looks.clear()
		var point := _fixture.at(id)
		await _fixture.touch(0, point)
		# The press has fired before the finger has moved.
		assert_bool(Input.is_action_pressed(id)).override_failure_message(str(id)).is_true()
		assert_int(looks.size()).is_equal(0)
		await _fixture.drag(0, point + Vector2(-90.0, -20.0), Vector2(-90.0, -20.0))
		assert_int(looks.size()).is_equal(1)
		# The finger lifts after a long drag and the action lets go after its least hold.
		await _fixture.lift(0)
		await await_millis(250)
		assert_bool(Input.is_action_pressed(id)).is_false()


func test_a_look_that_begins_beside_reload_is_not_eaten_by_it_when_it_drags_across() -> void:
	var circle := _fixture.controls.button_circle(TouchLayout.RELOAD)
	var centre: Vector2 = circle[&"centre"]
	# Just outside the hit area, on the side away from Fire: free ground, so a look.
	var away := (centre - _fixture.at(TouchLayout.FIRE)).normalized()
	var start := centre + away * (float(circle[&"hit"]) + 10.0)
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	await _fixture.touch(0, start)
	assert_bool(Input.is_action_pressed(&"reload")).is_false()
	# ... across Reload and out the other side: the look goes on, and nothing is pressed.
	var at := start
	for _step in 6:
		var next := at - away * 60.0
		await _fixture.drag(0, next, next - at)
		at = next
	assert_int(looks.size()).is_equal(6)
	assert_bool(Input.is_action_pressed(&"reload")).is_false()
	await _fixture.lift(0)


func test_a_finger_in_the_margin_round_reload_presses_it_and_looks() -> void:
	var circle := _fixture.controls.button_circle(TouchLayout.RELOAD)
	var centre: Vector2 = circle[&"centre"]
	var away := (centre - _fixture.at(TouchLayout.FIRE)).normalized()
	# Past the drawn rim, inside the area a thumb may land (the fingertip floor).
	var start := centre + away * (float(circle[&"radius"]) + 4.0)
	assert_float(start.distance_to(centre)).is_less(float(circle[&"hit"]))
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	await _fixture.touch(0, start)
	assert_bool(Input.is_action_pressed(&"reload")).is_true()
	await _fixture.drag(0, start + Vector2(0.0, -50.0), Vector2(0.0, -50.0))
	assert_int(looks.size()).is_equal(1)
	await _fixture.lift(0)


func test_a_look_and_a_button_finger_turn_the_view_together() -> void:
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	await _fixture.touch(0, Vector2(1500.0, 250.0))
	var point := _fixture.at(TouchLayout.JUMP)
	await _fixture.touch(1, point)
	await _fixture.drag(1, point + Vector2(-30.0, 0.0), Vector2(-30.0, 0.0))
	await _fixture.drag(0, Vector2(1560.0, 250.0), Vector2(60.0, 0.0))
	assert_int(looks.size()).is_equal(2)
	await _fixture.lift(1)
	await _fixture.lift(0)


# --- Crouch is a toggle ---


func test_a_tap_on_crouch_crouches_and_stays_crouched_until_the_next_tap() -> void:
	var point := _fixture.at(TouchLayout.CROUCH)
	await _fixture.tap(point)
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"crouch")).is_true()
	assert_bool(_fixture.controls.is_crouch_latched()).is_true()
	await _fixture.tap(point)
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"crouch")).is_false()
	assert_bool(_fixture.controls.is_crouch_latched()).is_false()


func test_jump_stands_a_crouched_thumb_up_and_still_jumps() -> void:
	await _fixture.tap(_fixture.at(TouchLayout.CROUCH))
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"crouch")).is_true()
	await _fixture.touch(0, _fixture.at(TouchLayout.JUMP))
	assert_bool(Input.is_action_pressed(&"crouch")).is_false()
	assert_bool(Input.is_action_pressed(&"jump")).is_true()
	assert_bool(_fixture.controls.is_crouch_latched()).is_false()
	await _fixture.lift(0)


func test_hiding_the_layer_lets_go_of_a_crouch() -> void:
	await _fixture.tap(_fixture.at(TouchLayout.CROUCH))
	await await_millis(250)
	_fixture.controls.live = false
	assert_bool(Input.is_action_pressed(&"crouch")).is_false()
	assert_bool(_fixture.controls.is_crouch_latched()).is_false()
	_fixture.controls.live = true


# --- Icons, no words ---


func test_every_control_shows_an_icon_and_no_caption_table_is_left() -> void:
	for row in TouchLayout.BUTTONS:
		assert_bool(TouchIcons.has_icon(row[0])).override_failure_message(str(row[0])).is_true()
	for id in [TouchLayout.PAUSE, TouchLayout.PING]:
		assert_bool(TouchIcons.has_icon(id)).override_failure_message(str(id)).is_true()
	# The words are gone: the only one left is the interact button's verb.
	assert_bool(_fixture.controls.get_script().get_script_constant_map().has("LABELS")).is_false()
	for id: StringName in _fixture.controls.circles():
		var shapes := HudShapes.new()
		var circle: Dictionary = _fixture.controls.button_circle(id)
		TouchIcons.add(shapes, id, circle[&"centre"], circle[&"radius"], Color.WHITE, Color.BLACK)
		assert_bool(shapes.is_empty()).override_failure_message(str(id)).is_false()


func test_each_icon_fits_inside_its_button() -> void:
	for id: StringName in _fixture.controls.circles():
		var shapes := HudShapes.new()
		TouchIcons.add(shapes, id, Vector2.ZERO, 100.0, Color.WHITE, Color.BLACK)
		var reach := 0.0
		for point in shapes._points:
			reach = maxf(reach, point.length())
		# Inside the rim, with the stroke's own width to spare.
		(
			assert_float(reach)
			. override_failure_message("%s reaches %.1f of 100" % [id, reach])
			. is_less(100.0 * 0.95)
		)


func test_a_left_handed_layout_puts_the_stick_on_the_right_and_fire_on_the_left() -> void:
	var mirrored: Array[bool] = []
	_fixture.controls.mirrored_changed.connect(func(on: bool) -> void: mirrored.append(on))
	_fixture.left_handed()
	assert_bool(_fixture.controls.is_mirrored()).is_true()
	assert_array(mirrored).is_equal([true])
	var canvas := TouchFixture.PHONE
	# Fire is on the left half now, and a finger on it presses `fire`.
	assert_float(_fixture.at(TouchLayout.FIRE).x).is_less(canvas.x * 0.25)
	await _fixture.touch(0, _fixture.at(TouchLayout.FIRE))
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	await _fixture.lift(0)
	# The stick starts on the right and walks the player; the same spot on the left is not a stick.
	var start := Vector2(canvas.x - 330.0, 760.0)
	await _fixture.touch(1, start)
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	await _fixture.drag(1, start + Vector2(90.0, 0.0), Vector2(90.0, 0.0))
	assert_float(_move().x).is_greater(0.6)
	await _fixture.lift(1)
	await _fixture.touch(2, Vector2(300.0, 900.0))
	assert_bool(_fixture.controls.is_stick_down()).is_false()
	await _fixture.lift(2)
	# A drag on the left of the screen's middle still looks (the look area is what no button covers).
	var looks: Array[Vector2] = []
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: looks.append(relative))
	var spot := Vector2(canvas.x * 0.5, 300.0)
	await _fixture.touch(3, spot)
	await _fixture.drag(3, spot + Vector2(50.0, 0.0), Vector2(50.0, 0.0))
	await _fixture.lift(3)
	assert_int(looks.size()).is_equal(1)
	_fixture.left_handed(false)
	assert_bool(_fixture.controls.is_mirrored()).is_false()
	assert_array(mirrored).is_equal([true, false])
	assert_float(_fixture.at(TouchLayout.FIRE).x).is_greater(canvas.x * 0.75)


func test_the_hand_flips_only_where_touch_controls_are_wanted_and_stays_under_a_menu() -> void:
	TouchMode.device_is_touch = false
	_fixture.controls.refresh()
	_fixture.left_handed()
	assert_bool(_fixture.controls.is_mirrored()).is_false()
	TouchMode.device_is_touch = true
	_fixture.controls.refresh()
	assert_bool(_fixture.controls.is_mirrored()).is_true()
	_fixture.controls.live = false
	assert_bool(_fixture.controls.is_mirrored()).is_true()


## Counts the pause action presses that reach the game.
class PauseSpy:
	extends Node
	var pressed := 0

	func _input(event: InputEvent) -> void:
		if event is InputEventAction and event.is_action_pressed(&"pause"):
			pressed += 1


## Counts how often the controls were drawn over `frames` frames, from now.
func _draws_over(frames: int) -> int:
	var draws := [0]
	var count := func() -> void: draws[0] += 1
	_fixture.controls.draw.connect(count)
	for i in frames:
		await get_tree().process_frame
	_fixture.controls.draw.disconnect(count)
	return draws[0]


# Each `draw_circle` and `draw_arc` is a polygon the Compatibility renderer builds into buffers of
# its own, so a redraw every frame made the web page create a couple of hundred WebGL objects a
# frame, which its id tables keep for good (#834): the buttons are drawn when they change.
func test_idle_controls_are_not_redrawn_every_frame() -> void:
	await get_tree().process_frame
	assert_int(await _draws_over(30)).is_less(3)


func test_a_held_button_and_a_moving_stick_are_redrawn() -> void:
	await get_tree().process_frame
	var point := _fixture.at(TouchLayout.AIM)
	var draws := [0]
	_fixture.controls.draw.connect(func() -> void: draws[0] += 1)
	await _fixture.touch(0, point)
	await get_tree().process_frame
	assert_int(draws[0]).is_greater(0)
	await _fixture.lift(0, point)
	var start := Vector2(300.0, 800.0)
	draws[0] = 0
	await _fixture.touch(1, start)
	await _fixture.drag(1, start + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
	await get_tree().process_frame
	assert_int(draws[0]).is_greater(1)
	await _fixture.lift(1)
