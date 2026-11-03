class_name WorldProbe
extends RefCounted
## The server's `world_ray` made from the physics space: the distance to the first solid thing on a
## segment. It is the only place the weapons code touches the physics server, so everything else
## stays testable with a box and a Callable.

## The physics layer of walls, props and doors that stop a shot (layer 1 by default).
const WORLD_MASK := 1
## Moving bodies `static_distance` looks past on one ray, at the most.
const STATIC_TRIES := 6

var _space: PhysicsDirectSpaceState3D
var _mask: int


func _init(space: PhysicsDirectSpaceState3D, mask: int = WORLD_MASK) -> void:
	_space = space
	_mask = mask


## Distance from `from` to the first surface on the way to `to`, or -1.0 when clear.
func distance(from: Vector3, to: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, to, _mask)
	var hit := _space.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	return from.distance_to(hit["position"])


func callable() -> Callable:
	return distance


## Like `distance`, but only what stands still counts: walls, props and boards (static bodies and
## the lot's CSG boxes), not a person, a zombie or a thrown thing in the way. The bots ask whether a
## way is walled off, which is not the same as whether someone stands on it.
func static_distance(from: Vector3, to: Vector3) -> float:
	var skipped: Array[RID] = []
	for _try in STATIC_TRIES:
		var query := PhysicsRayQueryParameters3D.create(from, to, _mask)
		query.exclude = skipped
		var hit := _space.intersect_ray(query)
		if hit.is_empty():
			return -1.0
		var collider: Object = hit["collider"]
		if collider is StaticBody3D or collider is CSGShape3D:
			return from.distance_to(hit["position"])
		skipped.append(hit["rid"])
	return -1.0


func static_callable() -> Callable:
	return static_distance
