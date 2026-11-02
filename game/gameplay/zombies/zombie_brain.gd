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
## Returns the strike that landed this tick as `{"zombie_id", "target_id", "damage", "knockback"}`
## (the zombie's own, from its profile), or `{}`.
static func step(
	zombie: ZombieBody,
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
		ZombieBody.Mode.EMERGING:
			if zombie.mode_time >= zombie.profile.emerge:
				zombie.enter(ZombieBody.Mode.CHASE)
		ZombieBody.Mode.CHASE:
			_chase(zombie, tuning, delta, has_target, target_pos, waypoint, move_speed)
		ZombieBody.Mode.ATTACK:
			strike = _attack(zombie, tuning, delta, has_target, target_pos)
		ZombieBody.Mode.STAGGER:
			if zombie.mode_time >= maxf(zombie.profile.stagger, zombie.stun_seconds):
				zombie.enter(ZombieBody.Mode.CHASE)
	zombie.move_speed = zombie.velocity.length()
	return strike


## Turns the zombie toward `point` for one tick (a zombie standing about a lure).
static func face(zombie: ZombieBody, tuning: ZombieTuning, delta: float, point: Vector3) -> void:
	var to_point := point - zombie.position
	to_point.y = 0.0
	_turn_toward(zombie, to_point, tuning.turn_rate * delta)


## A hit that did not kill: the zombie stops and loses its swing for the profile's stagger time.
static func stagger(zombie: ZombieBody) -> void:
	if zombie.mode == ZombieBody.Mode.CHASE or zombie.mode == ZombieBody.Mode.ATTACK:
		zombie.enter(ZombieBody.Mode.STAGGER)


## A blast: the zombie is held for `seconds` (a stagger that is already on starts over), however
## short its own stagger is. One that is still rising or already down is left alone.
static func stun(zombie: ZombieBody, seconds: float) -> void:
	if zombie.mode == ZombieBody.Mode.CHASE or zombie.mode == ZombieBody.Mode.ATTACK:
		zombie.enter(ZombieBody.Mode.STAGGER)
	if zombie.mode == ZombieBody.Mode.STAGGER:
		zombie.mode_time = 0.0
		zombie.stun_seconds = maxf(seconds, 0.0)


static func die(zombie: ZombieBody) -> void:
	if zombie.mode != ZombieBody.Mode.DYING:
		zombie.enter(ZombieBody.Mode.DYING)


static func _chase(
	zombie: ZombieBody,
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
		zombie.enter(ZombieBody.Mode.ATTACK)
		return
	var to_waypoint := waypoint - zombie.position
	to_waypoint.y = 0.0
	if to_waypoint.length_squared() > 0.0001:
		zombie.velocity = to_waypoint.normalized() * move_speed
		_turn_toward(zombie, to_waypoint, tuning.turn_rate * delta)


static func _attack(
	zombie: ZombieBody, tuning: ZombieTuning, delta: float, has_target: bool, target_pos: Vector3
) -> Dictionary:
	var strike := {}
	var profile := zombie.profile
	if has_target:
		var to_target := target_pos - zombie.position
		to_target.y = 0.0
		_turn_toward(zombie, to_target, tuning.turn_rate * delta)
		if not zombie.struck and zombie.mode_time >= profile.windup:
			zombie.struck = true
			if to_target.length() <= tuning.reach + tuning.strike_slack:
				strike = {
					"zombie_id": zombie.id,
					"target_id": zombie.target_id,
					"damage": profile.damage,
					"knockback": profile.knockback,
				}
	if zombie.mode_time >= profile.windup + tuning.recovery_seconds():
		zombie.enter(ZombieBody.Mode.CHASE)
	return strike


static func _turn_toward(zombie: ZombieBody, direction: Vector3, max_step: float) -> void:
	if direction.length_squared() > 0.0001:
		zombie.yaw = lerp_angle(zombie.yaw, atan2(direction.x, direction.z), minf(1.0, max_step))


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
