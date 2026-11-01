extends GdUnitTestSuite
## How a grenade flies: the arc, the bounce, the roll and the rest, and that the same throw lands
## on the same point every time.

var _def: GrenadeDef


func before_test() -> void:
	_def = GrenadesFixture.def()


func _fly(state: GrenadeState, cast: Callable, seconds: float) -> void:
	for _i in roundi(seconds / GrenadesFixture.STEP):
		state.step(GrenadesFixture.STEP, cast)


func test_a_throw_lands_on_the_same_point_every_time() -> void:
	var cast := GrenadesFixture.world_cast()
	var aim := Vector3(0.2, 0.1, -1.0)
	var a := GrenadeArc.predict(
		_def, Vector3(0, 1.5, 0), aim, Vector3.ZERO, false, cast, GrenadesFixture.STEP
	)
	var b := GrenadeArc.predict(
		_def, Vector3(0, 1.5, 0), aim, Vector3.ZERO, false, cast, GrenadesFixture.STEP
	)
	assert_vector(a["landing"]).is_equal(b["landing"])
	assert_int(a["bounces"]).is_equal(b["bounces"])
	assert_float(a["rest_time"]).is_equal(b["rest_time"])


func test_a_different_aim_lands_somewhere_else() -> void:
	var cast := GrenadesFixture.world_cast()
	var near := GrenadeArc.predict(
		_def, Vector3(0, 1.5, 0), Vector3(0, 0, -1), Vector3.ZERO, true, cast, GrenadesFixture.STEP
	)
	var far := GrenadeArc.predict(
		_def, Vector3(0, 1.5, 0), Vector3(0, 0, -1), Vector3.ZERO, false, cast, GrenadesFixture.STEP
	)
	assert_float(far["landing"].distance_to(Vector3(0, 1.5, 0))).is_greater(
		near["landing"].distance_to(Vector3(0, 1.5, 0)) + 4.0
	)


func test_it_falls_bounces_and_comes_to_rest_on_the_floor() -> void:
	var cast := GrenadesFixture.world_cast()
	var state := GrenadeState.new(1, 1, _def, Vector3(0, 2.0, 0), Vector3(0, 0, -5), 99.0)
	_fly(state, cast, 0.5)
	assert_int(state.bounces).is_greater(0)
	_fly(state, cast, 5.0)
	assert_bool(state.at_rest).is_true()
	assert_float(state.position.y).is_equal_approx(_def.radius, 0.01)
	assert_vector(state.velocity).is_equal(Vector3.ZERO)


func test_each_bounce_is_weaker_than_the_last() -> void:
	var cast := GrenadesFixture.world_cast()
	var state := GrenadeState.new(1, 1, _def, Vector3(0, 3.0, 0), Vector3(0, 0, -2), 99.0)
	var speeds: Array[float] = []
	for _i in 300:
		state.step(GrenadesFixture.STEP, cast)
		for contact in state.contacts:
			speeds.append(contact["speed"])
	assert_int(speeds.size()).is_greater(1)
	for i in range(1, speeds.size()):
		assert_float(speeds[i]).is_less(speeds[i - 1])


func test_it_bounces_off_a_wall_and_comes_back() -> void:
	var cast := GrenadesFixture.world_cast(-6.0)
	var state := GrenadeState.new(1, 1, _def, Vector3(0, 1.2, 0), Vector3(0, 0, -14), 99.0)
	var wall_hits := 0
	var turned := false
	for _i in 120:
		state.step(GrenadesFixture.STEP, cast)
		for contact in state.contacts:
			if contact["wall"]:
				wall_hits += 1
		if state.velocity.z > 0.0:
			turned = true
	assert_int(wall_hits).is_greater(0)
	assert_bool(turned).is_true()
	assert_float(state.position.z).is_greater(-6.0)


func test_it_never_passes_through_the_floor_even_when_thrown_hard() -> void:
	var cast := GrenadesFixture.world_cast()
	var state := GrenadeState.new(1, 1, _def, Vector3(0, 0.5, 0), Vector3(0, -60, -10), 99.0)
	for _i in 200:
		state.step(GrenadesFixture.STEP, cast)
		assert_float(state.position.y).is_greater_equal(0.0)


func test_a_rolling_grenade_runs_off_a_ledge_and_falls() -> void:
	var ledge := func(from: Vector3, to: Vector3) -> Dictionary:
		# A floor that ends at z = -3 (nothing beyond), at y = 0.
		var length := from.distance_to(to)
		if from.y >= 0.0 and to.y < 0.0:
			var t := from.y / (from.y - to.y)
			var at: Vector3 = from.lerp(to, t)
			if at.z > -3.0:
				return {"distance": length * t, "normal": Vector3.UP}
		return {}
	var state := GrenadeState.new(1, 1, _def, Vector3(0, _def.radius, 0), Vector3(0, 0, -7), 99.0)
	state.grounded = true
	_fly(state, ledge, 1.0)
	assert_bool(state.grounded).is_false()
	assert_float(state.position.y).is_less(0.0)


func test_underarm_is_slower_and_lower_than_overarm() -> void:
	var aim := Vector3(0, 0, -1)
	var over := _def.launch_velocity(aim, false, Vector3.ZERO)
	var under := _def.launch_velocity(aim, true, Vector3.ZERO)
	assert_float(under.length()).is_less(over.length())
	assert_float(over.length()).is_equal_approx(_def.over_speed, 0.001)
	assert_float(under.y / under.length()).is_greater(over.y / over.length())


func test_a_moving_thrower_adds_part_of_their_speed() -> void:
	var still := _def.launch_velocity(Vector3(0, 0, -1), false, Vector3.ZERO)
	var running := _def.launch_velocity(Vector3(0, 0, -1), false, Vector3(0, 0, -6))
	assert_float(running.z - still.z).is_equal_approx(-6.0 * _def.inherit_velocity, 0.001)


func test_straight_up_or_down_still_throws() -> void:
	var up := _def.launch_velocity(Vector3.UP, false, Vector3.ZERO)
	assert_bool(up.is_finite()).is_true()
	assert_float(up.length()).is_equal_approx(_def.over_speed, 0.001)


func test_the_fuse_burns_in_flight() -> void:
	var cast := GrenadesFixture.world_cast()
	var state := GrenadeState.new(1, 1, _def, Vector3(0, 1.5, 0), Vector3(0, 0, -5), 1.0)
	_fly(state, cast, 0.5)
	assert_float(state.fuse_left).is_equal_approx(0.5, 0.02)
	assert_bool(state.is_spent()).is_false()
	_fly(state, cast, 0.6)
	assert_bool(state.is_spent()).is_true()
