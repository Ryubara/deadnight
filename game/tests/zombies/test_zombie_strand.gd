extends GdUnitTestSuite
## A zombie that has no way to its target and stands far from it (a pocket of the walking mesh the
## crowd shoved it into) is put back on a spawn point: the nightly soak found rounds that went on
## for eight minutes with one dead walker standing behind the screen, 15 m from the person it chased
## (#770).


## Answers every path with one that stops `short` metres before the target, as the navigation map
## does for a target it has no way to (the nearest point of the island the walker stands on).
class PartialPathing:
	extends ZombiePathing

	var short := 20.0

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		var gap := to - from
		gap.y = 0.0
		return PackedVector3Array([from, from + gap.limit_length(maxf(gap.length() - short, 0.0))])


func _sim(short := 20.0) -> ZombieSim:
	var sim := ZombieFixture.sim()
	var pathing := PartialPathing.new()
	pathing.short = short
	sim.pathing = pathing
	return sim


func _stranded(events: Array[Dictionary]) -> int:
	return ZombieFixture.count(events, &"zombie_stranded")


func test_a_zombie_with_no_way_to_a_far_target_is_stranded_after_a_while_and_not_before() -> void:
	var sim := _sim()
	ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	var targets := {1: Vector3(0.0, 0.0, -40.0)}
	var early := ZombieFixture.run(sim, ZombieSim.STRAND_SECONDS - 3.0, targets)
	assert_int(_stranded(early)).is_equal(0)
	var later := ZombieFixture.run(sim, 5.0, targets)
	assert_int(_stranded(later)).is_equal(1)
	(
		assert_int(
			later.filter(func(e: Dictionary) -> bool: return e["type"] == &"zombie_stranded")[0]["zombie_id"]
		)
		. is_equal(1)
	)


func test_it_says_so_again_every_so_often_while_it_stays_stranded() -> void:
	var sim := _sim()
	ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	var events := ZombieFixture.run(
		sim, ZombieSim.STRAND_SECONDS * 2.0 + 2.0, {1: Vector3(0.0, 0.0, -40.0)}
	)
	assert_int(_stranded(events)).is_equal(2)


func test_a_zombie_with_a_way_to_its_target_is_not_stranded() -> void:
	var sim := _sim(0.0)
	ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	var events := ZombieFixture.run(
		sim, ZombieSim.STRAND_SECONDS * 2.0, {1: Vector3(0.0, 0.0, -40.0)}
	)
	assert_int(_stranded(events)).is_equal(0)


func test_a_zombie_near_its_target_is_not_stranded_whatever_the_map_says() -> void:
	var sim := _sim()
	ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	# 8 m from the player: a car roof or a prop in the way, not a pocket across the lot.
	var events := ZombieFixture.run(
		sim, ZombieSim.STRAND_SECONDS * 2.0, {1: Vector3(0.0, 0.0, -8.0)}
	)
	assert_int(_stranded(events)).is_equal(0)


func test_a_zombie_at_its_boards_is_not_stranded() -> void:
	var sim := _sim()
	# The breach is the line z = 5 and the way in is +z: the zombie stands outside it, boards up.
	sim.gates[&"north"] = ZombieGate.new(&"north", Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, 1.0))
	sim.barricades = BarricadeState.new(BarricadeTuning.new())
	sim.barricades.boards[&"north"] = 3
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	zombie.gate_id = &"north"
	var events := ZombieFixture.run(
		sim, ZombieSim.STRAND_SECONDS * 2.0, {1: Vector3(0.0, 0.0, -40.0)}
	)
	assert_int(_stranded(events)).is_equal(0)


func test_relocating_puts_the_zombie_back_on_the_point_rising_with_no_path() -> void:
	var sim := _sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 0.0)
	ZombieFixture.run(sim, 1.0, {1: Vector3(0.0, 0.0, -40.0)})
	assert_bool(zombie.path.is_empty()).is_false()
	sim.relocate(1, Vector3(30.0, 0.0, 10.0), &"east")
	assert_vector(zombie.position).is_equal(Vector3(30.0, 0.0, 10.0))
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.EMERGING)
	assert_bool(zombie.path.is_empty()).is_true()
	assert_str(zombie.gate_id).is_equal("east")
	assert_float(zombie.stranded_for).is_equal(0.0)


func test_the_director_relocates_a_stranded_zombie_to_a_spawn_point() -> void:
	var rules := RulesFixture.make_rules(1, 99, RulesFixture.tuning())
	var sim := _sim()
	var points: Array[Vector3] = [Vector3(30.0, 0.0, 0.0), Vector3(-30.0, 0.0, 0.0)]
	var director := ZombieDirector.new(rules, sim, points)
	var zombie := ZombieFixture.standing(sim, 1, Vector3(0.0, 0.0, -50.0), 0.0)
	var targets := {1: Vector3(0.0, 0.0, -10.0)}
	for _i in ceili((ZombieSim.STRAND_SECONDS + 2.0) / ZombieSim.STEP):
		director.tick(ZombieSim.STEP, targets)
	assert_int(director.relocated).is_equal(1)
	assert_float(absf(zombie.position.x)).is_equal_approx(30.0, 1.0)
	director.close()
