class_name LotNavmeshes
extends Resource
## The zombies' navigation meshes of the lot, baked ahead of time: one for each set of doors the
## shop can have sold (nine), saved by `tools/world/bake_lot_navmeshes.gd` as `lot_navmeshes.res`.
##
## Baking the lot takes half a second, on the main thread in the browser, which has no worker
## threads (#335). A mesh is found by the key of the geometry it was baked from
## (`NavmeshBaker.key`), not by door names: `mesh_for(lot)` hashes the lot as it stands, doors open
## or closed, and a lot that changed since the bake finds nothing, so the caller bakes (a test
## fails first: `test_lot_navmeshes.gd`). Bake again with
##
##   godot --headless --path game -s res://tools/world/bake_lot_navmeshes.gd

const PATH := "res://world/drive_in/lot_navmeshes.res"

static var _shared: LotNavmeshes

## The meshes by `NavmeshBaker.key`.
@export var meshes: Dictionary[String, NavigationMesh] = {}


## The saved meshes, or null when none were saved. Loaded once.
static func shared() -> LotNavmeshes:
	if _shared == null and ResourceLoader.exists(PATH):
		_shared = load(PATH) as LotNavmeshes
	return _shared


## The saved mesh for the lot as it stands (the doors it has open), or null when it matches none.
func mesh_for(lot: Node3D) -> NavigationMesh:
	return meshes.get(NavmeshBaker.key(NavmeshBaker.source_data(lot)))


## The sets of door ids the shop can have sold: each door's prerequisite (its `requires` meta) is in
## the set too. Nothing, the concession alone, the concession and any mix of the rest.
static func door_sets(doors: Node) -> Array[Array]:
	var ids: Array[StringName] = []
	var needs: Dictionary[StringName, StringName] = {}
	for door in doors.get_children():
		var id := StringName(door.get_meta(&"shop_id"))
		ids.append(id)
		needs[id] = StringName(door.get_meta(&"requires", ""))
	var sets: Array[Array] = []
	for mask in 1 << ids.size():
		var sold: Array[StringName] = []
		for i in ids.size():
			if mask & (1 << i):
				sold.append(ids[i])
		if sold.all(func(id: StringName) -> bool: return needs[id] == &"" or sold.has(needs[id])):
			sets.append(sold)
	return sets
