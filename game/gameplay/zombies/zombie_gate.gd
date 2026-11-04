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
## The sill (#915): every breach is a window, never a door. A zombie that walks through one with its
## boards down climbs over the sill: it is lifted to the sill's height over `CLIMB_RAMP` metres on
## each side of the wall's thickness, at its own pace (a slower climb moved the bots' night: the
## solo bot's weapon came a break later in two seeds of four).
## The navigation mesh runs through the gap at the ground (the sill is a body the baker never
## reads), so the climb is the simulation's own link across it.
const CLIMB_RAMP := 0.6

var id: StringName = &""
## The middle of the gap, on the fence line.
var centre := Vector3.ZERO
## Flat, unit length, pointing into the field.
var inward := Vector3.FORWARD
## Half the width of the gap along the fence line, in metres. `INF` is a line with no ends (a
## test's straight-line field).
var half_width := INF
## How high the sill is above the ground (0 for a gate with none: a test's straight-line field), how
## thick the wall it is cut in, and half the opening's width, where the sill is.
var sill := 0.0
var thickness := 0.4
var opening_half := INF


func _init(
	p_id: StringName,
	p_centre: Vector3,
	p_inward: Vector3,
	p_half_width: float = INF,
	p_sill: float = 0.0,
	p_thickness: float = 0.4,
	p_opening_half: float = INF
) -> void:
	id = p_id
	centre = p_centre
	inward = Vector3(p_inward.x, 0.0, p_inward.z).normalized()
	half_width = p_half_width
	sill = p_sill
	thickness = p_thickness
	opening_half = p_opening_half if is_finite(p_opening_half) else p_half_width


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


## Whether `point` is in the opening's reach, where the sill lifts a zombie: over the sill and the
## ramps on both sides of it, within the opening's width.
func climbs(point: Vector3) -> bool:
	if sill <= 0.0:
		return false
	# The depth first: nearly every zombie of the night is far from every wall.
	if absf(depth_of(point)) >= thickness * 0.5 + CLIMB_RAMP:
		return false
	return absf(along_of(point)) <= opening_half


## How far above the ground the sill carries a zombie at `point`: the whole sill over the wall's
## thickness, falling smoothly to nothing at the ends of the ramps.
func lift_at(point: Vector3) -> float:
	if not climbs(point):
		return 0.0
	var half := thickness * 0.5
	return sill * (1.0 - smoothstep(half, half + CLIMB_RAMP, absf(depth_of(point))))
