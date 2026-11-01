class_name DampedSpring3
extends RefCounted
## `DampedSpring` on a point, with its own angular frequency for each axis (so a camera can follow
## a jump more slowly than it follows a run).

var value := Vector3.ZERO
var velocity := Vector3.ZERO


func _init(start := Vector3.ZERO) -> void:
	value = start


func snap(at: Vector3) -> void:
	value = at
	velocity = Vector3.ZERO


## Advance `delta` seconds toward `target`; `frequency` is rad/s on x, y and z.
func step(target: Vector3, frequency: Vector3, delta: float) -> void:
	for axis in 3:
		var w := frequency[axis]
		var decay := exp(-w * delta)
		var offset := value[axis] - target[axis]
		var wt := w * delta
		var new_offset := (offset * (1.0 + wt) + velocity[axis] * delta) * decay
		velocity[axis] = (velocity[axis] * (1.0 - wt) - offset * w * wt) * decay
		value[axis] = target[axis] + new_offset
