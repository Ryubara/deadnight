extends GdUnitTestSuite
## A solid box the dead stand outside of (the prize crane's cabinet, #1352): what is inside it and
## where a dead inside is put, on a box turned off the axes as the crane stands at its spots.

const SIZE := Vector3(1.8, 2.6, 1.4)
## Its middle, turned a quarter, so its width runs along z.
const AT := Vector3(10.0, 0.0, 4.0)


func _box() -> ZombieSolid:
	var solid := ZombieSolid.new()
	solid.place(Transform3D(Basis(Vector3.UP, PI * 0.5), AT), SIZE)
	return solid


func test_a_box_that_stands_nowhere_holds_no_one() -> void:
	var solid := ZombieSolid.new()
	assert_bool(solid.contains(AT)).is_false()
	solid = _box()
	solid.clear()
	assert_bool(solid.contains(AT)).is_false()


func test_the_footprint_is_the_box_turned_with_it() -> void:
	var solid := _box()
	# Turned a quarter: 1.8 m wide along z, 1.4 m deep along x.
	assert_bool(solid.contains(AT + Vector3(0.6, 0.0, 0.8))).is_true()
	assert_bool(solid.contains(AT + Vector3(0.8, 0.0, 0.6))).is_false()
	assert_bool(solid.contains(AT + Vector3(0.0, 0.0, -0.85))).is_true()
	assert_bool(solid.contains(AT + Vector3(0.0, 0.0, -0.95))).is_false()


func test_a_point_over_the_box_or_far_under_it_is_outside() -> void:
	var solid := _box()
	assert_bool(solid.contains(AT + Vector3(0.0, 2.7, 0.0))).is_false()
	assert_bool(solid.contains(AT + Vector3(0.0, -0.05, 0.0))).is_true()
	assert_bool(solid.contains(AT + Vector3(0.0, -1.0, 0.0))).is_false()


func test_a_dead_inside_is_put_outside_the_nearest_face_at_its_own_height() -> void:
	var solid := _box()
	var near_end := AT + Vector3(0.1, -0.05, 0.8)
	var out := solid.outside(near_end)
	assert_float(out.z).is_equal_approx(AT.z + 0.9 + ZombieSolid.CLEARANCE, 0.001)
	assert_float(out.x).is_equal_approx(near_end.x, 0.001)
	assert_float(out.y).is_equal_approx(-0.05, 0.001)
	assert_bool(solid.contains(out)).is_false()
	var near_side := AT + Vector3(-0.6, 0.0, 0.1)
	out = solid.outside(near_side)
	assert_float(out.x).is_equal_approx(AT.x - 0.7 - ZombieSolid.CLEARANCE, 0.001)
	assert_bool(solid.contains(out, 0.0)).is_false()


func test_a_dead_with_a_target_comes_out_on_the_target_s_side() -> void:
	var solid := _box()
	# Nearest face is the end at +z, but the target stands at -x of the box.
	var inside := AT + Vector3(0.1, -0.05, 0.6)
	var out := solid.outside(inside, AT + Vector3(-3.0, 0.0, 0.0))
	assert_float(out.x).is_equal_approx(AT.x - 0.7 - ZombieSolid.CLEARANCE, 0.001)
	assert_float(out.z).is_equal_approx(inside.z, 0.001)
	out = solid.outside(inside, AT + Vector3(0.0, 0.0, 3.0))
	assert_float(out.z).is_equal_approx(AT.z + 0.9 + ZombieSolid.CLEARANCE, 0.001)
	out = solid.outside(inside, AT + Vector3(0.0, 0.0, -3.0))
	assert_float(out.z).is_equal_approx(AT.z - 0.9 - ZombieSolid.CLEARANCE, 0.001)
	assert_bool(solid.contains(out)).is_false()


func test_placing_it_again_counts_a_new_landing() -> void:
	var solid := _box()
	var before := solid.generation
	solid.place(Transform3D(Basis.IDENTITY, AT), SIZE)
	assert_int(solid.generation).is_equal(before + 1)
