class_name DoorNavigation
extends Node
## Keeps the zombies' navigation mesh in step with the lot's doors. The mesh is baked from the CSG
## boxes with every closed slab a wall, so a bought door leaves it stale: the dead stop at a wall
## that is gone. Each `LotDoors.door_opened` bakes a new mesh on a worker thread (about a second;
## zombies keep using the old one until it lands) and swaps it into the region.
##
## A bake already running is not interrupted: doors opened meanwhile are caught by one more bake
## when it lands, so the mesh always ends up matching the last door, however fast they are bought.
## The server does this; clients draw zombies from bytes and need no mesh.

## A new mesh is in the region (the map takes it over the next few physics ticks).
signal baked

## How many meshes have been baked, the first included.
var bake_count := 0

var _lot: Node3D
var _region: NavigationRegion3D
var _baking := false
var _stale := false


## Bakes the lot as it stands, joins the mesh to the lot's navigation map and follows `doors`. The
## first bake is synchronous: the lot is not played on before it has a mesh.
func setup(lot: Node3D, doors: LotDoors) -> void:
	_lot = lot
	_region = NavigationRegion3D.new()
	_region.navigation_mesh = NavmeshBaker.bake(lot)
	bake_count = 1
	lot.add_child(_region)
	doors.door_opened.connect(_on_door_opened)


## True while a bake is running or waiting to run.
func is_busy() -> bool:
	return _baking or _stale


func _on_door_opened(_door_id: StringName) -> void:
	if _baking:
		_stale = true
		return
	_baking = true
	NavmeshBaker.bake_async(_lot, _on_baked)


func _on_baked(navmesh: NavigationMesh) -> void:
	_baking = false
	if not is_instance_valid(_region):
		return
	_region.navigation_mesh = navmesh
	bake_count += 1
	baked.emit()
	if _stale:
		_stale = false
		_on_door_opened(&"")
