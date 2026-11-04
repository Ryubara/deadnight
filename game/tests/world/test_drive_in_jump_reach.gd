# A full jump lifts the player 1.1 m (`PlayerTuning.jump_height`), but the real body climbs 1.25 m
# from level ground (`CameraProbe.BODY_REACH`: the step-up at an edge and the capsule's rounded foot
# add the rest, #848), and a car roof is 1.65 m up. Can a climb from anything reachable get onto a
# closed door's slab or out over the lot's perimeter? Two proofs. A navigation mesh baked with the
# reach as its climb finds the platforms a player can stand on, and a reach from each says whether
# a barrier's top is within the body's climb. The real player body, run through `PlayerSimulation`,
# then tries from every car roof beside the perimeter. `test_drive_in_escape_sweep.gd` runs the
# body at every prop beside the walls.
extends GdUnitTestSuite

## A platform is a spot the walking mesh reaches at least this high.
const PLATFORM_FROM := 1.0
## Platforms closer together than this are one.
const PLATFORM_CELL := 1.0
## How near a path must end to a mesh vertex for the player to have reached it.
const REACHED := 0.4
## How far in from the cabin's edge the real body starts.
const ROOF_EDGE := 0.2
## Seconds the real body spends pushing at a barrier.
const PUSH_SECONDS := 4.0
## A car roof within this many metres of a perimeter wall is tried with the real body.
const ROOF_NEAR := 8.0


func test_no_platform_within_the_reach_of_a_door_slab_or_the_perimeter() -> void:
	var table := LotFixture.door_table()
	for door: String in table:
		var closed := _with_dependents(door, table)
		var sold: Array = table.keys().filter(func(id: String) -> bool: return not closed.has(id))
		var lot := await LotFixture.make_lot(self, sold)
		auto_free(lot.get_parent())
		var nav := LotNavigation.new(lot, CameraProbe.body_radius(), CameraProbe.BODY_REACH)
		await nav.settle(get_tree())
		var platforms := _platforms(nav, lot)
		assert_int(platforms.size()).override_failure_message(door).is_greater(0)
		var failures: Array[String] = []
		for barrier in _barriers(lot, closed):
			failures.append_array(_reachable_tops(platforms, barrier))
		(
			assert_array(failures)
			. override_failure_message("%s closed: %s" % [closed, failures])
			. is_empty()
		)


func test_the_real_player_cannot_jump_out_of_the_lot_from_a_car_roof() -> void:
	var lot := await LotFixture.make_lot(self, [])
	auto_free(lot.get_parent())
	var tried := 0
	for wall in LotFixture.perimeter(lot):
		var outward := _outward(wall)
		for roof in _roofs_near(lot, wall):
			tried += 1
			var verdict := _push(lot, roof, outward, wall)
			(
				assert_str(verdict)
				. override_failure_message(
					"from the roof at %s towards %s: %s" % [roof, wall.name, verdict]
				)
				. is_empty()
			)
	# The north fence has cars beside it; if none is found the test is not looking.
	assert_int(tried).is_greater(0)


## `door` and every door that needs it, directly or not.
func _with_dependents(door: String, table: Dictionary) -> Array[String]:
	var closed: Array[String] = [door]
	var grew := true
	while grew:
		grew = false
		for item: String in table:
			if not closed.has(item) and closed.has(table[item]):
				closed.append(item)
				grew = true
	return closed


## Spots the walking mesh reaches from the start that are at least `PLATFORM_FROM` high, one for
## each `PLATFORM_CELL` metre cell, at the height of the solid top under them: the mesh floats about
## 0.1 m over what it was baked from, and a car roof (1.65 m) read as 1.75 m is within the reach of
## a 3.0 m fence when it is not.
func _platforms(nav: LotNavigation, lot: Node3D) -> Array[Vector3]:
	var space := lot.get_world_3d().direct_space_state
	var cells := {}
	for vertex in nav.navmesh.get_vertices():
		if vertex.y < PLATFORM_FROM:
			continue
		var cell := Vector3i(
			floori(vertex.x / PLATFORM_CELL),
			floori(vertex.y / PLATFORM_CELL),
			floori(vertex.z / PLATFORM_CELL)
		)
		if cells.has(cell):
			continue
		var way := nav.path(LotFixture.START, vertex)
		if not way.is_empty() and way[way.size() - 1].distance_to(vertex) <= REACHED:
			var ray := PhysicsRayQueryParameters3D.create(
				vertex + Vector3(0, 0.3, 0), vertex - Vector3(0, 0.6, 0)
			)
			ray.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
			var hit := space.intersect_ray(ray)
			cells[cell] = hit["position"] if not hit.is_empty() else vertex
	var platforms: Array[Vector3] = []
	for vertex: Vector3 in cells.values():
		platforms.append(vertex)
	return platforms


## The solid boxes a player must not get onto: the closed doors' slabs, the walls of the areas they
## close, the fence between the field and the yard and back lot, and the perimeter.
func _barriers(lot: Node3D, closed: Array[String]) -> Array[CSGBox3D]:
	var boxes: Array[CSGBox3D] = []
	boxes.append_array(LotFixture.slabs(lot, closed))
	for area: String in LotFixture.AREA_DOOR:
		if closed.has(LotFixture.AREA_DOOR[area]):
			boxes.append_array(LotFixture.walls_of(lot.get_node(area)))
	for fence in lot.get_node("Field").get_children():
		if fence is CSGBox3D and String(fence.name).begins_with("FenceS"):
			boxes.append(fence)
	boxes.append_array(LotFixture.perimeter(lot))
	return boxes


## The first platform from which the body climbs onto `barrier`'s top, described; none when none
## can.
func _reachable_tops(platforms: Array[Vector3], barrier: CSGBox3D) -> Array[String]:
	var found: Array[String] = []
	var top := barrier.global_position.y + barrier.size.y * 0.5
	for platform in platforms:
		var rise := top - platform.y
		if rise > CameraProbe.BODY_REACH:
			continue
		if _distance_to_footprint(platform, barrier) <= _horizontal_reach(maxf(rise, 0.0)):
			found.append("%s (top %.2f) from %s" % [barrier.get_path(), top, platform])
			break
	return found


## How far the body travels sideways, at the fastest ground speed, while it is at least `rise`
## metres above where it jumped: up to the top of the jump, and down again to `rise`.
func _horizontal_reach(rise: float) -> float:
	var tuning := CameraProbe.PLAYER_TUNING
	var gravity := (
		float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * tuning.gravity_scale
	)
	var up := sqrt(2.0 * tuning.jump_height / gravity)
	var down := sqrt(2.0 * maxf(tuning.jump_height - rise, 0.0) / gravity)
	return tuning.sprint_speed * (up + down) + tuning.radius


func _distance_to_footprint(point: Vector3, box: CSGBox3D) -> float:
	var local := box.global_transform.affine_inverse() * point
	var half := box.size * 0.5
	return Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.z) - half.z, 0.0)).length()


## Which way is out for a thin wall: along its thin axis, away from the middle of the lot.
func _outward(wall: CSGBox3D) -> Vector3:
	var from_middle := wall.global_position - Vector3(0, 0, 5)
	if wall.size.x < wall.size.z:
		return Vector3(signf(from_middle.x), 0, 0)
	return Vector3(0, 0, signf(from_middle.z))


## Spots on the roofs of the cars within `ROOF_NEAR` metres of the wall: the middle and the edges
## of each cabin, where a run-up and a jump start.
func _roofs_near(lot: Node3D, wall: CSGBox3D) -> Array[Vector3]:
	var roofs: Array[Vector3] = []
	for cabin in lot.find_children("Cabin", "CSGBox3D", true, false):
		var box := cabin as CSGBox3D
		if _distance_to_footprint(box.global_position, wall) > ROOF_NEAR:
			continue
		var half := box.size * 0.5 - Vector3(ROOF_EDGE, 0, ROOF_EDGE)
		for x in [-half.x, 0.0, half.x]:
			for z in [-half.z, 0.0, half.z]:
				roofs.append(box.global_transform * Vector3(x, box.size.y * 0.5 + 0.02, z))
	return roofs


## Runs the real player body from `start`, sprinting at the wall and jumping the whole time. Returns
## a description when it got past the wall's middle line or stood on top of it, else "".
func _push(lot: Node3D, start: Vector3, outward: Vector3, wall: CSGBox3D) -> String:
	var tuning := CameraProbe.PLAYER_TUNING
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.radius
	capsule.height = tuning.height
	shape.shape = capsule
	shape.position.y = tuning.height * 0.5
	body.add_child(shape)
	body.floor_snap_length = 0.3
	# The player's own mask: the world and the fence's boards.
	body.collision_mask = 1 | Barricade.BOARD_LAYER
	lot.add_child(body)
	var state := PlayerMotionState.new()
	state.position = start
	var command := PlayerCommand.new()
	command.move = Vector2(0, -1)
	command.sprint = true
	command.jump = true
	command.yaw = atan2(-outward.x, -outward.z)
	var delta := 1.0 / Engine.physics_ticks_per_second
	var top := wall.global_position.y + wall.size.y * 0.5
	var verdict := ""
	for tick in ceili(PUSH_SECONDS / delta):
		PlayerSimulation.simulate(body, state, command, tuning, delta)
		var past := (state.position - wall.global_position).dot(outward)
		var on_top := (
			state.position.y >= top - 0.05
			and _distance_to_footprint(state.position, wall) < tuning.radius
		)
		if past > 0.0 or on_top:
			verdict = (
				"got to %s (%.2f m past the middle line, feet at %.2f, wall top %.2f)"
				% [state.position, past, state.position.y, top]
			)
			break
	body.free()
	return verdict
