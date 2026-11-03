class_name WorldCast
extends RefCounted
## The grenade's `cast` made from the physics space: the first solid surface on a segment, with its
## normal. Like `WorldProbe` for shots, it is the only place the grenades touch the physics server,
## so everything else stays testable with plain functions.

## The physics layers of walls, props and floors and of players' bodies (the same the shots use).
const WORLD_MASK := PhysicsLayers.WORLD | PhysicsLayers.BODY

var _space: PhysicsDirectSpaceState3D
var _mask: int


func _init(space: PhysicsDirectSpaceState3D, mask: int = WORLD_MASK) -> void:
	_space = space
	_mask = mask


## `{}` when clear, else `{"distance": float, "normal": Vector3}`.
func cast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, _mask)
	var hit := _space.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"distance": from.distance_to(hit["position"]), "normal": hit["normal"]}


func callable() -> Callable:
	return cast
