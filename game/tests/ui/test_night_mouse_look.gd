# Look during a night through the real input path, by mouse and by any gamepad.
#
# A full-screen control that catches the mouse marks every motion handled before the player's
# `_unhandled_input`; that is how mouse look broke on desktop and the web. A headless run skips the
# GUI's mouse handling, so pushing a motion cannot show it: the first test checks the controls
# themselves, the second the look once the event reaches the player.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const MAIN := "res://main.tscn"

var _arrival := false


func before() -> void:
	# GdUnit minimizes the window after every suite and a minimized window draws no frame,
	# which the warm-up waits for (#1207).
	await WindowFixture.make_drawable(get_tree())


func before_test() -> void:
	# The helicopter drop a window plays at the start of a night (#1057) holds the look, the
	# touch layer and the HUD until it ends; a headless run has none. This suite is about
	# the mouse and the pad, in a night the player has control of (`--noarrival`);
	# `test_arrival_night` is about the drop.
	_arrival = NightScreen.arrival_enabled
	NightScreen.arrival_enabled = false


func after_test() -> void:
	NightScreen.arrival_enabled = _arrival
	# The menu this suite goes back to would cover the mouse for every suite after it.
	await RouterFixture.clear(get_tree())


## The game's own root (`main.tscn`) is loaded as in a real run: it is a full-screen Control too.
func _enter_night() -> NightScreen:
	var main := (load(MAIN) as PackedScene).instantiate()
	get_tree().root.add_child(main)
	auto_free(main)
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	await get_tree().physics_frame
	return screen


func _leave() -> void:
	UIRouter.pop()
	await UIRouter.idle


func test_nothing_over_a_running_night_catches_the_mouse() -> void:
	await _enter_night()
	var centre := get_viewport().get_visible_rect().get_center()
	var catchers: Array[String] = []
	for node in get_tree().root.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		var path := str(control.get_path())
		if control.get_global_rect().has_point(centre) and not path.contains("GdUnit"):
			catchers.append(path)
	assert_array(catchers).is_empty()
	await _leave()


func test_mouse_motion_through_the_viewport_turns_the_camera() -> void:
	var screen := await _enter_night()
	var rig := screen.night.player().camera_rig
	var before: float = rig.yaw
	var event := InputEventMouseMotion.new()
	event.position = get_viewport().get_visible_rect().get_center()
	event.global_position = event.position
	event.relative = Vector2(200.0, 0.0)
	event.screen_relative = event.relative
	get_viewport().push_input(event)
	for _i in 30:
		await get_tree().physics_frame  # and nothing turns it back
	assert_float(absf(rig.yaw - before)).is_greater(0.01)
	await _leave()


func test_a_gamepad_that_is_not_device_zero_moves_and_looks() -> void:
	var screen := await _enter_night()
	var player := screen.night.player()
	var rig := player.camera_rig
	var yaw_before: float = rig.yaw
	var start := player.global_position
	for axis in [JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X]:
		var motion := InputEventJoypadMotion.new()
		motion.device = 3  # a pad that reconnected, or came after a virtual one
		motion.axis = axis
		motion.axis_value = -1.0 if axis == JOY_AXIS_LEFT_Y else 1.0
		Input.parse_input_event(motion)
	for _i in 40:
		await get_tree().physics_frame
	for axis in [JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X]:
		var release := InputEventJoypadMotion.new()
		release.device = 3
		release.axis = axis
		release.axis_value = 0.0
		Input.parse_input_event(release)
	assert_float(absf(rig.yaw - yaw_before)).is_greater(0.05)
	assert_float(player.global_position.distance_to(start)).is_greater(0.3)
	await _leave()


func test_a_bumped_mouse_keeps_the_gamepad_glyphs_and_a_real_move_takes_them() -> void:
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	UIInputMode.track(press)
	assert_bool(UIInputMode.gamepad).is_true()
	var bump := InputEventMouseMotion.new()
	bump.screen_relative = Vector2(1.0, 1.0)
	UIInputMode.track(bump)
	assert_bool(UIInputMode.gamepad).is_true()
	var move := InputEventMouseMotion.new()
	move.screen_relative = Vector2(12.0, 0.0)
	UIInputMode.track(move)
	assert_bool(UIInputMode.gamepad).is_false()
	assert_bool(UIInputMode.pointer).is_true()
