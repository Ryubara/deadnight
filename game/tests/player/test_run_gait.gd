# The Run clip's planted-foot speed (#75): `PlayerTuning.run_clip_speed` is the ground speed at
# which the clip's feet stay put, so it is measured off the clip, not estimated, and the real
# animation tree is checked for sliding at the paces the player runs at. A planted foot is one
# within `STANCE_BAND` metres of its lowest point; its speed is the ground it sweeps over the
# frames it stays there. Stepped by hand, a fixed tick at a time (docs/research/run-clip-speed.md).
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const SOLDIER := "res://assets/characters/soldier_parts/soldier_parts.glb"
const TICK := 1.0 / 60.0
## How high above its own lowest point a foot may be and still count as planted (metres, at the
## model's scale in the game).
const STANCE_BAND := 0.05
## The shortest stance worth measuring (frames).
const MIN_STANCE := 3
const FEET: Array[String] = ["Foot.L", "Foot.R"]
## How far the tuning's value may sit from the measured one, and how far the feet may skate in the
## real tree (the share the planted foot's speed is off the ground's).
const CLIP_TOLERANCE := 0.03
const SLIDE_TOLERANCE := 0.06

var _tuning: PlayerTuning


func before_test() -> void:
	_tuning = load("res://gameplay/player/player_tuning_default.tres")


## The speed of the planted foot in a track of its positions, one a tick, and the direction it
## moves in (horizontal, unit): the mean over the stretches in which it stays planted.
static func stance_of(track: Array[Vector3]) -> Dictionary:
	var low := INF
	for at in track:
		low = minf(low, at.y)
	var speeds: Array[float] = []
	var sum := Vector3.ZERO
	var start := -1
	for i in track.size() + 1:
		var planted := i < track.size() and track[i].y <= low + STANCE_BAND
		if planted and start < 0:
			start = i
		elif not planted and start >= 0:
			if i - start >= MIN_STANCE:
				var swept := track[i - 1] - track[start]
				swept.y = 0.0
				speeds.append(swept.length() / ((i - 1 - start) * TICK))
				sum += swept
			start = -1
	var total := 0.0
	for speed in speeds:
		total += speed
	return {
		"speed": total / speeds.size() if not speeds.is_empty() else 0.0,
		"direction": sum.normalized(),
		"stances": speeds.size(),
	}


## The skeleton pose of `bone_name` in the world. A skeleton stepped by hand has not refreshed its
## global poses, so the pose is composed from the bone's own pose and its parent's.
func _bone_position(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	var local := Transform3D(
		Basis(skeleton.get_bone_pose_rotation(bone)), skeleton.get_bone_pose_position(bone)
	)
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
	return (skeleton.global_transform * parent * local).origin


## The mean planted-foot speed of both feet over `tracks` (foot name to positions), and the
## direction they sweep.
func _both_feet(tracks: Dictionary, label: String) -> Dictionary:
	var speed := 0.0
	var direction := Vector3.ZERO
	for foot in FEET:
		var stance := stance_of(tracks[foot])
		assert_int(stance["stances"]).override_failure_message("%s %s" % [label, foot]).is_greater(
			0
		)
		speed += stance["speed"] / FEET.size()
		direction += stance["direction"]
	return {"speed": speed, "direction": direction.normalized()}


func _empty_tracks() -> Dictionary:
	var tracks := {}
	for foot in FEET:
		var empty: Array[Vector3] = []
		tracks[foot] = empty
	return tracks


## The planted-foot speed of a clip played alone on the Soldier at the game's scale and facing, in
## metres a second, the direction the feet sweep and the clip's length.
func _clip_stance(clip: StringName) -> Dictionary:
	var model := (load(SOLDIER) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * _tuning.model_scale
	model.rotation.y = PI
	add_child(model)
	var animation := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	assert_bool(animation.has_animation(clip)).override_failure_message(clip).is_true()
	animation.assigned_animation = clip
	var length := animation.get_animation(clip).length
	var tracks := _empty_tracks()
	for i in roundi(length / TICK):
		animation.seek(i * TICK, true)
		for foot in FEET:
			tracks[foot].append(_bone_position(skeleton, foot))
	var stance := _both_feet(tracks, String(clip))
	model.free()
	stance["seconds"] = length
	return stance


func test_the_run_clip_speed_is_what_the_clip_measures() -> void:
	var run := _clip_stance(&"Run")
	print("Run: planted foot %.3f m/s at scale %s" % [run["speed"], _tuning.model_scale])
	(
		assert_float(_tuning.run_clip_speed / run["speed"])
		. override_failure_message(
			(
				"run_clip_speed is %.2f; the Run clip's planted foot moves at %.3f m/s"
				% [_tuning.run_clip_speed, run["speed"]]
			)
		)
		. is_between(1.0 - CLIP_TOLERANCE, 1.0 + CLIP_TOLERANCE)
	)


func test_the_planted_foot_sweeps_backward() -> void:
	# The model faces -z in the game, so a planted foot moves toward +z.
	for clip: StringName in [&"Run", &"Run_Gun"]:
		var stance := _clip_stance(clip)
		assert_float(stance["direction"].dot(Vector3.BACK)).is_greater(0.95)


func test_the_gun_run_is_measured_too() -> void:
	# `Run_Gun` is unused (the Rifle and Shotgun clips hold the gun over `Run`), but it is the
	# kit's other run: its own planted speed is on record in docs/research/run-clip-speed.md.
	var run := _clip_stance(&"Run")
	var gun := _clip_stance(&"Run_Gun")
	print("Run_Gun: planted foot %.3f m/s" % gun["speed"])
	assert_float(gun["speed"]).is_greater(0.5 * run["speed"])
	assert_float(gun["seconds"]).is_equal_approx(run["seconds"], 0.01)


func test_the_footstep_stride_is_half_the_clips_cycle() -> void:
	var run := _clip_stance(&"Run")
	var stride: float = run["speed"] * run["seconds"] / 2.0
	assert_float(_tuning.step_distance / stride).is_between(0.95, 1.05)


## The planted foot's speed in the real animation tree while the player moves straight ahead at
## `speed` (by state alone: physics is off), and its direction.
func _tree_stance(speed: float) -> Dictionary:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	player.camera_rig.set_process(false)
	player.set_physics_process(false)
	var animation := player.get_node("AnimationTree") as PlayerAnimation
	animation.set_process(false)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var playback := animation.get(&"parameters/body/playback") as AnimationNodeStateMachinePlayback
	playback.start(PlayerAnimation.STATE_LOCOMOTION)
	player.state.facing = 0.0
	player.state.on_floor = true
	player.state.velocity = Vector3(0.0, 0.0, -speed)
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var tracks := _empty_tracks()
	for step in 60 + 180:
		animation._process(TICK)
		animation.advance(TICK)
		if step >= 60:
			for foot in FEET:
				tracks[foot].append(_bone_position(skeleton, foot))
	return _both_feet(tracks, "pace %s" % speed)


func test_the_feet_stay_planted_at_the_run_and_the_sprint() -> void:
	for pace: float in [_tuning.run_speed, _tuning.sprint_speed]:
		var stance := _tree_stance(pace)
		print("pace %.2f m/s: planted foot %.2f m/s" % [pace, stance["speed"]])
		(
			assert_float(stance["speed"] / pace)
			. override_failure_message(
				"at %.2f m/s the planted foot moves at %.2f m/s" % [pace, stance["speed"]]
			)
			. is_between(1.0 - SLIDE_TOLERANCE, 1.0 + SLIDE_TOLERANCE)
		)
		assert_float(stance["direction"].dot(Vector3.BACK)).is_greater(0.95)
