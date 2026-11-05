# The platform takes the mouse back (a browser's first Esc frees the pointer lock and the key never
# reaches the page; a window loses focus): the night's menu opens in the same frame, as Esc would,
# and while the mouse is free the view does not turn and a click does not fire (#476).
#
# A headless run cannot capture a mouse (`Input.mouse_mode` reads back VISIBLE), so a stand-in
# platform is put under the player's `MouseGrip`: it captures when asked and is told to let go.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"

var _mode := Input.MOUSE_MODE_VISIBLE
## True while the stand-in platform refuses to capture (a browser outside a click).
var _refuses := false
var _asked: Array[int] = []
var _quiet := ""
var _arrival := false


func before() -> void:
	# GdUnit minimizes the window after every suite and a minimized window draws no frame,
	# which the warm-up waits for (#1207).
	await WindowFixture.make_drawable(get_tree())


func before_test() -> void:
	_arrival = NightScreen.arrival_enabled
	# No drop due, as headless always has it (`--noarrival`): this suite is not about the drop.
	NightScreen.arrival_enabled = false
	_mode = Input.MOUSE_MODE_VISIBLE
	_refuses = false
	_asked = []
	_quiet = OS.get_environment("GDS_QUIET")
	OS.unset_environment("GDS_QUIET")


func after_test() -> void:
	NightScreen.arrival_enabled = _arrival
	if _quiet != "":
		OS.set_environment("GDS_QUIET", _quiet)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.action_release(&"fire")
	await RouterFixture.clear(get_tree())


func _platform_mode() -> Input.MouseMode:
	return _mode


func _platform_ask(mode: Input.MouseMode) -> void:
	_asked.append(mode)
	if mode == Input.MOUSE_MODE_CAPTURED and _refuses:
		return
	_mode = mode


func _stand_in(grip: MouseGrip) -> void:
	grip.reader = _platform_mode
	grip.writer = _platform_ask


func _enter_night() -> NightScreen:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	_stand_in(screen.night.player().grip)
	# The player asks for the mouse again, from the stand-in, and the platform gives it.
	screen.night.player().set_controls_enabled(true)
	await _frame()
	return screen


## `process_frame` is emitted before the nodes' `_process`: the frame a change is seen in ends at
## the second one.
func _frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _overlay_shown(screen: NightScreen) -> bool:
	for candidate in screen.find_children("*", "UIButton", true, false):
		if (candidate as UIButton).text == "Resume":
			return (candidate as UIButton).is_visible_in_tree()
	return false


func _motion(dx: float) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_viewport().get_visible_rect().get_center()
	event.global_position = event.position
	event.relative = Vector2(dx, 0.0)
	event.screen_relative = event.relative
	get_viewport().push_input(event)


func _click() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = get_viewport().get_visible_rect().get_center()
	event.global_position = event.position
	get_viewport().push_input(event)


func test_the_grip_is_lost_once_after_it_was_held() -> void:
	var grip := MouseGrip.new()
	_stand_in(grip)
	grip.want(true)
	assert_bool(grip.poll()).is_false()
	_mode = Input.MOUSE_MODE_VISIBLE
	assert_bool(grip.poll()).is_true()
	assert_bool(grip.poll()).is_false()


func test_a_platform_that_cannot_capture_loses_nothing() -> void:
	var grip := MouseGrip.new()
	grip.reader = func() -> Input.MouseMode: return Input.MOUSE_MODE_VISIBLE
	grip.writer = func(_mode: Input.MouseMode) -> void: pass
	grip.want(true)
	for _i in 3:
		assert_bool(grip.poll()).is_false()
	assert_bool(grip.is_pending()).is_false()


func test_the_first_esc_of_a_browser_opens_the_menu_in_the_same_frame() -> void:
	var screen := await _enter_night()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_CAPTURED)
	assert_bool(screen.night.is_paused()).is_false()
	# The browser frees the lock: no key press, no `pause` action, only the mode changes.
	_mode = Input.MOUSE_MODE_VISIBLE
	await _frame()
	assert_bool(screen.night.is_paused()).is_true()
	assert_bool(_overlay_shown(screen)).is_true()
	assert_bool(screen.night.player().controls_enabled()).is_false()
	assert_bool(screen.night.running).is_false()


func test_a_window_that_loses_focus_opens_the_menu() -> void:
	var screen := await _enter_night()
	screen.night.player().notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_bool(screen.night.is_paused()).is_true()
	assert_bool(_overlay_shown(screen)).is_true()


func test_the_mouse_is_not_taken_back_by_the_menu_and_resume_asks_for_it() -> void:
	var screen := await _enter_night()
	_mode = Input.MOUSE_MODE_VISIBLE
	await _frame()
	_asked.clear()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	for candidate in screen.find_children("*", "UIButton", true, false):
		if (candidate as UIButton).text == "Resume":
			candidate.pressed.emit()
	assert_array(_asked).contains([Input.MOUSE_MODE_CAPTURED])
	assert_int(_mode).is_equal(Input.MOUSE_MODE_CAPTURED)
	assert_bool(screen.night.is_paused()).is_false()
	assert_bool(screen.night.player().controls_enabled()).is_true()
	# And it pauses again the next time the platform takes it.
	await _frame()
	_mode = Input.MOUSE_MODE_VISIBLE
	await _frame()
	assert_bool(screen.night.is_paused()).is_true()


func test_an_ordinary_esc_still_pauses_once() -> void:
	var screen := await _enter_night()
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	get_viewport().push_input(event)
	await _frame()
	assert_bool(screen.night.is_paused()).is_true()
	# The lock the page gave up follows the menu; nothing opens a second one.
	await _frame()
	assert_bool(screen.night.is_paused()).is_true()
	assert_int(UIRouter.depth()).is_equal(2)


func test_a_free_mouse_neither_looks_nor_fires_until_a_click_gets_the_lock_back() -> void:
	var screen := await _enter_night()
	var player := screen.night.player()
	# Resume where the browser refused the lock: controls on, mouse free.
	_refuses = true
	_mode = Input.MOUSE_MODE_VISIBLE
	player.set_controls_enabled(true)
	assert_bool(player.grip.is_pending()).is_true()
	var yaw := player.camera_rig.yaw
	_motion(300.0)
	await get_tree().physics_frame
	assert_float(player.camera_rig.yaw).is_equal(yaw)
	# The click, as the engine sends it: the left button down, which `fire` is bound to.
	var held := InputEventMouseButton.new()
	held.button_index = MOUSE_BUTTON_LEFT
	held.pressed = true
	Input.parse_input_event(held)
	Input.flush_buffered_events()
	var command := HumanController.new().command(player, Night.PLAYER_ID)
	assert_bool(command.fire).is_false()
	held.pressed = false
	Input.parse_input_event(held)
	Input.flush_buffered_events()
	# A click asks for the lock again, from the click itself; the browser grants it this time.
	_refuses = false
	_asked.clear()
	_click()
	assert_array(_asked).contains([Input.MOUSE_MODE_CAPTURED])
	assert_bool(player.controls_enabled()).is_true()
	_motion(300.0)
	await get_tree().physics_frame
	assert_float(player.camera_rig.yaw).is_not_equal(yaw)
