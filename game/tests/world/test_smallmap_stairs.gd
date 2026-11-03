extends OmniHarness
## The small-map kit's stairs, rails and debris blocker (issue #634;
## tools/blender/build_kit_stairs.py writes the models and these fixture scenes). The real player
## body (`PlayerSimulation`, fed commands) walks up and down each stair: it never steps up (each
## flight's collision is one hidden ramp through the treads' middles, so fifteen 0.2 m risers
## never lift the view) and never leaves the floor. A flight whose collision is its treads does
## step, which shows the measure sees it.

const FIXTURES := "res://world/smallmap/fixtures/"
## Where the stairs stand in the test room: a clear patch east of the pillars.
const AT := Vector3(10.0, 0.0, 10.0)
const STOREY := 3.0
const RISE := 0.2
const TREAD := 0.3
## Half the footprints (m): the straight flight is 4.5 long, the L stair 3.5 square.
const STRAIGHT_HALF := 2.25
const L_HALF := 1.75
const WIDTH := 1.4
## A change of the drawn body's height per tick that counts as a kink (m): at a run of 4.8 m/s a
## 33.7 degree ramp climbs 0.053 m a tick.
const KINK := 0.02


## The upper floor beyond a stair's top: a slab 0.2 m thick, its top at the storey.
func _add_upper_floor(centre: Vector3, size: Vector2) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 0.2, size.y)
	shape.shape = box
	body.add_child(shape)
	_player.get_parent().add_child(body)
	body.global_position = Vector3(centre.x, STOREY - 0.1, centre.z)


func _add_fixture(scene: String, at := AT) -> Node3D:
	var fixture := (load(FIXTURES + scene + ".tscn") as PackedScene).instantiate() as Node3D
	_player.get_parent().add_child(fixture)
	fixture.global_position = at
	return fixture


func _add_straight() -> Node3D:
	var stair := _add_fixture("stair_straight")
	_add_upper_floor(Vector3(AT.x, 0.0, AT.z - STRAIGHT_HALF - 1.0), Vector2(3.0, 2.0))
	return stair


## The L stair turning `hand` ("left" or "right"), and the upper floor its top arrives at.
func _add_l(hand: String) -> Dictionary:
	var stair := _add_fixture("stair_l_" + hand)
	var sign := -1.0 if hand == "left" else 1.0
	# The lower flight's middle is 1.05 m off the footprint's middle, away from the turn.
	var foot := Vector3(AT.x - sign * 1.05, 0.05, AT.z + L_HALF + 1.5)
	var landing := Vector3(foot.x, 1.65, AT.z - L_HALF + WIDTH / 2.0)
	var top := Vector3(AT.x + sign * (L_HALF + 1.0), 3.05, landing.z)
	_add_upper_floor(top, Vector2(2.0, 3.0))
	return {"stair": stair, "foot": foot, "landing": landing, "top": top}


## What a walk saw, tick by tick.
class Walk:
	var ticks := 0
	var steps := 0
	var off_floor := 0
	## The largest drop of the drawn body in one tick while climbing (a dip is a bob).
	var worst_dip := 0.0
	## The largest rise of the drawn body in one tick while going down (a hop is a bob).
	var worst_hop := 0.0
	## The sums of those drops (climbing) and rises (going down) over the whole walk.
	var total_dip := 0.0
	var total_hop := 0.0
	## Ticks where the drawn body's climb rate changed by more than KINK m a tick: a ramp has two (its
	## foot and its top), a flight of steps one or two per step.
	var kinks := 0
	var reached := false


## Walks the player towards each point of `path` in turn (x and z; y is ignored), recording steps
## and floor contact. `up` says which way the walk goes, for the dip and hop measures.
func _walk(path: Array[Vector3], up: bool, sprint := false, walk := Walk.new()) -> Walk:
	var model := _player.get_node("Model") as Node3D
	var last_rise := 0.0
	for target in path:
		var arrived := false
		for i in 600:
			var here := _player.state.position
			var to := Vector2(target.x - here.x, target.z - here.z)
			if to.length() < 0.15:
				arrived = true
				break
			var command := PlayerCommand.new()
			command.move = to.normalized()
			command.sprint = sprint
			var before := _player.global_position.y + model.position.y
			_step(command)
			var after := _player.global_position.y + model.position.y
			walk.ticks += 1
			if absf((after - before) - last_rise) > KINK:
				walk.kinks += 1
			last_rise = after - before
			if _player.state.stepped_up > 0.0:
				walk.steps += 1
			if not _player.state.on_floor:
				walk.off_floor += 1
			if up:
				walk.worst_dip = maxf(walk.worst_dip, before - after)
				walk.total_dip += maxf(0.0, before - after)
			else:
				walk.worst_hop = maxf(walk.worst_hop, after - before)
				walk.total_hop += maxf(0.0, after - before)
		if not arrived:
			return walk
	walk.reached = true
	return walk


## One line per walk in the log, for the pull request's numbers.
func _report(walk: Walk, what: String) -> void:
	print(
		(
			(
				"STAIRWALK %s ticks=%d steps=%d off_floor=%d worst_dip=%.4f total_dip=%.4f"
				+ " worst_hop=%.4f kinks=%d"
			)
			% [
				what,
				walk.ticks,
				walk.steps,
				walk.off_floor,
				walk.worst_dip,
				walk.total_dip,
				walk.worst_hop,
				walk.kinks
			]
		)
	)


## No step and no fall. Where a slope meets the flat, the capsule's round foot rolls over the edge
## and the body settles a few millimetres in a tick (8 mm at most, a 25th of a riser): a step would
## lift it by a whole riser.
func _assert_smooth(walk: Walk, what: String) -> void:
	_report(walk, what)
	assert_bool(walk.reached).override_failure_message(what + ": never got there").is_true()
	assert_int(walk.steps).override_failure_message(what + ": stepped up").is_equal(0)
	assert_int(walk.off_floor).override_failure_message(what + ": left the floor").is_equal(0)
	assert_float(walk.worst_dip).override_failure_message(what + ": dipped").is_less(0.01)
	assert_float(walk.total_dip).override_failure_message(what + ": dipped").is_less(0.02)
	assert_float(walk.worst_hop).override_failure_message(what + ": hopped").is_less(0.01)


# --- the ramp is where the treads are ---


func test_the_straight_ramp_runs_through_the_middle_of_every_tread() -> void:
	_add_straight()
	await _flush_physics()
	var space := _player.get_world_3d().direct_space_state
	var foot_z := AT.z + STRAIGHT_HALF
	for i in 14:
		var z := foot_z - (i + 0.5) * TREAD
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(AT.x, 5.0, z), Vector3(AT.x, -1.0, z)
		)
		var hit := space.intersect_ray(query)
		assert_bool(hit.is_empty()).is_false()
		assert_float(hit.position.y).is_equal_approx((i + 1) * RISE, 0.01)


# --- walking the stairs ---


func test_the_straight_stair_is_walked_up_and_down_without_a_step() -> void:
	_add_straight()
	await _flush_physics()
	_player.teleport(Vector3(AT.x, 0.05, AT.z + STRAIGHT_HALF + 2.0))
	await _run(Vector2.ZERO, 10)
	var top: Array[Vector3] = [Vector3(AT.x, 0.0, AT.z - STRAIGHT_HALF - 1.0)]
	_assert_smooth(_walk(top, true), "up")
	assert_float(_player.state.position.y).is_equal_approx(STOREY, 0.02)
	var foot: Array[Vector3] = [Vector3(AT.x, 0.0, AT.z + STRAIGHT_HALF + 1.5)]
	_assert_smooth(_walk(foot, false), "down")
	assert_float(_player.state.position.y).is_equal_approx(0.0, 0.02)


func test_the_straight_stair_is_sprinted_up_and_down_without_a_step() -> void:
	_add_straight()
	await _flush_physics()
	_player.teleport(Vector3(AT.x, 0.05, AT.z + STRAIGHT_HALF + 2.0))
	await _run(Vector2.ZERO, 10)
	var top: Array[Vector3] = [Vector3(AT.x, 0.0, AT.z - STRAIGHT_HALF - 1.0)]
	_assert_smooth(_walk(top, true, true), "sprint up")
	var foot: Array[Vector3] = [Vector3(AT.x, 0.0, AT.z + STRAIGHT_HALF + 1.5)]
	_assert_smooth(_walk(foot, false, true), "sprint down")


func test_each_l_stair_is_walked_up_and_down_without_a_step() -> void:
	for hand: String in ["left", "right"]:
		var placed := _add_l(hand)
		await _flush_physics()
		_player.teleport(placed.foot)
		await _run(Vector2.ZERO, 10)
		var up: Array[Vector3] = [placed.landing, placed.top]
		_assert_smooth(_walk(up, true), hand + " up")
		assert_float(_player.state.position.y).is_equal_approx(STOREY, 0.02)
		var down: Array[Vector3] = [placed.landing, placed.foot]
		_assert_smooth(_walk(down, false), hand + " down")
		assert_float(_player.state.position.y).is_equal_approx(0.0, 0.02)
		placed.stair.free()
		for child in _player.get_parent().get_children():
			if child is StaticBody3D:
				child.free()


func test_cutting_the_l_stairs_corner_never_meets_a_ledge() -> void:
	var placed := _add_l("left")
	await _flush_physics()
	_player.teleport(placed.foot)
	await _run(Vector2.ZERO, 10)
	# Straight from the lower flight's top towards the upper flight, across the landing's corner.
	var corner: Vector3 = placed.landing + Vector3(0.0, 0.0, 0.3)
	var path: Array[Vector3] = [corner, placed.top]
	_assert_smooth(_walk(path, true, true), "corner")


func test_treads_as_collision_would_step_and_the_measure_sees_it() -> void:
	# The same flight with a box per tread instead of the ramp: the body climbs by stepping up.
	for i in 15:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var top := (i + 1) * RISE
		box.size = Vector3(WIDTH, top, TREAD)
		shape.shape = box
		body.add_child(shape)
		_player.get_parent().add_child(body)
		body.global_position = Vector3(AT.x, top / 2.0, AT.z + STRAIGHT_HALF - (i + 0.5) * TREAD)
	_add_upper_floor(Vector3(AT.x, 0.0, AT.z - STRAIGHT_HALF - 1.0), Vector2(3.0, 2.0))
	await _flush_physics()
	_player.teleport(Vector3(AT.x, 0.05, AT.z + STRAIGHT_HALF + 2.0))
	await _run(Vector2.ZERO, 10)
	var top: Array[Vector3] = [Vector3(AT.x, 0.0, AT.z - STRAIGHT_HALF - 1.0)]
	var walk := _walk(top, true)
	_report(walk, "treads")
	assert_bool(walk.reached).is_true()
	assert_int(walk.steps).is_greater(10)
	assert_int(walk.kinks).is_greater(10)


# --- rails ---


func test_a_rail_stops_the_player_but_not_a_shot() -> void:
	var rail := _add_fixture("rail_flat", Vector3(AT.x, 0.0, AT.z))
	await _flush_physics()
	var blocker := rail.get_node("Blocker") as CSGBox3D
	# On the boards' layer: the player's body collides with it, the shots' probe does not.
	assert_int(blocker.collision_layer).is_equal(2)
	assert_int(_player.collision_mask & blocker.collision_layer).is_not_equal(0)
	assert_int(WorldProbe.WORLD_MASK & blocker.collision_layer).is_equal(0)
	_player.teleport(Vector3(AT.x, 0.05, AT.z + 2.0))
	await _run(Vector2.ZERO, 10)
	await _run(Vector2(0.0, -1.0), 90)
	assert_float(_player.state.position.z).is_greater(AT.z)


func test_the_straight_stairs_rails_follow_its_open_sides() -> void:
	var stair := _add_fixture("stair_straight") as KitStair
	var left := stair.get_node("RailLeftBlocker") as CSGBox3D
	var right := stair.get_node("RailRightBlocker") as CSGBox3D
	assert_bool(left.use_collision).is_true()
	assert_bool(right.use_collision).is_false()
	assert_bool((stair.get_node("Model/RailRight") as Node3D).visible).is_false()
	stair.rail_left = false
	stair.rail_right = true
	assert_bool(left.use_collision).is_false()
	assert_bool(right.use_collision).is_true()
	assert_bool((stair.get_node("Model/RailLeft") as Node3D).visible).is_false()
	assert_bool((stair.get_node("Model/RailRight") as Node3D).visible).is_true()


# --- the debris blocker ---


func test_the_debris_blocker_fills_its_opening_and_comes_apart_in_order() -> void:
	var debris := _add_fixture("debris_blocker")
	await _flush_physics()
	var model := debris.get_node("Model")
	var names: Array[String] = []
	for child in model.get_children():
		names.append(child.name)
	(
		assert_array(names)
		. contains_exactly(
			[
				"Part1_Planks",
				"Part2_Chair",
				"Part3_Table",
				"Part4_Beam",
				"Part5_Dresser",
				"Part6_Rubble",
			]
		)
	)
	var blocker := debris.get_node("Blocker") as CSGBox3D
	assert_vector(blocker.size).is_equal(Vector3(1.4, 2.4, 1.0))
	_player.teleport(Vector3(AT.x, 0.05, AT.z + 2.0))
	await _run(Vector2.ZERO, 10)
	await _run(Vector2(0.0, -1.0), 90)
	assert_float(_player.state.position.z).is_greater(AT.z + 0.5)
