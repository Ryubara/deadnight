class_name ZombieSolid
extends RefCounted
## A solid box in the lot that moves in the course of a night (the prize crane's cabinet,
## `CraneBlock`), as the dead's sim sees it: plain data, no node. The cabinet is solid to every
## sight line and shot, and the dead are not physics bodies, so a dead that stands inside it cannot
## be seen or hit by anyone while it swings at whoever stands beside it: the round waits on it for
## ever (#1352). `ZombieSim` keeps the dead out of the boxes it holds (`ZombieSim.solids`).

## Metres the dead are put clear of a face, so that its hit zones (the widest, 0.35 m about the
## feet) are all outside the wall.
const CLEARANCE := 0.45
## Metres below the box's floor that still count as inside it (a zombie's feet sit a hair under the
## floor's top).
const FEET_SLACK := 0.5

## Whether the box stands anywhere.
var enabled := false
## Counts every placement; a sim that sees it change puts the dead that stand inside out, even a
## walking one (the box has just landed on them).
var generation := 0

var _to_local := Transform3D.IDENTITY
var _to_world := Transform3D.IDENTITY
var _half := Vector3.ZERO
var _height := 0.0


## The box is at `transform` (its middle of the floor) and is `size` metres across, `size.y` high.
func place(transform: Transform3D, size: Vector3) -> void:
	_to_world = transform
	_to_local = transform.affine_inverse()
	_half = size * 0.5
	_height = size.y
	enabled = true
	generation += 1


## The box stands nowhere.
func clear() -> void:
	if enabled:
		enabled = false
		generation += 1


## Whether `point` is inside the box grown by `margin` on its four sides.
func contains(point: Vector3, margin: float = 0.0) -> bool:
	if not enabled:
		return false
	var local := _to_local * point
	return (
		absf(local.x) < _half.x + margin
		and absf(local.z) < _half.z + margin
		and local.y > -FEET_SLACK
		and local.y < _height
	)


## A place `CLEARANCE` outside one of the box's four faces, at the height of `point`: the face whose
## place is nearest `toward` (the one the dead swings at: it stands on that side, where it can be
## seen), or the nearest face when `toward` is `Vector3.INF`.
func outside(point: Vector3, toward: Vector3 = Vector3.INF) -> Vector3:
	var local := _to_local * point
	var wanted := local if toward == Vector3.INF else _to_local * toward
	var best := local
	var best_apart := INF
	for axis in 2:
		for side in [-1.0, 1.0]:
			var place := local
			if axis == 0:
				place.x = side * (_half.x + CLEARANCE)
			else:
				place.z = side * (_half.z + CLEARANCE)
			var apart := place.distance_squared_to(wanted)
			if toward == Vector3.INF:
				# The nearest face: the way out that moves the dead least.
				apart = place.distance_squared_to(local)
			if apart < best_apart:
				best_apart = apart
				best = place
	return _to_world * best
