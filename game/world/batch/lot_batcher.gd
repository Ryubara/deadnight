class_name LotBatcher
extends RefCounted
## Draws a map's still scenery as a few meshes instead of a thousand (#728). A night builds the map
## from the scene as it is written (every barrel, car and wall where it was put), and then `batch`
## folds what never moves into `MeshBatch` cells: the models of the props, the cars, the fixtures,
## the lamp posts' poles and the boxes the map is built of. Nothing in the scene file changes, so a
## prop moved by hand in the editor moves in the night too, and every node a script or the rules
## reach (the doors, the barricades, the machines, a lamp's bulb, the screen) is left alone.
##
## A solid CSG box is hidden, not removed: it is the collision of the wall. Its mesh is what is
## drawn by the batch.

## A piece whose longest side is under this is a small prop (a paper, a cone, a plank): one the
## camera can stop drawing from far away (`small_range`).
const SMALL_SIDE := 2.0
## A piece longer than this many cells is left as it is (the ground, a long wall): in a cell it
## would make the cell's box the size of the map.
const LONGEST_IN_CELLS := 1.5
## Scenes whose models are still: every mesh in an instance of one of these folders or files may be
## batched.
const STILL_SCENES: PackedStringArray = [
	"res://world/drive_in/props/",
	"res://world/drive_in/fixtures/",
	"res://world/drive_in/car.tscn",
	"res://world/drive_in/wreck.tscn",
]
## The scripts a still scene may carry (the car puts its model in `_ready`, the rest only name
## things).
const STILL_SCRIPTS: PackedStringArray = ["res://world/drive_in/car.gd"]
## The parts of a lamp post that never change; its bulb (`Head`), halo and pool follow the power.
const LAMP_POST_STILL: PackedStringArray = ["Post", "Housing"]
const BATCH_NODE := "Batched"
const GROUP_SMALL := &"small"
## A node that draws parts which move (a machine) names the ones that do not by this method, an
## `Array[MeshInstance3D]`; the batch takes those, and the machine keeps the rest.
const STILL_PARTS := &"still_meshes"
## The lights a fight adds to a mesh on top of the map's own: a muzzle flash, and a blast or a
## grenade's lamp. A batch leaves room for them, as the map does
## (`docs/research/night-environment.md`).
const DYNAMIC_LIGHTS := 2

## Whether a night batches its map. A bench turns it off to compare (`?batch=0`).
static var enabled := true
## The distance in metres past which the small props are not drawn, 0 for always (`?smallrange=D` on
## a bench).
static var small_range := 0.0
## For a bench (`?batch=toggle`): keep the nodes a batch replaces, hidden, so `switch` can show them
## again and a page can compare the two ways of drawing inside one run
## (`tools/web_smoke/phone_frames.py`).
static var keep_sources := false

static var _kept: Array[Node3D] = []
static var _holder: Node3D


## Whether a night on `info` batches its map: the map asks for it, the bench has not turned it off,
## and there is a screen to draw to (a game server draws nothing, and the batch would cost it time
## and memory).
static func wanted(info: MapInfo, headless: bool = DisplayServer.get_name() == "headless") -> bool:
	return enabled and info != null and info.batch_still and not headless


## Draws the last batched map from its batches (`true`) or from the nodes they replaced (`false`).
## Only after a batch that kept its sources (`keep_sources`).
static func switch(on: bool) -> void:
	if not is_instance_valid(_holder):
		return
	_holder.visible = on
	for source in _kept:
		if is_instance_valid(source):
			source.visible = not on


## Folds the still scenery under `world` into batches. `cell` is the cell's side in metres,
## `small_range`
## the distance past which the small props are not drawn (0 for always). Returns what it did:
## `pieces`, `surfaces_before`, `surfaces_after`, `cells`, `removed` and `msec`.
static func batch(
	world: Node3D, cell: float = MeshBatch.DEFAULT_CELL, small_range: float = 0.0
) -> Dictionary:
	var began := Time.get_ticks_usec()
	# Every light the map has, lit or not: a circuit that is off now is on later.
	var lights: Array[Light3D] = []
	for light in world.find_children("*", "Light3D", true, false):
		lights.append(light as Light3D)
	var merged := MeshBatch.new(cell, lights, LightReach.limit() - DYNAMIC_LIGHTS)
	var sources: Array[Node3D] = []
	var surfaces_before := 0
	var pieces := 0
	var skipped := {}
	var candidates: Array[MeshInstance3D] = []
	for node in world.find_children("*", "MeshInstance3D", true, false):
		if _still_model(node as MeshInstance3D, world):
			candidates.append(node as MeshInstance3D)
	for node in world.find_children("*", "Node3D", true, false):
		if node.has_method(STILL_PARTS):
			for part: MeshInstance3D in node.call(STILL_PARTS):
				if _still_part(part):
					candidates.append(part)
	for mesh_node in candidates:
		var count := mesh_node.mesh.get_surface_count()
		var xform := mesh_node.global_transform
		if not _fits(mesh_node.mesh.get_aabb(), xform, cell):
			continue
		if not _all_batchable(mesh_node, count, xform):
			continue
		for surface in count:
			merged.add(
				mesh_node.mesh,
				surface,
				xform,
				mesh_node.get_active_material(surface),
				_group(mesh_node.mesh.get_aabb(), xform)
			)
		surfaces_before += count
		pieces += count
		sources.append(mesh_node)
	for node in world.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		var made := _csg_pieces(shape, world, cell, skipped)
		if made.is_empty():
			continue
		for piece: Array in made:
			merged.add(piece[0], piece[1], piece[2], piece[3], piece[4])
		surfaces_before += made.size()
		pieces += made.size()
		sources.append(shape)
	# The pieces were given in the world's own space, so the holder takes no place from `world`.
	var holder := Node3D.new()
	holder.name = BATCH_NODE
	holder.top_level = true
	world.add_child(holder)
	var built := merged.build(holder)
	if small_range > 0.0:
		for instance in built:
			if instance.get_meta(MeshBatch.GROUP_META) == GROUP_SMALL:
				instance.visibility_range_end = small_range
	var removed := 0
	for source in sources:
		if source is CSGShape3D or keep_sources:
			source.visible = false
		else:
			source.get_parent().remove_child(source)
			source.queue_free()
		removed += 1
	if keep_sources:
		_kept = sources
		_holder = holder
	return {
		"pieces": pieces,
		"surfaces_before": surfaces_before,
		"surfaces_after": merged.surface_count(),
		"cells": merged.cell_count(),
		"removed": removed,
		"skipped_boxes": skipped,
		"msec": (Time.get_ticks_usec() - began) / 1000.0,
	}


## Whether a mesh of the map is a model that stands still: seen, not skinned, on the default layer,
## with no override a script made, and in a scene of `STILL_SCENES` (or a lamp post's pole).
static func _still_model(node: MeshInstance3D, world: Node3D) -> bool:
	if node.material_override != null:
		return false
	return _still_part(node) and _in_still_scene(node, world)


## Whether a mesh is plain enough to be drawn from a batch: seen, not skinned, on the default layer,
## with no overlay and no range of sight and no override of one surface (a script made it, to
## change it).
static func _still_part(node: MeshInstance3D) -> bool:
	if node.mesh == null or not node.is_visible_in_tree() or node.skin != null:
		return false
	if (
		node.layers != 1
		or node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		or node.material_overlay != null
		or node.visibility_range_end > 0.0
	):
		return false
	for surface in node.mesh.get_surface_count():
		if node.get_surface_override_material(surface) != null:
			return false
	return true


## Whether the scene `node` belongs to is one that stands still and no script above it moves it.
static func _in_still_scene(node: Node, world: Node3D) -> bool:
	var scene := ""
	var at := node.get_parent()
	while at != null and at != world:
		var script := at.get_script() as Script
		if script != null and not STILL_SCRIPTS.has(script.resource_path):
			return false
		if scene == "" and at.scene_file_path.get_extension() == "tscn":
			scene = at.scene_file_path
		at = at.get_parent()
	if scene == "":
		return false
	for allowed in STILL_SCENES:
		if scene.begins_with(allowed):
			return true
	return false


## The surfaces of a solid box of the map that are still, as `[mesh, surface, xform, material,
## group]`, or none: a CSG shape that is not the root of its tree, is hidden, is under a script, or
## wears anything but a plain material is left as it is.
static func _csg_pieces(
	shape: CSGShape3D, world: Node3D, cell: float, skipped: Dictionary
) -> Array:
	var none := []
	if shape.get_parent() is CSGShape3D or not shape.is_visible_in_tree():
		return none
	if shape.layers != 1 or shape.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		return _skip(skipped, "layer or shadow")
	if not _still_csg_owner(shape, world):
		return _skip(skipped, "under a script")
	var built := shape.get_meshes()
	if built.size() < 2 or not (built[1] is Mesh):
		return _skip(skipped, "no mesh yet")
	var mesh := built[1] as Mesh
	var xform := shape.global_transform
	if mesh.get_surface_count() == 0:
		return _skip(skipped, "no surface")
	if not _fits(mesh.get_aabb(), xform, cell):
		return _skip(skipped, "too long")
	var found := []
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if not MeshBatch.can_batch(material) or xform.basis.determinant() <= 0.0:
			var why := "material " + (material.get_class() if material != null else "none")
			return _skip(skipped, why)
		found.append([mesh, surface, xform, material, _group(mesh.get_aabb(), xform)])
	return found


static func _skip(skipped: Dictionary, why: String) -> Array:
	skipped[why] = int(skipped.get(why, 0)) + 1
	return []


## A box of the map is still when no script sits above it, but for a lamp post's pole and housing.
static func _still_csg_owner(shape: CSGShape3D, world: Node3D) -> bool:
	var at := shape.get_parent()
	while at != null and at != world:
		var script := at.get_script() as Script
		if script != null:
			return at is LampPost and LAMP_POST_STILL.has(String(shape.name))
		at = at.get_parent()
	return true


static func _all_batchable(node: MeshInstance3D, count: int, xform: Transform3D) -> bool:
	if xform.basis.determinant() <= 0.0:
		return false
	for surface in count:
		if not MeshBatch.can_batch(node.get_active_material(surface)):
			return false
	return true


## Whether a mesh at `xform` is small enough for a cell.
static func _fits(local: AABB, xform: Transform3D, cell: float) -> bool:
	var size := (xform * local).size
	return maxf(size.x, size.z) <= cell * LONGEST_IN_CELLS


static func _group(local: AABB, xform: Transform3D) -> StringName:
	var size := (xform * local).size
	return GROUP_SMALL if maxf(size.x, maxf(size.y, size.z)) < SMALL_SIDE else &"large"
