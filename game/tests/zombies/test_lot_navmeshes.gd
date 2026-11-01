# The lot's zombie navigation meshes are baked ahead of time (`LotNavmeshes`, #335) because baking
# one takes 11 to 13 s in one frame in the browser. This suite is what keeps the saved file honest:
# it fails when the lot's geometry changed and `tools/world/bake_lot_navmeshes.gd` was not run, and
# it shows a saved mesh is the very mesh the baker makes, so the dead walk the paths they did.
extends GdUnitTestSuite

const BAKE_FRAMES := 1800
const RERUN := "the lot's geometry changed: run tools/world/bake_lot_navmeshes.gd"

var _saved: LotNavmeshes


func before_test() -> void:
	_saved = LotNavmeshes.shared()


func _lot(sold: Array) -> Node3D:
	var lot := await LotFixture.make_lot(self, sold)
	auto_free(lot.get_parent())
	return lot


func test_the_meshes_are_saved() -> void:
	assert_object(_saved).override_failure_message("%s missing" % LotNavmeshes.PATH).is_not_null()


func test_every_set_of_doors_the_shop_can_sell_has_a_saved_mesh() -> void:
	for sold: Array in LotFixture.sold_sets():
		var lot := await _lot(sold)
		(
			assert_object(_saved.mesh_for(lot))
			. override_failure_message("doors %s: %s" % [sold, RERUN])
			. is_not_null()
		)
		lot.get_parent().queue_free()
		await get_tree().process_frame


func test_the_file_holds_one_mesh_for_each_set_and_no_stale_ones() -> void:
	assert_int(_saved.meshes.size()).override_failure_message(RERUN).is_equal(
		LotFixture.sold_sets().size()
	)


func test_a_lot_that_changed_finds_no_saved_mesh() -> void:
	var lot := await _lot([])
	var wall := _a_wall(lot)
	wall.position.x += 0.1
	assert_object(_saved.mesh_for(lot)).is_null()


func test_float_noise_below_a_millimetre_still_finds_the_mesh() -> void:
	var lot := await _lot([])
	var wall := _a_wall(lot)
	wall.position.x += 0.0001
	assert_object(_saved.mesh_for(lot)).is_not_null()


func test_a_saved_mesh_is_what_the_baker_makes_from_the_lot() -> void:
	for sold: Array in LotFixture.sold_sets():
		var lot := await _lot(sold)
		var saved := _saved.mesh_for(lot)
		var baked := NavmeshBaker.bake(lot)
		assert_object(saved).override_failure_message("doors %s: %s" % [sold, RERUN]).is_not_null()
		if saved == null:
			continue
		assert_int(saved.get_polygon_count()).is_equal(baked.get_polygon_count())
		assert_bool(saved.get_vertices() == baked.get_vertices()).is_true()
		for i in baked.get_polygon_count():
			if saved.get_polygon(i) != baked.get_polygon(i):
				fail("doors %s: polygon %d differs" % [sold, i])
				break
		lot.get_parent().queue_free()
		await get_tree().process_frame


func test_the_night_puts_the_saved_mesh_in_without_baking() -> void:
	var lot := await _lot([])
	var navigation := DoorNavigation.new()
	lot.add_child(navigation)
	navigation.setup(lot, lot.get_node("Doors"))
	await _reaches(lot, Vector3(0, 0, -30))
	assert_int(navigation.bake_count).is_equal(1)
	var concession: Vector3 = LotFixture.AREA_POINTS["Concession"][0]
	assert_bool(_reachable(lot, concession)).is_false()
	var swapped := [0]
	navigation.baked.connect(func() -> void: swapped[0] += 1)
	RulesFixture.buy(lot.get_meta(&"rules"), 1, &"door_concession")
	# At once, in the frame the door opens: no worker, nothing to wait for.
	assert_bool(navigation.is_busy()).is_false()
	assert_int(swapped[0]).is_equal(1)
	assert_int(navigation.bake_count).is_equal(2)
	await _reaches(lot, concession)
	assert_bool(_reachable(lot, concession)).is_true()


func test_a_lot_with_no_saved_mesh_is_baked_as_before() -> void:
	var lot := await _lot([])
	var navigation := DoorNavigation.new()
	navigation.saved = LotNavmeshes.new()
	lot.add_child(navigation)
	navigation.setup(lot, lot.get_node("Doors"))
	RulesFixture.buy(lot.get_meta(&"rules"), 1, &"door_concession")
	assert_bool(navigation.is_busy()).is_true()
	for i in BAKE_FRAMES:
		if not navigation.is_busy():
			break
		await get_tree().physics_frame
	assert_int(navigation.bake_count).is_equal(2)


## A box of the lot with collision.
func _a_wall(lot: Node3D) -> CSGBox3D:
	for box in lot.find_children("*", "CSGBox3D", true, false):
		if (box as CSGBox3D).use_collision:
			return box as CSGBox3D
	return null


func _reachable(lot: Node3D, to: Vector3) -> bool:
	var way := NavmeshPathing.new(lot.get_world_3d().navigation_map).find_path(LotFixture.START, to)
	return not way.is_empty() and way[way.size() - 1].distance_to(to) < LotFixture.REACHED


## Waits until the map answers for `to` (a mesh reaches the map a few physics ticks later).
func _reaches(lot: Node3D, to: Vector3) -> void:
	for i in BAKE_FRAMES:
		if _reachable(lot, to):
			return
		await get_tree().physics_frame
