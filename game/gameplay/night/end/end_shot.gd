class_name EndShot
extends Resource
## One authored angle of a map's end-of-night camera (`EndCamera`): the lens drifts in a straight
## line from `lens_from` to `lens_to` while it looks at a point that drifts from `look_from` to
## `look_to`, so no picture is still. In metres of the map. A test checks every shot of every map
## against the walls (`test_end_shots.gd`): the lens is never inside one along the whole drift and
## what it looks at is in sight.

@export var lens_from := Vector3.ZERO
@export var lens_to := Vector3.ZERO
@export var look_from := Vector3.ZERO
@export var look_to := Vector3.ZERO
@export_range(30.0, 100.0, 1.0, "suffix:°") var fov := 62.0


## A basis looking along `direction` with the sky up, even straight down or up.
static func facing(direction: Vector3) -> Basis:
	var along := direction.normalized() if not direction.is_zero_approx() else Vector3.FORWARD
	var up := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(along, up)


## The lens `fraction` (0 to 1) of the way through the shot.
func lens(fraction: float) -> Vector3:
	return lens_from.lerp(lens_to, fraction)


## The point the lens looks at `fraction` of the way through.
func look(fraction: float) -> Vector3:
	return look_from.lerp(look_to, fraction)


## The pose of the lens `fraction` of the way through.
func pose(fraction: float) -> Transform3D:
	var at := lens(fraction)
	return Transform3D(EndShot.facing(look(fraction) - at), at)
