class_name DoorNavigation
extends Node
## Keeps the zombies' navigation mesh in step with the lot's doors. The mesh is baked from the CSG
## boxes with every closed slab a wall, so a bought door leaves it stale: the dead stop at a wall
## that is gone. Each `LotDoors.door_opened` puts the mesh of the lot as it now stands into the
## region.
##
## That mesh is almost always a saved one (`LotNavmeshes`, one for each set of doors the shop can
## sell), swapped in at once: nothing is baked while the game plays. Only a lot nothing was saved
## for (its geometry changed and the tool was not run; a test fails first) is baked here, on a
## worker thread (about a second on a desktop; zombies keep using the old mesh until it lands).
## In the browser, which has no worker threads, that bake would stall the page.
##
## A bake already running is not interrupted: doors opened meanwhile are caught by one more bake
## when it lands, so the mesh always ends up matching the last door, however fast they are bought.
##
## The mesh goes in as two regions (`NavmeshSplit`, `NavLayers`): the mesh but for the polygons
## across a barricade, which everyone's paths use, and those polygons, which only the dead's do. A
## person is stopped by the boards the dead's mesh runs through, and a bot given the whole mesh
## walked into them (#995).
##
## The server does this; clients draw zombies from bytes and need no mesh.

## A new mesh is in the region (the map takes it over the next few physics ticks).
signal baked

## How many meshes have been put into the region, the first included (baked or saved).
var bake_count := 0

## The meshes saved ahead of time; null bakes every one at run time (tests of the bake itself).
var saved: LotNavmeshes = LotNavmeshes.shared()

var _lot: Node3D
var _region: NavigationRegion3D
var _gaps: NavigationRegion3D
var _strips: Array[NavmeshSplit.Strip] = []
var _baking := false
var _stale := false


## Joins the mesh of the lot as it stands to the lot's navigation map and follows `doors`. A mesh
## that has to be baked is baked synchronously: the lot is not played on before it has a mesh.
func setup(lot: Node3D, doors: LotDoors) -> void:
	_lot = lot
	_region = NavigationRegion3D.new()
	_region.navigation_layers = NavLayers.WALK
	_gaps = NavigationRegion3D.new()
	_gaps.navigation_layers = NavLayers.GAP
	lot.add_child(_region)
	lot.add_child(_gaps)
	_strips = NavmeshSplit.strips_of(lot, _region.global_transform)
	var first := _saved_mesh()
	if first == null:
		if saved != null:
			push_warning("no saved navigation mesh for the lot as it stands: baking one")
		first = NavmeshBaker.bake(lot)
	_install(first)
	bake_count = 1
	doors.door_opened.connect(_on_door_opened)


## True while a bake is running or waiting to run.
func is_busy() -> bool:
	return _baking or _stale


## The saved mesh for the lot as it stands, or null.
func _saved_mesh() -> NavigationMesh:
	return null if saved == null else saved.mesh_for(_lot)


## Puts `navmesh` in the two regions, cut at the barricades.
func _install(navmesh: NavigationMesh) -> void:
	var halves := NavmeshSplit.split(navmesh, _strips)
	_region.navigation_mesh = halves[0]
	_gaps.navigation_mesh = halves[1]


func _on_door_opened(_door_id: StringName) -> void:
	if _baking:
		_stale = true
		return
	var ready := _saved_mesh()
	if ready != null:
		_install(ready)
		bake_count += 1
		baked.emit()
		return
	_baking = true
	NavmeshBaker.bake_async(_lot, _on_baked)


func _on_baked(navmesh: NavigationMesh) -> void:
	_baking = false
	if not is_instance_valid(_region):
		return
	_install(navmesh)
	bake_count += 1
	baked.emit()
	if _stale:
		_stale = false
		_on_door_opened(&"")
