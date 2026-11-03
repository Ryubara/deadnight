# With the road door bought, a player left the lot over the ticket plaza's south-west corner in
# three hops by
# movement alone: a sprint-jump onto a crate at the end wall (0.63 m), a jump onto the small
# container beside it
# (1.71 m), and a sprint-jump over the corner of the 3.0 m walls onto the outskirts slab, 5.8 m
# outside (#845).
# The real body climbs 1.25 m, not the jump's 1.1 m (test_jump_reach.gd), so the container's top was
# 1.29 m under
# the wall, a hair over the reach. These tests run the real body (`PlayerSimulation`) from the
# plaza's floor and
# fail when any chain of hops leaves the plaza, and pin the margin between the tallest prop at a
# wall and its top.
extends GdUnitTestSuite

## The plaza's walls: the end wall's and the side walls' middle lines, and the gate's line it opens
## onto the midway by.
const PLAZA_WEST := -16.0
const PLAZA_EAST := 16.0
const PLAZA_END := 58.0
const PLAZA_GATE := 38.0
## The most a body is measured to climb from level ground (`test_jump_reach.gd`).
const BODY_REACH := CameraProbe.BODY_REACH
## A wall must stand this much over the tallest prop beside it plus the reach: the run-up and a
## corner give a
## little, and the old wall stood 0.04 m short of the reach.
const WALL_MARGIN := 0.5
## A prop within this distance of a plaza wall can be a step towards it.
const WALL_NEAR := 4.0
## A prop whose top is higher than two climbs cannot be stood on from the floor, so is no step.
const STANDABLE := BODY_REACH * 2.0
## Standing places the sweep starts from lie in this band along the end and side walls, on a grid of
## this step.
const BAND := 4.5
const GRID_STEP := 1.5
const HOP_TICKS := 54
const SETTLE_TICKS := 24
const HEADINGS := 8
## Jump moments (ticks into the run-up) tried when sprinting; walking jumps at the start.
const JUMP_TICKS := [0, 9, 20]
## How many hops a chain may have.
const DEPTH := 3
## The ways out found by the sweep on the old plaza (#845), hop by hop: the first starts on the
## solid floor, each
## later one from where the one before landed. A hop is [start, yaw, sprinting, the tick the jump is
## pressed].
## The first chain is the report's: crate, small container, over the corner onto the outskirts slab.
## The second climbs onto the corner of the walls (feet at 2.88 m).
const OLD_CHAINS := [
	[
		[Vector3(-13.35, 0.0, 56.85), -2.3562, true, 9],
		[Vector3.INF, 1.5708, true, 9],
		[Vector3.INF, 2.3562, true, 0],
	],
	[
		[Vector3(-13.35, 0.0, 56.85), -2.3562, true, 9],
		[Vector3.INF, 2.3562, true, 20],
		[Vector3.INF, 1.1781, false, 0],
		[Vector3.INF, 2.3562, true, 20],
	],
]
## A body this high beside a wall is standing on it.
const ON_A_WALL := 2.0
## Beside a wall: within this distance of its middle line.
const WALL_BESIDE := 0.7

var _lot: Node3D
var _body: CharacterBody3D
var _tuning: PlayerTuning
var _seen := {}


func before_test() -> void:
	_tuning = CameraProbe.tuning()
	var sold: Array = LotFixture.door_table().keys()
	_lot = await LotFixture.make_lot(self, sold)
	auto_free(_lot.get_parent())
	_body = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = _tuning.radius
	capsule.height = _tuning.height
	shape.shape = capsule
	shape.position.y = _tuning.height * 0.5
	_body.add_child(shape)
	_body.collision_layer = PhysicsLayers.BODY
	_body.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	_body.floor_snap_length = 0.3
	_lot.add_child(_body)
	_seen.clear()


func test_the_old_hops_out_of_the_corner_no_longer_leave_the_lot() -> void:
	for chain: Array in OLD_CHAINS:
		var at := Vector3.INF
		for hop: Array in chain:
			var from: Vector3 = hop[0] if at == Vector3.INF else at
			at = _run(from, hop[1], hop[2], hop[3])
		(
			assert_bool(_left(at))
			. override_failure_message("the old chain %s lands at %s" % [chain.size(), at])
			. is_false()
		)


func test_no_chain_of_hops_from_the_plaza_floor_leaves_it() -> void:
	var frontier: Array[Vector3] = []
	for start in _start_cells():
		for place in _hops_from(start, HEADINGS):
			(
				assert_bool(_left(place))
				. override_failure_message("a hop from %s lands at %s" % [start, place])
				. is_false()
			)
			if _is_new_standing_place(place):
				frontier.append(place)
	var depth := 1
	while not frontier.is_empty() and depth < DEPTH:
		var next: Array[Vector3] = []
		for from in frontier:
			for place in _hops_from(from, HEADINGS * 2):
				(
					assert_bool(_left(place))
					. override_failure_message(
						"hop %d from %s lands at %s" % [depth + 1, from, place]
					)
					. is_false()
				)
				if _is_new_standing_place(place):
					next.append(place)
		frontier = next
		depth += 1
	# The sweep must have looked at something: the stack by the wall is there to be climbed onto.
	assert_int(_seen.size()).is_greater(3)


func test_each_plaza_wall_stands_well_over_the_tallest_prop_beside_it() -> void:
	var needed := BODY_REACH + WALL_MARGIN
	for wall_name: String in ["FenceEnd0", "SideW0", "SideE0"]:
		var wall := _lot.get_node("Road/%s" % wall_name) as CSGBox3D
		var top := wall.global_position.y + wall.size.y * 0.5
		var tallest := _tallest_solid_near(wall)
		(
			assert_float(top - tallest)
			. override_failure_message(
				(
					"%s: top %.2f, tallest standable prop within %.0f m %.2f"
					% [wall_name, top, WALL_NEAR, tallest]
				)
			)
			. is_greater_equal(needed)
		)


## The highest top of a prop a body can stand on (a collider that is not a wall or the ground) near
## `wall`.
func _tallest_solid_near(wall: CSGBox3D) -> float:
	var tallest := 0.0
	var plaza := _lot.get_node("Road") as Node3D
	for node in _lot.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		if not box.use_collision or box == wall or _is_wall_or_ground(box, plaza):
			continue
		var top := box.global_position.y + box.size.y * 0.5
		var half_diagonal := Vector2(box.size.x, box.size.z).length() * 0.5
		if (
			top > STANDABLE
			or _distance_to_footprint(box.global_position, wall) - half_diagonal > WALL_NEAR
		):
			continue
		tallest = maxf(tallest, top)
	return tallest


## The plaza's own walls and gate fence (direct children of `Road`), the ground and anything outside
## the plaza.
func _is_wall_or_ground(box: CSGBox3D, plaza: Node3D) -> bool:
	if box.size.y <= 0.3 or not plaza.is_ancestor_of(box):
		return true
	var name := String(box.name)
	return box.get_parent() == plaza and (name.begins_with("Side") or name.begins_with("Fence"))


func _distance_to_footprint(point: Vector3, box: CSGBox3D) -> float:
	var local := box.global_transform.affine_inverse() * point
	var half := box.size * 0.5
	return Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.z) - half.z, 0.0)).length()


## Floor cells in a band along the end wall and both side walls (not at the gate), where the stack
## stands.
func _start_cells() -> Array[Vector3]:
	var cells: Array[Vector3] = []
	var x := PLAZA_WEST + 0.8
	while x < PLAZA_EAST:
		var z := PLAZA_GATE + 4.0
		while z < PLAZA_END - 0.5:
			var near_wall := z > PLAZA_END - BAND or x < PLAZA_WEST + BAND or x > PLAZA_EAST - BAND
			if near_wall and _solid_floor_at(x, z):
				cells.append(Vector3(x, 0.0, z))
			z += GRID_STEP
		x += GRID_STEP
	cells.append(Vector3(-12.6, 0.0, 56.1))  # where the old way out started
	return cells


## Whether a standing body fits at (x, z) on the floor, not inside a prop.
func _solid_floor_at(x: float, z: float) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = _tuning.radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	query.transform = Transform3D(Basis.IDENTITY, Vector3(x, _tuning.radius + 0.1, z))
	return _lot.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Where the body ends up after each way of hopping at each of `count` headings from `from`.
func _hops_from(from: Vector3, count: int) -> Array[Vector3]:
	var places: Array[Vector3] = []
	for i in count:
		var yaw := TAU * i / count
		for tick: int in JUMP_TICKS:
			places.append(_run(from, yaw, true, tick))
		places.append(_run(from, yaw, false, 0))
	return places


## One hop of the real body: run at `yaw`, jump pressed for three ticks from `jump_tick`, then
## settle.
func _run(from: Vector3, yaw: float, sprint: bool, jump_tick: int) -> Vector3:
	var state := PlayerMotionState.new()
	state.position = Vector3(from.x, from.y + 0.02, from.z)
	state.on_floor = true
	var command := PlayerCommand.new()
	command.move = Vector2(0, -1)
	command.yaw = yaw
	command.sprint = sprint
	var delta := 1.0 / Engine.physics_ticks_per_second
	for tick in HOP_TICKS:
		command.jump = tick >= jump_tick and tick < jump_tick + 3
		PlayerSimulation.simulate(_body, state, command, _tuning, delta)
	command.move = Vector2.ZERO
	command.sprint = false
	command.jump = false
	for _tick in SETTLE_TICKS:
		PlayerSimulation.simulate(_body, state, command, _tuning, delta)
	return state.position


## Whether a standing place is past the plaza's walls (or on top of one).
func _left(at: Vector3) -> bool:
	if at.x < PLAZA_WEST or at.x > PLAZA_EAST or at.z > PLAZA_END or at.y < -0.3:
		return true
	var beside_a_wall := (
		absf(at.x - PLAZA_WEST) < WALL_BESIDE
		or absf(at.x - PLAZA_EAST) < WALL_BESIDE
		or absf(at.z - PLAZA_END) < WALL_BESIDE
	)
	return beside_a_wall and at.y > ON_A_WALL


## A place off the floor that has not been tried from yet (the sweep follows only elevated ones).
func _is_new_standing_place(at: Vector3) -> bool:
	if at.y < 0.3:
		return false
	var key := Vector3i(roundi(at.x / 0.5), roundi(at.y / 0.25), roundi(at.z / 0.5))
	if _seen.has(key):
		return false
	_seen[key] = true
	return true
