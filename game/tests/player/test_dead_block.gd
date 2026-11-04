extends GdUnitTestSuite
## The player meets the dead (#914): a standing zombie stops the body, a sustained push moves the
## zombie, and a player ringed by the dead gets out.

var _lab: DeadLab


func after_test() -> void:
	if _lab != null and is_instance_valid(_lab.world):
		_lab.world.queue_free()
	_lab = null


func _edge() -> float:
	return PlayerTuning.new().radius + _lab.tuning.radius


func test_a_player_cannot_run_through_a_standing_zombie() -> void:
	_lab = await DeadLab.start(self)
	var id := _lab.place(_lab.spawn + Vector3(0.0, 0.0, -3.0))
	var nearest := INF
	for _i in 180:
		_lab.step(Vector2(0.0, -1.0), true)
		nearest = minf(nearest, _lab.apart(id))
		# A push this hard is not held long enough to move it (the shove waits for its hold).
		if _lab.shove.held_for(1, id) > 0.0:
			break
	assert_float(nearest).is_greater_equal(_edge() - 0.02)
	assert_float(_lab.apart(id)).is_less(_edge() + 0.1)


func test_without_the_dead_a_run_goes_straight_on() -> void:
	_lab = await DeadLab.start(self)
	var id := _lab.place(_lab.spawn + Vector3(0.0, 0.0, -3.0))
	_lab.field.tuning.enabled = false
	_lab.walk(120, Vector2(0.0, -1.0), true)
	assert_float(_lab.at().z).is_less(_lab.zombie_at(id).z - 1.0)


func test_a_player_slides_round_the_edge_of_a_zombie() -> void:
	_lab = await DeadLab.start(self)
	var id := _lab.place(_lab.spawn + Vector3(0.1, 0.0, -2.5))
	var nearest := INF
	for _i in 120:
		_lab.step(Vector2(0.0, -1.0), true)
		nearest = minf(nearest, _lab.apart(id))
	# Never nearer than the edge (a body that is not stopped goes through the middle), and past the
	# zombie by the end: held by it, then slid past its side.
	assert_float(nearest).is_greater_equal(_edge() - 0.02)
	assert_float(_lab.at().z).is_less(_lab.zombie_at(id).z - 0.5)


func test_a_sustained_push_moves_the_zombie_within_the_hold_time() -> void:
	var tuning := DeadContactTuning.shipped()
	tuning.policy = DeadContactTuning.Policy.TIMED
	_lab = await DeadLab.start(self, tuning)
	var start := _lab.spawn + Vector3(0.0, 0.0, -2.0)
	var id := _lab.place(start)
	var seconds := _lab.until(
		func() -> bool: return _lab.zombie_at(id).distance_to(start) > 0.3, Vector2(0.0, -1.0), 5.0
	)
	assert_float(seconds).is_greater(0.0)
	# The way to it, the hold, and the 0.3 m at the shove speed.
	assert_float(seconds).is_less(1.0 + tuning.hold_seconds + 0.3 / tuning.shove_speed)
	assert_float(seconds).is_greater(tuning.hold_seconds)


func test_a_push_that_lets_go_is_forgotten() -> void:
	var tuning := DeadContactTuning.shipped()
	_lab = await DeadLab.start(self, tuning)
	var start := _lab.spawn + Vector3(0.0, 0.0, -2.0)
	var id := _lab.place(start)
	var built := _lab.until(
		func() -> bool: return _lab.shove.held_for(1, id) > 0.2, Vector2(0.0, -1.0), 5.0
	)
	# The push built up while it lasted (and the zombie had not yet given way).
	assert_float(built).is_greater(0.0)
	assert_vector(_lab.zombie_at(id)).is_equal_approx(start, Vector3.ONE * 0.01)
	_lab.walk(int(2.0 / DeadLab.STEP), Vector2.ZERO)
	assert_float(_lab.shove.held_for(1, id)).is_equal(0.0)
	assert_vector(_lab.zombie_at(id)).is_equal_approx(start, Vector3.ONE * 0.01)


func test_a_player_ringed_by_the_dead_gets_out() -> void:
	var tuning := DeadContactTuning.shipped()
	_lab = await DeadLab.start(self, tuning)
	var centre := _lab.spawn + Vector3(0.0, 0.0, -4.0)
	_lab.body.teleport(centre)
	await get_tree().physics_frame
	_lab.ring(8, 1.1, centre)
	var seconds := _lab.until(
		func() -> bool:
			return Vector2(_lab.at().x - centre.x, _lab.at().z - centre.z).length() > 3.0,
		Vector2(0.0, -1.0),
		20.0,
		true
	)
	# Held in the ring until a push has rolled one of the dead aside, then out.
	assert_float(seconds).is_greater(tuning.hold_seconds)
	assert_float(seconds).is_less(10.0)


func test_a_zombie_is_not_nudged_into_a_wall() -> void:
	_lab = await DeadLab.start(self)
	# A zombie with the lot's edge close behind it: wherever a wall stands within the step, it stays.
	var id := _lab.place(_lab.spawn + Vector3(0.0, 0.0, -2.0))
	var zombie: ZombieBody = _lab.sim.zombies[id]
	var before := zombie.position
	_lab.sim.sight = func(_a: Vector3, _b: Vector3) -> float: return 0.1
	assert_bool(_lab.sim.nudge(id, Vector3(0.0, 0.0, -1.0), 0.1)).is_false()
	assert_vector(zombie.position).is_equal(before)
