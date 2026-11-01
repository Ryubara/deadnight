# gdlint:disable=max-public-methods
# The third-person player in the test room: input map, movement, camera, animation, commands.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _tuning: PlayerTuning
var _real_settings: Node


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_rig = _player.camera_rig
	_tuning = _player.tuning
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	# The camera's ease and the animation advance by the frame delta, which is wall time: a loaded
	# machine gives long, uneven frames. The tests step them by hand, one fixed tick per physics
	# frame (see _ticks), so the same ticks always give the same result.
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.teleport(START)
	await _ticks(20)  # settle onto the floor


func after_test() -> void:
	Engine.physics_ticks_per_second = int(
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second")
	)
	var service := get_tree().root.get_node_or_null(PlayerSettings.SERVICE_PATH)
	if service is _FakeSettings:
		service.free()
	if _real_settings != null and _real_settings.get_parent() == null:
		get_tree().root.add_child(_real_settings)
	_real_settings = null


## Take the game's Settings autoload out of the tree so a test can run without one or with a fake.
func _detach_settings() -> void:
	_real_settings = get_tree().root.get_node_or_null(PlayerSettings.SERVICE_PATH)
	if _real_settings != null:
		get_tree().root.remove_child(_real_settings)


func _install_fake_settings(values: Dictionary) -> void:
	_detach_settings()
	var service := _FakeSettings.new()
	service.name = "Settings"
	service.values = values
	get_tree().root.add_child(service)
	_player.refresh_settings()


## Waits `count` physics ticks and steps the frame-driven nodes (camera ease, animation) by the
## same fixed time after each, so game time never depends on how fast the machine renders.
func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		_step_frame_nodes(TICK)


func _step_frame_nodes(delta: float) -> void:
	_rig.step(delta, 1.0)
	_animation._process(delta)
	_animation.advance(delta)


func _seconds(seconds: float) -> void:
	await _ticks(roundi(seconds / TICK))


## Waits, in fixed ticks, until the upper one-shot has finished (or `limit` seconds of game time).
func _until_idle(limit: float) -> void:
	var waited := 0.0
	while _animation.action_clip != &"" and waited < limit:
		await _ticks(1)
		waited += TICK
	await _ticks(1)


func _plane_distance(from: Vector3) -> float:
	var d := _player.global_position - from
	return Vector2(d.x, d.z).length()


# --- input map ---


func _is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func test_input_map_has_every_action_with_keyboard_and_gamepad() -> void:
	for action in [
		"move_forward",
		"move_back",
		"move_left",
		"move_right",
		"sprint",
		"crouch",
		"jump",
		"swap_shoulder"
	]:
		assert_bool(InputMap.has_action(action)).is_true()
		var events := InputMap.action_get_events(action)
		assert_bool(events.any(func(e: InputEvent) -> bool: return e is InputEventKey)).is_true()
		assert_bool(events.any(_is_gamepad_event)).is_true()
	var aim := InputMap.action_get_events("aim")
	assert_bool(aim.any(func(e: InputEvent) -> bool: return e is InputEventMouseButton)).is_true()
	assert_bool(aim.any(func(e: InputEvent) -> bool: return e is InputEventJoypadMotion)).is_true()
	for action in ["look_left", "look_right", "look_up", "look_down"]:
		assert_bool(InputMap.has_action(action)).is_true()


# --- movement ---


func test_standing_still_stays_put_on_the_floor() -> void:
	var start := _player.global_position
	await _seconds(1.0)
	assert_bool(_player.state.on_floor).is_true()
	assert_float(_plane_distance(start)).is_less(0.01)


func test_run_forward_reaches_run_speed_along_minus_z_with_the_camera_behind() -> void:
	var start := _player.global_position
	_runner.simulate_action_press("move_forward")
	await _seconds(1.5)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.run_speed, 0.05)
	assert_float(_player.global_position.z).is_less(start.z - 4.0)
	assert_float(absf(_player.global_position.x - start.x)).is_less(0.01)


func test_acceleration_is_quick_but_not_instant() -> void:
	_runner.simulate_action_press("move_forward")
	await _ticks(3)
	assert_float(_player.ground_speed()).is_between(0.5, _tuning.run_speed - 0.5)
	await _seconds(0.3)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.run_speed, 0.05)


func test_sprint_is_faster_than_run() -> void:
	_runner.simulate_action_press("move_forward")
	_runner.simulate_action_press("sprint")
	await _seconds(1.5)
	assert_bool(_player.is_sprinting()).is_true()
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.sprint_speed, 0.05)


func test_sprint_works_sideways_too() -> void:
	# It used to need forward movement; now every direction sprints (test_omni_movement.gd).
	_runner.simulate_action_press("move_left")
	_runner.simulate_action_press("sprint")
	await _seconds(1.0)
	assert_bool(_player.is_sprinting()).is_true()
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.sprint_speed, 0.05)


func test_diagonal_is_no_faster_than_straight() -> void:
	_runner.simulate_action_press("move_forward")
	_runner.simulate_action_press("move_right")
	await _seconds(1.0)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.run_speed, 0.05)


func test_releasing_input_stops_the_player() -> void:
	_runner.simulate_action_press("move_forward")
	await _seconds(1.0)
	_runner.simulate_action_release("move_forward")
	await _seconds(0.5)
	assert_float(_player.ground_speed()).is_less(0.01)


func test_movement_is_relative_to_the_camera() -> void:
	_rig.yaw = -PI / 2.0  # camera looking along +X
	_runner.simulate_action_press("move_forward")
	await _seconds(1.0)
	assert_float(_player.state.velocity.x).is_greater(_tuning.run_speed - 0.1)
	assert_float(absf(_player.state.velocity.z)).is_less(0.01)


func test_body_turns_to_face_the_way_it_runs() -> void:
	_runner.simulate_action_press("move_right")
	await _seconds(0.5)
	assert_float(_player.rotation.y).is_equal_approx(-PI / 2.0, 0.02)


func test_a_turn_takes_time_not_a_snap() -> void:
	_runner.simulate_action_press("move_back")  # turn around, 180 degrees
	await _ticks(2)
	assert_float(absf(_player.rotation.y)).is_between(0.05, PI - 0.5)
	await _seconds(0.6)
	assert_float(absf(_player.rotation.y)).is_equal_approx(PI, 0.02)


func test_aim_slows_the_player_and_faces_the_camera() -> void:
	_rig.yaw = 1.0
	_runner.simulate_action_press("aim")
	_runner.simulate_action_press("move_forward")
	_runner.simulate_action_press("sprint")
	await _seconds(1.0)
	assert_bool(_player.is_aiming()).is_true()
	assert_bool(_player.is_sprinting()).is_false()
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.aim_speed, 0.05)
	assert_float(_player.rotation.y).is_equal_approx(1.0, 0.02)


# --- jump ---


func test_jump_reaches_the_tuned_height_and_lands() -> void:
	var events := {"jumped": 0, "landed": 0}
	_player.jumped.connect(func() -> void: events.jumped += 1)
	_player.landed.connect(func(_speed: float) -> void: events.landed += 1)
	var floor_y := _player.global_position.y
	var peak := floor_y
	_runner.simulate_action_press("jump")
	for i in 100:
		await get_tree().physics_frame
		peak = maxf(peak, _player.global_position.y)
		_runner.simulate_action_release("jump")
	assert_float(peak - floor_y).is_equal_approx(_tuning.jump_height, 0.08)
	assert_bool(_player.state.on_floor).is_true()
	assert_int(events.jumped).is_equal(1)
	assert_int(events.landed).is_equal(1)


func test_jump_pressed_in_the_air_just_before_landing_is_buffered() -> void:
	_player.teleport(Vector3(START.x, 0.3, START.z))
	await _ticks(2)
	var jumped := [0]
	_player.jumped.connect(func() -> void: jumped[0] += 1)
	var command := PlayerCommand.new()
	command.jump = true
	_player.local_input = false
	_player.submit_command(command)
	await _seconds(0.5)
	assert_int(jumped[0]).is_equal(1)


func test_no_double_jump() -> void:
	_runner.simulate_action_press("jump")
	await _ticks(1)
	_runner.simulate_action_release("jump")
	await _seconds(0.2)
	var jumped := [0]
	_player.jumped.connect(func() -> void: jumped[0] += 1)
	_runner.simulate_action_press("jump")
	await _ticks(1)
	_runner.simulate_action_release("jump")
	await _seconds(0.1)
	assert_int(jumped[0]).is_equal(0)


# --- fixed timestep ---


func test_distance_is_the_same_at_30_60_and_120_ticks_per_second() -> void:
	# move_and_slide steps by the engine's physics delta, so change the engine's tick rate. The
	# ticks are stepped by hand (the same two seconds of forward at every rate), so a late frame
	# on a loaded machine cannot change how many of them the press covers.
	_player.set_physics_process(false)
	var forward := PlayerCommand.new()
	forward.move = Vector2(0.0, -1.0)
	var distances: Array[float] = []
	for hz in [30, 60, 120]:
		Engine.physics_ticks_per_second = hz
		# The engine reads the new rate when it plans a step: let two steps run so the delta the
		# simulation reads is the new one.
		await get_tree().physics_frame
		await get_tree().physics_frame
		assert_float(_player.get_physics_process_delta_time()).is_equal_approx(1.0 / hz, 0.0001)
		_player.teleport(START)
		for i in hz / 6:
			_player.tick(PlayerCommand.new())  # settle onto the floor
		var start := _player.global_position
		for i in hz * 2:
			_player.tick(forward)
		distances.append(_plane_distance(start))
	assert_float(distances[1]).is_greater(5.0)  # it walked, so the comparison below means something
	assert_float(distances[0]).is_equal_approx(distances[1], 0.1)
	assert_float(distances[2]).is_equal_approx(distances[1], 0.1)


# --- look ---


func test_mouse_motion_turns_the_camera() -> void:
	await _ticks(5)
	_rig.yaw = 0.0
	_rig.pitch = 0.0
	var yaw_before := _rig.yaw
	var pitch_before := _rig.pitch
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(100.0, 50.0)
	_player._unhandled_input(event)  # the headless run does not transport real input events
	var turn := _tuning.mouse_radians_per_pixel
	assert_float(_rig.yaw).is_equal_approx(yaw_before - turn * 100.0, 0.001)  # right is clockwise
	assert_float(_rig.pitch).is_equal_approx(pitch_before - turn * 50.0, 0.001)  # down looks down


func test_pitch_is_clamped() -> void:
	_rig.apply_look(0.0, -100.0)
	assert_float(_rig.pitch).is_equal_approx(deg_to_rad(_tuning.pitch_max_degrees), 0.0001)
	_rig.apply_look(0.0, 200.0)
	assert_float(_rig.pitch).is_equal_approx(deg_to_rad(_tuning.pitch_min_degrees), 0.0001)


func test_gamepad_stick_turns_at_the_tuned_rate() -> void:
	var yaw_before := _rig.yaw
	_runner.simulate_action_press("look_right")
	await _seconds(0.5)
	_runner.simulate_action_release("look_right")
	await _ticks(2)
	assert_float(rad_to_deg(yaw_before - _rig.yaw)).is_equal_approx(
		_tuning.stick_degrees_per_second * 0.5, 8.0
	)


func test_defaults_apply_without_a_settings_service() -> void:
	_detach_settings()
	_player.refresh_settings()
	assert_float(_rig.sensitivity).is_equal(PlayerSettings.DEFAULT_SENSITIVITY)
	assert_bool(_rig.invert_y).is_equal(PlayerSettings.DEFAULT_INVERT_Y)


func test_settings_service_sets_sensitivity_and_invert_y() -> void:
	_install_fake_settings({PlayerSettings.KEY_SENSITIVITY: 2.0, PlayerSettings.KEY_INVERT_Y: true})
	assert_float(_rig.sensitivity).is_equal(2.0)
	assert_bool(_rig.invert_y).is_true()
	_rig.look_mouse(Vector2(0.0, 10.0))  # mouse down, inverted: looks up
	assert_float(_rig.pitch).is_equal_approx(10.0 * _tuning.mouse_radians_per_pixel * 2.0, 0.0001)


func test_a_broken_settings_service_falls_back_to_defaults() -> void:
	_install_fake_settings({PlayerSettings.KEY_SENSITIVITY: "loud", PlayerSettings.KEY_INVERT_Y: 3})
	assert_float(_rig.sensitivity).is_equal(PlayerSettings.DEFAULT_SENSITIVITY)
	assert_bool(_rig.invert_y).is_equal(PlayerSettings.DEFAULT_INVERT_Y)


func test_the_real_settings_autoload_drives_the_look() -> void:
	var settings := get_tree().root.get_node_or_null(PlayerSettings.SERVICE_PATH)
	assert_object(settings).is_not_null()
	var old_sensitivity: Variant = settings.call("get_value", PlayerSettings.KEY_SENSITIVITY)
	settings.call("set_value", PlayerSettings.KEY_SENSITIVITY, 2.5)
	assert_float(_rig.sensitivity).is_equal_approx(2.5, 0.001)  # via the changed signal
	settings.call("set_value", PlayerSettings.KEY_SENSITIVITY, old_sensitivity)


func test_disabled_controls_ignore_input() -> void:
	_player.set_controls_enabled(false)
	var start := _player.global_position
	_runner.simulate_action_press("move_forward")
	await _seconds(0.5)
	assert_float(_plane_distance(start)).is_less(0.01)


# --- camera ---


func test_aim_zooms_in_with_an_eased_fov_and_shorter_arm() -> void:
	var camera := _rig.camera()
	assert_float(camera.fov).is_equal_approx(_tuning.fov, 0.1)
	_runner.simulate_action_press("aim")
	await _seconds(0.05)
	# mid-ease, not a snap
	assert_float(camera.fov).is_between(_tuning.fov_aim + 0.5, _tuning.fov - 0.2)
	await _seconds(0.8)
	assert_float(camera.fov).is_equal_approx(_tuning.fov_aim, 0.3)
	assert_float(_rig.lens_distance()).is_equal_approx(_aim_lens_distance(), 0.05)
	_runner.simulate_action_release("aim")
	await _seconds(0.8)
	assert_float(camera.fov).is_equal_approx(_tuning.fov, 0.3)


func test_shoulder_swap_moves_the_camera_smoothly_to_the_other_side() -> void:
	var camera := _rig.camera()
	await _seconds(0.5)
	assert_float(_lateral(camera)).is_equal_approx(_tuning.shoulder_offset, 0.02)
	_runner.simulate_action_press("swap_shoulder")
	await _ticks(1)
	_runner.simulate_action_release("swap_shoulder")
	assert_float(_player.state.shoulder_side).is_equal(-1.0)
	await _ticks(3)
	assert_float(_lateral(camera)).is_between(
		-_tuning.shoulder_offset + 0.05, _tuning.shoulder_offset - 0.05
	)
	await _seconds(1.0)
	assert_float(_lateral(camera)).is_equal_approx(-_tuning.shoulder_offset, 0.02)


func test_camera_pulls_in_instead_of_clipping_a_wall() -> void:
	_player.teleport(Vector3(0.0, 0.05, 19.7))  # the south wall is right behind the camera
	await _seconds(0.5)
	assert_float(_rig.lens_distance()).is_less(_tuning.arm_length - 1.0)


## Sideways distance of the lens from the player's vertical axis, along the view's right.
func _lateral(camera: Camera3D) -> float:
	var offset := camera.global_position - _player.global_position
	return offset.dot(camera.global_transform.basis.x)


## Distance from the head to the lens when the aim zoom is in and the camera is over the shoulder.
func _aim_lens_distance() -> float:
	return Vector2(_tuning.shoulder_offset_aim, _tuning.arm_length_aim).length()


# --- animation ---


func test_idle_then_run_then_jump_states() -> void:
	await _seconds(0.8)  # let the landing from the spawn drop finish
	assert_str(str(_animation.current_state())).is_equal("locomotion")
	_runner.simulate_action_press("move_forward")
	await _seconds(1.0)
	assert_float(_animation.get(PlayerAnimation.MOVE_PARAMETER)).is_greater(0.95)
	# Feet stay planted: the Run clip's speed follows the ground speed.
	assert_float(_animation.get(PlayerAnimation.RUN_SPEED_PARAMETER)).is_equal_approx(
		_player.ground_speed() / _tuning.run_clip_speed, 0.02
	)
	_runner.simulate_action_press("jump")
	await _ticks(2)
	_runner.simulate_action_release("jump")
	assert_str(str(_animation.current_state())).is_equal("jump")
	await _seconds(0.6)
	assert_str(str(_animation.current_state())).is_not_equal("locomotion")
	await _seconds(1.0)
	assert_str(_animation.current_state()).is_equal("locomotion")


func test_the_weapon_rides_the_right_hand() -> void:
	var mount := _animation.weapon_mount()
	assert_object(mount).is_not_null()
	assert_str(mount.bone_name).is_equal(PlayerAnimation.HAND_BONE)
	# The weapon, and the repair hammer and the grenade waiting hidden.
	assert_int(mount.get_child_count()).is_equal(3)
	assert_bool(_animation.weapon().is_visible_in_tree()).is_true()
	assert_bool(_animation.hammer().visible).is_false()
	assert_str(_animation.weapon_class).is_equal("Rifle")
	# The grip follows the hand bone, so it sits beside the Soldier at about hand height.
	var hand := mount.global_position - _player.global_position
	assert_float(hand.y).is_between(0.4, 1.6)


func test_loops_come_from_the_clip_spec() -> void:
	var player := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in ["Idle", "Walk", "Run", "Aim_Rifle", "Aim_Melee", "Downed", "Jump_Idle"]:
		assert_int(player.get_animation(clip).loop_mode).is_equal(Animation.LOOP_LINEAR)
	for clip in ["Fire_Rifle", "Reload_Shotgun", "Death", "Equip_Melee"]:
		assert_int(player.get_animation(clip).loop_mode).is_equal(Animation.LOOP_NONE)


func test_equip_swaps_the_weapon_on_its_event_frame() -> void:
	var events: Array[StringName] = []
	_animation.clip_event.connect(
		func(_clip: StringName, event: StringName) -> void: events.append(event)
	)
	_animation.equip(&"Melee")
	assert_str(_animation.weapon_class).is_equal("Melee")
	assert_str(_animation.action_clip).is_equal("Equip_Melee")
	assert_bool(_animation.weapon().visible).is_false()
	await _until_idle(2.0)  # Equip is 10 frames at 24 fps; weapon_visible is frame 2
	assert_bool(_animation.weapon().visible).is_true()
	assert_array(events).contains_exactly([&"weapon_visible", &"ready"])
	assert_str(_animation.action_clip).is_equal("")
	assert_str(_animation.weapon().scene_file_path).ends_with("baseball_bat.glb")


func test_fire_and_reload_emit_their_event_frames() -> void:
	var events: Array[StringName] = []
	_animation.clip_event.connect(
		func(_clip: StringName, event: StringName) -> void: events.append(event)
	)
	assert_bool(_animation.play_action(&"Fire")).is_true()
	assert_array(events).contains_exactly([&"muzzle"])  # frame 0: the shot has no delay
	await _until_idle(2.0)
	assert_array(events).contains_exactly([&"muzzle", &"can_fire_again"])
	events.clear()
	_animation.play_action(&"Reload")
	await _until_idle(6.0)
	assert_array(events).contains_exactly(
		[&"round_in", &"round_in", &"round_in", &"lever", &"can_fire_again"]
	)
	assert_bool(_animation.play_action(&"Swing")).is_false()  # a rifle does not swing


func test_a_step_past_the_rounded_clip_length_still_emits_the_last_event() -> void:
	# Fire_Rifle is 0.333 s in clips.json but its last event is frame 8 of 24 (0.3333 s). A frame
	# step that ends between the two used to end the clip and drop can_fire_again for good.
	var events: Array[StringName] = []
	_animation.clip_event.connect(
		func(_clip: StringName, event: StringName) -> void: events.append(event)
	)
	assert_bool(_animation.play_action(&"Fire")).is_true()
	_animation._advance_events(0.3331)
	assert_str(_animation.action_clip).is_equal("Fire_Rifle")  # not over until its last event
	_animation._advance_events(0.01)
	assert_array(events).contains_exactly([&"muzzle", &"can_fire_again"])
	assert_str(_animation.action_clip).is_equal("")


func test_the_arms_aim_while_the_legs_run() -> void:
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var arm := skeleton.find_bone("UpperArm.R")
	var leg := skeleton.find_bone("UpperLeg.L")
	await _seconds(0.8)
	var arm_still := skeleton.get_bone_pose_rotation(arm)
	var leg_still := skeleton.get_bone_pose_rotation(leg)
	_runner.simulate_action_press("move_forward")
	await _seconds(1.0)
	# The upper bones hold Aim_Rifle; the legs follow the run.
	assert_float(skeleton.get_bone_pose_rotation(arm).angle_to(arm_still)).is_less(0.15)
	assert_float(skeleton.get_bone_pose_rotation(leg).angle_to(leg_still)).is_greater(0.05)
	assert_str(_animation.current_state()).is_equal("locomotion")


func test_footsteps_follow_distance_run() -> void:
	var steps := [0]
	_player.footstep.connect(func(_speed: float, _sprinting: bool) -> void: steps[0] += 1)
	_runner.simulate_action_press("move_forward")
	await _seconds(3.0)
	var expected := _tuning.run_speed * 3.0 / _tuning.step_distance
	assert_float(float(steps[0])).is_equal_approx(expected, 1.5)


# --- commands and state: the network boundary ---


func test_a_command_survives_serialization() -> void:
	var command := PlayerCommand.new()
	command.move = Vector2(0.5, -1.0)
	command.yaw = 1.25
	command.pitch = -0.3
	command.sprint = true
	command.jump = true
	command.aim = true
	command.fire = true
	command.swap_shoulder = true
	var copy := PlayerCommand.from_bytes(command.to_bytes())
	assert_dict(copy.to_dict()).is_equal(command.to_dict())


func test_replaying_the_same_commands_from_the_same_state_gives_the_same_result() -> void:
	# What prediction and server reconciliation rely on.
	_player.local_input = false
	var recorded: Array[PackedByteArray] = []
	var start := _player.state.duplicate_state()
	for i in 150:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -1.0) if i < 100 else Vector2(1.0, 0.0)
		command.yaw = 0.4
		command.sprint = i > 30 and i < 80
		command.jump = i == 60 or i == 110
		command.aim = i > 120
		command.fire = i > 40 and i < 90
		recorded.append(command.to_bytes())
		_player.submit_command(command)
		await get_tree().physics_frame
	var first_end := _player.state.duplicate_state()
	assert_float(first_end.position.distance_to(start.position)).is_greater(5.0)

	_player.state.copy_from(start)
	_player.global_position = start.position
	for bytes in recorded:
		_player.submit_command(PlayerCommand.from_bytes(bytes))
		await get_tree().physics_frame
	var replay_end := _player.state
	assert_vector(replay_end.position).is_equal_approx(first_end.position, Vector3.ONE * 0.001)
	assert_vector(replay_end.velocity).is_equal_approx(first_end.velocity, Vector3.ONE * 0.001)
	assert_float(replay_end.facing).is_equal_approx(first_end.facing, 0.001)


func test_the_simulation_does_not_read_the_controls() -> void:
	# A held key must not move a player that is being fed commands.
	_player.local_input = false
	_runner.simulate_action_press("move_forward")
	var start := _player.global_position
	_player.submit_command(PlayerCommand.new())
	for i in 30:
		_player.submit_command(PlayerCommand.new())
		await get_tree().physics_frame
	assert_float(_plane_distance(start)).is_less(0.01)


class _FakeSettings:
	extends Node
	var values := {}

	func get_value(key: StringName) -> Variant:
		return values.get(key)
