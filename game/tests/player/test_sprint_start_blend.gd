# The start of a sprint flows out of the pose the body is in (#619): from a run, from standing and
# from the aim (held on the spot and while moving), the spine, the chest, both arms, both hands and
# the weapon are drawn each tick over the first half second, and no tick turns or moves any of them
# more than a stride of the sprint itself does. On the build before the fix the weapon turned 29
# degrees and the left arm 65 in the single tick the hands' IK switched off, and the first tick of
# the carry turned the weapon 12. Both the player's own body and the puppet another machine draws
# from the server's frames (`RemoteAvatars`, 30 frames a second, drawn 0.1 s late) are checked.
# Stepped by hand with fixed ticks (no wall time).
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 17.0)
const PUPPET_ID := 2
## Ticks drawn from the one the sprint key goes down in: the speed builds up in 14 and the carry is
## in after 12 more of them; the puppet is drawn 0.1 s late and takes its speed from the frames, so
## its carry is in by about the 40th. Fifty ticks hold the whole start and some of the stride.
const WINDOW := 50
## The bones the pose reaches, and the weapon, which rides the right hand.
const TRACKED: Array[String] = [
	"Abdomen",
	"Torso",
	"UpperArm.R",
	"LowerArm.R",
	"Index1.R",
	"UpperArm.L",
	"LowerArm.L",
	"Index1.L",
]
const WEAPON := "Weapon"
## The most a bone may turn in one tick, in degrees. The sprint's own stride turns the arms 2 to 8
## and the crossing from the shouldered pose to the carry 12 at its fastest.
const MAX_TURN_DEG := 20.0
## The most a bone's place may move in one tick, in metres (the stride moves a hand 0.06, the
## crossing 0.12).
const MAX_STEP := 0.2
## The most one tick's turn may differ from the tick before's, in degrees: an arm that snaps to a
## new pose is a jump of 25 or more in it, whatever the speed of the swing around it.
const MAX_JERK_DEG := 15.0

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _avatars: RemoteAvatars
var _own: Recording
var _puppet: Recording
var _ticks := 0


## One body's drawn pose, tick by tick: what the skeleton hands the mesh after its modifiers.
class Recording:
	extends RefCounted

	var samples: Array[Dictionary] = []
	var recording := false
	var _skeleton: Skeleton3D
	var _body: Player
	var _animation: PlayerAnimation
	var _latest: Dictionary = {}

	func _init(body: Player) -> void:
		_body = body
		_animation = body.get_node("AnimationTree") as PlayerAnimation
		_skeleton = body.get_node("Model").find_child("Skeleton3D", true, false) as Skeleton3D
		_skeleton.skeleton_updated.connect(_on_updated)

	func _on_updated() -> void:
		_latest = {}
		for bone in TRACKED:
			var pose := _skeleton.get_bone_global_pose(_skeleton.find_bone(bone))
			_latest[bone] = Transform3D(pose.basis.orthonormalized(), pose.origin)
		var weapon := _body.global_transform.affine_inverse() * _animation.weapon().global_transform
		_latest[WEAPON] = Transform3D(weapon.basis.orthonormalized(), weapon.origin)

	func sample() -> void:
		if recording and not _latest.is_empty():
			samples.append(_latest)

	## The worst of each measure over the samples, as [name of the bone, tick, value]: the turn of
	## a tick, the move of a tick, and a tick's turn against the one before's.
	func worst() -> Dictionary:
		var out := {"turn": ["", 0, 0.0], "step": ["", 0, 0.0], "jerk": ["", 0, 0.0]}
		for bone in TRACKED + [WEAPON]:
			var last_turn := 0.0
			for i in range(1, samples.size()):
				var before: Transform3D = samples[i - 1][bone]
				var now: Transform3D = samples[i][bone]
				var turn := rad_to_deg(
					before.basis.get_rotation_quaternion().angle_to(
						now.basis.get_rotation_quaternion()
					)
				)
				var step := before.origin.distance_to(now.origin)
				var jerk := absf(turn - last_turn) if i > 1 else 0.0
				last_turn = turn
				for pair: Array in [["turn", turn], ["step", step], ["jerk", jerk]]:
					if pair[1] > out[pair[0]][2]:
						out[pair[0]] = [bone, i, pair[1]]
		return out


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	# The suite ticks the player by hand (PlayerHandStep), not at the physics clock's pace.
	_player.set_physics_process(false)
	_rig = _player.camera_rig
	_rig.set_process(false)
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_animation.equip(&"rifle")
	_own = Recording.new(_player)
	_avatars = RemoteAvatars.new()
	_avatars.setup(LookRegistry.new(), 0, TICK * 2.0)
	add_child(_avatars)
	_avatars.set_process(false)  # advanced by hand, once a tick
	_avatars.apply_frame(_frame(0))
	var body := _avatars.avatar(PUPPET_ID)
	var puppet_animation := body.get_node("AnimationTree") as PlayerAnimation
	puppet_animation.set_process(false)
	puppet_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_puppet = Recording.new(body)
	# The physics server learns of the room's static bodies on its first step: take that one by
	# the clock, then tick by hand.
	await get_tree().physics_frame


func after_test() -> void:
	_avatars.queue_free()


func _frame(tick: int) -> Dictionary:
	var state := _player.state
	return {
		"tick": tick,
		"players":
		{
			PUPPET_ID:
			{
				"pos": state.position,
				"facing": state.facing,
				"downed": false,
				"aim": state.aiming,
				"pitch": NightServer.pitch_step(_rig.pitch),
				"stance": PlayerStance.pack(state),
			}
		},
	}


## Ticks the player, the server's frame to the puppet (every other tick, as the server sends 30 a
## second) and both bodies' animation, and takes a sample of each while they record.
func _step(count: int, move: float, sprint: bool, aim := false) -> void:
	var puppet_animation := _avatars.avatar(PUPPET_ID).get_node("AnimationTree") as PlayerAnimation
	for i in count:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -move)
		command.sprint = sprint
		command.aim = aim
		command.yaw = _rig.yaw
		command.pitch = _rig.pitch
		_player.submit_command(command)
		PlayerHandStep.tick(_player)
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
		_ticks += 1
		if _ticks % 2 == 0:
			_avatars.apply_frame(_frame(_ticks / 2))
		_avatars.advance(TICK)
		puppet_animation._process(TICK)
		puppet_animation.advance(TICK)
		# The skeleton's modifiers run on the idle frame.
		await get_tree().process_frame
		_own.sample()
		_puppet.sample()


## Gets the body to `before` (stood, ran, aimed on the spot or while moving) and then holds the
## sprint key (and lets go of the aim button) for `WINDOW` ticks, drawn.
func _start_sprint(before: String) -> void:
	_player.teleport(START)
	_rig.yaw = 0.0
	_rig.pitch = -0.08
	match before:
		"stand":
			await _step(120, 0.0, false)
		"run":
			await _step(60, 1.0, false)
		"aim":
			await _step(90, 0.0, false, true)
		"aim_move":
			await _step(90, 1.0, false, true)
	_own.recording = true
	_puppet.recording = true
	await _step(WINDOW, 1.0, true)
	_own.recording = false
	_puppet.recording = false


func _assert_flows(recording: Recording, who: String, before: String) -> void:
	assert_int(recording.samples.size()).is_equal(WINDOW)
	var worst := recording.worst()
	var turn: Array = worst["turn"]
	var step: Array = worst["step"]
	var jerk: Array = worst["jerk"]
	(
		assert_float(turn[2])
		. override_failure_message(
			(
				"%s from %s: %s turned %.1f degrees in tick %d of the start (most %.0f)"
				% [who, before, turn[0], turn[2], turn[1], MAX_TURN_DEG]
			)
		)
		. is_less(MAX_TURN_DEG)
	)
	(
		assert_float(step[2])
		. override_failure_message(
			(
				"%s from %s: %s moved %.2f m in tick %d of the start (most %.2f)"
				% [who, before, step[0], step[2], step[1], MAX_STEP]
			)
		)
		. is_less(MAX_STEP)
	)
	(
		assert_float(jerk[2])
		. override_failure_message(
			(
				"%s from %s: %s's turn changed %.1f degrees in tick %d of the start (most %.0f)"
				% [who, before, jerk[0], jerk[2], jerk[1], MAX_JERK_DEG]
			)
		)
		. is_less(MAX_JERK_DEG)
	)


func test_the_sprint_start_flows_from_standing() -> void:
	await _start_sprint("stand")
	_assert_flows(_own, "player", "standing")
	_assert_flows(_puppet, "puppet", "standing")


func test_the_sprint_start_flows_from_a_run() -> void:
	await _start_sprint("run")
	_assert_flows(_own, "player", "a run")
	_assert_flows(_puppet, "puppet", "a run")


func test_the_sprint_start_flows_from_the_aim() -> void:
	await _start_sprint("aim")
	_assert_flows(_own, "player", "the aim")
	_assert_flows(_puppet, "puppet", "the aim")


func test_the_sprint_start_flows_from_the_aim_while_moving() -> void:
	await _start_sprint("aim_move")
	_assert_flows(_own, "player", "the aim on the move")
	_assert_flows(_puppet, "puppet", "the aim on the move")


func test_the_puppet_carries_the_weapon_by_the_end_of_the_start() -> void:
	await _start_sprint("stand")
	var puppet_animation := _avatars.avatar(PUPPET_ID).get_node("AnimationTree") as PlayerAnimation
	assert_float(puppet_animation.sprint_carry()).is_equal(1.0)
	assert_float(puppet_animation.hands().weight).is_equal(0.0)


func test_the_carry_ends_on_the_clips_arms() -> void:
	# With the carry in the hands' IK has no weight and is off, and the arms are the carry clip's:
	# switching the modifier off moved nothing.
	await _start_sprint("stand")
	assert_float(_animation.sprint_carry()).is_equal(1.0)
	assert_float(_animation.hands().weight).is_equal(0.0)
	assert_bool(_animation.hands().active).is_false()
