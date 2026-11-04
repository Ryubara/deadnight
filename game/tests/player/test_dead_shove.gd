extends GdUnitTestSuite
## How a sustained push yields (#914), by policy, on a zombie sim with no body: the numbers of
## `DeadShove` and the snapshot a server and a client both hold.

const STEP := 1.0 / 60.0

var _sim: ZombieSim


func before_test() -> void:
	_sim = ZombieSim.new(null, 1)


func _zombie(id: int, at: Vector3, profile: ZombieProfile = null) -> ZombieBody:
	var zombie := _sim.spawn(id, 0.0, at, 0.0, profile)
	zombie.enter(ZombieBody.Mode.CHASE)
	return zombie


## A field that says the body touched `id` (from the south, pushing at `push` m/s).
func _touching(id: int, push: float) -> DeadField:
	var field := DeadField.new()
	field.touch_ids.append(id)
	field.touch_normals.append(Vector3(0.0, 0.0, 1.0))
	field.touch_pushes.append(push)
	field.touch_intents.append(Vector3(0.0, 0.0, -1.0))
	return field


func _shove(policy: DeadContactTuning.Policy) -> DeadShove:
	var tuning := DeadContactTuning.shipped()
	tuning.policy = policy
	# These ask where a zombie goes straight away; the sideways roll has its own test.
	tuning.lateral = 0.0
	return DeadShove.new(_sim, tuning)


func test_a_timed_push_waits_for_its_hold_and_then_yields_at_the_shove_speed() -> void:
	var shove := _shove(DeadContactTuning.Policy.TIMED)
	var zombie := _zombie(1, Vector3.ZERO)
	var field := _touching(1, 4.0)
	var hold := shove.tuning.hold_seconds
	for _i in int(hold / STEP) - 2:
		shove.step(7, field, STEP)
	assert_vector(zombie.position).is_equal(Vector3.ZERO)
	for _i in 60:
		shove.step(7, field, STEP)
	# A second after the hold: a second at the shove speed, away from the body (north).
	assert_float(zombie.position.z).is_equal_approx(-shove.tuning.shove_speed * 1.0, 0.1)
	assert_float(zombie.position.x).is_equal_approx(0.0, 0.001)


func test_a_light_touch_builds_no_pressure() -> void:
	var shove := _shove(DeadContactTuning.Policy.TIMED)
	_zombie(1, Vector3.ZERO)
	var field := _touching(1, shove.tuning.press_min * 0.5)
	for _i in 120:
		shove.step(7, field, STEP)
	assert_float(shove.held_for(7, 1)).is_equal(0.0)


func test_a_wade_yields_at_once_by_a_share_of_the_push() -> void:
	var shove := _shove(DeadContactTuning.Policy.WADE)
	var zombie := _zombie(1, Vector3.ZERO)
	var field := _touching(1, 4.0)
	for _i in 60:
		shove.step(7, field, STEP)
	assert_float(zombie.position.z).is_equal_approx(-shove.tuning.wade_share * 4.0, 0.1)


func test_a_ramp_goes_faster_the_longer_the_push_holds() -> void:
	var shove := _shove(DeadContactTuning.Policy.RAMP)
	var zombie := _zombie(1, Vector3.ZERO)
	var field := _touching(1, 4.0)
	var seconds := shove.tuning.hold_seconds + shove.tuning.ramp_seconds + 1.0
	var last := 0.0
	var early := 0.0
	var late := 0.0
	for i in int(seconds / STEP):
		shove.step(7, field, STEP)
		var moved := -zombie.position.z
		if i == int((shove.tuning.hold_seconds + 0.3) / STEP):
			early = moved
		late = moved - last
		last = moved
	# The speed in the last tick has reached the top of the ramp.
	assert_float(late / STEP).is_equal_approx(shove.tuning.ramp_to, 0.1)
	assert_float(early).is_less(0.15)


func test_a_crowd_behind_a_zombie_slows_its_yield_and_a_boss_gives_little() -> void:
	var shove := _shove(DeadContactTuning.Policy.RAMP)
	shove.tuning.hold_seconds = 0.0
	var lone := _zombie(1, Vector3(0.0, 0.0, 0.0))
	var crowded := _zombie(2, Vector3(10.0, 0.0, 0.0))
	for i in 3:
		_zombie(10 + i, Vector3(10.0 + 0.3 * float(i + 1), 0.0, 0.0))
	var boss_profile := ZombieProfile.plain(_sim.tuning)
	boss_profile.boss = true
	var boss := _zombie(3, Vector3(20.0, 0.0, 0.0), boss_profile)
	# The sim's grid is made on its step.
	_sim.tick(ZombieSim.STEP, {})
	var before_lone := lone.position
	var before_crowded := crowded.position
	var before_boss := boss.position
	for id in [1, 2, 3]:
		var field := _touching(id, 4.0)
		for _i in 30:
			shove.step(7 + id, field, STEP)
	var moved_lone := before_lone.distance_to(lone.position)
	assert_float(before_crowded.distance_to(crowded.position)).is_less(moved_lone * 0.7)
	assert_float(before_boss.distance_to(boss.position)).is_less(moved_lone * 0.5)


func test_a_push_that_a_wall_stops_rolls_the_zombie_aside() -> void:
	var shove := _shove(DeadContactTuning.Policy.WADE)
	var zombie := _zombie(1, Vector3.ZERO)
	# A wall straight ahead (north, within the step and its clearance), none to the sides.
	_sim.sight = func(from: Vector3, to: Vector3) -> float:
		return 0.1 if to.z - from.z < -0.01 and absf(to.x - from.x) < 0.2 else -1.0
	var field := _touching(1, 4.0)
	for _i in 30:
		shove.step(7, field, STEP)
	assert_float(absf(zombie.position.x)).is_greater(0.2)


func test_the_snapshot_a_server_keeps_is_what_a_client_decodes_from_the_frame() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 12:
		_zombie(
			i + 1,
			Vector3(
				rng.randf_range(-30.0, 30.0),
				rng.randf_range(0.0, 3.4),
				rng.randf_range(-30.0, 30.0)
			)
		)
	var server := DeadSnapshot.of_sim(_sim.zombies, 5)
	var client := DeadSnapshot.of_entries(ZombieCodec.decode(ZombieCodec.encode(_sim.zombies)))
	assert_int(client.ids.size()).is_equal(server.ids.size())
	for i in server.ids.size():
		assert_int(client.ids[i]).is_equal(server.ids[i])
		assert_vector(client.positions[i]).is_equal_approx(
			server.positions[i], Vector3.ONE * 0.0001
		)


func test_the_dying_are_not_in_the_snapshot() -> void:
	_zombie(1, Vector3.ZERO)
	_zombie(2, Vector3(3.0, 0.0, 0.0))
	_sim.begin_death(2)
	var snapshot := DeadSnapshot.of_sim(_sim.zombies, 1)
	assert_array(Array(snapshot.ids)).is_equal([1])
	var client := DeadSnapshot.of_entries(ZombieCodec.decode(ZombieCodec.encode(_sim.zombies)))
	assert_array(Array(client.ids)).is_equal([1])


func test_a_sideways_yield_rolls_the_zombie_out_of_the_players_way() -> void:
	var tuning := DeadContactTuning.shipped()
	tuning.lateral = 1.0
	tuning.hold_seconds = 0.0
	var shove := DeadShove.new(_sim, tuning)
	# The player pushes north; the zombie stands a little to the west of the line.
	var left := _zombie(1, Vector3(-0.2, 0.0, 0.0))
	var field := _touching(1, 4.0)
	field.touch_normals[0] = Vector3(0.2, 0.0, 1.0).normalized()
	for _i in 60:
		shove.step(7, field, STEP)
	assert_float(left.position.x).is_less(-0.8)
	assert_float(absf(left.position.z)).is_less(0.05)
	# Dead ahead: the side is the zombie's id's, the same every time.
	var even := _zombie(2, Vector3(10.0, 0.0, 0.0))
	var odd := _zombie(3, Vector3(20.0, 0.0, 0.0))
	for id in [2, 3]:
		var ahead := _touching(id, 4.0)
		for _i in 60:
			shove.step(8 + id, ahead, STEP)
	assert_float(even.position.x - 10.0).is_less(-0.5)
	assert_float(odd.position.x - 20.0).is_greater(0.5)
