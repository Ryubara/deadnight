extends GdUnitTestSuite
## The touch aim assist inside a whole night (#286): the night builds it for a human, the touch
## layer's answer reaches it, and a touch player with auto-fire on shoots a zombie the crosshair
## rests on without touching Fire; with the assist off or a mouse the last input, the trigger stays
## where the player left it.

var _was_touch := false
var _touch_up := true


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_was_touch = UIInputMode.touch
	UIInputMode.touch = true
	_touch_up = true
	Input.action_release(&"fire")


func after_test() -> void:
	UIInputMode.touch = _was_touch
	Input.action_release(&"fire")
	Input.action_release(&"aim")


func _human_night() -> Night:
	var night := await NightFixture.start(self, Night.Mode.HUMAN)
	night.ticks_per_frame = 0
	night.touch_active = func() -> bool: return _touch_up
	return night


## Puts the zombie `distance` metres down the view with its chest on the crosshair's ray.
func _stand_on_crosshair(night: Night, zombie: ZombieBody, distance := 6.0) -> void:
	var view := night.player().camera_rig.aim_transform()
	zombie.position = view.origin + (-view.basis.z) * distance - Vector3.UP * 1.2
	zombie.velocity = Vector3.ZERO


## Plays `frames` ticks with the zombie held on the crosshair; the number of shots heard.
func _play(night: Night, zombie: ZombieBody, frames := 90) -> int:
	for _i in frames:
		await get_tree().process_frame
		_stand_on_crosshair(night, zombie)
		night.tick()
	return night.state.shots


func test_a_human_night_builds_the_assist_and_the_settings_reach_it() -> void:
	var night := await _human_night()
	assert_object(night.assist).is_not_null()
	assert_int(night.assist.auto_fire).is_equal(TouchAimAssist.AutoFire.WHILE_AIMING)
	assert_float(night.assist.strength).is_equal_approx(TouchAimAssist.ON_STRENGTH, 0.001)
	night.queue_free()


func test_an_autopilot_night_has_no_assist() -> void:
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT)
	assert_object(night.assist).is_null()
	night.queue_free()


func test_auto_fire_shoots_a_zombie_on_the_crosshair_while_aiming_without_fire_held() -> void:
	var night := await _human_night()
	Input.action_press(&"aim")
	var id := NightFixture.first_zombie(night)
	var zombie: ZombieBody = night.server.sim.zombies[id]
	var shots := await _play(night, zombie)
	assert_int(shots).is_greater(0)
	night.queue_free()


func test_auto_fire_off_leaves_the_trigger_alone() -> void:
	var night := await _human_night()
	night.assist.auto_fire = TouchAimAssist.AutoFire.OFF
	Input.action_press(&"aim")
	var id := NightFixture.first_zombie(night)
	var zombie: ZombieBody = night.server.sim.zombies[id]
	var shots := await _play(night, zombie)
	assert_int(shots).is_equal(0)
	night.queue_free()


func test_a_mouse_player_is_never_auto_fired_for() -> void:
	var night := await _human_night()
	Input.action_press(&"aim")
	UIInputMode.touch = false
	var id := NightFixture.first_zombie(night)
	var zombie: ZombieBody = night.server.sim.zombies[id]
	var shots := await _play(night, zombie)
	assert_int(shots).is_equal(0)
	night.queue_free()
