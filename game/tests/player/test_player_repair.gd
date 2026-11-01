# The Soldier's repair clip (#221): it plays on the rules' `board_repaired` events of its player,
# lands its `board_set` frame on each, keeps the pace of the repair interval and lets go once no
# board follows. Stepped by hand, a fixed tick at a time: nothing here waits on the clock.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
## Repair_Board's board_set frame (18 of 24, at 24 fps), in the clip's seconds.
const BOARD_SET := 18.0 / 24.0

var _runner: GdUnitSceneRunner
var _player: Player
var _animation: PlayerAnimation
var _events: Array[StringName] = []


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.camera_rig.set_process(false)
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_events.clear()
	_animation.clip_event.connect(
		func(clip: StringName, event: StringName) -> void:
			if clip == PlayerAnimation.REPAIR_CLIP:
				_events.append(event)
	)


func _step(ticks: int) -> void:
	for _i in ticks:
		_animation._process(TICK)
		_animation.advance(TICK)


func _count(event: StringName) -> int:
	return _events.count(event)


func test_the_clip_is_in_the_library_and_loops() -> void:
	var player := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_bool(player.has_animation(PlayerAnimation.REPAIR_CLIP)).is_true()
	var clip := player.get_animation(PlayerAnimation.REPAIR_CLIP)
	assert_int(clip.loop_mode).is_equal(Animation.LOOP_LINEAR)
	assert_float(clip.length).is_equal_approx(1.0, 0.01)
	assert_bool(_animation.is_repairing()).is_false()
	assert_float(_animation.repair_weight()).is_equal(0.0)


func test_a_repaired_board_starts_the_clip_on_its_board_set_frame() -> void:
	_animation.board_repaired(1.0)
	assert_bool(_animation.is_repairing()).is_true()
	assert_float(_animation.repair_time()).is_equal_approx(BOARD_SET, 0.001)
	assert_array(_events).contains_exactly_in_any_order([&"hammer", &"board_set"])
	assert_bool(_animation.weapon().visible).is_false()  # the hands are on the board
	_step(12)
	assert_float(_animation.repair_weight()).is_greater(0.9)


func test_a_held_repair_keeps_the_pace_of_the_rules() -> void:
	# The night repairs one board each `repair_interval` while use is held: the loop comes round
	# to board_set just as the next event arrives, so the seek is a no-op, not a jump.
	for board in 4:
		if board > 0:
			assert_float(_animation.repair_time()).is_equal_approx(BOARD_SET, 0.02)
		_animation.board_repaired(1.0)
		_step(60)
		assert_bool(_animation.is_repairing()).is_true()
	assert_int(_count(&"board_set")).is_equal(4)  # one per board: the rules' event, never the clip's
	assert_int(_count(&"hammer")).is_equal(8)  # two blows a board


func test_a_shorter_interval_plays_the_clip_faster() -> void:
	_animation.board_repaired(0.5)
	_step(30)
	assert_float(_animation.repair_time()).is_equal_approx(BOARD_SET, 0.02)
	_animation.board_repaired(0.5)
	assert_int(_count(&"board_set")).is_equal(2)


func test_the_clip_lets_go_when_no_board_follows() -> void:
	_animation.board_repaired(1.0)
	_step(80)  # past one interval: still waiting for the next board
	assert_bool(_animation.is_repairing()).is_true()
	_step(20)  # 1.5 intervals and none came
	assert_bool(_animation.is_repairing()).is_false()
	assert_bool(_animation.weapon().visible).is_true()
	_step(30)
	assert_float(_animation.repair_weight()).is_equal(0.0)


func test_stop_repair_lets_go_at_once() -> void:
	_animation.board_repaired(1.0)
	_animation.stop_repair()
	assert_bool(_animation.is_repairing()).is_false()
	assert_bool(_animation.weapon().visible).is_true()


func test_the_arms_follow_the_clip() -> void:
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip := player.get_animation(PlayerAnimation.REPAIR_CLIP)
	var track := clip.find_track(
		NodePath("%s:UpperArm.R" % player.get_node(player.root_node).get_path_to(skeleton)),
		Animation.TYPE_ROTATION_3D
	)
	_animation.board_repaired(1.0)
	for check in 3:
		_step(17)
		var want := clip.rotation_track_interpolate(track, _animation.repair_time())
		var have := skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperArm.R"))
		# Within a tick of the clip: the tree applies a seek on the next advance (3 degrees here).
		assert_float(rad_to_deg(have.angle_to(want))).is_less(5.0)
