# How high a ledge the real player body gets onto from level ground. The jump is 1.1 m
# (`PlayerTuning.jump_height`) but the body also steps up at an edge and its capsule has a rounded
# foot, so it climbs a little higher: the lot's reach test and the map pages once took 1.1 m as the
# most, and a prop 1.2 m high (the second map's counter) was climbed (#833,
# docs/research/map-review.md).
# This pins the measured reach so that a change to the jump, the step-up or the capsule shows up.
extends GdUnitTestSuite

## The most a player is measured to climb (metres): the highest block of the sweep it gets onto.
const MEASURED_REACH := 1.25
## How far the measure may move before this fails: other tests read the number, so a move is a
## decision.
const TOLERANCE := 0.06
const START_DISTANCES := [1.0, 2.0, 3.0, 4.0]
const JUMP_TICKS := [0, 3, 6, 9, 12, 16, 20, 26, 32]
const RUN_TICKS := 90
const STEP := 0.05

var _world: Node3D
var _block: CSGBox3D
var _body: CharacterBody3D


func before_test() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_box := CSGBox3D.new()
	floor_box.use_collision = true
	floor_box.size = Vector3(40, 1, 40)
	floor_box.position = Vector3(0, -0.5, 0)
	_world.add_child(floor_box)
	_block = CSGBox3D.new()
	_block.use_collision = true
	_world.add_child(_block)
	var tuning := CameraProbe.tuning()
	_body = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.radius
	capsule.height = tuning.height
	shape.shape = capsule
	shape.position.y = tuning.height * 0.5
	_body.add_child(shape)
	_body.collision_layer = PhysicsLayers.BODY
	_body.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	_body.floor_snap_length = 0.3
	_world.add_child(_body)
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_test() -> void:
	_world.free()


func test_the_body_climbs_the_measured_reach_and_no_more() -> void:
	var highest := 0.0
	var height := 1.05
	while height <= 1.5:
		if await _climbs(height):
			highest = height
		height += STEP
	assert_float(highest).is_between(MEASURED_REACH - TOLERANCE, MEASURED_REACH + TOLERANCE)


func test_the_jump_height_alone_understates_the_reach() -> void:
	# The reason for the number: a block a little over the jump is climbed.
	assert_bool(await _climbs(CameraProbe.tuning().jump_height + 0.1)).is_true()


## Whether the body, sprinting or walking at a block `height` high from several distances and
## jumping at several moments, ends up standing on it.
func _climbs(height: float) -> bool:
	var tuning := CameraProbe.tuning()
	_block.size = Vector3(6, height, 6)
	_block.position = Vector3(0, height * 0.5, -3.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var delta := 1.0 / Engine.physics_ticks_per_second
	for sprint in [true, false]:
		for start: float in START_DISTANCES:
			for jump_tick: int in JUMP_TICKS:
				var state := PlayerMotionState.new()
				state.position = Vector3(0, 0.02, start)
				state.on_floor = true
				var command := PlayerCommand.new()
				command.move = Vector2(0, -1)
				command.sprint = sprint
				for tick in RUN_TICKS:
					command.jump = tick >= jump_tick and tick < jump_tick + 3
					PlayerSimulation.simulate(_body, state, command, tuning, delta)
				if state.position.y > height - 0.1 and state.on_floor:
					return true
	return false
