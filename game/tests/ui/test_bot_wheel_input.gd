# The bot command wheel through the real input paths (#642): a key, a mouse, a pad that is not
# device 0 and a finger go in as events, the night screen's driver reads them, and the order reaches
# `BotOrderLink` (a stub here: `BotOrders` is #641's). Holding opens the wheel, the pointer picks,
# letting go over an entry gives the order, a tap or the middle gives none, and the view stays still
# while the wheel is held. The shoulder swap on C and the pings (middle mouse, Z, the pad, a touch
# button) are proved the same way.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const MAIN := "res://main.tscn"
## A pad that is not device 0: a reconnect or a virtual pad numbers them so.
const PAD := 3
## A frame of the driver, by hand; longer than the wheel takes to open.
const FRAME := 1.0 / 60.0
const OPEN_FRAMES := 14
const GROW_FRAMES := 10
const LOOK_TURN := 40.0
const PING_WAIT_FRAMES := 240

var _screen: NightScreen
var _heard: Array[Dictionary] = []
var _held: Array[InputEvent] = []
var _fixture: TouchFixture
var _arrival := false


func before_test() -> void:
	# The helicopter drop a window plays at the start of a night (#1057) holds the look, the touch
	# layer and the HUD until it ends; a headless run has none. This suite is about the wheel, in a
	# night the player has control of (`--noarrival`); `test_arrival_night` is about the drop.
	_arrival = NightScreen.arrival_enabled
	NightScreen.arrival_enabled = false
	await RouterFixture.clear(get_tree())
	_heard = []
	_held = []
	var main := (load(MAIN) as PackedScene).instantiate()
	get_tree().root.add_child(main)
	auto_free(main)
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top() as NightScreen
	await _screen.night.ready_to_play
	await get_tree().physics_frame
	# The test steps the driver itself; the stub stands where `BotOrders` will.
	_screen.wheel.set_process(false)
	_screen.wheel.link = BotOrderLink.new()
	_screen.wheel.link.issuer = func(order: StringName, issuer_id: int, at: Vector3) -> Dictionary:
		_heard.append({&"order": order, &"issuer": issuer_id, &"at": at})
		return {&"type": &"order", &"order": order, &"at": at}


func after_test() -> void:
	for event in _held.duplicate():
		_send(event, false)
	for action in [&"bot_wheel", &"ping", &"swap_shoulder"]:
		Input.action_release(action)
	if _fixture != null:
		_fixture.free_all()
		_fixture = null
	TouchMode.device_is_touch = null
	NightScreen.arrival_enabled = _arrival
	await RouterFixture.clear(get_tree())


func _wheel() -> BotWheelDriver:
	return _screen.wheel


func _bound(action: StringName, pad: bool) -> InputEvent:
	for event in InputMap.action_get_events(action):
		var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_pad == pad and (is_pad or event is InputEventKey or event is InputEventMouseButton):
			var copy := event.duplicate() as InputEvent
			if pad:
				copy.device = PAD
			return copy
	return null


func _send(event: InputEvent, pressed: bool) -> void:
	var copy := event.duplicate() as InputEvent
	if copy is InputEventKey:
		(copy as InputEventKey).pressed = pressed
	elif copy is InputEventMouseButton:
		(copy as InputEventMouseButton).pressed = pressed
	elif copy is InputEventJoypadButton:
		(copy as InputEventJoypadButton).pressed = pressed
	elif copy is InputEventJoypadMotion and not pressed:
		(copy as InputEventJoypadMotion).axis_value = 0.0
	if pressed:
		_held.append(event)
	else:
		_held.erase(event)
	Input.flush_buffered_events()
	Input.parse_input_event(copy)
	Input.flush_buffered_events()


## A mouse move of `relative` canvas units, alone and at once (the engine adds a motion waiting in
## the buffer to the next one, under the first one's device). The wheel's pointer reads `relative`
## and the look reads `screen_relative` (#928), so a real move carries both: with only `relative`
## the view would stay still for the wrong reason.
func _mouse_move(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	motion.screen_relative = relative
	motion.position = Vector2(960.0, 540.0)
	Input.flush_buffered_events()
	get_viewport().push_input(motion, true)


func _frames(count: int) -> void:
	for _i in count:
		_wheel().step(FRAME)


## The touch layer lets a short press go on frames (its minimum hold): waits, bounded, until the
## action is up, as the frames of a real night do.
func _wait_for_release() -> void:
	for _i in 120:
		if not Input.is_action_pressed(&"bot_wheel"):
			return
		await get_tree().process_frame


func _yaw() -> float:
	return _screen.night.player().camera_rig.yaw


## The mouse pushes the pointer to the rim in the direction of `order`'s entry.
func _point_mouse_at(order: StringName) -> void:
	_mouse_move(BotWheel.direction_of(order) * BotWheel.MOUSE_REACH)


# --- The mouse and keyboard ---


func test_holding_q_and_letting_go_over_each_entry_gives_that_order() -> void:
	var key := _bound(&"bot_wheel", false)
	for order in BotWheel.ORDERS:
		_heard.clear()
		_send(key, true)
		_frames(OPEN_FRAMES)
		assert_bool(_wheel().model.is_open()).is_true()
		_point_mouse_at(order)
		_frames(2)
		assert_str(_wheel().model.hovered()).is_equal(order)
		_send(key, false)
		_frames(1)
		(
			assert_array(_heard)
			. override_failure_message("releasing over %s gave %s" % [order, _heard])
			. has_size(1)
		)
		assert_str(_heard[0][&"order"]).is_equal(order)
		assert_int(_heard[0][&"issuer"]).is_equal(_screen.night.state.player_id)
		assert_vector(_heard[0][&"at"]).is_equal_approx(
			_screen.night.player().global_position, Vector3.ONE * 0.01
		)
		_frames(GROW_FRAMES)
		assert_bool(_wheel().model.is_holding()).is_false()


func test_q_is_the_key_and_it_is_the_one_the_map_binds() -> void:
	var key := _bound(&"bot_wheel", false) as InputEventKey
	assert_int(key.physical_keycode).is_equal(KEY_Q)


func test_a_tap_of_q_gives_no_order_and_does_not_open_the_wheel() -> void:
	var key := _bound(&"bot_wheel", false)
	_send(key, true)
	_frames(3)
	assert_bool(_wheel().model.is_open()).is_false()
	_point_mouse_at(BotWheel.FOLLOW)
	_send(key, false)
	_frames(1)
	assert_array(_heard).is_empty()
	assert_bool(_wheel().hud_wheel.visible).is_false()


func test_letting_go_in_the_middle_gives_no_order() -> void:
	var key := _bound(&"bot_wheel", false)
	_send(key, true)
	_frames(OPEN_FRAMES)
	_point_mouse_at(BotWheel.HOLD)
	_frames(1)
	# Back to the middle: the same motion the other way.
	_mouse_move(-BotWheel.direction_of(BotWheel.HOLD) * BotWheel.MOUSE_REACH)
	_frames(1)
	assert_str(_wheel().model.hovered()).is_equal("")
	_send(key, false)
	_frames(1)
	assert_array(_heard).is_empty()


func test_the_view_stays_still_while_the_wheel_is_held_and_turns_again_after() -> void:
	var player := _screen.night.player()
	# Without the wheel the mouse turns the view, so a still view below means the wheel took it.
	var before := _yaw()
	_mouse_move(Vector2(LOOK_TURN, 0.0))
	await get_tree().process_frame
	assert_float(_yaw()).is_not_equal(before)
	var key := _bound(&"bot_wheel", false)
	_send(key, true)
	_frames(OPEN_FRAMES)
	assert_bool(player.look_locked).is_true()
	before = _yaw()
	_point_mouse_at(BotWheel.ROAM)
	await get_tree().process_frame
	assert_float(_yaw()).is_equal(before)
	_send(key, false)
	_frames(1)
	assert_bool(player.look_locked).is_false()
	_mouse_move(Vector2(LOOK_TURN, 0.0))
	await get_tree().process_frame
	assert_float(_yaw()).is_not_equal(before)


func test_the_wheel_gives_nothing_while_the_night_is_paused() -> void:
	var key := _bound(&"bot_wheel", false)
	_screen.night.set_paused(true)
	_send(key, true)
	_frames(OPEN_FRAMES)
	assert_bool(_wheel().model.is_holding()).is_false()
	_send(key, false)
	_frames(1)
	assert_array(_heard).is_empty()
	_screen.night.set_paused(false)


func test_pausing_under_an_open_wheel_cancels_it() -> void:
	var key := _bound(&"bot_wheel", false)
	_send(key, true)
	_frames(OPEN_FRAMES)
	_point_mouse_at(BotWheel.FOLLOW)
	_frames(1)
	_screen.night.set_paused(true)
	_frames(1)
	_send(key, false)
	_frames(1)
	assert_array(_heard).is_empty()
	assert_bool(_wheel().model.is_holding()).is_false()
	_screen.night.set_paused(false)


func test_the_hud_says_the_new_order_for_a_moment() -> void:
	var key := _bound(&"bot_wheel", false)
	_send(key, true)
	_frames(OPEN_FRAMES)
	_point_mouse_at(BotWheel.HOLD)
	_frames(1)
	_send(key, false)
	_frames(1)
	var said := false
	for line in _screen.night.hud.notices.history:
		said = said or line == BotWheel.NOTICES[BotWheel.HOLD]
	assert_bool(said).is_true()
	assert_str(_wheel().model.current).is_equal(BotWheel.HOLD)


func test_an_order_that_was_refused_before_it_left_changes_nothing() -> void:
	_wheel().link.issuer = func(_o: StringName, _i: int, _a: Vector3) -> Dictionary: return {}
	var key := _bound(&"bot_wheel", false)
	_send(key, true)
	_frames(OPEN_FRAMES)
	_point_mouse_at(BotWheel.FOLLOW)
	_frames(1)
	_send(key, false)
	_frames(1)
	assert_str(_wheel().model.current).is_equal(BotWheel.DEFAULT_ORDER)
	for line in _screen.night.hud.notices.history:
		assert_str(line).not_contains("BOTS")


# --- The gamepad: a held button and the right stick ---


func test_a_pad_that_is_not_device_zero_picks_with_the_right_stick() -> void:
	var button := _bound(&"bot_wheel", true)
	assert_int((button as InputEventJoypadButton).button_index).is_equal(JOY_BUTTON_DPAD_LEFT)
	for order in BotWheel.ORDERS:
		_heard.clear()
		_send(button, true)
		_frames(OPEN_FRAMES)
		var push := BotWheel.direction_of(order)
		var horizontal := InputEventJoypadMotion.new()
		horizontal.device = PAD
		horizontal.axis = JOY_AXIS_RIGHT_X
		horizontal.axis_value = push.x
		var vertical := InputEventJoypadMotion.new()
		vertical.device = PAD
		vertical.axis = JOY_AXIS_RIGHT_Y
		vertical.axis_value = push.y
		Input.parse_input_event(horizontal)
		Input.parse_input_event(vertical)
		Input.flush_buffered_events()
		_frames(2)
		assert_str(_wheel().model.hovered()).is_equal(order)
		# Letting go of the stick centres the pointer; the button then gives nothing.
		horizontal.axis_value = 0.0
		vertical.axis_value = 0.0
		Input.parse_input_event(horizontal)
		Input.parse_input_event(vertical)
		Input.flush_buffered_events()
		_frames(1)
		assert_str(_wheel().model.hovered()).is_equal("")
		# Back out to the entry and let go of the button over it.
		horizontal.axis_value = push.x
		vertical.axis_value = push.y
		Input.parse_input_event(horizontal)
		Input.parse_input_event(vertical)
		Input.flush_buffered_events()
		_frames(1)
		_send(button, false)
		_frames(1)
		assert_array(_heard).has_size(1)
		assert_str(_heard[0][&"order"]).is_equal(order)
		horizontal.axis_value = 0.0
		vertical.axis_value = 0.0
		Input.parse_input_event(horizontal)
		Input.parse_input_event(vertical)
		Input.flush_buffered_events()
		_frames(GROW_FRAMES)


func test_the_right_stick_does_not_turn_the_view_while_the_wheel_is_held() -> void:
	var player := _screen.night.player()
	var button := _bound(&"bot_wheel", true)
	_send(button, true)
	_frames(OPEN_FRAMES)
	var before := _yaw()
	var horizontal := InputEventJoypadMotion.new()
	horizontal.device = PAD
	horizontal.axis = JOY_AXIS_RIGHT_X
	horizontal.axis_value = 1.0
	Input.parse_input_event(horizontal)
	Input.flush_buffered_events()
	_frames(2)
	for _i in 20:
		await get_tree().physics_frame
	assert_float(_yaw()).is_equal(before)
	assert_bool(player.look_locked).is_true()
	horizontal.axis_value = 0.0
	Input.parse_input_event(horizontal)
	Input.flush_buffered_events()
	_send(button, false)
	_frames(GROW_FRAMES)


# --- A finger: a held on-screen button and a drag ---


func _touch_layer() -> TouchControls:
	TouchMode.device_is_touch = true
	var controls := _screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	_fixture = TouchFixture.attach(self, controls)
	controls.refresh()
	await get_tree().process_frame
	return controls


func test_a_finger_holds_the_bots_button_and_drags_to_each_entry() -> void:
	var controls := await _touch_layer()
	for order in BotWheel.ORDERS:
		_heard.clear()
		var start := _fixture.at(TouchLayout.BOT_WHEEL)
		# The left thumb is on the stick the whole time: two fingers, as a phone has.
		var stick_at := Vector2(300.0, 800.0)
		await _fixture.touch(1, stick_at)
		await _fixture.touch(0, start)
		_frames(OPEN_FRAMES)
		assert_bool(controls.has_wheel_finger()).is_true()
		var drag := BotWheel.direction_of(order) * BotWheel.TOUCH_REACH
		await _fixture.drag(0, start + drag, drag)
		_frames(2)
		assert_str(_wheel().model.hovered()).is_equal(order)
		await _fixture.lift(0)
		await _wait_for_release()
		_frames(GROW_FRAMES)
		(
			assert_array(_heard)
			. override_failure_message("a drag to %s gave %s" % [order, _heard])
			. has_size(1)
		)
		assert_str(_heard[0][&"order"]).is_equal(order)
		await _fixture.lift(1)


func test_a_tap_on_the_bots_button_and_a_lift_in_the_middle_give_nothing() -> void:
	await _touch_layer()
	await _fixture.touch(0, _fixture.at(TouchLayout.BOT_WHEEL))
	_frames(3)
	await _fixture.lift(0)
	await _wait_for_release()
	_frames(GROW_FRAMES)
	assert_array(_heard).is_empty()
	await _fixture.touch(0, _fixture.at(TouchLayout.BOT_WHEEL))
	_frames(OPEN_FRAMES)
	await _fixture.lift(0)
	await _wait_for_release()
	_frames(GROW_FRAMES)
	assert_array(_heard).is_empty()


func test_a_drag_from_the_bots_button_does_not_turn_the_view() -> void:
	await _touch_layer()
	var start := _fixture.at(TouchLayout.BOT_WHEEL)
	var before := _yaw()
	await _fixture.touch(0, start)
	_frames(OPEN_FRAMES)
	await _fixture.drag(0, start + Vector2(-80.0, 0.0), Vector2(-80.0, 0.0), 400.0)
	await _fixture.settle_look()
	assert_float(_yaw()).is_equal(before)
	await _fixture.lift(0)
	_frames(GROW_FRAMES)


# --- C swaps the shoulder, and Q no longer does ---


func test_c_swaps_the_shoulder_and_q_does_not() -> void:
	var player := _screen.night.player()
	var c_key := _bound(&"swap_shoulder", false) as InputEventKey
	assert_int(c_key.physical_keycode).is_equal(KEY_C)
	var side := player.state.shoulder_side
	_send(c_key, true)
	for _i in 6:
		await get_tree().physics_frame
	_send(c_key, false)
	await get_tree().physics_frame
	assert_float(player.state.shoulder_side).is_not_equal(side)
	var q_key := _bound(&"bot_wheel", false)
	side = player.state.shoulder_side
	_send(q_key, true)
	for _i in 6:
		await get_tree().physics_frame
	_send(q_key, false)
	await get_tree().physics_frame
	assert_float(player.state.shoulder_side).is_equal(side)


func test_crouch_is_on_ctrl_and_the_pad_but_not_on_c() -> void:
	var keys: Array[int] = []
	for event in InputMap.action_get_events(&"crouch"):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
	assert_array(keys).contains_exactly([KEY_CTRL])


# --- Pings: middle mouse, Z, the pad and a touch button each mark a place ---


## Waits for the night's own ticks until a ping mark is on the board, up to a few seconds.
func _wait_for_ping() -> bool:
	for _i in PING_WAIT_FRAMES:
		await get_tree().physics_frame
		if not _screen.night.state.frame.get("pings", {}).is_empty():
			return true
	return false


func _clear_pings() -> void:
	_screen.night.server.ping_board.forget(_screen.night.state.player_id)
	for _i in 90:
		await get_tree().physics_frame


func test_every_ping_binding_marks_a_place_in_the_night() -> void:
	var bindings: Array[InputEvent] = []
	for event in InputMap.action_get_events(&"ping"):
		var copy := event.duplicate() as InputEvent
		if copy is InputEventJoypadButton:
			copy.device = PAD
		bindings.append(copy)
	# Z, the middle mouse button and one pad button.
	assert_array(bindings).has_size(3)
	for event in bindings:
		await _clear_pings()
		_send(event, true)
		for _i in 4:
			await get_tree().physics_frame
		_send(event, false)
		var marked := await _wait_for_ping()
		(
			assert_bool(marked)
			. override_failure_message("%s marked nothing in the night" % event.as_text())
			. is_true()
		)


func test_the_touch_ping_button_marks_a_place_in_the_night() -> void:
	await _touch_layer()
	await _clear_pings()
	await _fixture.touch(0, _fixture.at(TouchLayout.PING))
	for _i in 6:
		await get_tree().physics_frame
	await _fixture.lift(0)
	var marked := await _wait_for_ping()
	assert_bool(marked).is_true()
