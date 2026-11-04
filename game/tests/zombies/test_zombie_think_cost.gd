extends GdUnitTestSuite
## The dead's thinking is cut to what each zombie needs in a step (#947), and none of the cuts
## changes what the dead do: a scripted night of 60 dead (targets that walk, a gate with boards, a
## lure, statuses, a blast, a cripple, deaths, a map with two storeys) ends at the state the sim
## reached before the cuts, and a step asks the map's sight only for a zombie that may swing.

## The digest of the scripted night, taken on the code before the cuts. A change of the dead's
## behaviour moves it; update it only for a change that is meant to move the dead.
const GOLDEN_FLAT := "c1da01f3416ab19fd0e47b19ce97eb68"
const GOLDEN_STOREY := "c99cc0d5ccafcd57b997cd1be04ab2d8"
const STEPS := 450
const STOREY := 3.4
const GATE := &"nw"
const OTHER_GATE := &"ne"


## A walking mesh in miniature: a path with a bend, over the floor by the baker's lift.
class BentPathing:
	extends ZombiePathing

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		var lift := Vector3(0.0, ZombieSim.NAV_LIFT, 0.0)
		var middle := from.lerp(to, 0.5)
		middle.x += 2.0
		return PackedVector3Array([from + lift, middle + lift, to + lift])

	func ground_offset() -> float:
		return ZombieSim.NAV_LIFT


func _night(storey: float) -> String:
	var sim := ZombieFixture.sim(5)
	sim.pathing = BentPathing.new()
	sim.rounds = RoundTuning.new()
	sim.lit_probe = func(point: Vector3) -> bool: return int(point.x * 0.5) % 2 == 0
	if storey > 0.0:
		sim.set_floors(
			storey,
			func(from: Vector3, _to: Vector3) -> float: return -1.0 if int(from.x) % 3 != 0 else 1.0
		)
	var boards := BarricadeState.new(BarricadeTuning.new())
	sim.barricades = boards
	sim.gates[GATE] = ZombieGate.new(GATE, Vector3(-8, 0, 0), Vector3.RIGHT, 3.0)
	sim.gates[OTHER_GATE] = ZombieGate.new(OTHER_GATE, Vector3(8, 0, 6), Vector3.LEFT, 3.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 155
	for i in 60:
		var up := storey > 0.0 and i % 5 == 0
		var at := Vector3(rng.randf_range(-40, 40), storey if up else 0.0, rng.randf_range(-40, 40))
		var gate := &""
		if i % 11 == 0:
			at = Vector3(-14.0 + rng.randf() * 2.0, 0.0, -2.0 + rng.randf() * 4.0)
			gate = GATE
		elif i % 13 == 0:
			at = Vector3(14.0 - rng.randf() * 2.0, 0.0, 5.0 + rng.randf() * 2.0)
			gate = OTHER_GATE
		var zombie := sim.spawn(i + 1, 1.0 + rng.randf() * 1.5, at, rng.randf() * TAU, null, gate)
		if i % 3 != 0:
			zombie.enter(ZombieBody.Mode.CHASE)
	var lines := PackedStringArray()
	for step in STEPS:
		var t := float(step) * ZombieSim.STEP
		var targets := {
			1: Vector3(cos(t * 0.3) * 12.0, 0.0, sin(t * 0.3) * 12.0),
			2: Vector3(-20.0 + t * 0.1, storey, 10.0),
			3: Vector3(25.0, 0.0, -15.0),
			4: Vector3.ZERO if step % 400 < 300 else Vector3(1000.0, 0.0, 1000.0),
		}
		_script(sim, step)
		for event in sim.tick(ZombieSim.STEP, targets):
			if event["type"] == &"zombie_tore":
				boards.tear(event["gate_id"])
			lines.append(
				(
					"%d %s %s %s"
					% [step, event["type"], event.get("zombie_id", 0), event.get("damage", 0.0)]
				)
			)
		if step % 25 == 24:
			lines.append(_state(sim))
	return "\n".join(lines).md5_text()


## What happens to the crowd on its way: a lure, a freeze and a chill, a blast, deaths, a cripple.
func _script(sim: ZombieSim, step: int) -> void:
	match step:
		60:
			sim.add_lure(1, Vector3(20, 0, 20), 25.0, 6.0)
		120:
			for id in [3, 4, 5, 6]:
				sim.set_status(id, 2, true, 1.0)
			for id in [7, 8, 9]:
				sim.set_status(id, 3, false, 0.5)
		160:
			for id in [3, 4, 5, 6]:
				sim.set_status(id, 0, false, 1.0)
		200:
			for id in range(20, 28):
				sim.blast(id, Vector3(4, 0, 2), 1.5)
			for id in range(30, 34):
				sim.begin_death(id)
			for id in range(40, 44):
				sim.react_to_hit(id)
		260:
			sim.shatter(50)
			sim.despawn(51)
			for id in range(55, 58):
				sim.cripple(id, ZombieProfile.plain(sim.tuning), 0.5)


func _state(sim: ZombieSim) -> String:
	var ids: Array = sim.zombies.keys()
	ids.sort()
	var parts := PackedStringArray()
	for id: int in ids:
		var z: ZombieBody = sim.zombies[id]
		(
			parts
			. append(
				(
					"%d %d %.4f %.4f %.4f %.4f %d %d %.4f %.4f"
					% [
						id,
						z.mode,
						z.position.x,
						z.position.y,
						z.position.z,
						z.yaw,
						z.target_id,
						z.path_index,
						z.mode_time,
						z.tear_progress,
					]
				)
			)
		)
	return ";".join(parts)


func test_a_scripted_night_on_the_lot_ends_where_it_did_before_the_cuts() -> void:
	var digest := _night(0.0)
	assert_str(digest).is_equal(GOLDEN_FLAT)


func test_a_scripted_night_on_a_map_with_storeys_ends_where_it_did_before_the_cuts() -> void:
	var digest := _night(STOREY)
	assert_str(digest).is_equal(GOLDEN_STOREY)


## A sim on a map with storeys whose sight counts how often it is asked.
func _counting_sim(asked: Array[int]) -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.set_floors(
		STOREY,
		func(_from: Vector3, _to: Vector3) -> float:
			asked[0] += 1
			return -1.0
	)
	return sim


func test_a_step_asks_the_sight_only_for_a_zombie_that_may_swing() -> void:
	var asked: Array[int] = [0]
	var sim := _counting_sim(asked)
	# Twenty rising and twenty staggered, at the target's feet: none of them may swing this step.
	for i in 20:
		sim.spawn(i + 1, 2.0, Vector3(1.0 + 0.1 * i, 0.0, 0.0))
		ZombieBrain.stagger(ZombieFixture.standing(sim, 100 + i, Vector3(-1.0 - 0.1 * i, 0.0, 0.0)))
	sim.tick(ZombieSim.STEP, {1: Vector3.ZERO})
	assert_int(asked[0]).is_equal(0)


func test_a_step_asks_the_sight_for_a_zombie_that_walks_up_to_its_target() -> void:
	var asked: Array[int] = [0]
	var sim := _counting_sim(asked)
	ZombieFixture.standing(sim, 1, Vector3(1.5, 0.0, 0.0))
	sim.tick(ZombieSim.STEP, {1: Vector3.ZERO})
	assert_int(asked[0]).is_greater(0)


func test_a_calm_step_answers_with_the_one_empty_strike() -> void:
	var tuning := ZombieTuning.shipped()
	var zombie := ZombieBody.new()
	zombie.profile = ZombieProfile.plain(tuning)
	zombie.enter(ZombieBody.Mode.CHASE)
	var first := ZombieBrain.step(
		zombie, tuning, ZombieSim.STEP, true, Vector3(30, 0, 0), Vector3(30, 0, 0), 2.0
	)
	var second := ZombieBrain.step(
		zombie, tuning, ZombieSim.STEP, true, Vector3(30, 0, 0), Vector3(30, 0, 0), 2.0
	)
	assert_bool(first.is_empty()).is_true()
	assert_bool(is_same(first, second)).is_true()
