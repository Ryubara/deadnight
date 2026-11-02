# The Start button of a gamepad pauses the night and resumes it, through the real night screen and
# the real player, on device 0 and on a pad that is not device 0 (#494). A pad numbered 3 is what a
# reconnect or a virtual pad gives; the `pause` action is bound to every device.
#
# A pad cannot give a browser the pointer lock: a gamepad button is not a user gesture, which
# `requestPointerLock` waits for. The stand-in platform under the player's `MouseGrip` refuses the
# lock as a browser does outside a click, and a player on a pad must still play after Resume.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
## The pad of a reconnect or a virtual pad: not device 0.
const OTHER_PAD := 3
const DEVICES: Array[int] = [0, OTHER_PAD]

var _mode := Input.MOUSE_MODE_VISIBLE
## True while the stand-in platform refuses to capture (a browser outside a click or a key).
var _refuses := false
var _quiet := ""


func before_test() -> void:
	_mode = Input.MOUSE_MODE_VISIBLE
	_refuses = false
	_quiet = OS.get_environment("GDS_QUIET")
	OS.unset_environment("GDS_QUIET")


func after_test() -> void:
	if _quiet != "":
		OS.set_environment("GDS_QUIET", _quiet)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await RouterFixture.clear(get_tree())


func _platform_mode() -> Input.MouseMode:
	return _mode


func _platform_ask(mode: Input.MouseMode) -> void:
	if mode == Input.MOUSE_MODE_CAPTURED and _refuses:
		return
	_mode = mode


func _enter_night() -> NightScreen:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	var grip := screen.night.player().grip
	grip.reader = _platform_mode
	grip.writer = _platform_ask
	# The player asks for the mouse again, from the stand-in, and the platform gives it.
	screen.night.player().set_controls_enabled(true)
	await _frame()
	return screen


## `process_frame` is emitted before the nodes' `_process`: the frame a change is seen in ends at
## the second one.
func _frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## A pad button pressed and let go, as the engine sends it.
func _tap(button: JoyButton, device: int) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frame()


func test_start_is_the_first_press_that_pauses_a_live_night_on_every_device() -> void:
	for device in DEVICES:
		var screen := await _enter_night()
		assert_bool(screen.night.is_paused()).is_false()
		await _tap(JOY_BUTTON_START, device)
		(
			assert_bool(screen.night.is_paused())
			. override_failure_message("Start on device %d did not pause the night" % device)
			. is_true()
		)
		assert_bool(screen.night.running).is_false()
		await RouterFixture.clear(get_tree())


func test_start_resumes_a_paused_night_on_every_device() -> void:
	for device in DEVICES:
		var screen := await _enter_night()
		await _tap(JOY_BUTTON_START, device)
		await _tap(JOY_BUTTON_START, device)
		(
			assert_bool(screen.night.is_paused())
			. override_failure_message("a second Start on device %d did not resume" % device)
			. is_false()
		)
		assert_bool(screen.night.running).is_true()
		await RouterFixture.clear(get_tree())


func test_b_resumes_a_paused_night_on_every_device() -> void:
	for device in DEVICES:
		var screen := await _enter_night()
		await _tap(JOY_BUTTON_START, device)
		await _tap(JOY_BUTTON_B, device)
		assert_bool(screen.night.is_paused()).is_false()
		await RouterFixture.clear(get_tree())


func test_b_does_not_pause_a_live_night() -> void:
	var screen := await _enter_night()
	await _tap(JOY_BUTTON_B, 0)
	assert_bool(screen.night.is_paused()).is_false()


func test_a_pad_that_resumed_plays_when_the_browser_will_not_give_the_lock() -> void:
	for device in DEVICES:
		var screen := await _enter_night()
		_refuses = true
		await _tap(JOY_BUTTON_START, device)
		await _tap(JOY_BUTTON_START, device)
		(
			assert_bool(screen.night.player().controls_enabled())
			. override_failure_message(
				(
					"after Start, Start on device %d the pad has no controls: no click can bring the lock"
					% device
				)
			)
			. is_true()
		)
		await RouterFixture.clear(get_tree())


func test_the_trigger_fires_while_the_mouse_waits_for_its_lock() -> void:
	var screen := await _enter_night()
	var player := screen.night.player()
	_refuses = true
	_mode = Input.MOUSE_MODE_VISIBLE
	player.set_controls_enabled(true)
	assert_bool(player.grip.is_pending()).is_true()
	var pull := InputEventJoypadMotion.new()
	pull.device = OTHER_PAD
	pull.axis = JOY_AXIS_TRIGGER_RIGHT
	pull.axis_value = 1.0
	Input.parse_input_event(pull)
	Input.flush_buffered_events()
	var command := HumanController.new().command(player, Night.PLAYER_ID)
	pull.axis_value = 0.0
	Input.parse_input_event(pull)
	Input.flush_buffered_events()
	assert_bool(command.fire).is_true()
