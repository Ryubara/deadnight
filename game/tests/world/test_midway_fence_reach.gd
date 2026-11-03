# The midway's fences are not stairs into the shut areas (#846, docs/design/map.md "Nobody leaves by
# jumping"). With only the concession bought, a player once got into the back lot (1,250) in four
# hops from the west alley: a walk-jump onto the barrels (0.82 m), a sprint-jump onto the dumpster
# (1.62 m) and a sprint-jump over the 2.6 m fence. The body climbs 1.25 m
# (`tools/world/ledge_probe`), not the 1.1 m jump, and a prop that is itself a step brings the
# fence within reach.
# Two proofs, both by the real player body (`PlayerSimulation`, the rules the night ticks): the old
# hops replayed from the real floor, and a bounded sweep of hop chains from the ground beside the
# midway's fences, with the doors in each state a team can have them.
extends GdUnitTestSuite

## The ground beside a midway fence (either side) a hop is tried from, in metres from the fence.
const LAUNCH_BAND := 4.0
## Metres between launch cells.
const LAUNCH_STEP := 1.0
## Ticks of a hop (running at a wall, jumping), then of settling.
const HOP_TICKS := 54
const SETTLE_TICKS := 24
## The ticks the jump button goes down on, one hop each (sprinting); and one walking hop.
const JUMP_TICKS := [0, 9, 20]
## Headings tried from a launch cell and from a perch.
const HEADINGS := 8
const HEADINGS_FROM_PERCH := 16
## A chain is this many hops at most.
const DEPTH := 3
## Feet this high are on a wall or a fence.
const ON_A_WALL := 2.4
## A landing this far over the floor is a perch (the top of a prop): the next hop starts there.
const PERCH := 0.3
## A hop that ends this near where it began learned nothing.
const NO_MOVE := 0.6
## A hop runs at a wall: something solid this far ahead at knee height.
const WALL_AHEAD := 3.0
## The doors a team can have bought (each needs the one before it; the yard and the back lot, the
## booth).
const STATES := [
	[],
	["door_concession"],
	["door_concession", "door_booth"],
	["door_concession", "door_booth", "door_yard", "door_back_lot"],  # all but the road
]
## How the west alley was climbed before the fix: a sprint-jump from the floor onto a barrel (0.82
## m), a sprint-jump onto the dumpster (1.62 m), a sprint-jump south-west over the 2.6 m fence into
## the back lot. Each hop is the heading (yaw), whether it sprinted and the tick the jump went down
## on; each starts where the one before landed, the first on the floor at `from`.
const OLD_CHAIN := [
	{"from": Vector3(-13.5, 0.0, 1.5), "yaw": 0.7854, "sprint": true, "jump_tick": 20},
	{"from": Vector3.ZERO, "yaw": 0.0, "sprint": true, "jump_tick": 9},
	{"from": Vector3.ZERO, "yaw": 2.356, "sprint": true, "jump_tick": 0},
]

var _tuning: PlayerTuning
var _lot: Node3D
var _body: CharacterBody3D
var _space: PhysicsDirectSpaceState3D


func before_test() -> void:
	_tuning = CameraProbe.tuning()


func after_test() -> void:
	_body = null
	_lot = null


func test_the_old_hops_from_the_west_alley_no_longer_end_in_the_back_lot() -> void:
	await _enter(["door_concession"])
	var at := Vector3.INF
	for hop: Dictionary in OLD_CHAIN:
		var from: Vector3 = hop["from"] if at == Vector3.INF else at
		var landed := _run_hop(from, hop["yaw"], hop["sprint"], hop["jump_tick"])
		at = landed if landed != Vector3.INF else from
	var back_lot := LotFixture.footprint(_lot, "BackLot")
	(
		assert_bool(LotFixture.inside(back_lot, at))
		. override_failure_message("the old chain ends at %s, inside the back lot" % [at])
		. is_false()
	)
	assert_float(at.y).override_failure_message("the old chain ends on a wall: %s" % [at]).is_less(
		ON_A_WALL
	)


func test_no_hop_chain_from_beside_the_midway_fences_ends_in_a_closed_area_or_on_a_wall() -> void:
	for sold: Array in STATES:
		await _enter(sold)
		var violations := _sweep(sold)
		(
			assert_array(violations)
			. override_failure_message("sold %s: %s" % [sold, violations])
			. is_empty()
		)


func _enter(sold: Array) -> void:
	_lot = await LotFixture.make_lot(self, sold)
	auto_free(_lot.get_parent())
	_space = _lot.get_world_3d().direct_space_state
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


## Every chain of hops from the launch cells; the places a chain ends that are inside a closed area
## or on top of a wall, described.
func _sweep(sold: Array) -> Array[String]:
	var closed: Dictionary = {}
	for area: String in LotFixture.AREA_DOOR:
		if not LotFixture.is_open(area, sold):
			closed[area] = LotFixture.footprint(_lot, area)
	var seen := {}
	var found: Array[String] = []
	var frontier: Array = []
	for cell in _launch_cells(sold):
		for hop in _hops_from(cell, HEADINGS, []):
			_file(hop, closed, seen, found, frontier)
	for depth in range(1, DEPTH):
		var next: Array = []
		for place: Dictionary in frontier:
			for hop in _hops_from(place["pos"], HEADINGS_FROM_PERCH, place["via"]):
				_file(hop, closed, seen, found, next)
		frontier = next
	return found


## Files where a hop settled: a violation inside a closed area or on a wall, and a perch to try
## again from when it is a new place off the floor.
func _file(
	hop: Dictionary, closed: Dictionary, seen: Dictionary, found: Array[String], next: Array
) -> void:
	var pos: Vector3 = hop["pos"]
	var key := Vector3i(roundi(pos.x / 0.5), roundi(pos.y / 0.25), roundi(pos.z / 0.5))
	if seen.has(key):
		return
	seen[key] = true
	for area: String in closed:
		if LotFixture.inside(closed[area], pos):
			found.append("%s: in the shut %s via %s" % [pos, area, hop["via"]])
			return
	if pos.y >= ON_A_WALL:
		found.append("%s: on top of a wall via %s" % [pos, hop["via"]])
	elif pos.y >= PERCH:
		next.append(hop)


## Ground cells in the open areas within `LAUNCH_BAND` of a midway fence or alley end, where the
## body fits.
func _launch_cells(sold: Array) -> Array[Vector3]:
	var cells: Array[Vector3] = []
	var fences := _midway_fences()
	for area: String in ["Field"] + LotFixture.AREA_DOOR.keys():
		if not LotFixture.is_open(area, sold):
			continue
		for cell in LotFixture.grid(LotFixture.footprint(_lot, area), LAUNCH_STEP):
			for fence in fences:
				if _distance_to_box(cell, fence) <= LAUNCH_BAND:
					if _clear(cell):
						cells.append(cell)
					break
	return cells


## The midway's fences and alley ends: the thin, tall boxes of the area.
func _midway_fences() -> Array[CSGBox3D]:
	var fences: Array[CSGBox3D] = []
	for child in _lot.get_node("Midway").get_children():
		var name := String(child.name)
		if child is CSGBox3D and (name.begins_with("Fence") or name.begins_with("AlleyEnd")):
			fences.append(child)
	return fences


func _distance_to_box(point: Vector3, box: CSGBox3D) -> float:
	var local := box.global_transform.affine_inverse() * point
	var half := box.size * 0.5
	return Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.z) - half.z, 0.0)).length()


## Whether a standing body fits at `at` (nothing solid in its capsule).
func _clear(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = _tuning.radius
	capsule.height = _tuning.height - 0.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, _tuning.height * 0.5 + 0.05, 0))
	return _space.intersect_shape(query, 1).is_empty()


## Where the body settles after running at each heading with a wall ahead: sprint-jumping at the
## moments in `JUMP_TICKS`, and a walking jump. Each is {pos, via}.
func _hops_from(from: Vector3, headings: int, via: Array) -> Array:
	var results: Array = []
	for i in headings:
		var angle := TAU * i / headings
		var direction := Vector3(sin(angle), 0, cos(angle))
		if not _wall_ahead(from, direction):
			continue
		var yaw := atan2(-direction.x, -direction.z)
		var plans: Array = []
		for jump_tick: int in JUMP_TICKS:
			plans.append([true, jump_tick])
		plans.append([false, 0])
		for plan: Array in plans:
			var landed := _run_hop(from, yaw, plan[0], plan[1])
			if landed != Vector3.INF:
				var step := {
					"from": from,
					"yaw": snappedf(yaw, 0.0001),
					"sprint": plan[0],
					"jump_tick": plan[1]
				}
				results.append({"pos": landed, "via": via + [step]})
	return results


func _wall_ahead(at: Vector3, direction: Vector3) -> bool:
	var start := at + Vector3(0, 0.55, 0)
	var query := PhysicsRayQueryParameters3D.create(start, start + direction * WALL_AHEAD)
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	return not _space.intersect_ray(query).is_empty()


## One run of the real body from `from`: forward at `yaw`, the jump held for three ticks from
## `jump_tick`, then settling. Returns where it ended, or INF when it ended where it began.
func _run_hop(from: Vector3, yaw: float, sprint: bool, jump_tick: int) -> Vector3:
	var state := PlayerMotionState.new()
	# A perch is where the body stood: start at that spot exactly (the floor under a capsule resting
	# on a rim is the ground, and a start there is inside the prop). From the ground, start just
	# over the floor.
	if from.y > PERCH:
		state.position = from
	else:
		state.position = Vector3(from.x, _floor_under(from) + 0.02, from.z)
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
	for tick in SETTLE_TICKS:
		PlayerSimulation.simulate(_body, state, command, _tuning, delta)
	if not state.on_floor:
		return Vector3.INF
	if state.position.distance_to(from) < NO_MOVE and absf(state.position.y - from.y) < PERCH:
		return Vector3.INF
	return state.position


func _floor_under(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3(0, 0.6, 0), at - Vector3(0, 1.0, 0)
	)
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	var hit := _space.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else at.y
