# The sprint carry in the real night (#459): sprint commands through the night's link make the
# player's Soldier carry the weapon with the stride, and the first shot after the sprint comes on
# the same tick as a shot from a standstill, with the carry gone within its blend-out time.
extends GdUnitTestSuite

const STEP := Night.STEP

var _ticks := 0
var _shot_at := -1


func _drive(night: Night, animation: PlayerAnimation, ticks: int, command: NightCommand) -> void:
	for _i in ticks:
		NightFixture.run(night, 1, command)
		_ticks += 1
		animation._process(STEP)
		animation.advance(STEP)


func _sprint(facing: float) -> NightCommand:
	var command := NightCommand.new()
	command.motion.yaw = facing
	command.motion.move = Vector2(0.0, -1.0)
	command.motion.sprint = true
	return command


func _shot(night: Night, from: NightCommand) -> NightCommand:
	var command := NightCommand.from_dict(from.to_dict())
	var eye := night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	var ahead := Vector3(-sin(from.motion.yaw), 0.0, -cos(from.motion.yaw))
	command.origin = eye
	command.dir = (ahead * 10.0 + Vector3(0.0, Autopilot.CHEST - Autopilot.EYE, 0.0)).normalized()
	command.fire = true
	return command


## Ticks from the first tick the trigger is held to the night's `shot_fired`.
func _ticks_to_shot(night: Night, animation: PlayerAnimation, command: NightCommand) -> int:
	_shot_at = -1
	var start := _ticks
	for _i in 30:
		_drive(night, animation, 1, _shot(night, command))
		if _shot_at >= 0:
			return _shot_at - start
	return -1


func test_a_sprint_carries_the_weapon_and_the_first_shot_is_not_delayed() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var player := night.player()
	var animation := player.get_node("AnimationTree") as PlayerAnimation
	animation.set_process(false)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	night.state.event_received.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"shot_fired" and _shot_at < 0:
				_shot_at = _ticks
	)
	# A shot from a standstill, for the reference.
	var still := NightCommand.new()
	still.motion.yaw = player.state.facing
	_drive(night, animation, 60, still)
	var from_still := _ticks_to_shot(night, animation, still)
	assert_int(from_still).is_greater_equal(0)
	_drive(night, animation, 90, still)  # the hip-fire hold and the cooldown are over

	var sprint := _sprint(player.state.facing)
	_drive(night, animation, roundi(0.8 / STEP), sprint)
	assert_bool(player.is_sprinting()).is_true()
	assert_float(player.ground_speed()).is_greater(player.tuning.sprint_carry_min_speed)
	assert_float(animation.sprint_carry()).is_equal(1.0)
	assert_str(String(animation.tree_root.get_node(&"carry_clip").animation)).is_equal(
		"Sprint_%s" % animation.weapon_class
	)

	var from_sprint := _ticks_to_shot(night, animation, sprint)
	assert_int(from_sprint).is_equal(from_still)
	assert_str(String(animation.action_clip)).starts_with("Fire_")
	_drive(night, animation, ceili(player.tuning.sprint_carry_out / STEP) - 1, _shot(night, sprint))
	assert_float(animation.sprint_carry()).is_equal(0.0)
	night.queue_free()
