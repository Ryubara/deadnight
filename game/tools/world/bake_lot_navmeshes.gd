extends SceneTree
## Bakes the lot's zombie navigation mesh for every set of doors the shop can have sold and saves
## them as `res://world/drive_in/lot_navmeshes.res` (`LotNavmeshes`). Run it after the lot's
## geometry changes (a test fails until it is run), from the repository root:
##
##   godot --headless --path game -s res://tools/world/bake_lot_navmeshes.gd
##
## Each set is baked on a lot of its own, built as the night builds it (the scene, a few physics
## frames, then the doors opened through `LotDoors`), so the key of its geometry is the one the
## night looks up. Prints one line a set and exits 1 when nothing could be saved.
##
## Another map's meshes (the second map's, #631) with `-- --scene=<res path> --out=<res path>`:
##
##   godot --headless --path game -s res://tools/world/bake_lot_navmeshes.gd -- \
##     --scene=res://world/smallmap/smallmap_greybox.tscn \
##     --out=res://world/smallmap/smallmap_navmeshes.res

const GREYBOX := "res://world/drive_in_greybox.tscn"
const SETTLE_FRAMES := NightWorld.SETTLE_FRAMES

var _scene := GREYBOX
var _out := LotNavmeshes.PATH


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			_scene = argument.trim_prefix("--scene=")
		elif argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	_run()


func _run() -> void:
	var saved := LotNavmeshes.new()
	var sets := _door_sets()
	for sold: Array[StringName] in sets:
		var lot := (load(_scene) as PackedScene).instantiate() as Node3D
		root.add_child(lot)
		for _i in SETTLE_FRAMES:
			await physics_frame
		var doors := lot.get_node("Doors") as LotDoors
		for id in sold:
			doors.open(id)
		var started := Time.get_ticks_msec()
		var key := NavmeshBaker.key(NavmeshBaker.source_data(lot))
		var navmesh := NavmeshBaker.bake(lot)
		saved.meshes[key] = navmesh
		print(
			(
				"doors %s: %d polygons, %d vertices, %d ms"
				% [
					sold,
					navmesh.get_polygon_count(),
					navmesh.get_vertices().size(),
					Time.get_ticks_msec() - started
				]
			)
		)
		root.remove_child(lot)
		lot.free()
	var error := ResourceSaver.save(saved, _out, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("cannot save %s: %s" % [_out, error_string(error)])
		quit(1)
		return
	print("saved %d meshes to %s" % [saved.meshes.size(), _out])
	quit(0)


func _door_sets() -> Array[Array]:
	var lot := (load(_scene) as PackedScene).instantiate()
	var sets := LotNavmeshes.door_sets(lot.get_node("Doors"))
	lot.free()
	return sets
