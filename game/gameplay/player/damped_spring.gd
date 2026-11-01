class_name DampedSpring
extends RefCounted
## A critically damped spring on one number: it reaches its target as fast as it can without
## overshooting, keeps its velocity so a start and a stop have no kink, and is exact for any time
## step (it is the closed-form solution, not an Euler step), so it feels the same at 30, 60 or
## 144 frames a second. See docs/research/shoulder-camera.md.

## Angular frequency (rad/s) at which the error is down to 5 percent after `1 / frequency * SETTLE`
## seconds: the error falls as (1 + w t) e^(-w t), which is 0.05 at w t = 4.75.
const SETTLE := 4.75

var value := 0.0
var velocity := 0.0


## Seconds a spring of `frequency` takes to close 95 percent of a step.
static func settle_time(frequency: float) -> float:
	return SETTLE / frequency


func _init(start := 0.0) -> void:
	value = start


## Put the spring at `at`, at rest.
func snap(at: float) -> void:
	value = at
	velocity = 0.0


## Advance `delta` seconds toward `target` with angular frequency `frequency` (rad/s).
func step(target: float, frequency: float, delta: float) -> void:
	var next := advance(value - target, velocity, frequency, delta)
	value = target + next.x
	velocity = next.y


## The same step on a bare offset from the target and its velocity, for a caller that wraps them
## (an angle): returns Vector2(new offset, new velocity).
static func advance(offset: float, velocity: float, frequency: float, delta: float) -> Vector2:
	var decay := exp(-frequency * delta)
	var wt := frequency * delta
	return Vector2(
		(offset * (1.0 + wt) + velocity * delta) * decay,
		(velocity * (1.0 - wt) - offset * frequency * wt) * decay
	)
