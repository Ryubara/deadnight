extends GdUnitTestSuite
## Where a shot goes: the camera aim, the muzzle check at corners, pellets and penetration.

## An over-the-shoulder rig: the camera is behind and to the right of the muzzle.
const CAMERA := Vector3(0.8, 1.9, 2.5)
const MUZZLE := Vector3(0.3, 1.45, -0.4)
## A wall at z = -3 that ends at x = 1.1.
const WALL := AABB(Vector3(-5, 0, -3.1), Vector3(6.1, 2.2, 0.2))


func _shoot(def: WeaponDef, target_x: float, world: Callable, seed_value: int = 1) -> Dictionary:
	var targets := WeaponsFixture.targets_of({1: Vector3(target_x, 0, -8)})
	var dir := (Vector3(target_x, 1.1, -8) - CAMERA).normalized()
	return AimResolver.trace_hitscan(def, CAMERA, dir, MUZZLE, targets, world, seed_value)


func test_a_shot_from_the_shoulder_hits_what_the_crosshair_is_on() -> void:
	var shot := _shoot(WeaponsFixture.def(&"pistol"), 3.5, Callable())
	var hits: Array = shot["pellets"][0]["hits"]
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0]["target_id"]).is_equal(1)


func test_a_corner_between_the_muzzle_and_the_target_stops_the_shot() -> void:
	var world := WeaponsFixture.box_world(WALL)
	# The camera sees past the wall's end; the muzzle, further left, does not.
	var target_x := 2.0
	var camera_x_at_wall := CAMERA.x + (target_x - CAMERA.x) * (5.5 / 10.5)
	assert_float(camera_x_at_wall).is_greater(1.1)
	var shot := _shoot(WeaponsFixture.def(&"pistol"), target_x, world)
	var pellet: Dictionary = shot["pellets"][0]
	assert_array(pellet["hits"]).is_empty()
	assert_float(pellet["end"].z).is_equal_approx(-2.9, 0.05)


func test_the_same_shot_without_the_corner_hits() -> void:
	var shot := _shoot(WeaponsFixture.def(&"pistol"), 2.0, Callable())
	assert_array(shot["pellets"][0]["hits"]).has_size(1)


func test_a_target_clear_of_the_corner_is_hit_with_the_wall_there() -> void:
	var shot := _shoot(WeaponsFixture.def(&"pistol"), 3.5, WeaponsFixture.box_world(WALL))
	assert_array(shot["pellets"][0]["hits"]).has_size(1)


func test_a_wall_in_front_of_the_camera_ray_is_what_the_shot_hits() -> void:
	var wall := AABB(Vector3(-5, 0, -4.1), Vector3(10, 3, 0.2))
	var shot := _shoot(WeaponsFixture.def(&"pistol"), 0.0, WeaponsFixture.box_world(wall))
	var pellet: Dictionary = shot["pellets"][0]
	assert_array(pellet["hits"]).is_empty()
	assert_float(pellet["end"].z).is_equal_approx(-3.9, 0.05)


func test_something_between_the_camera_and_the_shooter_is_ignored() -> void:
	# A zombie standing at the camera's feet is behind the muzzle: the aim skips it.
	var targets := WeaponsFixture.targets_of({1: Vector3(0.8, 0, 2.0), 2: Vector3(0.3, 0, -6)})
	var pistol := WeaponsFixture.def(&"pistol")
	var dir := Vector3(-0.5, -0.35, -8.5).normalized() * -1.0 * -1.0
	var aim := Vector3(0.3, 1.1, -6) - Vector3(0.8, 1.9, 2.5)
	dir = aim.normalized()
	var pellet := AimResolver.trace_one(
		pistol, Vector3(0.8, 1.9, 2.5), dir, MUZZLE, targets, Callable()
	)
	assert_array(pellet["hits"]).has_size(1)
	assert_int(pellet["hits"][0]["target_id"]).is_equal(2)


func test_a_shot_at_nothing_ends_at_the_weapons_range() -> void:
	var pistol := WeaponsFixture.def(&"pistol")
	var pellet := AimResolver.trace_one(pistol, CAMERA, Vector3(0, 0, -1), MUZZLE, {}, Callable())
	assert_array(pellet["hits"]).is_empty()
	assert_float(MUZZLE.distance_to(pellet["end"])).is_equal_approx(pistol.max_range, 0.01)


func test_a_hit_beyond_the_range_does_not_count() -> void:
	var pistol := WeaponsFixture.def(&"pistol")
	var targets := WeaponsFixture.targets_of({1: Vector3(0.3, 0, -100)})
	var dir := (Vector3(0.3, 1.1, -100) - CAMERA).normalized()
	var pellet := AimResolver.trace_one(pistol, CAMERA, dir, MUZZLE, targets, Callable())
	assert_array(pellet["hits"]).is_empty()


func test_a_headshot_reports_the_head_and_its_damage() -> void:
	var pistol := WeaponsFixture.def(&"pistol")
	var targets := WeaponsFixture.targets_of({1: Vector3.ZERO})
	var from := Vector3(0, 1.62, 6)
	var pellet := AimResolver.trace_one(pistol, from, Vector3(0, 0, -1), from, targets, Callable())
	var hit: Dictionary = pellet["hits"][0]
	assert_str(hit["zone"]).is_equal("head")
	assert_float(hit["damage"]).is_equal_approx(pistol.damage * 2.5, 0.01)


func test_the_rifle_goes_through_two_bodies_and_stops_in_the_third() -> void:
	var rifle := WeaponsFixture.def(&"rifle")
	var targets := WeaponsFixture.targets_of(
		{1: Vector3(0, 0, 0), 2: Vector3(0, 0, -2), 3: Vector3(0, 0, -4), 4: Vector3(0, 0, -6)}
	)
	var from := Vector3(0, 1.1, 6)
	var pellet := AimResolver.trace_one(rifle, from, Vector3(0, 0, -1), from, targets, Callable())
	var hits: Array = pellet["hits"]
	assert_int(hits.size()).is_equal(3)
	assert_int(hits[0]["target_id"]).is_equal(1)
	assert_int(hits[2]["target_id"]).is_equal(3)
	assert_float(hits[1]["damage"]).is_equal_approx(
		hits[0]["damage"] * rifle.penetration_falloff, 0.01
	)
	assert_float(from.distance_to(pellet["end"])).is_equal_approx(hits[2]["distance"], 0.01)


func test_a_wall_stops_a_penetrating_shot() -> void:
	var rifle := WeaponsFixture.def(&"rifle")
	var targets := WeaponsFixture.targets_of({1: Vector3(0, 0, 0), 2: Vector3(0, 0, -4)})
	var wall := AABB(Vector3(-2, 0, -2.1), Vector3(4, 3, 0.2))
	var from := Vector3(0, 1.1, 6)
	var pellet := AimResolver.trace_one(
		rifle, from, Vector3(0, 0, -1), from, targets, WeaponsFixture.box_world(wall)
	)
	assert_int(pellet["hits"].size()).is_equal(1)


func test_a_shotgun_throws_its_pellets_in_a_cone() -> void:
	var shotgun := WeaponsFixture.def(&"shotgun")
	var dirs := AimResolver.spread_dirs(shotgun, Vector3(0, 0, -1), 5)
	assert_int(dirs.size()).is_equal(shotgun.pellets)
	var widest := 0.0
	for dir in dirs:
		widest = maxf(widest, rad_to_deg(dir.angle_to(Vector3(0, 0, -1))))
	assert_float(widest).is_less_equal(shotgun.spread_deg + 0.001)
	assert_float(widest).is_greater(1.0)


func test_the_spread_is_the_same_for_the_same_seed_and_new_for_another() -> void:
	var shotgun := WeaponsFixture.def(&"shotgun")
	var one := AimResolver.spread_dirs(shotgun, Vector3(0, 0, -1), 5)
	var again := AimResolver.spread_dirs(shotgun, Vector3(0, 0, -1), 5)
	var other := AimResolver.spread_dirs(shotgun, Vector3(0, 0, -1), 6)
	assert_array(one).is_equal(again)
	assert_array(one).is_not_equal(other)


func test_a_shot_seed_depends_on_the_match_the_shooter_and_the_shot() -> void:
	var base := AimResolver.shot_seed(7, 1, 1)
	assert_int(AimResolver.shot_seed(7, 1, 1)).is_equal(base)
	assert_int(AimResolver.shot_seed(7, 1, 2)).is_not_equal(base)
	assert_int(AimResolver.shot_seed(7, 2, 1)).is_not_equal(base)
	assert_int(AimResolver.shot_seed(8, 1, 1)).is_not_equal(base)


func test_a_precise_weapon_has_no_spread() -> void:
	var rifle := WeaponsFixture.def(&"rifle")
	var dirs := AimResolver.spread_dirs(rifle, Vector3(0, 0, -1), 1)
	assert_array(dirs).is_equal([Vector3(0, 0, -1)])


func test_a_melee_sweep_reaches_a_close_zombie_and_not_a_far_one() -> void:
	var crowbar := WeaponsFixture.def(&"crowbar")
	var near := WeaponsFixture.targets_of({1: Vector3(0, 0, -1.4)})
	var far := WeaponsFixture.targets_of({1: Vector3(0, 0, -3.5)})
	var from := Vector3(0, 1.1, 0)
	(
		assert_array(AimResolver.sweep_melee(crowbar, from, Vector3(0, 0, -1), near, Callable()))
		. has_size(1)
	)
	(
		assert_array(AimResolver.sweep_melee(crowbar, from, Vector3(0, 0, -1), far, Callable()))
		. is_empty()
	)


func test_a_melee_sweep_is_fat_enough_to_catch_a_zombie_off_the_line() -> void:
	var crowbar := WeaponsFixture.def(&"crowbar")
	var beside := WeaponsFixture.targets_of({1: Vector3(0.5, 0, -1.2)})
	var hits := AimResolver.sweep_melee(
		crowbar, Vector3(0, 1.1, 0), Vector3(0, 0, -1), beside, Callable()
	)
	assert_array(hits).has_size(1)
	var wide := WeaponsFixture.targets_of({1: Vector3(1.5, 0, -1.2)})
	(
		assert_array(
			AimResolver.sweep_melee(
				crowbar, Vector3(0, 1.1, 0), Vector3(0, 0, -1), wide, Callable()
			)
		)
		. is_empty()
	)


func test_a_melee_swing_hits_at_most_its_target_count_nearest_first() -> void:
	var crowbar := WeaponsFixture.def(&"crowbar")
	var line := WeaponsFixture.targets_of(
		{1: Vector3(0, 0, -1.6), 2: Vector3(0, 0, -1.0), 3: Vector3(0, 0, -1.3)}
	)
	var hits := AimResolver.sweep_melee(
		crowbar, Vector3(0, 1.1, 0), Vector3(0, 0, -1), line, Callable()
	)
	assert_int(hits.size()).is_equal(crowbar.melee_max_targets)
	assert_int(hits[0]["target_id"]).is_equal(2)


func test_a_wall_blocks_a_melee_swing() -> void:
	var crowbar := WeaponsFixture.def(&"crowbar")
	var wall := AABB(Vector3(-2, 0, -0.8), Vector3(4, 3, 0.2))
	var near := WeaponsFixture.targets_of({1: Vector3(0, 0, -1.4)})
	var hits := AimResolver.sweep_melee(
		crowbar, Vector3(0, 1.1, 0), Vector3(0, 0, -1), near, WeaponsFixture.box_world(wall)
	)
	assert_array(hits).is_empty()
