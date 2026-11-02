# The Soldier's downed and revive clips (#504): Downed_Idle, Revive_Kneel and the optional
# Downed_Crawl are in the library from their own files, key no finger, and the AnimationTree reaches
# each through an eased weight (never a flip). Stepped by hand, a fixed tick at a time.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const FINGERS := ["Pinky", "Middle", "Index", "Thumb"]

var _runner: GdUnitSceneRunner
var _player: Player
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _clips: AnimationPlayer
var _presses := 0


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.camera_rig.set_process(false)
	_player.set_physics_process(false)
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_clips = _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_presses = 0
	_animation.clip_event.connect(
		func(clip: StringName, event: StringName) -> void:
			if clip == DownedPose.REVIVE_CLIP and event == &"press":
				_presses += 1
	)


func _step(ticks: int) -> void:
	for _i in ticks:
		_animation._process(TICK)
		_animation.advance(TICK)


## A bone's height above the player's feet in the world, composed from the local poses: stepping
## the tree by hand never reaches the skeleton's deferred global-pose update.
func _height(bone_name: String) -> float:
	var bone := _skeleton.find_bone(bone_name)
	var pose := Transform3D()
	while bone >= 0:
		pose = _skeleton.get_bone_pose(bone) * pose
		bone = _skeleton.get_bone_parent(bone)
	return (_skeleton.global_transform * pose).origin.y - _player.global_position.y


func _clip_names() -> Array[StringName]:
	var names: Array[StringName] = [DownedPose.DOWNED_CLIP, DownedPose.REVIVE_CLIP]
	if _animation.has_crawl():
		names.append(DownedPose.CRAWL_CLIP)
	return names


func test_the_clips_are_in_the_library_loop_and_key_no_finger() -> void:
	assert_bool(_animation.has_crawl()).is_true()  # the optional file is in this build
	var lengths := {&"Downed_Idle": 2.0, &"Revive_Kneel": 1.0, &"Downed_Crawl": 32.0 / 24.0}
	for clip in _clip_names():
		assert_bool(_clips.has_animation(clip)).override_failure_message(String(clip)).is_true()
		var animation := _clips.get_animation(clip)
		assert_int(animation.loop_mode).is_equal(Animation.LOOP_LINEAR)
		assert_float(animation.length).is_equal_approx(lengths[clip], 0.02)
		var bones := {}
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			var bone := String(path).get_slice(":", 1)
			# Every track finds its bone on the player's own skeleton (the shared rig and path).
			assert_object(_clips.get_node(_clips.root_node).get_node_or_null(path)).is_not_null()
			assert_int(_skeleton.find_bone(bone)).is_greater_equal(0)
			bones[bone] = true
			for finger: String in FINGERS:
				(
					assert_bool(bone.begins_with(finger))
					. override_failure_message(
						"%s keys the finger %s: the hands belong to HandGripPose" % [clip, bone]
					)
					. is_false()
				)
		# Full body: the legs and the spine are theirs.
		for bone: String in ["Body", "UpperLeg.L", "LowerLeg.R", "Foot.L", "Abdomen", "Head"]:
			assert_bool(bones.has(bone)).override_failure_message("%s %s" % [clip, bone]).is_true()


func test_the_tree_reaches_every_clip() -> void:
	var root := _animation.tree_root as AnimationNodeBlendTree
	var nodes := {&"downed_clip": &"Downed_Idle", &"revive_clip": &"Revive_Kneel"}
	if _animation.has_crawl():
		nodes[&"crawl_clip"] = &"Downed_Crawl"
	for node: StringName in nodes:
		assert_bool(root.has_node(node)).is_true()
		assert_str(String((root.get_node(node) as AnimationNodeAnimation).animation)).is_equal(
			String(nodes[node])
		)
	# Wired to the output: the full-body OneShot takes the downed layer, which takes the kneel.
	assert_bool(root.has_node(&"downed")).is_true()
	assert_bool(root.has_node(&"kneel")).is_true()


func test_going_down_eases_the_body_to_the_ground_and_back_up() -> void:
	_step(30)
	var standing := _height("Head")
	_animation.set_downed(true)
	_step(1)
	# One tick in, the weight has only started: an eased weight, not a flip on the bool.
	assert_float(_animation.downed_weight()).is_between(0.01, 0.2)
	_step(90)
	assert_float(_animation.downed_weight()).is_equal(1.0)
	var down := _height("Head")
	assert_float(down).is_less(standing * 0.6)
	assert_float(_height("Body")).is_less(standing * 0.3)
	assert_bool(_animation.weapon().visible).is_false()
	assert_float(_animation.hands().influence).is_less(0.01)
	_animation.set_downed(false)
	_step(90)
	assert_float(_animation.downed_weight()).is_equal(0.0)
	assert_float(_height("Head")).is_equal_approx(standing, standing * 0.1)  # Idle breathes
	assert_bool(_animation.weapon().visible).is_true()


func test_the_downed_idle_breathes_and_looks_around() -> void:
	_animation.set_downed(true)
	_step(90)
	var head := _skeleton.find_bone("Head")
	var turns: Array[Quaternion] = []
	for _i in 24:  # one 2 s loop, every 5 ticks
		turns.append(_skeleton.get_bone_pose_rotation(head))
		_step(5)
	var widest := 0.0
	for a in turns:
		for b in turns:
			widest = maxf(widest, a.angle_to(b))
	assert_float(widest).is_greater(deg_to_rad(15.0))  # the head looks left, then right


func test_a_revive_kneels_and_presses_twice_a_second_while_held() -> void:
	_step(30)
	var standing := _height("Head")
	_animation.set_reviving(true)
	_step(1)
	assert_float(_animation.kneel_weight()).is_between(0.01, 0.3)
	_step(59)
	assert_float(_animation.kneel_weight()).is_equal(1.0)
	var kneeling := _height("Head")
	assert_float(kneeling).is_less(standing * 0.8)
	assert_float(kneeling).is_greater(standing * 0.4)
	assert_bool(_animation.weapon().visible).is_false()
	_presses = 0
	_step(120)
	assert_int(_presses).is_equal(4)
	_animation.set_reviving(false)
	_step(60)
	assert_float(_animation.kneel_weight()).is_equal(0.0)
	assert_bool(_animation.weapon().visible).is_true()


func test_going_down_drops_a_revive_and_a_downed_player_does_not_kneel() -> void:
	_animation.set_reviving(true)
	_animation.set_downed(true)
	assert_bool(_animation.is_reviving()).is_false()
	_animation.set_reviving(true)
	assert_bool(_animation.is_reviving()).is_false()
	_step(90)
	assert_float(_animation.kneel_weight()).is_equal(0.0)
	assert_float(_animation.downed_weight()).is_equal(1.0)


func test_moving_while_down_crawls_at_the_clips_pace() -> void:
	if not _animation.has_crawl():
		return
	_animation.set_downed(true)
	_step(90)
	assert_float(_animation.crawl_weight()).is_equal(0.0)
	_player.state.velocity = Vector3(0.0, 0.0, -0.45)
	_step(60)
	assert_float(_animation.crawl_weight()).is_greater(0.99)
	assert_float(float(_animation.get(DownedPose.CRAWL_RATE_PARAMETER))).is_equal_approx(1.0, 0.05)
	# The heels move: the right foot is not where it was half a loop ago.
	var foot := _skeleton.find_bone("Foot.R")
	var before := _skeleton.get_bone_pose_position(foot)
	_step(40)
	assert_float(before.distance_to(_skeleton.get_bone_pose_position(foot))).is_greater(0.05)
	_player.state.velocity = Vector3.ZERO
	_step(60)
	assert_float(_animation.crawl_weight()).is_less(0.01)
