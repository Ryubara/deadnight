extends GdUnitTestSuite
## The hit zones: which zone a ray finds, from where, and the shapes' edge cases.


func _zone_at(height: float, x: float = 0.0, yaw: float = 0.0) -> StringName:
	var origin := Vector3(x, height, 6)
	var hit := Hitbox.ray(origin, Vector3(0, 0, -1), 20.0, Vector3.ZERO, yaw)
	return hit.get("zone", &"")


func test_head_body_and_legs_are_where_a_zombie_has_them() -> void:
	assert_str(_zone_at(1.65)).is_equal("head")
	assert_str(_zone_at(1.1)).is_equal("body")
	assert_str(_zone_at(0.4)).is_equal("limb")


func test_arms_are_limbs_beside_the_body() -> void:
	assert_str(_zone_at(1.15, 0.40)).is_equal("limb")
	assert_str(_zone_at(1.15, -0.40)).is_equal("limb")


func test_arms_turn_with_the_zombie() -> void:
	# Turned a quarter, the arms lie in front and behind: the old arm spot is empty air.
	assert_str(_zone_at(1.15, 0.40, PI / 2.0)).is_equal("")
	assert_str(_zone_at(1.15, 0.0, PI / 2.0)).is_not_equal("")


func test_above_beside_and_a_mile_away_miss() -> void:
	assert_str(_zone_at(2.4)).is_equal("")
	assert_str(_zone_at(1.1, 1.5)).is_equal("")
	var far := Hitbox.ray(Vector3(0, 1.1, 500), Vector3(0, 0, -1), 20.0, Vector3.ZERO, 0.0)
	assert_bool(far.is_empty()).is_true()


func test_a_ray_that_stops_short_misses() -> void:
	var hit := Hitbox.ray(Vector3(0, 1.1, 6), Vector3(0, 0, -1), 3.0, Vector3.ZERO, 0.0)
	assert_bool(hit.is_empty()).is_true()


func test_the_distance_is_to_the_first_surface() -> void:
	var hit := Hitbox.ray(Vector3(0, 1.1, 6), Vector3(0, 0, -1), 20.0, Vector3.ZERO, 0.0)
	assert_float(hit["distance"]).is_equal_approx(6.0 - 0.26, 0.001)


func test_a_ray_down_the_axis_of_a_capsule_still_hits() -> void:
	var t := HitShapes.ray_capsule(
		Vector3(0, 5, 0), Vector3.DOWN, Vector3(0, 0, 0), Vector3(0, 1, 0), 0.3
	)
	assert_float(t).is_equal_approx(3.7, 0.001)


func test_a_ray_that_starts_inside_answers_zero() -> void:
	var t := HitShapes.ray_capsule(
		Vector3(0, 0.5, 0), Vector3.RIGHT, Vector3(0, 0, 0), Vector3(0, 1, 0), 0.3
	)
	assert_float(t).is_equal(0.0)


func test_fattening_the_shapes_catches_a_near_miss() -> void:
	var origin := Vector3(0.6, 1.1, 6)
	var thin := Hitbox.ray(origin, Vector3(0, 0, -1), 20.0, Vector3.ZERO, 0.0)
	var fat := Hitbox.ray(origin, Vector3(0, 0, -1), 20.0, Vector3.ZERO, 0.0, 0.3)
	assert_bool(thin.is_empty()).is_true()
	assert_bool(fat.is_empty()).is_false()


func test_a_blast_distance_is_zero_inside_and_grows_outside() -> void:
	assert_float(Hitbox.distance_from(Vector3(0, 1.1, 0), Vector3.ZERO, 0.0)).is_equal(0.0)
	var one_out := Hitbox.distance_from(Vector3(1.26, 1.1, 0), Vector3.ZERO, 0.0)
	assert_float(one_out).is_less(1.0)
	assert_float(one_out).is_greater(0.4)
