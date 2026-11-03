class_name SilhouetteMesh
extends RefCounted
## The flat shape of a wall weapon's own model, as one mesh (#829): what a wall spot shows on its
## plaque instead of the weapon's name. Made by a rule from the glb the Soldier holds, never drawn
## by hand, so a weapon whose model lands has nothing more to draw for its wall spot.
##
## Every triangle of the model's meshes is laid along the plaque with the barrel pointing right (the
## HUD's rule, `WeaponSilhouettes.turn_to_the_right`), squashed flat and merged into ONE surface. A
## spot is then one draw call (the sign it replaces was two), the mesh is shared by every spot of
## the same weapon, the material is one unshaded colour for all, and nothing is drawn into a texture
## (no `SubViewport`, no render pass at load, no new shader program): a phone's draw calls fall.
## A shop id with no model yet gets a plain firearm shape (`stand_in`), never text.
##
## A plaque that stands on end (the cabinet's) takes `upright`: the weapon lies along the plaque's
## long side, barrel up.

## The size of the picture on the plaque, metres: the longest weapon fills its width. The plaque is
## 1.7 x 0.9 m.
const FRAME := Vector2(1.5, 0.72)
## The thickness the model is squashed to, metres: flat enough to be a stencil, not zero (a
## singular matrix would spoil the mesh's normals). The depth axis is turned over with the picture
## (the model is seen from its -Z side, as the HUD does), so the faces that look at the viewer keep
## their winding and the material can cull the back faces: the same program as the night's other
## flat opaque materials, none of its own.
const THICKNESS := 0.001
## One flat colour, dark brown as the plaque's name was, and lit by nothing: the plaque behind it
## glows amber, so the shape reads in the dark. Settings as a flat opaque material the night
## already draws, so it adds no shader program (`test_wall_silhouettes`).
const MATERIAL := preload("res://assets/lot/materials/silhouette.tres")
## A quarter turn about the plaque's normal: the barrel from the right to up.
const UPRIGHT := Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3.ZERO)
## The shop ids that are not `weapon_<id>`, and the weapon each sells.
const OTHER_IDS := {&"grenades": &"grenade"}
const MODEL_DIR := "res://assets/weapons/"

static var _cache: Dictionary[StringName, ArrayMesh] = {}
static var _stand_ins: Dictionary[StringName, bool] = {}


## The catalogue id a wall spot's shop id sells (`weapon_rifle` is `rifle`, `grenades` `grenade`).
static func weapon_of(shop_id: StringName) -> StringName:
	return OTHER_IDS.get(shop_id, WeaponCatalog.catalog_id(shop_id))


## The silhouette mesh of what `shop_id` sells: the same instance every time, in the plaque's plane
## (x to the viewer's right, y up, z towards the viewer), centred on the origin.
static func mesh_for(shop_id: StringName, upright := false) -> ArrayMesh:
	var weapon := weapon_of(shop_id)
	var key := StringName("%s|up" % weapon if upright else String(weapon))
	if not _cache.has(key):
		var turn := UPRIGHT if upright else Transform3D.IDENTITY
		var made := _from_model(weapon, turn)
		_stand_ins[key] = made == null
		_cache[key] = made if made != null else stand_in(turn)
	return _cache[key]


## Whether the silhouette of `shop_id` is the stand-in because its model is not in the game yet.
static func is_stand_in(shop_id: StringName, upright := false) -> bool:
	mesh_for(shop_id, upright)
	var weapon := weapon_of(shop_id)
	return _stand_ins[StringName("%s|up" % weapon if upright else String(weapon))]


## The model file of a weapon: its own hold file's (`holds/<id>.tres`), else by the folder
## convention `assets/weapons/<id>/<id>.glb`; "" when neither has arrived. A weapon with no hold
## file of its own is not held as its class here: another weapon's shape would be a wrong sign.
static func model_path(weapon: StringName) -> String:
	var hold := _own_hold(weapon)
	if hold != null:
		return hold.scene
	var guess := "%s%s/%s.glb" % [MODEL_DIR, weapon, weapon]
	return guess if ResourceLoader.exists(guess) else ""


## A plain firearm shape (barrel, receiver, grip), for a weapon whose model has not landed.
static func stand_in(turn := Transform3D.IDENTITY) -> ArrayMesh:
	var half := FRAME * 0.5
	var boxes: Array[Rect2] = [
		Rect2(-half.x * 0.6, 0.02, half.x * 1.2, 0.14),
		Rect2(-half.x * 0.1, -0.1, half.x * 0.5, 0.26),
		Rect2(-half.x * 0.05, -half.y * 0.9, 0.16, half.y * 0.9 - 0.04),
	]
	var points := PackedVector3Array()
	var indices := PackedInt32Array()
	for box in boxes:
		var first := points.size()
		points.append(turn * Vector3(box.position.x, box.position.y, 0.0))
		points.append(turn * Vector3(box.end.x, box.position.y, 0.0))
		points.append(turn * Vector3(box.end.x, box.end.y, 0.0))
		points.append(turn * Vector3(box.position.x, box.end.y, 0.0))
		indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, MATERIAL)
	return mesh


## How many triangles a silhouette has (a test and the load numbers).
static func triangle_count(mesh: ArrayMesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return indices.size() / 3 if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3


static func _own_hold(weapon: StringName) -> WeaponHold:
	var path := PlayerAnimation.HOLDS_DIR + String(weapon) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var hold := load(path) as WeaponHold
	return hold if hold != null and hold.has_model() else null


## The weapon's model flattened into one surface, or null when it has no model.
static func _from_model(weapon: StringName, turn: Transform3D) -> ArrayMesh:
	var path := model_path(weapon)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	var holder := Node3D.new()
	holder.add_child(model)
	var meshes: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).visible:
			meshes.append(node as MeshInstance3D)
	if meshes.is_empty():
		holder.free()
		return null
	model.rotation.z = WeaponSilhouettes.turn_to_the_right(
		WeaponSilhouettes.bounds_of(meshes, model)
	)
	var bounds := WeaponSilhouettes.bounds_of(meshes, holder)
	var length := _length_of(weapon, bounds)
	var fit := minf(
		FRAME.x * WeaponSilhouettes.share_of_length(length) / maxf(bounds.size.x, 0.001),
		FRAME.y / maxf(bounds.size.y, 0.001)
	)
	# The viewer's right is the model's -X (the barrel), and the centre goes to the origin.
	var centre := bounds.get_center()
	var flatten := Transform3D(
		Basis.from_scale(Vector3(-fit, fit, -THICKNESS)),
		Vector3(centre.x * fit, -centre.y * fit, 0.0)
	)
	var merged := SurfaceTool.new()
	merged.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mesh in meshes:
		var to_plane := turn * flatten * WeaponSilhouettes.relative_transform(mesh, holder)
		for surface in mesh.mesh.get_surface_count():
			merged.append_from(mesh.mesh, surface, to_plane)
	holder.free()
	var made := merged.commit()
	if made == null or made.get_surface_count() == 0:
		return null
	made.surface_set_material(0, MATERIAL)
	return made


## The weapon's length in the HUD's units: the hold's own, else the model's longest side.
static func _length_of(weapon: StringName, bounds: AABB) -> float:
	var hold := _own_hold(weapon)
	if hold != null:
		return hold.model_length * hold.model_scale
	return maxf(bounds.size.x, bounds.size.y)
