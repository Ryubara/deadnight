extends GdUnitTestSuite
## The hit zones: which zone a ray finds, from where, and the shapes' edge cases.


## The zone a ray down -z finds on the simple standing set (`Hitbox.STANDING`).
func _zone_at(height: float, x: float = 0.0, yaw: float = 0.0) -> StringName:
	var origin := Vector3(x, height, 6)
	var hit := _ray(origin, 20.0, yaw)
	return hit.get("zone", &"")


func _ray(origin: Vector3, reach: float, yaw: float = 0.0, inflate: float = 0.0) -> Dictionary:
	return Hitbox.ray(
		origin, Vector3(0, 0, -1), reach, Vector3.ZERO, yaw, inflate, 1.0, false, Hitbox.STANDING
	)


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
	assert_bool(_ray(Vector3(0, 1.1, 500), 20.0).is_empty()).is_true()


func test_a_ray_that_stops_short_misses() -> void:
	assert_bool(_ray(Vector3(0, 1.1, 6), 3.0).is_empty()).is_true()


func test_the_distance_is_to_the_first_surface() -> void:
	var hit := _ray(Vector3(0, 1.1, 6), 20.0)
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
	var thin := _ray(origin, 20.0)
	var fat := _ray(origin, 20.0, 0.0, 0.3)
	assert_bool(thin.is_empty()).is_true()
	assert_bool(fat.is_empty()).is_false()


func test_a_blast_distance_is_zero_inside_and_grows_outside() -> void:
	assert_float(Hitbox.distance_from(Vector3(0, 1.1, 0), Vector3.ZERO, 0.0)).is_equal(0.0)
	var one_out := Hitbox.distance_from(Vector3(1.26, 1.1, 0), Vector3.ZERO, 0.0)
	assert_float(one_out).is_less(1.0)
	assert_float(one_out).is_greater(0.4)


func test_a_limb_in_front_gives_way_to_the_body_and_head_behind_it() -> void:
	# A ray that meets an arm and, a hand's width behind, the torso is a torso shot; one that meets
	# an arm and nothing else is a limb shot.
	var arm_over_body := {
		"zone": &"limb", "a": Vector3(0, 1.0, 0.3), "b": Vector3(0, 1.0, 0.3), "r": 0.1
	}
	var torso := {"zone": &"body", "a": Vector3(0, 1.0, 0.0), "b": Vector3(0, 1.0, 0.0), "r": 0.25}
	var head := {"zone": &"head", "a": Vector3(0, 1.0, -0.3), "b": Vector3(0, 1.0, -0.3), "r": 0.2}
	var lone := {"shapes": [arm_over_body], "bound_centre": Vector3(0, 1, 0), "bound_radius": 1.0}
	var covered := {
		"shapes": [arm_over_body, torso], "bound_centre": Vector3(0, 1, 0), "bound_radius": 1.0
	}
	var all := {
		"shapes": [arm_over_body, torso, head],
		"bound_centre": Vector3(0, 1, 0),
		"bound_radius": 1.0
	}
	var origin := Vector3(0, 1.0, 5)
	var dir := Vector3(0, 0, -1)
	assert_str(Hitbox.ray_in(lone, origin, dir, 20.0, Vector3.ZERO, 0.0)["zone"]).is_equal("limb")
	assert_str(Hitbox.ray_in(covered, origin, dir, 20.0, Vector3.ZERO, 0.0)["zone"]).is_equal(
		"body"
	)
	assert_str(Hitbox.ray_in(all, origin, dir, 20.0, Vector3.ZERO, 0.0)["zone"]).is_equal("body")
	# The distance is to the first surface, the arm's, whichever zone is counted.
	var hit := Hitbox.ray_in(covered, origin, dir, 20.0, Vector3.ZERO, 0.0)
	assert_float(hit["distance"]).is_equal_approx(5.0 - 0.4, 0.001)


func test_a_pose_the_set_does_not_have_falls_back_to_the_bodys_moving_set() -> void:
	assert_bool(is_same(Hitbox.fitted(&"crawler.tear"), Hitbox.fitted(&"crawler.move"))).is_true()
	(
		assert_bool(is_same(Hitbox.fitted(&"unknown.move"), Hitbox.fitted(Hitbox.DEFAULT_SET)))
		. is_true()
	)
	assert_bool(is_same(Hitbox.fitted(&"walker.tear"), Hitbox.fitted(&"walker.move"))).is_false()


func test_every_fitted_set_has_shapes_for_the_head_and_the_body() -> void:
	for id: StringName in HitPoseData.sets():
		var zones := {}
		for shape: Dictionary in HitPoseData.sets()[id]["shapes"]:
			zones[shape["zone"]] = true
		assert_bool(zones.has(Hitbox.HEAD)).is_true()
		assert_bool(zones.has(Hitbox.BODY)).is_true()
		assert_bool(zones.has(Hitbox.LIMB)).is_true()
