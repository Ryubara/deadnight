class_name ZombieFixture
extends RefCounted
## Shared helpers for the zombie suites: a sim in an empty field, runs of fixed steps.

const STEP := ZombieSim.STEP


static func sim(p_seed: int = 7) -> ZombieSim:
	return ZombieSim.new(ZombieTuning.new(), p_seed)


## Runs `seconds` of fixed steps; returns every event, in order.
static func run(sim: ZombieSim, seconds: float, targets: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _i in ceili(seconds / STEP):
		events.append_array(sim.tick(STEP, targets))
	return events


static func count(events: Array[Dictionary], type: StringName) -> int:
	var n := 0
	for event in events:
		if event["type"] == type:
			n += 1
	return n


## A zombie that has finished emerging, at `at`.
static func standing(sim: ZombieSim, zombie_id: int, at: Vector3, speed: float = 2.0) -> ZombieBody:
	var zombie := sim.spawn(zombie_id, speed, at)
	zombie.enter(ZombieBody.Mode.CHASE)
	return zombie
