class_name ZombieLure
extends RefCounted
## Something that calls the dead: a burning flare. For `left` seconds every zombie within `radius`
## (metres, along the ground) walks to `position` instead of to a player. It is plain data the
## server's `ZombieSim` steps; it hurts no one.

var id: int = 0
var position := Vector3.ZERO
var radius: float = 0.0
var left: float = 0.0


func _init(p_id: int, p_position: Vector3, p_radius: float, p_seconds: float) -> void:
	id = p_id
	position = p_position
	radius = p_radius
	left = p_seconds


## Whether a zombie standing at `at` hears it.
func reaches(at: Vector3) -> bool:
	return Vector2(at.x - position.x, at.z - position.z).length() <= radius
