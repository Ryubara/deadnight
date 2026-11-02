# The Soldier's repair clip (#221): it plays on the rules' `board_repaired` events of its player,
# lands its `board_set` frame on each, keeps the pace of the repair interval and lets go once no
# board follows. Stepped by hand, a fixed tick at a time: nothing here waits on the clock.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
## Repair_Board's board_set frame (18 of 24, at 24 fps), in the clip's seconds.
const BOARD_SET := 18.0 / 24.0
## Where a board's event puts the clip at the 1 s interval: the blow less the board's mend (#245).
const LEAD := BOARD_SET - Barricade.MEND_SECONDS

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


func test_a_repaired_board_lands_the_blow_as_the_board_knocks_home() -> void:
	# The board slides in for the barricade's mend time; the clip starts that long before its blow,
	# so the first board gets a lead-in (the fist rises and comes down) instead of a fist already down.
	_animation.board_repaired(1.0)
	assert_bool(_animation.is_repairing()).is_true()
	assert_float(_animation.repair_time()).is_equal_approx(LEAD, 0.001)
	assert_float(_animation.repair_lead(1.0)).is_equal_approx(LEAD, 0.001)
	assert_array(_events).is_empty()
	assert_bool(_animation.weapon().visible).is_false()  # the hands are on the board
	_step(roundi(Barricade.MEND_SECONDS * 60.0) - 2)
	assert_array(_events).is_empty()
	_step(4)
	assert_array(_events).contains_exactly_in_any_order([&"hammer", &"board_set"])
	_step(12)
	assert_float(_animation.repair_weight()).is_greater(0.9)


func test_a_held_repair_keeps_the_pace_of_the_rules() -> void:
	# The night repairs one board each `repair_interval` while use is held: the loop comes round
	# to the lead just as the next event arrives, so the seek is a no-op, not a jump.
	for board in 4:
		if board > 0:
			assert_float(_animation.repair_time()).is_equal_approx(LEAD, 0.02)
		_animation.board_repaired(1.0)
		_step(60)
		assert_bool(_animation.is_repairing()).is_true()
	assert_int(_count(&"board_set")).is_equal(4)  # one per board: the rules' event, never the clip's
	assert_int(_count(&"hammer")).is_equal(8)  # two blows a board


func test_a_shorter_interval_plays_the_clip_faster() -> void:
	_animation.board_repaired(0.5)
	_step(30)
	assert_float(_animation.repair_time()).is_equal_approx(_animation.repair_lead(0.5), 0.02)
	_animation.board_repaired(0.5)
	_step(30)
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


func test_the_hammer_is_in_the_hand_while_the_clip_holds_the_arms() -> void:
	assert_bool(_animation.hammer().visible).is_false()
	_animation.board_repaired(1.0)
	assert_bool(_animation.hammer().visible).is_true()
	assert_bool(_animation.weapon().visible).is_false()
	_step(100)  # 1.5 intervals and no board: the clip lets go
	assert_bool(_animation.hammer().visible).is_false()
	assert_bool(_animation.weapon().visible).is_true()
	_animation.board_repaired(1.0)
	_animation.stop_repair()
	assert_bool(_animation.hammer().visible).is_false()
	assert_bool(_animation.weapon().visible).is_true()


func test_an_equip_during_the_repair_keeps_the_hammer() -> void:
	_animation.board_repaired(1.0)
	_animation.equip(&"Melee")
	_step(60)  # the Equip clip's weapon_visible frame passes
	assert_bool(_animation.hammer().visible).is_true()
	assert_bool(_animation.weapon().visible).is_false()


func test_the_face_leads_the_blow() -> void:
	# The hammer rides the hand bone: over one loop its face swings down from the raise onto the
	# board, face first. Read from the bone (a BoneAttachment3D follows only on a processed frame).
	assert_object(_animation.hammer().get_parent()).is_same(_animation.weapon_mount())
	# The hold file's size on the hammer's own grip (solved from its sockets, keeping the tipped
	# melee grip's turn about the handle: docs/design/animation.md, "Grips").
	var grip := _animation.hammer().transform
	var hold := load(PlayerAnimation.HAMMER_HOLD) as WeaponHold
	assert_float(grip.basis.get_scale().x).is_equal_approx(hold.model_scale, 0.001)
	var solved := HandGrip.for_scene(hold.scene).hold
	assert_bool(grip.orthonormalized().is_equal_approx(solved)).is_true()
	var face_node := _animation.hammer().find_child(PlayerAnimation.HAMMER_FACE) as Node3D
	assert_object(face_node).is_not_null()
	# The face in the hammer scene's own space (the model carries it, not the code).
	var face_local := (
		_animation.hammer().global_transform.affine_inverse() * face_node.global_transform
	)
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var hand := skeleton.find_bone(PlayerAnimation.HAND_BONE)
	_animation.board_repaired(1.0)
	_step(45)
	_animation.board_repaired(1.0)  # the next board: the layer is at full weight from here
	var faces: Array[Vector3] = []
	var dirs: Array[Vector3] = []
	var grips: Array[Vector3] = []
	for _i in 60:
		_step(1)
		var held := skeleton.global_transform * skeleton.get_bone_global_pose(hand) * grip
		var face := held * face_local
		faces.append(face.origin)
		dirs.append(-face.basis.z.normalized())
		grips.append(held.origin)
	var low := 0
	var high := 0
	for i in faces.size():
		if faces[i].y < faces[low].y:
			low = i
		if faces[i].y > faces[high].y:
			high = i
	assert_float(faces[high].y - faces[low].y).is_greater(0.5)  # a real swing, not a twitch
	var blow := (faces[low] - faces[high]).normalized()
	assert_float(dirs[low].dot(blow)).is_greater(0.7)  # face first
	var forward := -_player.global_transform.basis.z
	assert_float(dirs[low].dot(forward)).is_greater(0.7)  # square to the board in front
	# The head out ahead of the fist.
	assert_float((faces[low] - grips[low]).dot(forward)).is_greater(0.15)


func test_the_arm_ik_is_off_while_the_clip_holds_the_arms() -> void:
	# At influence 0 the IK modifier still overrode the arms in the drawn pose (only a rendered
	# frame shows it), so the repair's swing and the hammer never showed: it is switched off.
	_step(30)
	assert_bool(_animation.hands().active).is_true()  # the rifle shouldered at rest
	_animation.board_repaired(1.0)
	_step(30)
	assert_float(_animation.hands().influence).is_equal(0.0)
	assert_bool(_animation.hands().active).is_false()
	_animation.stop_repair()
	_step(30)
	assert_bool(_animation.hands().active).is_true()
