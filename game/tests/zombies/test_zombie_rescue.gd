extends GdUnitTestSuite
## A round that is down to its last few dead and in which nothing happens to them is not left to
## stand: they are walked to the people (#950). The soak found rounds that waited minutes on one
## dead pulling at boards that were put back, in a pocket of the walking mesh, or shuffling at the
## edge of it.

const FAR := Vector3(0.0, 0.0, -40.0)
## The gap a path leaves to its target when the mesh has no way there (a pocket).
const NO_WAY := 10.0

var _rules: GameRules
var _sim: ZombieSim
var _director: ZombieDirector


func before_test() -> void:
	_rules = RulesFixture.make_rules(1, 99, RulesFixture.tuning())
	_sim = ZombieFixture.sim()
	var points: Array[Vector3] = [Vector3(30, 0, 0), Vector3(-30, 0, 0), Vector3(0, 0, 8)]
	_director = ZombieDirector.new(_rules, _sim, points)
	RulesFixture.into_round_one(_rules)


func after_test() -> void:
	_director.close()


func _run(seconds: float) -> void:
	for _i in ceili(seconds / ZombieSim.STEP):
		_rules.apply(RulesAction.tick(ZombieSim.STEP))
		_director.tick(ZombieSim.STEP, {1: Vector3.ZERO})


## Kills the dead as they come, until `keep` are left of the round, and stands those still: held in
## place, far from the person.
func _leave(keep: int) -> Array[ZombieBody]:
	var guard := 0
	while guard < 600:
		guard += 1
		_run(0.5)
		var alive: Array[int] = []
		for id: int in _sim.zombies.keys():
			if _sim.zombies[id].is_alive():
				alive.append(id)
		if _rules.zombies_remaining() <= keep and alive.size() == _rules.zombies_remaining():
			break
		for id in alive:
			if _rules.zombies_remaining() > keep:
				_director.take_hit(id, &"head", 10000.0, 1)
	var left: Array[ZombieBody] = []
	for zombie: ZombieBody in _sim.zombies.values():
		if zombie.is_alive():
			zombie.enter(ZombieBody.Mode.CHASE)
			zombie.position = FAR
			zombie.path_gap = NO_WAY
			_sim.set_status(zombie.id, 1, true, 0.0)
			left.append(zombie)
	return left


func test_the_last_dead_with_nothing_happening_to_them_are_walked_to_the_people() -> void:
	var left := _leave(1)
	assert_int(left.size()).is_equal(1)
	_run(ZombieDirector.RESCUE_AFTER - 5.0)
	assert_int(_director.rescued).is_equal(0)
	assert_vector(left[0].position).is_equal(FAR)
	_run(10.0)
	assert_int(_director.rescued).is_equal(1)
	assert_float(Vector2(left[0].position.x, left[0].position.z).length()).is_between(25.0, 32.0)
	assert_int(left[0].mode).is_equal(ZombieBody.Mode.EMERGING)


func test_a_hit_on_one_of_them_puts_the_wait_off() -> void:
	var left := _leave(1)
	_run(ZombieDirector.RESCUE_AFTER - 5.0)
	_director.take_hit(left[0].id, &"body", 1.0, 1)
	_run(ZombieDirector.RESCUE_AFTER - 5.0)
	assert_int(_director.rescued).is_equal(0)


func test_a_dead_with_a_way_to_its_target_is_left_where_it_is() -> void:
	# A headliner after a person with an empty gun: slow, but coming.
	var left := _leave(1)
	left[0].path_gap = 0.5
	_run(ZombieDirector.RESCUE_AFTER * 2.0)
	assert_int(_director.rescued).is_equal(0)
	assert_vector(left[0].position).is_equal(FAR)


func test_a_map_with_no_spawn_point_far_from_the_people_takes_the_farthest() -> void:
	var near_points: Array[Vector3] = [Vector3(12, 0, 0), Vector3(-9, 0, 0), Vector3(0, 0, 6)]
	_director.spawn_points = near_points
	var left := _leave(1)
	_run(ZombieDirector.RESCUE_AFTER + 5.0)
	assert_int(_director.rescued).is_equal(1)
	assert_float(Vector2(left[0].position.x, left[0].position.z).length()).is_equal_approx(
		12.0, 1.0
	)


func test_a_round_with_more_than_the_marked_few_left_is_not_rescued() -> void:
	var keep := _sim.tuning.mark_last + 2
	_leave(keep)
	_run(ZombieDirector.RESCUE_AFTER * 2.0)
	assert_int(_director.rescued).is_equal(0)


func test_a_break_between_rounds_does_not_count() -> void:
	_leave(1)
	_run(0.5)
	var id: int = _sim.zombies.keys()[0]
	_director.take_hit(id, &"head", 10000.0, 1)
	_run(ZombieDirector.RESCUE_AFTER * 2.0)
	assert_int(_director.rescued).is_equal(0)
