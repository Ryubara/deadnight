# The arms and armbands stay out of the body in the poses #1037 left over the tolerance (#1282): the
# crawl's blend-in, the pistol's strike and sprint, the melee swing's armband and sprint, the
# grenade's cook. The real player on both looks, each pose read as the skeleton draws it (after the
# hand IK) and measured by `ClipFit`: nothing deeper than its tolerance. On main before #1282 the
# crawl's right hand went 81-87 mm into the trunk, the melee armband 41-45, the house pistol's
# and the ray gun's sprint hand 33-37, the pistol's strike 31-32 and the grenade's cook 30-31.
# Stepped by hand with fixed ticks; docs/design/animation.md, "Arms and the body".
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
const CHECKS: Array[String] = ["left arm", "right arm", "armbands"]
## Ticks between two kept poses while a beat plays (the deepest poses last a few ticks).
const EVERY := 2
## The crawl's blend-in is over in about ten ticks, and its deepest poses were in the first: each
## is kept.
const CRAWL_TICKS := 16
const EQUIP_TICKS := 40
const STRIKE_TICKS := 45
const SPRINT_TICKS := 60
const SWING_TICKS := 40
const COOK_TICKS := 40
const SETTLE_TICKS := 30
const DOWN_TICKS := 90
## The guns the pistol hold's sprint and strike are measured with, and the melee weapon.
const PISTOLS: Array[StringName] = [&"house_pistol", &"ray_gun", &"pistol", &"flare_gun"]
const MELEE: StringName = &"baseball_bat"

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _latest: Array[Transform3D] = []
## Kept poses: [tag, poses].
var _kept: Array[Array] = []
var _physics_ticks := 60
var _command := PlayerCommand.new()


func before_test() -> void:
	# The probes wait two physics steps for each new surface: step faster than the game does.
	_physics_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 480
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.set_physics_process(false)
	_player.local_input = false
	_rig = _player.camera_rig
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_grab)
	_kept.clear()
	_command = PlayerCommand.new()


func after_test() -> void:
	Engine.physics_ticks_per_second = _physics_ticks


func _grab() -> void:
	_latest.clear()
	for b in _skeleton.get_bone_count():
		_latest.append(_skeleton.get_bone_global_pose(b))


func _dress(look: int) -> void:
	_player.dress(CharacterLook.from_preset(look))
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_grab)
	_player.teleport(START)
	await get_tree().physics_frame
	await _ticks(1)


func _step_once() -> void:
	_command.yaw = _rig.yaw
	_command.pitch = _rig.pitch
	_player.submit_command(_command)
	PlayerHandStep.tick(_player)
	_rig.step(TICK, 1.0)
	_animation._process(TICK)
	_animation.advance(TICK)


func _ticks(count: int) -> void:
	for i in count:
		_step_once()
	await get_tree().process_frame


## Plays `count` ticks of a beat and keeps the pose the skeleton draws every `EVERY`.
func _beat(tag: String, count: int, every := EVERY) -> void:
	for t in count:
		if t % every == 0:
			await _ticks(1)
			_kept.append(["%s tick %d" % [tag, t], _latest.duplicate()])
		else:
			_step_once()
	await get_tree().process_frame


func _equip(id: StringName) -> void:
	_animation.equip(id)
	await _ticks(EQUIP_TICKS)


func _sprint(id: StringName) -> void:
	_command.move = Vector2(0.0, -1.0)
	_command.sprint = true
	await _beat("%s sprint" % id, SPRINT_TICKS)
	_command.move = Vector2.ZERO
	_command.sprint = false
	await _ticks(SETTLE_TICKS)
	_player.teleport(START)
	await _ticks(SETTLE_TICKS)


func _strike(id: StringName) -> void:
	_animation.strike()
	await _beat("%s strike" % id, STRIKE_TICKS, 1)
	await _ticks(SETTLE_TICKS)


## Measures every kept pose: one line for each with an arm or an armband deeper than the tolerance.
func _measure() -> Array[String]:
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var host := Node3D.new()
	add_child(host)
	var fit := BodyFit.new(host, _skeleton)
	var sampler := ClipFit.new(fit, _player)
	var fails: Array[String] = []
	for kept: Array in _kept:
		var found := await sampler.measure(kept[1], 2, CHECKS)
		for check: String in found:
			var deepest: Dictionary = found[check][0]
			fails.append("%s %s: %.3f m (%s)" % [kept[0], check, deepest.depth, deepest.group])
	fit.free_bodies()
	host.free()
	return fails


func _check_look(look: int) -> void:
	await _dress(look)
	for id in PISTOLS:
		await _equip(id)
		await _strike(id)
		await _sprint(id)
	await _equip(MELEE)
	_animation.play_action(&"Swing", 0)
	await _beat("%s swing" % MELEE, SWING_TICKS, 1)
	await _ticks(SETTLE_TICKS)
	await _sprint(MELEE)
	_animation.grenade(&"cook")
	await _beat("grenade cook", COOK_TICKS, 1)
	_animation.grenade(&"throw")
	await _ticks(60)
	_animation.set_downed(true)
	await _ticks(DOWN_TICKS)
	_command.move = Vector2(0.0, -1.0)
	await _beat("crawl", CRAWL_TICKS, 1)
	assert_array(await _measure()).is_empty()


## Her rolled sleeves, the maintainer's look.
func test_the_arms_stay_out_of_the_body_in_these_poses_in_rolled_sleeves() -> void:
	await _check_look(10)


## His jacket, the thickest sleeves and the thickest chest.
func test_the_arms_stay_out_of_the_body_in_these_poses_in_a_jacket() -> void:
	await _check_look(0)
