extends GdUnitTestSuite
## The dead on a map with floors above one another (the second map): they follow the walking mesh up
## a stair, are as far from a player on another floor as the stair makes them, and neither start nor
## land a swing across a floor. A flat map (the lot, `storey` 0) is untouched.

const STOREY := 3.4
## A path point sits this far over the floor it walks on (the baker's surface,
## `ZombieSim.NAV_LIFT`).
const LIFT := ZombieSim.NAV_LIFT


## A pathing that walks the way given, as the navigation map's points would: it starts where the
## walker stands (over the floor by `LIFT`) and goes on through the points ahead of it.
class RampPathing:
	extends ZombiePathing
	var points := PackedVector3Array()

	func find_path(from: Vector3, _to: Vector3) -> PackedVector3Array:
		var ahead := PackedVector3Array([from + Vector3(0.0, LIFT, 0.0)])
		for point in points:
			if point.x > from.x + 0.01:
				ahead.append(point)
		return ahead


## A pathing for a target that cannot be reached on this floor: the way ends on the zombie's own
## floor, under the target, as the map's closest point does.
class FloorPathing:
	extends ZombiePathing

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		return PackedVector3Array([Vector3(to.x, from.y + LIFT, to.z)])


func _sim(storey: float) -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.storey = storey
	return sim


## A stair from (0, 0, 0) at the foot up to (6, 3.4, 0) at the top, then 4 m along the upper floor.
func _stair() -> RampPathing:
	var pathing := RampPathing.new()
	pathing.points = PackedVector3Array(
		[
			Vector3(0.0, LIFT, 0.0),
			Vector3(1.0, LIFT, 0.0),
			Vector3(6.0, STOREY + LIFT, 0.0),
			Vector3(10.0, STOREY + LIFT, 0.0),
		]
	)
	return pathing


func test_a_zombie_climbs_a_stair_along_the_path() -> void:
	var sim := _sim(STOREY)
	sim.pathing = _stair()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	var target := {1: Vector3(10.0, STOREY, 0.0)}
	var heights: Array[float] = []
	for _i in 600:
		sim.tick(ZombieFixture.STEP, target)
		heights.append(zombie.position.y)
	# It started on the floor, rose along the ramp and ended on the upper floor, never below it.
	assert_float(heights[0]).is_equal_approx(0.0, 0.05)
	assert_float(zombie.position.y).is_equal_approx(STOREY, 0.05)
	assert_float(zombie.position.x).is_greater(8.0)
	for height in heights:
		assert_float(height).is_between(-0.05, STOREY + 0.05)
	# Half way up the ramp it is half way up: the stair is a ramp, not a step.
	var halfway := heights.filter(func(h: float) -> bool: return h > 1.6 and h < 1.8)
	assert_bool(halfway.is_empty()).is_false()


func test_on_a_flat_map_the_height_stays_where_it_spawned() -> void:
	var sim := _sim(0.0)
	sim.pathing = _stair()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	ZombieFixture.run(sim, 5.0, {1: Vector3(10.0, STOREY, 0.0)})
	assert_float(zombie.position.y).is_equal(0.0)


func test_it_does_not_start_a_swing_at_a_player_on_the_floor_above() -> void:
	var sim := _sim(STOREY)
	sim.pathing = FloorPathing.new()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	# The player stands right above it: flat distance 0.3 m, a floor between them.
	var events := ZombieFixture.run(sim, 3.0, {1: Vector3(0.3, STOREY, 0.0)})
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.CHASE)
	# On one floor the same distance is a swing.
	var flat := _sim(STOREY)
	flat.pathing = FloorPathing.new()
	var neighbour := ZombieFixture.standing(flat, 1, Vector3.ZERO, 0.0)
	var blows := ZombieFixture.run(flat, 3.0, {1: Vector3(0.3, 0.0, 0.0)})
	assert_int(ZombieFixture.count(blows, &"zombie_struck")).is_greater(0)
	assert_int(neighbour.target_id).is_equal(1)


func test_a_player_on_the_counter_is_still_within_reach() -> void:
	var sim := _sim(STOREY)
	sim.pathing = FloorPathing.new()
	ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	var events := ZombieFixture.run(sim, 3.0, {1: Vector3(0.3, 1.2, 0.0)})
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_greater(0)


func test_it_picks_the_player_on_its_own_floor_over_one_flat_nearer_upstairs() -> void:
	var sim := _sim(STOREY)
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	# Player 1 is 2 m away flat but a floor up; player 2 is 8 m away on the zombie's floor.
	ZombieFixture.run(sim, 0.1, {1: Vector3(2.0, STOREY, 0.0), 2: Vector3(8.0, 0.0, 0.0)})
	assert_int(zombie.target_id).is_equal(2)


func test_on_a_flat_map_the_nearest_player_is_the_flat_nearest() -> void:
	var sim := _sim(0.0)
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	ZombieFixture.run(sim, 0.1, {1: Vector3(2.0, STOREY, 0.0), 2: Vector3(8.0, 0.0, 0.0)})
	assert_int(zombie.target_id).is_equal(1)


func test_it_does_not_swing_through_a_wall() -> void:
	var sim := _sim(STOREY)
	sim.pathing = FloorPathing.new()
	# A wall between them: the way is blocked at 0.5 m from the zombie.
	sim.sight = func(from: Vector3, to: Vector3) -> float:
		return 0.5 if from.x < 0.5 and to.x > 0.5 else -1.0
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	var events := ZombieFixture.run(sim, 3.0, {1: Vector3(1.0, 0.0, 0.0)})
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.CHASE)
	# With the wall gone the same player is hit.
	sim.sight = func(_from: Vector3, _to: Vector3) -> float: return -1.0
	var later := ZombieFixture.run(sim, 3.0, {1: Vector3(1.0, 0.0, 0.0)})
	assert_int(ZombieFixture.count(later, &"zombie_struck")).is_greater(0)
