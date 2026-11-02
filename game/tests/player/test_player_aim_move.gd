# Moving while aiming (#74): the Soldier keeps facing the camera, so moving sideways or back
# plays a strafe or a backpedal, blended by the direction of travel, at a rate that keeps the
# planted foot on the ground. Stepped by hand, a fixed tick at a time.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
## A planted foot is one within this share of its own lift from its lowest point (the measure of
## docs/research/zombie-gait.md).
const PLANTED := 0.2
const FEET: Array[String] = ["Foot.L", "Foot.R"]

var _runner: GdUnitSceneRunner
var _player: Player
var _animation: PlayerAnimation


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.camera_rig.set_process(false)
	_player.set_physics_process(false)
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# The body enters locomotion on the player's first landing; physics is off here, so start it.
	var playback := _animation.get(&"parameters/body/playback") as AnimationNodeStateMachinePlayback
	playback.start(PlayerAnimation.STATE_LOCOMOTION)


func _step(ticks: int) -> void:
	for _i in ticks:
		# The aim weight is the camera's: the legs and the hands read it.
		_player.camera_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)


## Moves the player (by state alone: physics is off) at `speed` toward `local` (x right, y ahead)
## while aiming, with the body facing `facing`.
func _move(local: Vector2, speed: float, facing := 0.0) -> void:
	var ahead := Vector3(-sin(facing), 0.0, -cos(facing))
	var right := Vector3(cos(facing), 0.0, -sin(facing))
	_player.state.facing = facing
	_player.state.aiming = true
	_player.camera_rig.aiming = true
	_player.state.on_floor = true
	_player.state.velocity = (right * local.x + ahead * local.y).normalized() * speed


func test_the_clips_are_in_the_library_and_loop_in_step() -> void:
	var player := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip: StringName in PlayerAnimation.AIM_MOVES:
		assert_bool(player.has_animation(clip)).override_failure_message(clip).is_true()
		var animation := player.get_animation(clip)
		assert_int(animation.loop_mode).is_equal(Animation.LOOP_LINEAR)
		# One length for all four: the 2D blend keeps them in step.
		assert_float(animation.length).is_equal_approx(17.0 / 24.0, 0.01)


func test_the_blend_follows_the_direction_of_travel() -> void:
	var speed := _player.tuning.aim_speed
	for facing in [0.0, 1.1, -2.5]:
		var ahead := Vector3(-sin(facing), 0.0, -cos(facing))
		var right := Vector3(cos(facing), 0.0, -sin(facing))
		for local: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var velocity := (right * local.x - ahead * local.y) * speed
			var gait := PlayerAnimation.aim_move_for(velocity, facing, speed)
			# Godot's Vector2.UP is (0, -1): ahead is -local.y in this loop.
			var expected := Vector2(local.x, -local.y)
			(
				assert_vector(gait["position"])
				. override_failure_message("facing %s toward %s" % [facing, local])
				. is_equal_approx(expected, Vector2(0.001, 0.001))
			)
			assert_float(gait["rate"]).is_equal_approx(1.0, 0.001)
	# Standing still is the Idle in the middle; a diagonal sits between two clips.
	var still := PlayerAnimation.aim_move_for(Vector3.ZERO, 0.0, speed)
	assert_vector(still["position"]).is_equal(Vector2.ZERO)
	var diagonal := PlayerAnimation.aim_move_for(Vector3(1.0, 0.0, -1.0) * speed, 0.0, speed)
	assert_float(diagonal["position"].x).is_equal_approx(diagonal["position"].y, 0.001)
	# Faster than the clips: played faster, within the limit.
	var fast := PlayerAnimation.aim_move_for(Vector3(0, 0, -2.0 * speed), 0.0, speed)
	assert_float(fast["rate"]).is_equal(PlayerAnimation.AIM_RATE_MAX)


func test_aiming_takes_the_aim_gait_and_letting_go_returns() -> void:
	_move(Vector2.RIGHT, _player.tuning.aim_speed)
	_step(60)
	assert_float(_animation.aim_weight()).is_equal_approx(1.0, 0.001)
	assert_vector(_animation.aim_move()).is_equal_approx(Vector2.RIGHT, Vector2(0.01, 0.01))
	assert_vector(_animation.get(PlayerAnimation.AIM_MOVE_PARAMETER)).is_equal_approx(
		Vector2.RIGHT, Vector2(0.01, 0.01)
	)
	_player.state.aiming = false
	_player.camera_rig.aiming = false
	_step(60)
	assert_float(_animation.aim_weight()).is_equal_approx(0.0, 0.001)


## Where a bone is in the world after the last advance. The skeleton refreshes its global poses on
## a deferred update, which stepping by hand never reaches, so the pose is composed from the
## bone's own (local) pose and its parent's (the feet hang from `Root`, which holds still).
func _bone_position(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	var local := Transform3D(
		Basis(skeleton.get_bone_pose_rotation(bone)), skeleton.get_bone_pose_position(bone)
	)
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
	return (skeleton.global_transform * parent * local).origin


## How the planted feet move in the body's frame while moving toward `local` at the aim speed:
## their mean direction (x right, y ahead) and median speed.
func _planted_motion(local: Vector2) -> Dictionary:
	var speed := _player.tuning.aim_speed
	_move(local, speed)
	_step(60)  # settle the blends
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var ahead := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	var tracks := {}
	for foot in FEET:
		tracks[foot] = []
	for _i in 180:
		_step(1)
		for foot in FEET:
			tracks[foot].append(_bone_position(skeleton, foot))
	var speeds: Array[float] = []
	var sum := Vector2.ZERO
	for foot in FEET:
		var points: Array = tracks[foot]
		var low := INF
		var high := -INF
		for at: Vector3 in points:
			low = minf(low, at.y)
			high = maxf(high, at.y)
		var limit := low + (high - low) * PLANTED
		for i in range(1, points.size()):
			var a: Vector3 = points[i - 1]
			var b: Vector3 = points[i]
			if a.y <= limit and b.y <= limit:
				var move := Vector2((b - a).dot(right), (b - a).dot(ahead)) / TICK
				speeds.append(move.length())
				sum += move
	speeds.sort()
	return {"direction": sum.normalized(), "speed": speeds[speeds.size() / 2]}


func test_the_planted_foot_sweeps_against_the_travel_at_its_speed() -> void:
	# The feet keep up with the ground: a planted foot moves back along the travel, in the body's
	# frame, as fast as the body moves (strafing and backpedalling included).
	var speed := _player.tuning.aim_speed
	for local: Vector2 in [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]:
		var motion := _planted_motion(local)
		print(
			(
				"aim move toward %s: planted foot %s at %.2f m/s"
				% [local, motion["direction"], motion["speed"]]
			)
		)
		(
			assert_float(motion["direction"].dot(-local))
			. override_failure_message(
				"toward %s the planted foot moves %s" % [local, motion["direction"]]
			)
			. is_greater(0.9)
		)
		(
			assert_float(motion["speed"] / speed)
			. override_failure_message(
				"toward %s the planted foot moves at %.2f m/s" % [local, motion["speed"]]
			)
			. is_between(0.8, 1.25)
		)
