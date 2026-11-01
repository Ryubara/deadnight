class_name ZombiePathing
extends RefCounted
## Where to walk next. This base walks in a straight line; NavmeshPathing follows the navigation
## mesh. The simulation only asks for a path and walks it, so it runs with either.


## Waypoints from `from` to `to`, the first being near `from`.
func find_path(_from: Vector3, to: Vector3) -> PackedVector3Array:
	return PackedVector3Array([to])
