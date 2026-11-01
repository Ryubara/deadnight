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


func test_pushing_the_stick_up_walks_forward_and_to_the_rim_sprints() -> void:
	var start := Vector2(300.0, 800.0)
	await _fixture.touch(0, start)
	await _fixture.drag(0, start + Vector2(0.0, -60.0), Vector2(0.0, -60.0))
	assert_float(Input.get_action_strength(&"move_forward")).is_greater(0.3)
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()
	await _fixture.drag(0, start + Vector2(0.0, -140.0), Vector2(0.0, -80.0))
	assert_bool(_fixture.controls.is_sprinting()).is_true()
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	await _fixture.drag(0, start + Vector2(0.0, -60.0), Vector2(0.0, 80.0))
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()
	await _fixture.lift(0)


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
	var turn := TouchLook.RADIANS_PER_HEIGHT * 100.0 / 1080.0
	assert_float(looks[0].x).is_equal_approx(turn / TouchLook.mouse_radians_per_pixel, 0.01)
	await _fixture.lift(0)


func test_a_fast_flick_turns_further_than_a_slow_drag() -> void:
	var slow := TouchLook.mouse_equivalent(Vector2(100.0, 0.0), 200.0, 1080.0)
	var fast := TouchLook.mouse_equivalent(Vector2(100.0, 0.0), 3000.0, 1080.0)
	assert_float(fast.x / slow.x).is_equal_approx(TouchLook.MAX_GAIN, 0.001)


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
	var ids: Array[StringName] = [
		TouchLayout.AIM, TouchLayout.RELOAD, TouchLayout.SWAP, TouchLayout.GRENADE
	]
	for id in ids:
		var point := _fixture.at(id)
		await _fixture.touch(0, point)
		assert_bool(Input.is_action_pressed(id)).override_failure_message(str(id)).is_true()
		await _fixture.lift(0, point)
		await await_millis(250)
		assert_bool(Input.is_action_pressed(id)).is_false()


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


## Counts the pause action presses that reach the game.
class PauseSpy:
	extends Node
	var pressed := 0

	func _input(event: InputEvent) -> void:
		if event is InputEventAction and event.is_action_pressed(&"pause"):
			pressed += 1
