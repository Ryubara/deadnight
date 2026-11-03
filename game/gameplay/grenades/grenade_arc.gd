class_name GrenadeArc
extends RefCounted
## Where a throw will go: the same `GrenadeState` stepping the server uses, run ahead on the same
## fixed step, so the preview line, the client's prediction and the server's grenade agree on the
## landing point (same def, same input, same world: same answer).


## Flies a throw from `hand` along `aim` until it rests or `max_time` passes. Answers
## `{"points": PackedVector3Array, "landing": Vector3, "bounces": int, "rest_time": float,
## "rested": bool}`; `landing` is the last position, `rest_time` when it stopped (or `max_time`).
## `points` has one point per `sample_every` steps, for drawing. `bodies` is the zombies in the way
## (`ZombieBump`), as the server flies them; without it the throw flies through the dead.
static func predict(
	def: GrenadeDef,
	hand: Vector3,
	aim: Vector3,
	carrier_velocity: Vector3,
	underarm: bool,
	cast: Callable,
	delta: float,
	max_time: float = 6.0,
	sample_every: int = 3,
	bodies: Callable = Callable()
) -> Dictionary:
	var state := GrenadeState.new(
		0, 0, def, hand, def.launch_velocity(aim, underarm, carrier_velocity), INF
	)
	var points := PackedVector3Array([hand])
	var steps := ceili(max_time / delta)
	var step_count := 0
	while step_count < steps and not state.at_rest:
		state.step(delta, cast, bodies)
		step_count += 1
		if step_count % sample_every == 0:
			points.append(state.position)
	points.append(state.position)
	return {
		"points": points,
		"landing": state.position,
		"bounces": state.bounces,
		"rest_time": step_count * delta,
		"rested": state.at_rest,
	}
