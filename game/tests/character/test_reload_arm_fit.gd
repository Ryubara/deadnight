# The hand IK keeps the arms out of the body (#987): the real player on both looks, every gun's
# reload and every two-handed gun aimed and fired, each pose read as the skeleton draws it (after
# the IK) and measured by `ClipFit`: no forearm or hand deeper than its tolerance into the trunk,
# the legs, the head or the other arm. On main before #987 the left hand went 94-125 mm into the
# hip at the belt, the two hands 33-101 mm into each other, the right forearm 30-53 mm into the
# jacket firing. Stepped by hand with fixed ticks; docs/design/animation.md, "Reloading".
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## A reload's length here: every motion stretches over its gun's own time, so one length samples
## every key of every gun.
const RELOAD_SECONDS := 1.6
## Ticks between two kept poses (a key lasts at least nine).
const EVERY := 4
const ARMS: Array[String] = ["left arm", "right arm"]
## A shot's kick is at its peak a few ticks after it: the shots of the fire beat and the kept pose.
const SHOTS := 3
const SHOT_TICKS := 9
const KICK_TICKS := 6

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _latest: Array[Transform3D] = []
## Kept poses: [tag, poses].
var _kept: Array[Array] = []
var _physics_ticks := 60


func before_test() -> void:
	# The probes wait two physics steps for each new surface: step faster than the game does.
	_physics_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 480
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.set_physics_process(false)
	_rig = _player.camera_rig
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_grab)
	_kept.clear()


func after_test() -> void:
	Engine.physics_ticks_per_second = _physics_ticks
	Input.action_release("aim")


func _grab() -> void:
	_latest.clear()
	for b in _skeleton.get_bone_count():
		_latest.append(_skeleton.get_bone_global_pose(b))


func _ticks(count: int) -> void:
	for i in count:
		PlayerHandStep.tick(_player)
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	await get_tree().process_frame


## Advances `count` ticks and keeps the pose the skeleton then draws.
func _keep(tag: String, count: int) -> void:
	await _ticks(count)
	_kept.append([tag, _latest.duplicate()])


func _dress(look: int) -> void:
	_player.dress(CharacterLook.from_preset(look))
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_player.teleport(START)
	await get_tree().physics_frame
	await _ticks(1)


func _reload(id: StringName) -> void:
	_animation.equip(id)
	await _ticks(40)
	_animation.reload(RELOAD_SECONDS)
	for i in roundi(RELOAD_SECONDS / TICK / EVERY):
		await _keep("%s reload tick %d" % [id, i * EVERY], EVERY)
	await _ticks(30)


func _hold(id: StringName) -> void:
	_animation.equip(id)
	await _ticks(40)
	await _keep("%s hold" % id, 1)
	_runner.simulate_action_press("aim")
	await _ticks(40)
	await _keep("%s aim" % id, 1)
	for shot in SHOTS:
		_animation.play_action(&"Fire", shot % 2)
		await _keep("%s fire" % id, KICK_TICKS)
		await _ticks(SHOT_TICKS - KICK_TICKS)
	_runner.simulate_action_release("aim")
	await _ticks(40)


## Measures every kept pose: one line for each pose with an arm deeper than the tolerance.
func _measure() -> Array[String]:
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var host := Node3D.new()
	add_child(host)
	var fit := BodyFit.new(host, _skeleton)
	var sampler := ClipFit.new(fit, _player)
	var fails: Array[String] = []
	for kept: Array in _kept:
		var found := await sampler.measure(kept[1], 2, ARMS)
		for check: String in found:
			var deepest: Dictionary = found[check][0]
			fails.append("%s %s: %.3f m (%s)" % [kept[0], check, deepest.depth, deepest.group])
	fit.free_bodies()
	host.free()
	return fails


func _guns() -> Array[StringName]:
	var guns: Array[StringName] = []
	for id in WeaponCatalog.IDS:
		if not WeaponCatalog.get_def(id).is_melee():
			guns.append(id)
	return guns


func _two_handed() -> Array[StringName]:
	var guns: Array[StringName] = []
	for id in _guns():
		if WeaponHoldMap.hold_for(id).stance_turn_deg > 0.0:
			guns.append(id)
	return guns


func _check_look(look: int) -> void:
	await _dress(look)
	for id in _guns():
		await _reload(id)
	for id in _two_handed():
		await _hold(id)
	assert_array(await _measure()).is_empty()


## Her rolled sleeves, the maintainer's look.
func test_the_arms_stay_out_of_the_body_in_rolled_sleeves() -> void:
	await _check_look(10)


## His jacket, the thickest sleeves and the thickest chest.
func test_the_arms_stay_out_of_the_body_in_a_jacket() -> void:
	await _check_look(0)
