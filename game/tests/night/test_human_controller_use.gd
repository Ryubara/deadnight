# What a person's interact button becomes in the night's command (#297): the press is an edge, the
# level is `use_held`, from the keyboard, any gamepad and the touch layer alike, since all of them
# press the same `interact` action.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"

var _runner: GdUnitSceneRunner
var _player: Player
var _controller := HumanController.new()


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	Input.action_release(&"interact")


func after_test() -> void:
	Input.action_release(&"interact")


func _command() -> NightCommand:
	return _controller.command(_player, 1)


func test_holding_the_action_is_one_press_and_a_level() -> void:
	assert_bool(_command().use_held).is_false()
	Input.action_press(&"interact")
	var first := _command()
	assert_bool(first.use).is_true()
	assert_bool(first.use_held).is_true()
	for _i in 5:
		var later := _command()
		assert_bool(later.use).is_false()
		assert_bool(later.use_held).is_true()
	Input.action_release(&"interact")
	var released := _command()
	assert_bool(released.use).is_false()
	assert_bool(released.use_held).is_false()


func test_a_gamepad_button_from_any_device_holds_it_too() -> void:
	for device in [0, 1, 3]:
		var press := InputEventJoypadButton.new()
		press.device = device
		press.button_index = JOY_BUTTON_Y
		press.pressed = true
		Input.parse_input_event(press)
		Input.flush_buffered_events()
		assert_bool(Input.is_action_pressed(&"interact")).is_true()
		assert_bool(_command().use_held).is_true()
		var release := press.duplicate() as InputEventJoypadButton
		release.pressed = false
		Input.parse_input_event(release)
		Input.flush_buffered_events()
		assert_bool(_command().use_held).is_false()


func test_the_keyboard_key_holds_it() -> void:
	var press := InputEventKey.new()
	press.physical_keycode = KEY_E
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	assert_bool(_command().use_held).is_true()
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	assert_bool(_command().use_held).is_false()


func test_a_paused_player_holds_nothing() -> void:
	Input.action_press(&"interact")
	_player.set_controls_enabled(false)
	var command := _command()
	assert_bool(command.use).is_false()
	assert_bool(command.use_held).is_false()
	_player.set_controls_enabled(true)
