class_name DeadLab
extends RefCounted
## One player body on the lot with a handful of standing dead, stepped by hand the way the server
## steps them (#914): the field filled from the dead, the body moved, the push counted
## (`DeadShove`), the zombies' own sim run at its 30 Hz. For the suites and the measurements of the
## player's meeting with the dead; the dead stand where they are put (no target, no walk).

const STEP := 1.0 / 60.0

var world: NightWorld
var sim: ZombieSim
var shove: DeadShove
var tuning: DeadContactTuning
var body: Player
var field: DeadField
var spawn := Vector3.ZERO
var ticks := 0
var _next_id := 1


static func start(parent: Node, p_tuning: DeadContactTuning = null) -> DeadLab:
	var lab := DeadLab.new()
	lab.tuning = p_tuning if p_tuning != null else DeadContactTuning.shipped()
	lab.world = NightWorld.new()
	parent.add_child(lab.world)
	await lab.world.build()
	lab.spawn = lab.world.player_spawn(0)
	lab.body = lab.world.add_body(lab.spawn, false, false)
	lab.field = DeadField.new(lab.tuning)
	lab.body.dead = lab.field
	lab.sim = ZombieSim.new(null, 1)
	lab.sim.set_floors(
		0.0, WorldProbe.new(lab.world.get_world_3d().direct_space_state).static_callable()
	)
	lab.shove = DeadShove.new(lab.sim, lab.tuning)
	await parent.get_tree().physics_frame
	await parent.get_tree().physics_frame
	return lab


## A zombie standing at `at`, up and with no target. Returns its id.
func place(at: Vector3, profile: ZombieProfile = null) -> int:
	var id := _next_id
	_next_id += 1
	var zombie := sim.spawn(id, 1.0, at, 0.0, profile)
	zombie.enter(ZombieBody.Mode.CHASE)
	return id


## `count` dead on a ring of `radius` metres round `centre`.
func ring(count: int, radius: float, centre: Vector3) -> Array[int]:
	var placed: Array[int] = []
	for i in count:
		var angle := TAU * float(i) / float(count)
		placed.append(place(centre + Vector3(sin(angle), 0.0, cos(angle)) * radius))
	return placed


## One 60 Hz tick as the server runs it, with the body asked to move by `move` (x right, y back) and
## the view along `yaw`.
func step(move: Vector2, sprint: bool = false, yaw: float = 0.0) -> void:
	var command := PlayerCommand.new()
	command.move = move
	command.sprint = sprint
	command.yaw = yaw
	field.fill(DeadSnapshot.of_sim(sim.zombies, ticks), body.global_position)
	body.tick(command)
	shove.step(1, field, STEP)
	ticks += 1
	if ticks % 2 == 0:
		sim.tick(ZombieSim.STEP, {})


## Steps `count` ticks of the same push.
func walk(count: int, move: Vector2, sprint: bool = false, yaw: float = 0.0) -> void:
	for _i in count:
		step(move, sprint, yaw)


## Steps until `done` is true or `limit` seconds pass; returns the seconds it took (-1 if never).
func until(
	done: Callable, move: Vector2, limit: float, sprint: bool = false, yaw: float = 0.0
) -> float:
	var left := int(limit / STEP)
	for i in left:
		step(move, sprint, yaw)
		if done.call():
			return float(i + 1) * STEP
	return -1.0


func at() -> Vector3:
	return body.global_position


func zombie_at(id: int) -> Vector3:
	return sim.zombies[id].position


## Flat metres from the body to a zombie.
func apart(id: int) -> float:
	var z := zombie_at(id)
	return Vector2(at().x - z.x, at().z - z.z).length()
