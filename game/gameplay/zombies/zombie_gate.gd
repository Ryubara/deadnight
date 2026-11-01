class_name ZombieGate
extends RefCounted
## One breach of the fence as the zombie simulation sees it: a line across the gap and the way into
## the field. A zombie that came for this gate stops short of the line while boards stand across it
## and tears them off one at a time; with none up it walks through. Pure data: how many boards stand
## is the rules' (`ZombieSim.boards_probe`).

var id: StringName = &""
## The middle of the gap, on the fence line.
var centre := Vector3.ZERO
## Flat, unit length, pointing into the field.
var inward := Vector3.FORWARD


func _init(p_id: StringName, p_centre: Vector3, p_inward: Vector3) -> void:
	id = p_id
	centre = p_centre
	inward = Vector3(p_inward.x, 0.0, p_inward.z).normalized()


## How far `point` is past the line into the field, in metres: negative outside.
func depth_of(point: Vector3) -> float:
	var offset := point - centre
	offset.y = 0.0
	return offset.dot(inward)
