# The playable space of each map, read from its scene (`PlayBounds`, issue #862): every place a
# player can be on is inside it (the starts, the dead's spawns, the shops, each door's stands), and
# every place past the fences is outside. The second half asks the physics: from above, the first
# solid thing under each point of a grid is the map's own (the point is inside) or the horizon slab
# or nothing (outside), and the bounds must say the same at every point of the grid.
extends GdUnitTestSuite

const LOT := preload("res://world/drive_in_greybox.tscn")
const SMALL := preload("res://world/smallmap/smallmap_greybox.tscn")
const SETTLE_FRAMES := 4
## Where the ray starts (above the tallest piece, the screen) and ends.
const RAY_TOP := 60.0
const RAY_BOTTOM := -30.0
## Metres between two probed points, and the offset that keeps them off the edges of the pieces.
const GRID := 1.0
const GRID_SHIFT := 0.37
## How far past the pieces the grid reaches on each side.
const GRID_MARGIN := 14.0
## Points on the horizon slab beside the lot's road and past its ends, and in the notches of the
## aprons: not in the lot.
const LOT_OUTSIDE: Array[Vector3] = [
	Vector3(40.0, 0.0, 50.0),
	Vector3(-40.0, 0.0, 50.0),
	Vector3(0.0, 0.0, 66.0),
	Vector3(0.0, 0.0, -66.0),
	Vector3(75.0, 0.0, -20.0),
	Vector3(-75.0, 0.0, -20.0),
	Vector3(66.0, 0.0, -34.0),
	Vector3(-66.0, 0.0, -34.0),
	Vector3(27.0, 0.0, 44.0),
	Vector3(100.0, 0.0, 100.0),
]
## Points in the lot's corners and ends that are inside: the aprons' ends and the road's.
const LOT_INSIDE: Array[Vector3] = [
	Vector3(66.0, 0.0, 6.0),
	Vector3(-66.0, 0.0, 34.0),
	Vector3(36.0, 0.0, 42.0),
	Vector3(20.0, 0.0, 49.5),
	Vector3(-66.0, 0.0, -46.0),
	Vector3(66.0, 0.0, -46.0),
	Vector3(-36.0, 0.0, -56.0),
	Vector3(0.0, 0.0, 56.0),
	Vector3(61.0, 0.0, 37.0),
	Vector3(-61.0, 0.0, 37.0),
]
const SMALL_OUTSIDE: Array[Vector3] = [
	Vector3(40.0, 0.0, 0.0),
	Vector3(-40.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 40.0),
	Vector3(0.0, 0.0, -40.0),
	Vector3(0.0, -20.0, 0.0),
]
const SMALL_INSIDE: Array[Vector3] = [
	Vector3(7.0, 0.0, 10.5),
	Vector3(0.0, 0.0, 0.0),
	Vector3(-25.0, 0.0, 10.0),
]


func _scene(packed: PackedScene) -> Node3D:
	var scene := auto_free(packed.instantiate()) as Node3D
	add_child(scene)
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	return scene


func test_the_lot_is_bounded_by_its_floors_and_fences_not_by_the_horizon_slab() -> void:
	var scene := await _scene(LOT)
	var bounds := PlayBounds.of(scene)
	assert_bool(bounds.is_empty()).is_false()
	for point in LOT_OUTSIDE:
		assert_bool(bounds.is_out(point)).override_failure_message("%s is inside" % point).is_true()
	for point in LOT_INSIDE:
		assert_bool(bounds.is_out(point)).override_failure_message("%s is out" % point).is_false()


func test_the_small_map_is_bounded_and_a_fall_is_out_wherever_it_is() -> void:
	var scene := await _scene(SMALL)
	var bounds := PlayBounds.of(scene)
	for point in SMALL_OUTSIDE:
		assert_bool(bounds.is_out(point)).override_failure_message("%s is inside" % point).is_true()
	for point in SMALL_INSIDE:
		assert_bool(bounds.is_out(point)).override_failure_message("%s is out" % point).is_false()
	# Under the lowest floor by more than the depth: out above the map's own footprint too.
	assert_bool(bounds.is_out(Vector3(7.0, -PlayBounds.DEPTH - 1.0, 10.5))).is_true()


func test_a_scene_with_nothing_solid_has_no_bounds_and_nobody_is_out() -> void:
	var scene := auto_free(Node3D.new()) as Node3D
	add_child(scene)
	var bounds := PlayBounds.of(scene)
	assert_bool(bounds.is_empty()).is_true()
	assert_bool(bounds.is_out(Vector3(500.0, -500.0, 500.0))).is_false()


func test_every_place_the_map_is_played_at_is_inside_in_both_maps() -> void:
	for packed: PackedScene in [LOT, SMALL]:
		var scene := await _scene(packed)
		var bounds := PlayBounds.of(scene)
		var places: Array[Node3D] = []
		for group in ["PlayerSpawns", "ZombieSpawns", "ShopSpots", "FuelSpots"]:
			for holder in scene.find_children(group, "Node3D", true, false):
				for child in holder.get_children():
					places.append(child as Node3D)
		assert_int(places.size()).is_greater(20)
		for place in places:
			(
				assert_bool(bounds.is_out(place.global_position))
				. override_failure_message(
					"%s of %s is out at %s" % [place.name, scene.name, place.global_position]
				)
				. is_false()
			)


## The physics' answer for the point `(x, z)`: whether the first solid thing under it is a piece of
## the map. The horizon slab and nothing at all are not.
func _under_it_is_the_map(space: PhysicsDirectSpaceState3D, x: float, z: float) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, RAY_TOP, z), Vector3(x, RAY_BOTTOM, z)
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit["collider"] as Node
	return collider != null and collider.name != PlayBounds.OUTSKIRTS


func _sweep(packed: PackedScene) -> Dictionary:
	var scene := await _scene(packed)
	var bounds := PlayBounds.of(scene)
	var space := scene.get_world_3d().direct_space_state
	var first := Vector2(INF, INF)
	var last := Vector2(-INF, -INF)
	for shape in scene.find_children("*", "CSGBox3D", true, false):
		if shape.name == PlayBounds.OUTSKIRTS:
			continue
		var at := (shape as Node3D).global_position
		first = Vector2(minf(first.x, at.x), minf(first.y, at.z))
		last = Vector2(maxf(last.x, at.x), maxf(last.y, at.z))
	first -= Vector2.ONE * GRID_MARGIN
	last += Vector2.ONE * GRID_MARGIN
	var inside := 0
	var outside := 0
	var wrong: Array[String] = []
	var mismatches := 0
	var x := first.x + GRID_SHIFT
	while x < last.x:
		var z := first.y + GRID_SHIFT
		while z < last.y:
			var map_there := _under_it_is_the_map(space, x, z)
			# Feet on whatever is under them; the horizon slab is below the lot's floor.
			var out := bounds.is_out(Vector3(x, 0.0, z))
			if map_there:
				inside += 1
			else:
				outside += 1
			if out == map_there:
				mismatches += 1
				if wrong.size() < 12:
					wrong.append("(%.2f, %.2f) map under it: %s, out: %s" % [x, z, map_there, out])
			z += GRID
		x += GRID
	return {"inside": inside, "outside": outside, "wrong": wrong, "mismatches": mismatches}


func test_the_bounds_agree_with_the_physics_at_every_point_of_the_lot() -> void:
	var result := await _sweep(LOT)
	assert_int(result["inside"]).is_greater(8000)
	assert_int(result["outside"]).is_greater(2000)
	(
		assert_array(result["wrong"])
		. override_failure_message(
			"%d points disagree, first: %s" % [result["mismatches"], result["wrong"]]
		)
		. is_empty()
	)


func test_the_bounds_agree_with_the_physics_at_every_point_of_the_small_map() -> void:
	var result := await _sweep(SMALL)
	assert_int(result["inside"]).is_greater(1500)
	assert_int(result["outside"]).is_greater(500)
	(
		assert_array(result["wrong"])
		. override_failure_message(
			"%d points disagree, first: %s" % [result["mismatches"], result["wrong"]]
		)
		. is_empty()
	)
