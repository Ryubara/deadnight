class_name WeaponSilhouettes
extends Node
## The flat shape of each weapon, drawn from its own model (#682): the same glb the Soldier holds
## (`WeaponHoldMap.hold_for`), seen from its side with every surface one unshaded white, into a
## transparent texture that a part tints. Nothing is drawn by hand, so a new weapon model gets its
## silhouette with its hold file. Each weapon is drawn once, the first time a part asks for it
## (`UPDATE_ONCE`, then left alone), and the barrel points right.
##
## The size is the weapon's: the longest weapon fills `FILL` of the picture's width and a shorter
## one less, but never under `SMALLEST_SHARE` of it, so a pistol still reads as a pistol.
## Tests that need no picture set `live` to false: no world is built and every texture is null.

## The picture each weapon is drawn into, twice the size it is shown at so it stays crisp at 1440p.
const PICTURE := Vector2i(256, 128)
## The share of the picture's width and height the longest weapon, and the tallest, may fill.
const FILL := Vector2(0.94, 0.86)
const SMALLEST_SHARE := 0.58
## How far behind the weapon the camera stands, metres (an orthogonal view: only the depth range).
const STANDOFF := 5.0

## Whether silhouettes are drawn. A test with no use for the picture turns it off.
static var live := true
## The longest weapon in the catalogue, in the units of `WeaponHold.model_length x model_scale`.
static var _longest := 0.0

var _views: Dictionary[StringName, SubViewport] = {}


## The silhouette of `weapon_id` as a white-on-clear texture, or null for an id with no model or
## when silhouettes are not live. The texture fills in on the next frame the first time it is asked.
func texture_of(weapon_id: StringName) -> Texture2D:
	if not live or weapon_id == &"":
		return null
	if not _views.has(weapon_id):
		var made := _build(weapon_id)
		if made == null:
			return null
		_views[weapon_id] = made
	return _views[weapon_id].get_texture()


## Whether a silhouette has been made for `weapon_id`.
func has(weapon_id: StringName) -> bool:
	return _views.has(weapon_id)


## The share of the picture's width a weapon of this hold fills, longer weapons more.
static func width_share(hold: WeaponHold) -> float:
	return share_of_length(hold.model_length * hold.model_scale)


## The same for a weapon of this `length` in the units of `model_length x model_scale`.
static func share_of_length(length: float) -> float:
	if _longest <= 0.0:
		for id in WeaponCatalog.IDS:
			var other := WeaponHoldMap.hold_for(id)
			if other != null:
				_longest = maxf(_longest, other.model_length * other.model_scale)
	var share := length / maxf(_longest, 0.001)
	return clampf(share, SMALLEST_SHARE, 1.0) * FILL.x


func _build(weapon_id: StringName) -> SubViewport:
	var hold := WeaponHoldMap.hold_for(weapon_id)
	if hold == null or not hold.has_model():
		return null
	var model := (load(hold.scene) as PackedScene).instantiate() as Node3D
	var view := SubViewport.new()
	view.size = PICTURE
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	view.add_child(model)
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = Color.WHITE
	flat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var meshes: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = flat
		meshes.append(node as MeshInstance3D)
	# Lay the weapon along the picture's width with the long side from its grip to the right: a gun
	# already is (its barrel is its -X), a club stands on its end in the model.
	model.rotation.z = turn_to_the_right(bounds_of(meshes, model))
	var bounds := bounds_of(meshes, view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.05
	camera.far = STANDOFF * 4.0
	view.add_child(camera)
	var centre := bounds.get_center()
	var px_per_metre := minf(
		width_share(hold) * PICTURE.x / maxf(bounds.size.x, 0.001),
		FILL.y * PICTURE.y / maxf(bounds.size.y, 0.001)
	)
	camera.size = PICTURE.y / px_per_metre
	# From the -Z side, the model's -X is the picture's right.
	camera.look_at_from_position(centre + Vector3(0.0, 0.0, -STANDOFF), centre, Vector3.UP)
	return view


## The turn about Z (radians) that lays a model with these `bounds` (origin on the grip) along the
## picture's width, its longer side from the grip pointing to the picture's right (the model's -X).
static func turn_to_the_right(bounds: AABB) -> float:
	var along := Vector2.RIGHT if bounds.size.x >= bounds.size.y else Vector2.UP
	var low := -(bounds.position.x if along.x != 0.0 else bounds.position.y)
	var high := bounds.end.x if along.x != 0.0 else bounds.end.y
	var long_side := along * (-1.0 if low >= high else 1.0)
	return PI - long_side.angle()


## The box of `meshes` in the space of `frame`, one of their ancestors.
static func bounds_of(meshes: Array[MeshInstance3D], frame: Node) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in meshes:
		var to_frame := relative_transform(mesh, frame)
		var local := mesh.get_aabb()
		var box := AABB(to_frame * local.position, Vector3.ZERO)
		for i in 8:
			box = box.expand(to_frame * local.get_endpoint(i))
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


## `node`'s transform in the space of `ancestor`, by the chain of transforms between them (so it
## also works for a node that is not in the tree yet).
static func relative_transform(node: Node3D, ancestor: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var step: Node = node
	while step != null and step != ancestor:
		if step is Node3D:
			result = (step as Node3D).transform * result
		step = step.get_parent()
	return result
