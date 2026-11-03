# The lot's opening order (docs/design/map.md): with every set of doors the shop can have sold, a
# player reaches exactly the areas those doors open. The proof is a baked navigation mesh, not a ray
# per door, and the doors are sold through the rules and opened by the game's own `LotDoors`, the
# same path the game takes.
extends GdUnitTestSuite

## Metres between the points that judge a closed area: a leak anywhere in its footprint shows.
const GRID_STEP := 4.0


func test_every_area_is_reachable_with_all_doors_open() -> void:
	var lot := await _lot(LotFixture.door_table().keys())
	var nav := LotNavigation.new(lot, CameraProbe.body_radius())
	await nav.settle(get_tree())
	_assert_all_reachable(nav, LotFixture.door_table().keys())


func test_each_area_is_reached_only_through_its_door() -> void:
	var sold_sets := LotFixture.sold_sets()
	assert_int(sold_sets.size()).is_equal(9)
	for sold: Array in sold_sets:
		var lot := await _lot(sold)
		var nav := LotNavigation.new(lot, CameraProbe.body_radius())
		await nav.settle(get_tree())
		_assert_all_reachable(nav, sold)
		for area: String in LotFixture.AREA_POINTS:
			if not LotFixture.is_open(area, sold):
				_assert_no_leak(nav, lot, area, sold)
		lot.get_parent().queue_free()
		await get_tree().process_frame


func test_the_leak_check_catches_a_slab_removed_without_a_purchase() -> void:
	# Negative control: the booth's slab freed by hand, the shop never asked.
	var lot := await _lot(["door_concession"])
	lot.get_node("Doors/Door_ProjectionBooth/Front").free()
	var nav := LotNavigation.new(lot, CameraProbe.body_radius())
	await nav.settle(get_tree())
	assert_str(_leak(nav, lot, "ProjectionBooth")).is_not_empty()
	assert_str(_leak(nav, lot, "Road")).is_empty()


func test_nothing_walkable_lies_past_the_plazas_wall() -> void:
	# The road past the ticket plaza is gone (#686): with every door open the mesh ends at its wall.
	var lot := await _lot(LotFixture.door_table().keys())
	var nav := LotNavigation.new(lot, CameraProbe.body_radius())
	await nav.settle(get_tree())
	var farthest := -INF
	for vertex in nav.navmesh.get_vertices():
		farthest = maxf(farthest, vertex.z)
	assert_float(farthest).is_less(58.0)
	assert_float(farthest).is_greater(55.0)


func test_the_camera_gets_everywhere_the_player_does() -> void:
	# An agent as wide as the shoulder camera's reach on either side of the player (0.75 m + 0.1 m
	# of air, rounded up): if a passage were narrower than 1.8 m, this agent could not cross it and
	# an area would drop out.
	var lot := await _lot(LotFixture.door_table().keys())
	var nav := LotNavigation.new(
		lot, CameraProbe.shoulder_offset() + CameraProbe.CAMERA_CLEAR + 0.05
	)
	await nav.settle(get_tree())
	_assert_all_reachable(nav, LotFixture.door_table().keys())


## Every sample point of every area `sold` opens is reachable from the start.
func _assert_all_reachable(nav: LotNavigation, sold: Array) -> void:
	for area: String in LotFixture.AREA_POINTS:
		if not LotFixture.is_open(area, sold):
			continue
		for point: Vector3 in LotFixture.AREA_POINTS[area]:
			var message := "sold %s, area %s at %s" % [sold, area, point]
			(
				assert_bool(nav.can_reach(LotFixture.START, point, LotFixture.REACHED))
				. override_failure_message(message)
				. is_true()
			)


## No point of a closed area's footprint is reached: the way to each grid point, and to the samples
## of the area, never enters the footprint.
func _assert_no_leak(nav: LotNavigation, lot: Node3D, area: String, sold: Array) -> void:
	var leak := _leak(nav, lot, area)
	assert_str(leak).override_failure_message("sold %s: %s" % [sold, leak]).is_empty()


## A description of the first way into `area`'s footprint, or "" when there is none.
func _leak(nav: LotNavigation, lot: Node3D, area: String) -> String:
	var footprint := LotFixture.footprint(lot, area)
	assert_int(footprint.size()).override_failure_message(area).is_greater(0)
	var targets := LotFixture.grid(footprint, GRID_STEP)
	targets.append_array(LotFixture.AREA_POINTS[area])
	for target in targets:
		for point in LotFixture.along(nav.path(LotFixture.START, target)):
			if LotFixture.inside(footprint, point):
				return "a way towards %s enters %s at %s" % [target, area, point]
	return ""


## The lot with `sold` bought through the rules, built and ready, in a world of its own.
func _lot(sold: Array) -> Node3D:
	var lot := await LotFixture.make_lot(self, sold)
	auto_free(lot.get_parent())
	return lot
