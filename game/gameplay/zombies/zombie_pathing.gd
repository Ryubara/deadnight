class_name ZombiePathing
extends RefCounted
## Where to walk next. This base walks in a straight line; NavmeshPathing follows the navigation
## mesh. The simulation only asks for a path and walks it, so it runs with either.


## Waypoints from `from` to `to`, the first being near `from`.
func find_path(_from: Vector3, to: Vector3) -> PackedVector3Array:
	return PackedVector3Array([to])


## How far above the floor the points of a path lie, when they are ground at all (a navigation mesh
## sits above the floor it was baked from). A path that is NAN here is a straight line to a target,
## whose heights are not the floor's: the zombies keep the height they have.
func ground_offset() -> float:
	return NAN
