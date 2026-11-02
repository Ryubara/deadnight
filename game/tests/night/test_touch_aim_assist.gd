extends GdUnitTestSuite
## The touch aim assist on a real player (#286): `HumanController` asks `TouchAimAssist` before it
## reads the controls, so the view is nudged toward a zombie while the player aims or fires, the
## look drag is slowed near one, and the trigger pulls itself when the setting says so. All of it
## only while the touch layer is up and a finger was the last input.

const TEST_ROOM := "res://world/test_room.tscn"
const PISTOL := &"pistol"
const CROWBAR := &"crowbar"
const SETTINGS_FILE := "user://touch_aim_assist_test.cfg"

var _runner: GdUnitSceneRunner
var _player: Player
var _state: ClientState
var _assist: TouchAimAssist
var _controller := HumanController.new()
var _touch_up := true
var _was_touch := false


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	await _runner.simulate_frames(4)
	_state = ClientState.new()
	_state.player_id = 1
	_state.frame = {
		"players": {1: {"weapon": PISTOL, "ammo": 8, "reloading": false, "downed": false}}
	}
	_assist = TouchAimAssist.new(get_tree(), _state)
	_assist.strength = 1.0
	_assist.touch_active = func() -> bool: return _touch_up
	_controller.assist = _assist
	_touch_up = true
	_was_touch = UIInputMode.touch
	UIInputMode.touch = true
	Input.action_release(&"aim")
	Input.action_release(&"fire")


func after_test() -> void:
	UIInputMode.touch = _was_touch
	Input.action_release(&"aim")
	Input.action_release(&"fire")


## A walker `distance` metres down the view, with its chest on the view's ray, `right` metres off
## to the right of it.
func _zombie_on_view(distance := 8.0, right := 0.0) -> Dictionary:
	var view := _player.camera_rig.aim_transform()
	var eye := view.origin
	var dir := -view.basis.z
	var side := view.basis.x
	var chest := eye + dir * distance + side * right
	return {
		"id": 1,
		"position": chest - Vector3.UP * 1.2,
		"yaw": 0.0,
		"mode": ZombieBody.Mode.CHASE,
		"look": ZombieModels.DEFAULT,
	}


func _command() -> NightCommand:
	return _controller.command(_player, 1)


## How far the view is from the zombie's chest, as an angle in radians.
func _error(zombie: Dictionary) -> float:
	var view := _player.camera_rig.aim_transform()
	var chest: Vector3 = (zombie["position"] as Vector3) + Vector3.UP * 1.2
	return (-view.basis.z).angle_to((chest - view.origin).normalized())


func _settle(frames := 3) -> void:
	await _runner.simulate_frames(frames)


func test_aiming_turns_the_view_toward_a_zombie_beside_the_crosshair() -> void:
	var zombie := _zombie_on_view(8.0, -0.6)
	_state.zombies = [zombie]
	var before := _error(zombie)
	Input.action_press(&"aim")
	for _i in 30:
		_command()
		await _settle(1)
	assert_float(_error(zombie)).is_less(before * 0.5)


func test_firing_pulls_too_and_idling_does_not() -> void:
	var zombie := _zombie_on_view(8.0, -0.6)
	_state.zombies = [zombie]
	var yaw := _player.camera_rig.yaw
	for _i in 20:
		_command()
		await _settle(1)
	assert_float(_player.camera_rig.yaw).is_equal(yaw)
	Input.action_press(&"fire")
	for _i in 20:
		_command()
		await _settle(1)
	assert_float(absf(angle_difference(yaw, _player.camera_rig.yaw))).is_greater(0.001)


func test_nothing_happens_without_the_touch_layer() -> void:
	_touch_up = false
	_assist.auto_fire = TouchAimAssist.AutoFire.ALWAYS
	var zombie := _zombie_on_view(8.0, 0.0)
	_state.zombies = [zombie]
	var yaw := _player.camera_rig.yaw
	Input.action_press(&"aim")
	var command := _command()
	await _settle()
	_command()
	assert_float(_player.camera_rig.yaw).is_equal(yaw)
	assert_float(_assist.friction()).is_equal(1.0)
	assert_bool(command.fire).is_false()


func test_nothing_happens_when_a_mouse_was_the_last_input() -> void:
	UIInputMode.touch = false
	_assist.auto_fire = TouchAimAssist.AutoFire.ALWAYS
	var zombie := _zombie_on_view(8.0, -0.6)
	_state.zombies = [zombie]
	var yaw := _player.camera_rig.yaw
	Input.action_press(&"aim")
	for _i in 10:
		_command()
		await _settle(1)
	assert_float(_player.camera_rig.yaw).is_equal(yaw)
	assert_float(_assist.friction()).is_equal(1.0)
	assert_bool(_command().fire).is_false()


func test_a_strength_of_zero_is_off() -> void:
	_assist.strength = 0.0
	var zombie := _zombie_on_view(8.0, -0.6)
	_state.zombies = [zombie]
	var yaw := _player.camera_rig.yaw
	Input.action_press(&"aim")
	for _i in 10:
		_command()
		await _settle(1)
	assert_float(_player.camera_rig.yaw).is_equal(yaw)
	assert_float(_assist.friction()).is_equal(1.0)


func test_a_zombie_that_is_dying_is_not_helped() -> void:
	var zombie := _zombie_on_view(8.0, -0.6)
	zombie["mode"] = ZombieBody.Mode.DYING
	_state.zombies = [zombie]
	var yaw := _player.camera_rig.yaw
	Input.action_press(&"aim")
	for _i in 10:
		_command()
		await _settle(1)
	assert_float(_player.camera_rig.yaw).is_equal(yaw)


func test_the_look_drag_is_slowed_near_a_zombie() -> void:
	_state.zombies = [_zombie_on_view(8.0, 0.0)]
	_command()
	assert_float(_assist.friction()).is_less(0.6)
	_state.zombies = []
	_command()
	assert_float(_assist.friction()).is_equal(1.0)


func test_auto_fire_is_off_by_default() -> void:
	assert_int(TouchAimAssist.new(get_tree(), _state).auto_fire).is_equal(
		TouchAimAssist.AutoFire.OFF
	)
	_state.zombies = [_zombie_on_view(8.0, 0.0)]
	assert_bool(_command().fire).is_false()


func test_always_pulls_the_trigger_on_a_zombie_and_lets_go_when_it_is_off_it() -> void:
	_assist.auto_fire = TouchAimAssist.AutoFire.ALWAYS
	_state.zombies = [_zombie_on_view(8.0, 0.0)]
	var on := _command()
	assert_bool(on.fire).is_true()
	assert_bool(on.motion.fire).is_true()
	_state.zombies = [_zombie_on_view(8.0, 3.0)]
	assert_bool(_command().fire).is_false()


func test_while_aiming_waits_for_the_aim_button() -> void:
	_assist.auto_fire = TouchAimAssist.AutoFire.WHILE_AIMING
	_state.zombies = [_zombie_on_view(8.0, 0.0)]
	assert_bool(_command().fire).is_false()
	Input.action_press(&"aim")
	assert_bool(_command().fire).is_true()


func test_auto_fire_does_not_spend_ammunition_it_cannot_use() -> void:
	_assist.auto_fire = TouchAimAssist.AutoFire.ALWAYS
	_state.zombies = [_zombie_on_view(8.0, 0.0)]
	var me: Dictionary = _state.frame["players"][1]
	me["ammo"] = 0
	assert_bool(_command().fire).is_false()
	me["ammo"] = 8
	me["reloading"] = true
	assert_bool(_command().fire).is_false()
	me["reloading"] = false
	me["downed"] = true
	assert_bool(_command().fire).is_false()


func test_auto_fire_keeps_to_its_reach() -> void:
	_assist.auto_fire = TouchAimAssist.AutoFire.ALWAYS
	_state.zombies = [_zombie_on_view(_assist.tuning.auto_fire_reach + 6.0, 0.0)]
	assert_bool(_command().fire).is_false()


func test_a_crowbar_swings_at_a_zombie_within_its_arm() -> void:
	_assist.auto_fire = TouchAimAssist.AutoFire.ALWAYS
	var me: Dictionary = _state.frame["players"][1]
	me["weapon"] = CROWBAR
	me["ammo"] = 0
	_state.zombies = [_zombie_on_view(1.2, 0.0)]
	assert_bool(_command().fire).is_true()
	_state.zombies = [_zombie_on_view(6.0, 0.0)]
	assert_bool(_command().fire).is_false()


func test_the_player_holding_fire_still_fires_with_the_assist_off() -> void:
	_touch_up = false
	Input.action_press(&"fire")
	assert_bool(_command().fire).is_true()


func test_the_settings_set_the_strength_and_the_auto_fire() -> void:
	# A file of its own: the player's real settings are never written by a test.
	var settings := get_tree().root.get_node("Settings")
	var saved_path: String = settings.path
	settings.path = SETTINGS_FILE
	settings.reset_defaults()
	var fresh := TouchAimAssist.new(get_tree(), _state)
	assert_float(fresh.strength).is_equal_approx(0.5, 0.001)
	settings.set_value(SettingsService.TOUCH_AIM_ASSIST, 0.8)
	settings.set_value(SettingsService.TOUCH_AUTO_FIRE, 2)
	assert_float(fresh.strength).is_equal_approx(0.8, 0.001)
	assert_int(fresh.auto_fire).is_equal(TouchAimAssist.AutoFire.ALWAYS)
	settings.reset_defaults()
	settings.save()
	settings.path = saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))


func test_the_defaults_are_gentle_assist_and_no_auto_fire() -> void:
	assert_float(float(SettingsService.DEFAULTS[SettingsService.TOUCH_AIM_ASSIST])).is_equal(0.5)
	assert_int(int(SettingsService.DEFAULTS[SettingsService.TOUCH_AUTO_FIRE])).is_equal(0)
