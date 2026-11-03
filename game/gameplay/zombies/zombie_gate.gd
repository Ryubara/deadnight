class_name ZombieGate
extends RefCounted
## One breach of the fence as the zombie simulation sees it: a line across the gap and the way into
## the field. A zombie that came for this gate stops short of the line while boards stand across it
## and tears them off one at a time; with none up it walks through. Pure data: how many boards stand
## is the rules' (`ZombieSim.barricades`).
##
## The line has the gap's width: a zombie only works the boards of a gate it is in front of
## (`spans`). Without that the line is the whole wall, and a dead walking along the wall to the next
## window stood at its own gate's line out of sight, tearing boards it was not at, while the bot
## mended them for ever (#810).

## Metres either side of the gap's ends at which a zombie still counts as in front of the gate (its
## body is wider than a point).
const SPAN_SLACK := 0.5
## Metres out from the line within which a zombie in front of the gap is taken to be at this gate
## and not just passing it.
const REACH := 1.5

var id: StringName = &""
## The middle of the gap, on the fence line.
var centre := Vector3.ZERO
## Flat, unit length, pointing into the field.
var inward := Vector3.FORWARD
## Half the width of the gap along the fence line, in metres. `INF` is a line with no ends (a
## test's straight-line field).
var half_width := INF


func _init(
	p_id: StringName, p_centre: Vector3, p_inward: Vector3, p_half_width: float = INF
) -> void:
	id = p_id
	centre = p_centre
	inward = Vector3(p_inward.x, 0.0, p_inward.z).normalized()
	half_width = p_half_width


## How far `point` is past the line into the field, in metres: negative outside.
func depth_of(point: Vector3) -> float:
	var offset := point - centre
	offset.y = 0.0
	return offset.dot(inward)


## How far `point` is along the fence line from the middle of the gap, in metres (right of `inward`
## is positive).
func along_of(point: Vector3) -> float:
	var offset := point - centre
	offset.y = 0.0
	return offset.dot(inward.cross(Vector3.UP))


## Whether `point` is in front of the gap: within its width and the body's slack, on either side of
## the line.
func spans(point: Vector3) -> bool:
	return absf(along_of(point)) <= half_width + SPAN_SLACK


## Whether `point` is outside the line and close enough to it, in front of the gap, to be at this
## gate.
func is_at(point: Vector3) -> bool:
	var depth := depth_of(point)
	return depth < 0.0 and depth > -REACH and spans(point)
