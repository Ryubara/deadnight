# The sprint carry (#459): while the body sprints on the ground the arms carry the weapon with the
# stride (Sprint_<Class>, at the Run clip's time), it holds still in the air, and the aim, a shot, a
# reload or a swing take the arms back within the blend-out time. The player is driven by commands
# through its own simulation (`tick`) and the tree is stepped by hand, a fixed tick at a time, so
# nothing here waits on the clock.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 17.0)
## One frame of the 24 fps clips, in seconds.
const FRAME := 1.0 / 24.0

var _player: Player
var _animation: PlayerAnimation
var _tuning: PlayerTuning


func before_test() -> void:
	var runner := scene_runner(TEST_ROOM)
	_player = runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.camera_rig.set_process(false)
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tuning = _player.tuning
	_player.teleport(START)
	await get_tree().physics_frame
	await get_tree().physics_frame


## Runs the player and its animation for `ticks` ticks with the given command fields.
func _run(ticks: int, sprint: bool = true, extra: Dictionary = {}) -> void:
	for _i in ticks:
		var command := PlayerCommand.new()
		command.move = extra.get("move", Vector2(0.0, -1.0) if sprint else Vector2.ZERO)
		command.sprint = sprint
		command.aim = extra.get("aim", false)
		command.fire = extra.get("fire", false)
		command.jump = extra.get("jump", false)
		extra.erase("jump")  # a press, one tick
		_player.tick(command)
		_player.camera_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)


func _ticks(seconds: float) -> int:
	return ceili(seconds / TICK - 0.001)


func _phase_error() -> float:
	var length: float = _animation._clip_seconds(&"Run")
	return absf(
		wrapf(_animation.sprint_carry_time() - _animation.run_time(), -length * 0.5, length * 0.5)
	)


func test_every_class_has_its_carry_on_runs_cycle() -> void:
	var anim_player := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var run := anim_player.get_animation(&"Run")
	for cls: StringName in PlayerAnimation.CLASSES:
		var clip := anim_player.get_animation(StringName("Sprint_%s" % cls))
		assert_object(clip).override_failure_message(String(cls)).is_not_null()
		assert_int(clip.loop_mode).is_equal(Animation.LOOP_LINEAR)
		assert_float(clip.length).is_equal_approx(run.length, 0.001)


func test_the_carry_plays_only_while_sprinting_on_the_ground() -> void:
	_run(30, false)
	assert_float(_animation.sprint_carry()).is_equal(0.0)
	_run(30, false, {"move": Vector2(0.0, -1.0)})  # a run without the sprint key
	assert_bool(_player.is_sprinting()).is_false()
	assert_float(_animation.sprint_carry()).is_equal(0.0)
	_run(_ticks(0.25))  # the sprint builds up past the carry's speed
	_run(_ticks(_tuning.sprint_carry_in))
	assert_bool(_player.state.on_floor).is_true()
	assert_float(_animation.sprint_carry()).is_equal(1.0)
	# Let go of the key: it eases out.
	_run(_ticks(_tuning.sprint_carry_out), false, {"move": Vector2(0.0, -1.0)})
	assert_float(_animation.sprint_carry()).is_equal(0.0)


func test_in_the_air_the_carry_holds_still_and_never_starts() -> void:
	_run(60)
	assert_float(_animation.sprint_carry()).is_equal(1.0)
	_run(1, true, {"jump": true})
	_run(2)
	assert_bool(_player.state.on_floor).is_false()
	var held := _animation.sprint_carry_time()
	_run(10)
	assert_bool(_player.state.on_floor).is_false()
	assert_bool(_player.is_sprinting()).is_true()  # the sprint carries through the jump
	assert_float(_animation.sprint_carry()).is_equal(1.0)
	assert_float(_animation.sprint_carry_time()).is_equal(held)  # no swing without the feet
	# A jump from a standstill with the sprint key held does not start it in the air.
	_run(120, false)
	_run(1, false, {"jump": true})
	for _i in 10:
		_run(1, true, {"move": Vector2(0.0, -1.0)})
		assert_float(_animation.sprint_carry()).is_equal(0.0)


func test_its_phase_matches_the_run_clip() -> void:
	_run(60)
	for _i in 40:
		_run(1)
		assert_float(_phase_error()).is_less(0.002)
	# The clip the tree draws is where the carry says it is.
	var drawn: float = _animation.get(&"parameters/carry_clip/current_position")
	assert_float(drawn).is_equal_approx(_animation.sprint_carry_time(), 0.002)


func test_after_a_landing_it_catches_up_with_the_run_without_jumping() -> void:
	_run(60)
	_run(1, true, {"jump": true})
	var before := _animation.sprint_carry_time()
	var largest := 0.0
	for _i in 120:
		_run(1)
		var length: float = _animation._clip_seconds(&"Run")
		var moved := absf(
			wrapf(_animation.sprint_carry_time() - before, -length * 0.5, length * 0.5)
		)
		largest = maxf(largest, moved)
		before = _animation.sprint_carry_time()
	assert_bool(_player.state.on_floor).is_true()
	assert_float(_phase_error()).is_less(0.002)
	# The Run plays at about 1.3 times its pace at a sprint: 0.022 s a tick. A catch-up adds at
	# most a fifth of the gap (half the clip) in a tick, never a jump across the cycle.
	assert_float(largest).is_less(0.022 + 0.2 * 0.36)


func test_the_aim_takes_the_arms_back_within_the_blend_out() -> void:
	_run(60)
	_run(_ticks(_tuning.sprint_carry_out), true, {"aim": true})
	assert_float(_animation.sprint_carry()).is_equal(0.0)
	assert_bool(_animation.hands().active).is_true()  # the shouldered pose is coming back


func test_a_shot_from_the_hip_takes_the_arms_back_within_the_blend_out() -> void:
	_run(60)
	_run(1, true, {"fire": true})
	assert_float(_animation.sprint_carry()).is_less(1.0)
	_run(_ticks(_tuning.sprint_carry_out) - 1)
	assert_float(_animation.sprint_carry()).is_equal(0.0)


func test_a_reload_and_a_swing_take_the_arms_back_within_the_blend_out() -> void:
	for action: StringName in [&"Reload", &"Swing"]:
		_animation.equip(&"Melee" if action == &"Swing" else &"Rifle")
		_run(60)
		assert_float(_animation.sprint_carry()).override_failure_message(action).is_equal(1.0)
		assert_bool(_animation.play_action(action)).is_true()
		_run(_ticks(_tuning.sprint_carry_out))
		assert_float(_animation.sprint_carry()).override_failure_message(action).is_equal(0.0)


func test_going_down_or_kneeling_at_a_revive_takes_the_arms_back() -> void:
	for down: bool in [true, false]:
		_run(60)
		assert_float(_animation.sprint_carry()).is_equal(1.0)
		if down:
			_animation.set_downed(true)
		else:
			_animation.set_reviving(true)
		_run(_ticks(_tuning.sprint_carry_out))
		assert_float(_animation.sprint_carry()).override_failure_message(str(down)).is_equal(0.0)
		_animation.set_downed(false)
		_animation.set_reviving(false)


func test_the_first_shot_after_a_sprint_has_no_extra_delay() -> void:
	# The muzzle event is frame 0 of Fire: it comes in the same call that starts the clip, with
	# the carry fully in or not at all.
	var muzzles: Array[float] = []
	_animation.clip_event.connect(
		func(_clip: StringName, event: StringName) -> void:
			if event == &"muzzle":
				muzzles.append(_animation.sprint_carry())
	)
	_run(60)
	assert_float(_animation.sprint_carry()).is_equal(1.0)
	assert_bool(_animation.play_action(&"Fire")).is_true()
	assert_array(muzzles).is_equal([1.0])
	_run(30, false)
	assert_bool(_animation.play_action(&"Fire")).is_true()
	assert_array(muzzles).is_equal([1.0, 0.0])


## The hand the weapon rides (Index1.R) from the hips, in metres in the hips' frame, read off the
## pose the tree just drew: the stride's bob and turn of the hips are the legs' (the aim pose held
## through a sprint keeps the hand still here), the rest is the upper body's.
func _hand() -> Vector3:
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var hand := skeleton.get_bone_global_pose(skeleton.find_bone(PlayerAnimation.HAND_BONE))
	var hips := skeleton.get_bone_global_pose(skeleton.find_bone("Hips"))
	return skeleton.global_basis.get_scale() * (hips.affine_inverse() * hand).origin


func test_the_weapon_swings_with_the_stride_in_every_class() -> void:
	for cls: StringName in PlayerAnimation.CLASSES:
		_player.teleport(START)  # room to sprint in: 10 m for each class
		await get_tree().physics_frame
		_animation.equip(cls)
		_run(30, false)
		var aimed := _hand()
		_run(60)
		assert_str(String(_animation.tree_root.get_node(&"carry_clip").animation)).is_equal(
			"Sprint_%s" % cls
		)
		# The hand leaves the aim pose for the carry, and through one stride it swings: its
		# path from the hips spans more than 5 cm (the aim pose held through a sprint: under 1).
		print("CARRY %s aim->carry %.3f" % [cls, _hand().distance_to(aimed)])
		assert_float(_hand().distance_to(aimed)).override_failure_message(cls).is_greater(0.1)
		var low := Vector3.INF
		var high := -Vector3.INF
		for _i in _ticks(0.71 / 1.3):
			_run(1)
			low = low.min(_hand())
			high = high.max(_hand())
		print("CARRY %s stride span %.3f" % [cls, (high - low).length()])
		assert_float((high - low).length()).override_failure_message(cls).is_greater(0.05)
		_run(30, false)


func test_the_clips_move_only_the_spine_shoulders_and_arms() -> void:
	# The fingers are the grip's (#460: `HandGripPose` closes them) and the legs are the Run's: no
	# Sprint clip moves a finger or a lower-body bone. The hand bones (`Index1`, the palm the weapon
	# rides) turn, as the arms' IK turns them, so the weapon points where the carry wants it and
	# the left hand holds the fore-end the way the grip says (#527).
	var anim_player := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var moving := ["Abdomen", "Torso", "Neck", "Head", "Shoulder", "UpperArm", "LowerArm", "Index1"]
	for cls: StringName in PlayerAnimation.CLASSES:
		var clip := anim_player.get_animation(StringName("Sprint_%s" % cls))
		var moved: Array[String] = []
		for track in clip.get_track_count():
			var bone := String(clip.track_get_path(track)).get_slice(":", 1)
			if bone.get_slice(".", 0) in moving or clip.track_get_key_count(track) < 2:
				continue
			var first: Variant = clip.track_get_key_value(track, 0)
			for key in clip.track_get_key_count(track):
				var value: Variant = clip.track_get_key_value(track, key)
				var same: bool = (
					(value as Quaternion).is_equal_approx(first)
					if value is Quaternion
					else (value as Vector3).is_equal_approx(first)
				)
				if not same:
					moved.append(bone)
					break
		assert_array(moved).override_failure_message("%s moves %s" % [cls, moved]).is_empty()
