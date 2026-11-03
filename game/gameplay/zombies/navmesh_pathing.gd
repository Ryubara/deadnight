class_name NavmeshPathing
extends ZombiePathing
## Paths through a navigation map with NavigationServer3D directly: no NavigationAgent3D nodes, so
## the server simulation needs no scene tree. The map is the world's (`World3D.navigation_map`).

## The baked mesh lies this far above the floor: the baker rounds the floor up to a whole cell
## (0.25 m) and the mesh then sits another cell-height above it. Measured on the lot: flat ground
## 0.35 m, the roost's floor 0.45 m, the ramp 0.4 to 0.5 m.
const GROUND_OFFSET := 0.4

var map: RID


func _init(p_map: RID) -> void:
	map = p_map


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(map, from, to, true)


func ground_offset() -> float:
	return GROUND_OFFSET
