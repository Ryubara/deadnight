# The shoulder camera on a body that goes down and is raised (#532): while the player is down the
# pivot sinks toward the body and the view tips down, so the whole body is in the picture; both
# ease in on the down and out on the revive, and the player's own pitch is never touched. Driven
# through a real night: the rules' blow brings the player down, a teammate holding use raises them.
# Stepped by hand, a fixed tick at a time: no wall time.
extends GdUnitTestSuite

const TICK := 1.0 / 60.0
const MATE := 2
## The share of the picture's width and height kept clear at its edges: the HUD and the vignette
## live there, and a body touching the edge is cut.
const EDGE := 0.04
const FINGERS := ["Pinky", "Middle", "Index", "Thumb"]

var _night: Night
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _tuning: PlayerTuning


func before_test() -> void:
	var rules := RulesFixture.tuning()
	rules.rounds.first_spawn_delay = 600.0
	_night = await NightFixture.start(self, Night.Mode.MANUAL, rules)
	_player = _night.player()
	_player.capture_mouse = false
	_player.local_input = false
	_night.server.apply({"type": NightServer.JOIN, "player_id": MATE, "local": false})
	_night.server.rules.apply(RulesAction.skip_break())
	_rig = _player.camera_rig
	_rig.set_process(false)
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	# A private copy of the numbers, so a test may change them without touching other suites.
	_tuning = _player.tuning.duplicate() as PlayerTuning
	_player.tuning = _tuning
	_rig.setup(_player, _tuning)
	_night.server.body_of(MATE).teleport(_player.global_position + Vector3(-4.0, 0.0, 3.0))
	_rig.pitch = -0.12
	_tick(30)


func after_test() -> void:
	_night.queue_free()


## `count` ticks of the night, each followed by the animation and the camera, as a frame would.
func _tick(count: int, hold_use := false) -> void:
	for _i in count:
		var mate := NightCommand.new()
		mate.use_held = hold_use
		_night.server.submit(MATE, mate)
		var command := NightCommand.new()
		command.motion.yaw = _rig.yaw
		command.motion.pitch = _rig.pitch
		_night.link.send(command.to_dict())
		_night.tick()
		_animation._process(TICK)
		_animation.advance(TICK)
		_rig.step(TICK, 1.0)


func _go_down() -> void:
	_night.state.apply_events(_night.server.rules.apply(RulesAction.blow(1, 500.0)))


func _raise() -> void:
	_night.server.body_of(MATE).teleport(
		_night.server.body_of(1).global_position + Vector3(-0.9, 0.0, 0.0)
	)
	_tick(2)
	_tick(roundi((_night.server.rules.tuning.health.revive_seconds + 0.5) / TICK), true)


## Where every bone of the skeleton is in the world, composed from the local poses: stepping the
## tree by hand never reaches the skeleton's deferred global-pose update. Fingers are left out
## (the downed clips key none; they sit with the hands).
func _bone_points() -> Dictionary:
	var points := {}
	for bone in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(bone)
		if FINGERS.any(func(finger: String) -> bool: return bone_name.begins_with(finger)):
			continue
		var pose := Transform3D()
		var up := bone
		while up >= 0:
			pose = _skeleton.get_bone_pose(up) * pose
			up = _skeleton.get_bone_parent(up)
		points[bone_name] = (_skeleton.global_transform * pose).origin
	return points


## The bones the player's camera does not show: behind the lens or outside the picture's frame.
func _bones_out_of_view() -> Array[String]:
	var camera := _rig.camera()
	var size := camera.get_viewport().get_visible_rect().size
	var frame := Rect2(size * EDGE, size * (1.0 - 2.0 * EDGE))
	var missing: Array[String] = []
	var points := _bone_points()
	for bone_name: String in points:
		var point: Vector3 = points[bone_name]
		if (
			camera.is_position_behind(point)
			or not frame.has_point(camera.unproject_position(point))
		):
			missing.append(bone_name)
	return missing


func test_going_down_eases_the_pivot_and_the_view_to_the_body() -> void:
	var standing_pitch := _rig.view_pitch()
	assert_float(_rig.downed_amount()).is_equal(0.0)
	assert_float(_rig.view_pitch()).is_equal_approx(_rig.pitch, 0.0001)
	_go_down()
	_tick(1)
	assert_bool(_rig.downed).is_true()
	# One tick in the weight has only started: an ease, not a flip on the flag.
	assert_float(_rig.downed_amount()).is_between(0.001, 0.1)
	var last := _rig.downed_amount()
	var last_height := _rig.pivot_position().y
	for _i in 120:
		_tick(1)
		assert_float(_rig.downed_amount()).is_greater_equal(last)
		assert_float(_rig.pivot_position().y).is_less_equal(last_height + 0.0001)
		last = _rig.downed_amount()
		last_height = _rig.pivot_position().y
	assert_float(_rig.downed_amount()).is_greater(0.99)
	var feet := _player.global_position.y
	assert_float(_rig.pivot_position().y - feet).is_equal_approx(_tuning.downed_pivot_height, 0.02)
	var tip := deg_to_rad(_tuning.downed_pitch_degrees)
	assert_float(_rig.view_pitch()).is_equal_approx(standing_pitch - tip, 0.01)
	assert_float(_rig.camera().global_rotation.x).is_equal_approx(standing_pitch - tip, 0.01)
	# The player's own look is theirs: the tip is laid over it, never written into it.
	assert_float(_rig.pitch).is_equal(-0.12)


func test_the_whole_downed_body_is_in_the_players_view_where_the_standing_camera_cuts_it() -> void:
	# The control: the camera as it was (no drop, no tip) leaves bones out of the picture.
	_tuning.downed_pivot_height = _tuning.pivot_height
	_tuning.downed_pitch_degrees = 0.0
	_go_down()
	_tick(150)
	var cut := _bones_out_of_view()
	assert_array(cut).override_failure_message("the old camera shows the whole body").is_not_empty()
	# The camera as shipped frames every bone, here and at a few looks of the player's own.
	var shipped := load("res://gameplay/player/player_tuning_default.tres") as PlayerTuning
	_tuning.downed_pivot_height = shipped.downed_pivot_height
	_tuning.downed_pitch_degrees = shipped.downed_pitch_degrees
	_tick(150)
	for look: float in [-0.12, 0.0, -0.3, -0.5]:
		_rig.pitch = look
		_tick(120)
		(
			assert_array(_bones_out_of_view())
			. override_failure_message("looking %.2f rad" % look)
			. is_empty()
		)
	assert_float(_rig.lens_distance()).is_greater(_tuning.hide_body_distance)


func test_getting_up_eases_the_view_back_to_the_standing_one() -> void:
	var standing_height := _rig.pivot_position().y
	var standing_pitch := _rig.camera().global_rotation.x
	_go_down()
	_tick(150)
	assert_float(_rig.downed_amount()).is_greater(0.99)
	_raise()
	assert_bool(_night.server.rules.players[1].downed).is_false()
	assert_bool(_animation.is_downed()).is_false()
	_tick(2)
	assert_bool(_rig.downed).is_false()
	# Back up in an ease: not already home a tick after the revive, and home after a few seconds.
	_tick(150)
	assert_float(_rig.downed_amount()).is_less(0.001)
	assert_float(_rig.pivot_position().y).is_equal_approx(standing_height, 0.02)
	assert_float(_rig.camera().global_rotation.x).is_equal_approx(standing_pitch, 0.01)
	assert_float(_rig.view_pitch()).is_equal_approx(_rig.pitch, 0.0001)


func test_the_view_comes_up_after_the_revive_without_a_jump() -> void:
	_go_down()
	_tick(150)
	_raise()
	var heights: Array[float] = [_rig.pivot_position().y]
	for _i in 90:
		_tick(1)
		heights.append(_rig.pivot_position().y)
	# Never down again, and no frame jumps by more than a few centimetres.
	for i in range(1, heights.size()):
		assert_float(heights[i]).is_greater_equal(heights[i - 1] - 0.0001)
		assert_float(heights[i] - heights[i - 1]).is_less(0.06)
	assert_float(heights[0]).is_less(heights[-1])


func test_a_spawn_while_down_starts_at_the_downed_height() -> void:
	_go_down()
	_tick(150)
	var at := _player.global_position + Vector3(2.0, 0.0, 0.0)
	_rig.snap_to(at)
	assert_float(_rig.downed_amount()).is_greater(0.99)
	assert_float(_rig.pivot_position().y - at.y).is_equal_approx(_tuning.downed_pivot_height, 0.05)
