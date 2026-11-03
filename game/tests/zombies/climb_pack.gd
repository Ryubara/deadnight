class_name ClimbPack
extends RefCounted
## A pack of zombies sent up a climb (Deadnight #681), and what it did: when each reached the top
## and the longest any of them went without rising. Ticks are run by hand through `tick` (a night's
## step or a bare simulation's), so there is no clock and no frame in it.
##
## "Stuck" is a zombie that has begun the climb (rose `BEGUN` metres) and then goes without
## setting a new best height `PROGRESS` metres above the last, short of the top: the seconds it
## went so.

const BEGUN := 0.3
const PROGRESS := 0.15
## Zombie ids of a pack start here (the director's own stay below).
const FIRST_ID := 5000
## The step of the clock (seconds): the night's.
const STEP := Night.STEP

var sim: ZombieSim
## `Callable() -> void`: advances the sim by one step.
var tick: Callable
var top: float
var deadline: float = 40.0

## Seconds into the run at which each zombie (id) first stood at `top`.
var arrived := {}
var longest_stuck := 0.0
var max_height := 0.0

var _best := {}
var _rose_at := {}
var _ids: Array[int] = []


func _init(p_sim: ZombieSim, p_tick: Callable, p_top: float) -> void:
	sim = p_sim
	tick = p_tick
	top = p_top


## Puts `count` zombies, two abreast and `speed` m/s fast, at `from` (rows `row_gap` metres apart
## along `back`), all chasing.
func spawn(count: int, from: Vector3, speed: float, back: Vector3, row_gap := 1.2) -> void:
	var side := Vector3(back.z, 0.0, -back.x).normalized()
	for i in count:
		var at := from + side * (float(i % 2) - 0.5) + back * (float(i / 2) * row_gap)
		var zombie := sim.spawn(FIRST_ID + i, speed, at)
		zombie.enter(ZombieBody.Mode.CHASE)
		_ids.append(zombie.id)


## Runs until every zombie is at the top or `deadline` seconds have passed.
func run() -> void:
	var now := 0.0
	var count := int(deadline / STEP)
	for _i in count:
		tick.call()
		now += STEP
		for id in _ids:
			var zombie: ZombieBody = sim.zombies.get(id)
			if zombie != null:
				_watch(zombie, now)
		if arrived.size() == _ids.size():
			return


func reached() -> int:
	return arrived.size()


## Seconds until the first zombie stood at the top (INF when none did).
func first_seconds() -> float:
	return arrived.values().min() if not arrived.is_empty() else INF


## Seconds until the last zombie stood at the top (INF when one never did).
func last_seconds() -> float:
	return arrived.values().max() if arrived.size() == _ids.size() else INF


func summary(label: String) -> String:
	return (
		"CLIMB %s: %d/%d at the top, first %.2f s, last %.2f s, longest stuck %.2f s, highest %.2f m"
		% [
			label,
			reached(),
			_ids.size(),
			first_seconds(),
			last_seconds(),
			longest_stuck,
			max_height
		]
	)


func _watch(zombie: ZombieBody, now: float) -> void:
	max_height = maxf(max_height, zombie.position.y)
	if arrived.has(zombie.id):
		return
	if zombie.position.y >= top:
		arrived[zombie.id] = now
		return
	if zombie.position.y < BEGUN and not _best.has(zombie.id):
		return
	if not _best.has(zombie.id) or zombie.position.y >= float(_best[zombie.id]) + PROGRESS:
		_best[zombie.id] = zombie.position.y
		_rose_at[zombie.id] = now
	else:
		longest_stuck = maxf(longest_stuck, now - float(_rose_at[zombie.id]))
