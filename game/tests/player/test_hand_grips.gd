# The Soldier's hands on every weapon (Deadnight #460, docs/design/animation.md, "Grips"): in every
# pose the player uses, no part of a hand goes more than 2 mm into the weapon it holds, and every
# part the weapon's grip says touches (the trigger finger, the fingers round the grip, the thumb,
# the palm; the left hand on the fore-end) is within 5 mm of it. Measured on the skin as drawn
# (`HandContact`), at the end of the skeleton's update, in the real player with the real clips.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## Every weapon the player holds, by catalogue id (and `Melee` for the class hold, the bat).
const WEAPONS: Array[StringName] = [
	&"pistol", &"flare_gun", &"smg", &"rifle", &"shotgun", &"crowbar", &"Melee"
]
## Every model in `assets/weapons/` has a grip (the grenade's is for the shell in the hand).
const MODELS: Array[String] = [
	"baseball_bat",
	"crowbar",
	"double_shotgun",
	"fire_axe",
	"flare_gun",
	"grenade",
	"hammer",
	"lever_rifle",
	"revolver",
	"tommy_gun",
	# The heavy batch (#796).
	"m249",
	"fifty_cal",
	"pump_870",
]
## The heavy batch's guns (#796): a trigger finger each.
const HEAVY: Array[String] = ["m249", "fifty_cal", "pump_870"]

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _contact: HandContact
## The measurement asked for and taken at the next `skeleton_updated`.
var _want := false
var _measured := {}


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_rig = _player.camera_rig
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_player.set_physics_process(false)
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_on_updated)
	_player.teleport(START)
	await _ticks(20)
	_contact = HandContact.new(_skeleton)


## Steps the player, the camera and the animation by hand, `count` fixed ticks back to back, then
## one frame so the skeleton draws the last one (the grip modifiers keep no clock, so the pose in
## between is never needed). A wait for a physics frame per tick tied the test to the wall clock
## (60 ticks a second): 38 s on CI, which pushed the suite past its time limit.
func _ticks(count: int) -> void:
	for i in count:
		_player.tick(_player.sample_command())
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	await get_tree().process_frame


## The held item now (the hammer while repairing, the grenade while in the hand, else the weapon).
func _held() -> Node3D:
	if _animation.hammer().visible:
		return _animation.hammer()
	var grenade := _animation.weapon_mount().get_node("Grenade") as Node3D
	if grenade.visible:
		return grenade
	return _animation.weapon()


func _on_updated() -> void:
	if not _want:
		return
	_want = false
	_contact.set_weapon(_held())
	_measured = {
		"R": _contact.measure("R"),
		"L": _contact.measure("L"),
		"right_weight": _animation.fingers().right_weight,
		"left_weight": _animation.fingers().left_weight,
	}


func _measure() -> Dictionary:
	_want = true
	await _ticks(1)
	return _measured


## Checks one pose: both hands against the grip of what they hold. Returns the failures.
func _check(tag: String, grip: HandGrip) -> Array[String]:
	var m := await _measure()
	var fails: Array[String] = []
	if grip == null:
		return ["%s: no grip" % tag]
	if m.right_weight < 0.99:
		fails.append("%s: right hand not on its grip (%.2f)" % [tag, m.right_weight])
	fails.append_array(_hand(tag + " R", m.R, grip.right_contacts))
	if grip.has_left and m.left_weight >= 0.99:
		fails.append_array(_hand(tag + " L", m.L, grip.left_contacts))
	return fails


func _hand(tag: String, parts: Dictionary, contacts: PackedStringArray) -> Array[String]:
	return HandContact.failures(tag, parts, contacts)


func _release() -> void:
	for action in ["aim", "move_forward", "fire", "sprint"]:
		_runner.simulate_action_release(action)


func test_every_model_has_a_grip_at_its_hold_size() -> void:
	for model in MODELS:
		var grip := HandGrip.for_name(model)
		assert_object(grip).override_failure_message("%s: no grip" % model).is_not_null()
		assert_int(grip.right.size()).override_failure_message("%s: no fingers" % model).is_greater(
			6
		)
	for id in WeaponCatalog.IDS:
		var hold := WeaponHoldMap.hold_for(id)
		var grip := HandGrip.for_scene(hold.scene)
		(
			assert_float(grip.model_scale)
			. override_failure_message("%s: grip solved at another size" % id)
			. is_equal_approx(hold.model_scale, 0.001)
		)
	# A gun's trigger finger is on its trigger or along its frame, never left in the air.
	for model in ["revolver", "flare_gun", "tommy_gun", "lever_rifle", "double_shotgun"] + HEAVY:
		assert_str(HandGrip.for_name(model).trigger_finger).is_not_empty()


func test_the_hands_are_measured_on_the_near_meshes_only() -> void:
	# The far level of detail (#139) is hidden by its range, not by `visible`: measured with it, a
	# fingertip 6.9 mm off the rifle passed on the decimated hand's longer tip (#716).
	var far := SoldierLook.far_meshes(_player)
	assert_bool(far.is_empty()).override_failure_message("no far meshes found").is_false()
	var measured := _contact.meshes()
	assert_bool(measured.is_empty()).is_false()
	for mi: MeshInstance3D in measured:
		(
			assert_bool(mi in far.values())
			. override_failure_message("%s is the far level of detail" % mi.name)
			. is_false()
		)
		assert_float(mi.visibility_range_begin).is_equal(0.0)


func test_hands_hold_every_weapon_in_every_pose() -> void:
	var fails: Array[String] = []
	for id in WEAPONS:
		_release()
		_animation.equip(id)
		await _ticks(40)
		var grip := _animation.weapon_grip()
		var melee := _animation.weapon_class == &"Melee"
		fails.append_array(await _check("%s equipped" % id, grip))
		await _ticks(20)
		fails.append_array(await _check("%s idle" % id, grip))
		_runner.simulate_action_press("move_forward")
		await _ticks(30)
		fails.append_array(await _check("%s run" % id, grip))
		# The sprint carry (#527): the clip holds the weapon, both hands on its grip. It plays only
		# on the floor, so the player starts on it: the ticks above never step the physics, and
		# until one physics frame has passed the room's floor is not there to stand on.
		_player.teleport(START)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_runner.simulate_action_press("sprint")
		await _ticks(40)
		for i in 3:
			var tag := "%s sprint %d" % [id, i]
			fails.append_array(await _check(tag, grip))
			if _animation.sprint_carry() < 0.99:
				fails.append("%s: not carrying (%.2f)" % [tag, _animation.sprint_carry()])
			if grip.has_left and _measured.left_weight < 0.99:
				fails.append("%s: left hand not on its grip (%.2f)" % [tag, _measured.left_weight])
			await _ticks(9)
		_release()
		await _ticks(30)
		if melee:
			# The swing's wind-up, the blow and the follow-through (frames at 24 fps, ticks at 60).
			_animation.play_action(&"Swing")
			var at := 0
			for frame in [6, 10, 12, 18]:
				var tick := roundi(frame * 60.0 / 24.0)
				await _ticks(tick - at)
				at = tick + 1
				fails.append_array(await _check("%s swing %d" % [id, frame], grip))
			continue
		_runner.simulate_action_press("aim")
		await _ticks(40)
		fails.append_array(await _check("%s aim" % id, grip))
		# Looking up and down: the chest leans and the arms follow, the hands stay on.
		for pitch: float in [-0.6, 0.6]:
			_rig.pitch = pitch
			await _ticks(30)
			fails.append_array(await _check("%s aim pitched %.1f" % [id, pitch], grip))
		_rig.pitch = 0.0
		await _ticks(30)
		_animation.play_action(&"Fire")
		await _ticks(2)
		fails.append_array(await _check("%s fire" % id, grip))
		_release()
		await _ticks(30)
		# The reload's motion (#683): the right hand keeps its grip while the weapon turns and the
		# left hand goes for ammunition (its fingers leave the fore-end, so it is not measured).
		var seconds: float = WeaponCatalog.get_def(id).reload_time
		_animation.reload(seconds)
		var done := 0
		for share: float in [0.25, 0.6]:
			var tick := roundi(share * seconds / TICK)
			await _ticks(tick - done)
			done = tick + 1
			fails.append_array(await _check("%s reload %.2f" % [id, share], grip))
		await _ticks(roundi(seconds / TICK) - done + 30)
	assert_array(fails).is_empty()


func test_the_repair_hammer_and_the_grenade_are_held_by_their_grips() -> void:
	var fails: Array[String] = []
	_animation.board_repaired(1.0)
	await _ticks(20)
	fails.append_array(await _check("hammer repair", HandGrip.for_name("hammer")))
	_animation.stop_repair()
	await _ticks(40)
	_animation.grenade(&"cook")
	await _ticks(40)
	fails.append_array(await _check("grenade cooked", HandGrip.for_name("grenade")))
	assert_array(fails).is_empty()
