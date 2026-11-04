class_name DeadShove
extends RefCounted
## What a person's sustained push does to the dead (#914), on the server. The body is stopped by a
## zombie at once (`DeadBlock`); here the push is counted, and a zombie pushed hard enough for long
## enough yields: it is moved away from the body by `ZombieSim.nudge`, and the body, which a moment
## ago was stopped, follows it as the zombie goes. How the yield grows with the push is the tuning's
## `Policy`. Pressure is kept per player and per zombie, and forgotten when the push lets go.

## Radians a blocked zombie turns from straight away to roll aside.
const ASIDE := 1.2
## A zombie whose middle is this near (cross product of unit vectors) the player's line is dead
## ahead.
const LEAN_MIN := 0.05

var tuning: DeadContactTuning
var sim: ZombieSim
## Numbers of a run: nudges made, and seconds of yield (summed over zombies).
var nudges := 0
var yielded_seconds := 0.0

## Seconds of push held, by player id and zombie id.
var _held: Dictionary[int, Dictionary] = {}


func _init(p_sim: ZombieSim, p_tuning: DeadContactTuning = null) -> void:
	sim = p_sim
	tuning = p_tuning if p_tuning != null else DeadContactTuning.shipped()


## One tick of `player_id`'s push: the zombies `field` says the body touched, how hard the stick
## pushed into each. Moves the ones that yield.
func step(player_id: int, field: DeadField, delta: float) -> void:
	if not tuning.enabled:
		return
	var held: Dictionary = _held.get(player_id, {})
	var pushed := {}
	for i in field.touch_ids.size():
		var zombie_id := field.touch_ids[i]
		var push := field.touch_pushes[i]
		if push < tuning.press_min:
			continue
		pushed[zombie_id] = true
		var seconds: float = held.get(zombie_id, 0.0) + delta
		held[zombie_id] = seconds
		var speed := _yield_speed(zombie_id, seconds, push)
		var way := _way(zombie_id, field.touch_normals[i], field.touch_intents[i])
		if speed > 0.0 and _nudge(zombie_id, way * speed, delta):
			nudges += 1
			yielded_seconds += delta
	for zombie_id: int in held.keys():
		if not pushed.has(zombie_id):
			held[zombie_id] -= tuning.release_rate * delta
			if held[zombie_id] <= 0.0:
				held.erase(zombie_id)
	if held.is_empty():
		_held.erase(player_id)
	else:
		_held[player_id] = held


## A player left the night.
func forget(player_id: int) -> void:
	_held.erase(player_id)


## Seconds the push on `zombie_id` by `player_id` has been held (for the tests and the numbers).
func held_for(player_id: int, zombie_id: int) -> float:
	return _held.get(player_id, {}).get(zombie_id, 0.0)


## The way a zombie yields: away from the body, bent across the player's way by the tuning's
## `lateral`, to the side it already leans to (its id's when it is dead ahead).
func _way(zombie_id: int, normal: Vector3, intent: Vector3) -> Vector3:
	var straight := -normal
	if tuning.lateral <= 0.0:
		return straight
	var lean := intent.cross(straight).y
	var side := signf(lean)
	if absf(lean) < LEAN_MIN:
		side = 1.0 if zombie_id % 2 == 0 else -1.0
	var aside := intent.rotated(Vector3.UP, side * PI * 0.5)
	return (straight * (1.0 - tuning.lateral) + aside * tuning.lateral).normalized()


## Away from the body; with a wall that way, to one side of it and then the other (the side a
## zombie takes first is its id's, so two in a corner do not both choose the same): a zombie rolls
## aside along the wall and does not hold a player in a corner for good.
func _nudge(zombie_id: int, velocity: Vector3, delta: float) -> bool:
	if sim.nudge(zombie_id, velocity, delta):
		return true
	var turn := ASIDE if zombie_id % 2 == 0 else -ASIDE
	return (
		sim.nudge(zombie_id, velocity.rotated(Vector3.UP, turn), delta)
		or sim.nudge(zombie_id, velocity.rotated(Vector3.UP, -turn), delta)
	)


func _yield_speed(zombie_id: int, seconds: float, push: float) -> float:
	var speed := 0.0
	match tuning.policy:
		DeadContactTuning.Policy.TIMED:
			if seconds >= tuning.hold_seconds:
				speed = tuning.shove_speed
		DeadContactTuning.Policy.WADE:
			speed = tuning.wade_share * push
		DeadContactTuning.Policy.RAMP:
			if seconds >= tuning.hold_seconds:
				var along := clampf((seconds - tuning.hold_seconds) / tuning.ramp_seconds, 0.0, 1.0)
				speed = lerpf(tuning.ramp_from, tuning.ramp_to, along)
				var crowd := sim.crowd_around(zombie_id, tuning.crowd_radius)
				speed /= 1.0 + tuning.crowd_drag * float(crowd)
	var zombie: ZombieBody = sim.zombies.get(zombie_id)
	if zombie != null and zombie.profile.boss:
		speed *= tuning.boss_share
	return minf(speed, tuning.yield_cap)
