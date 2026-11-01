class_name ZombieBrain
extends RefCounted
## One zombie's decisions for one tick: the state machine. Pure: it reads the zombie, the tuning and
## where its target is, then moves the zombie between modes and sets the velocity it wants. It
## never moves the zombie itself (the simulation does) and knows nothing of nodes or paths beyond
## the next waypoint.
##
## EMERGING -> CHASE <-> ATTACK, STAGGER from a hit (CHASE or ATTACK), DYING from the rules.


## Advances `zombie` by `delta`. `target_pos` is where its target stands (ignored without one);
## `waypoint` the next point on the way there; `move_speed` its speed on the ground it stands on.
## Returns the strike that landed this tick as `{"zombie_id", "target_id", "damage"}`, or `{}`.
static func step(
	zombie: ZombieState,
	tuning: ZombieTuning,
	delta: float,
	has_target: bool,
	target_pos: Vector3,
	waypoint: Vector3,
	move_speed: float
) -> Dictionary:
	zombie.mode_time += delta
	zombie.velocity = Vector3.ZERO
	var strike := {}
	match zombie.mode:
		ZombieState.Mode.EMERGING:
			if zombie.mode_time >= tuning.emerge_seconds:
				zombie.enter(ZombieState.Mode.CHASE)
		ZombieState.Mode.CHASE:
			_chase(zombie, tuning, delta, has_target, target_pos, waypoint, move_speed)
		ZombieState.Mode.ATTACK:
			strike = _attack(zombie, tuning, delta, has_target, target_pos)
		ZombieState.Mode.STAGGER:
			if zombie.mode_time >= tuning.stagger_seconds:
				zombie.enter(ZombieState.Mode.CHASE)
	zombie.move_speed = zombie.velocity.length()
	return strike


## A hit that did not kill: the zombie stops and loses its swing.
static func stagger(zombie: ZombieState) -> void:
	if zombie.mode == ZombieState.Mode.CHASE or zombie.mode == ZombieState.Mode.ATTACK:
		zombie.enter(ZombieState.Mode.STAGGER)


static func die(zombie: ZombieState) -> void:
	if zombie.mode != ZombieState.Mode.DYING:
		zombie.enter(ZombieState.Mode.DYING)


static func _chase(
	zombie: ZombieState,
	tuning: ZombieTuning,
	delta: float,
	has_target: bool,
	target_pos: Vector3,
	waypoint: Vector3,
	move_speed: float
) -> void:
	if not has_target:
		return
	if _flat_distance(zombie.position, target_pos) <= tuning.reach:
		zombie.enter(ZombieState.Mode.ATTACK)
		return
	var to_waypoint := waypoint - zombie.position
	to_waypoint.y = 0.0
	if to_waypoint.length_squared() > 0.0001:
		zombie.velocity = to_waypoint.normalized() * move_speed
		_turn_toward(zombie, to_waypoint, tuning.turn_rate * delta)


static func _attack(
	zombie: ZombieState, tuning: ZombieTuning, delta: float, has_target: bool, target_pos: Vector3
) -> Dictionary:
	var strike := {}
	if has_target:
		var to_target := target_pos - zombie.position
		to_target.y = 0.0
		_turn_toward(zombie, to_target, tuning.turn_rate * delta)
		if not zombie.struck and zombie.mode_time >= tuning.windup_seconds:
			zombie.struck = true
			if to_target.length() <= tuning.reach + tuning.strike_slack:
				strike = {
					"zombie_id": zombie.id,
					"target_id": zombie.target_id,
					"damage": tuning.strike_damage,
				}
	if zombie.mode_time >= tuning.swing_seconds:
		zombie.enter(ZombieState.Mode.CHASE)
	return strike


static func _turn_toward(zombie: ZombieState, direction: Vector3, max_step: float) -> void:
	if direction.length_squared() > 0.0001:
		zombie.yaw = lerp_angle(zombie.yaw, atan2(direction.x, direction.z), minf(1.0, max_step))


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
