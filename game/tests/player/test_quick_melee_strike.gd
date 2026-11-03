# The quick melee's blow on the Soldier (#411, docs/design/animation.md "Quick melee"): one clip per
# class that every weapon in the catalogue is struck with, checked against the weapon in the hand:
# it stays in the hand and shown, it travels a real way and lands forward of the body at the blow,
# it clears the head, it is over before the cooldown is, and the arms are back where they were.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## Every weapon the blow is made with, one of each kind the hold map knows.
const HELD: Array[StringName] = [&"pistol", &"rifle", &"shotgun", &"baseball_bat", &"fire_axe"]
## The weapon's origin travels at least this far (metres) between the wind-up and the blow.
const MIN_TRAVEL := 0.35
## At the blow the weapon is this far ahead of the neck at least (the Soldier faces -Z, so ahead is
## the negative of the body's own forward axis), and never nearer than this to the head.
const MIN_AHEAD := 0.15
const HEAD_CLEARANCE := 0.12
## The hand returns to within this of where it began once the clip is over.
const RETURN_TOLERANCE := 0.03

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _bones := {}


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.set_physics_process(false)
	_rig = _player.camera_rig
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	skeleton.skeleton_updated.connect(_record_bones.bind(skeleton))
	_player.teleport(START)
	await get_tree().physics_frame
	await _ticks(20)


func _record_bones(skeleton: Skeleton3D) -> void:
	for bone: String in ["Index1.R", "Neck", "Head", "Hips"]:
		var pose := skeleton.get_bone_global_pose(skeleton.find_bone(bone))
		_bones[bone] = skeleton.global_transform * pose.origin


func _ticks(count: int) -> void:
	for i in count:
		PlayerHandStep.tick(_player)
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	await get_tree().process_frame


## The weapon's own place now, in the player's frame (x right, y up, -z ahead of the body).
func _weapon_local() -> Vector3:
	return _player.to_local(_animation.weapon().global_position)


func _local(bone: String) -> Vector3:
	return _player.to_local(_bones[bone])


func test_every_class_has_its_clip_in_the_library_with_the_events() -> void:
	var player := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in QuickStrike.CLIPS:
		assert_bool(player.has_animation(clip)).override_failure_message("no %s" % clip).is_true()
		var events := _animation.clip_events(clip)
		for event in ["whoosh", "hit", "can_strike_again"]:
			(
				assert_bool(events.has(event))
				. override_failure_message("%s: no %s" % [clip, event])
				. is_true()
			)
		# Over before the quick melee's cooldown: a held button never queues a blow on a blow.
		assert_float(player.get_animation(clip).length).is_less(
			WeaponCatalog.quick_melee().fire_interval
		)


func test_each_weapon_is_struck_with_the_clip_of_its_class() -> void:
	for id in HELD:
		_animation.equip(id)
		await _ticks(40)
		var clip := StringName("Strike_%s" % WeaponHoldMap.class_of(id))
		assert_bool(_animation.strike()).is_true()
		assert_str(String(_animation.action_clip)).override_failure_message(id).is_equal(
			String(clip)
		)
		await _ticks(40)


func test_the_weapon_stays_in_the_hand_and_travels_to_a_blow_ahead_of_the_body() -> void:
	for id in HELD:
		_animation.equip(id)
		await _ticks(40)
		var rest := _weapon_local()
		_animation.strike()
		var travelled := 0.0
		var last := rest
		var windup := Vector3.ZERO
		var blow := Vector3.ZERO
		var hand_gap := 0.0
		var lowest_head_gap := INF
		var hit := _animation.clip_events(_animation.action_clip)["hit"] as float
		var wind_at := int(hit * 0.5 / 24.0 * 60.0)
		var hit_at := int(hit / 24.0 * 60.0)
		for tick in 40:
			await _ticks(1)
			var weapon := _animation.weapon()
			(
				assert_bool(weapon.visible)
				. override_failure_message("%s hidden at %d" % [id, tick])
				. is_true()
			)
			var here := _weapon_local()
			travelled += here.distance_to(last)
			last = here
			if tick == wind_at:
				windup = here
			if tick == hit_at:
				blow = here
			hand_gap = maxf(hand_gap, weapon.global_position.distance_to(_bones["Index1.R"]))
			lowest_head_gap = minf(
				lowest_head_gap, weapon.global_position.distance_to(_bones["Head"])
			)
		(
			assert_float(windup.distance_to(blow))
			. override_failure_message(
				"%s: wind-up to blow only %.2f m" % [id, windup.distance_to(blow)]
			)
			. is_greater(MIN_TRAVEL)
		)
		(
			assert_float(-(blow.z - _local("Neck").z))
			. override_failure_message("%s: the blow is not ahead of the body (%s)" % [id, blow])
			. is_greater(MIN_AHEAD)
		)
		(
			assert_float(lowest_head_gap)
			. override_failure_message(
				"%s: the weapon passes %.2f m from the head" % [id, lowest_head_gap]
			)
			. is_greater(HEAD_CLEARANCE)
		)
		# It is carried by the hand all along: the mount is on the hand bone, never loose.
		assert_float(hand_gap).override_failure_message("%s: left the hand" % id).is_less(0.6)
		# And the hand is home again: the shouldered pose eases back over a few ticks (it used to snap
		# back, an arm pop), so a gun is within a hand's breadth at the clip's end and home 10 ticks on.
		await _ticks(10)
		(
			assert_float(_weapon_local().distance_to(rest))
			. override_failure_message("%s: not back after the blow" % id)
			. is_less(RETURN_TOLERANCE + 0.05)
		)


func test_the_hit_event_comes_once_at_the_blow() -> void:
	for id in HELD:
		_animation.equip(id)
		await _ticks(40)
		var heard: Array[StringName] = []
		var listen := func(_clip: StringName, event: StringName) -> void: heard.append(event)
		_animation.clip_event.connect(listen)
		_animation.strike()
		await _ticks(45)
		_animation.clip_event.disconnect(listen)
		assert_array(heard.filter(func(e: StringName) -> bool: return e == &"hit")).has_size(1)
		assert_array(heard).contains([&"whoosh", &"hit", &"can_strike_again"])
