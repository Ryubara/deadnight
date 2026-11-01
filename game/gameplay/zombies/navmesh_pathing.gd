class_name NavmeshPathing
extends ZombiePathing
## Paths through a navigation map with NavigationServer3D directly: no NavigationAgent3D nodes, so
## the server simulation needs no scene tree. The map is the world's (`World3D.navigation_map`).

var map: RID


func _init(p_map: RID) -> void:
	map = p_map


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(map, from, to, true)
