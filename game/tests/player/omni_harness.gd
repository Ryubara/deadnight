class_name OmniHarness
extends GdUnitTestSuite
## The setup the omni movement suites share (docs/research/character-controller.md): the test room,
## and a player fed `PlayerCommand`s the way the server and a replay feed it, so no real input is
## involved and the run is deterministic.

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
## A clear patch of the test room: six metres each way is free of pillars and crates.
const START := Vector3(4.0, 0.05, 10.0)

var _runner: GdUnitSceneRunner
var _player: Player
var _tuning: PlayerTuning
var _yaw := 0.0
## True for a suite about the engine's own physics callback: it ticks the player at the physics
## clock (one command per physics frame) instead of by hand.
var _by_clock := false


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_tuning = _player.tuning
	_yaw = 0.0
	_player.get_node("AnimationTree").set_process(false)
	# The suite ticks the player itself (see `_step`): the engine's own physics frames would add ticks.
	_player.set_physics_process(_by_clock)
	_player.camera_rig.set_process(false)
	_player.teleport(START)
	# The physics server learns of the room's static bodies on its first step: take that one by
	# the clock, then tick by hand.
	await get_tree().physics_frame
	await _run(Vector2.ZERO, 20)  # settle onto the floor


func after_test() -> void:
	Engine.physics_ticks_per_second = int(
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second")
	)


## One fixed tick of the player with `command`, now. The tests step the simulation by hand, back to
## back: waiting a physics frame per tick would tie a test to the clock (60 ticks a second), and
## the simulation reads nothing but its arguments and the static world (`PlayerSimulation`).
func _step(command: PlayerCommand) -> void:
	_player.tick(command)


## Lets the physics server take in the bodies a test has just added: it indexes a new body on its
## next step, which hand ticks do not make. One real physics frame, once per setup and not per tick.
func _flush_physics() -> void:
	await get_tree().physics_frame


## Feeds the same command for `ticks` physics ticks.
func _run(move: Vector2, ticks: int, sprint := false, aim := false, jump_on_first := false) -> void:
	for i in ticks:
		var command := PlayerCommand.new()
		command.move = move
		command.yaw = _yaw
		command.sprint = sprint
		command.aim = aim
		command.jump = jump_on_first and i == 0
		if _by_clock:
			_player.submit_command(command)
			await get_tree().physics_frame
		else:
			_step(command)
	if not _by_clock:
		# One frame for what a frame does (deferred calls), once for the run and not per tick.
		await get_tree().process_frame


func _seconds(move: Vector2, seconds: float, sprint := false, aim := false) -> void:
	await _run(move, roundi(seconds / TICK), sprint, aim)


## The eight directions of the keys and stick, as the input map gives them (x right, y back).
func _directions() -> Array[Vector2]:
	var directions: Array[Vector2] = []
	for i in 8:
		var angle := TAU * i / 8.0
		directions.append(Vector2(sin(angle), -cos(angle)).snappedf(0.0001))
	return directions


## Where the body faces for a move vector with the view at `_yaw` (0 faces -Z).
func _facing_for(move: Vector2) -> float:
	var wish := Basis(Vector3.UP, _yaw) * Vector3(move.x, 0.0, move.y)
	return atan2(-wish.x, -wish.z)


func _heading_degrees() -> float:
	var v := _player.state.velocity
	return rad_to_deg(atan2(-v.x, -v.z))
