class_name GlowClip
extends RefCounted
## Keeps a glow card on its own side of a wall (issue #832, `docs/research/glow-bleed.md`). The
## Compatibility renderer casts no shadow, so a halo, a pool or a cone of haze is an additive quad
## that only the depth test hides: a card wider than its gap to a wall shows in the room behind
## it.  A card carries up to two world-space clip planes (`clip_a`, `clip_b` of `glow.gdshader`
## and  `beam.gdshader`: a point is not drawn where `dot(point, xyz) > w`); this class finds them
## from the  walls near the lamp, so a lamp placed beside a wall needs no number by hand.

## The boxes that stop light: a visible box with collision under one of these names. The wall test
## (`tests/world/glow_bleed.gd`) reads the same list.
const SOLID_PREFIXES: Array[String] = [
	"Wall",
	"Roof",
	"Slab",
	"StartSlab",
	"SideSlab",
	"UpperFloor",
	"Lintel",
	"Sill",
	"Jamb",
	"Pillar",
	"Parapet",
]
## A door's boxes sit under a node with this name prefix (`Doors/Door_*`).
const DOOR_PREFIX := "Door_"
## A lamp's cards are clipped by a wall only where its foot lies this far inside the wall's face
## (so the plane of a wall's end does not cut the open ground beyond the end).
const FACE_MARGIN := 0.3
## A lamp's origin this near a wall's face, or 2 cm inside it, is mounted on it.
const ON_FACE := 0.02


## The wall boxes under `root`, and with `doors` a purchase door's leaf too (a wall until it is
## bought, but  a gate in a fence lets light by, so only a test of what hangs in front of a door
## asks for them).
static func walls(root: Node, doors := false) -> Array[CSGBox3D]:
	var found: Array[CSGBox3D] = []
	if root == null:
		return found
	for node in root.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		if not box.use_collision or not box.is_visible_in_tree():
			continue
		if box.operation != CSGShape3D.OPERATION_UNION:
			continue
		# A purchase door's leaf is a wall until the door is bought.
		if doors and String(box.get_parent().name).begins_with(DOOR_PREFIX):
			found.append(box)
			continue
		for prefix in SOLID_PREFIXES:
			if String(box.name).begins_with(prefix):
				found.append(box)
				break
	return found


## The planes of the walls round `centre` within `reach` (at most two, the nearest, on different
## faces): each is the face of a wall the lamp stands in front of, `Vector4(normal into the wall,
## the face's offset)`.
static func planes_around(centre: Vector3, reach: float, around: Array[CSGBox3D]) -> Array[Vector4]:
	var candidates: Array = []
	for wall in around:
		var local := wall.global_transform.affine_inverse() * centre
		var half := wall.size * 0.5
		var outside := Vector3(
			absf(local.x) - half.x, absf(local.y) - half.y, absf(local.z) - half.z
		)
		var axis := 0
		for i in 3:
			if outside[i] > outside[axis]:
				axis = i
		# A lamp mounted on a wall has its origin on the face (ON_FACE either side of it).
		if outside[axis] < -ON_FACE or outside[axis] > reach:
			continue
		# The lamp must stand in front of the face (inside its rectangle, a margin spare).
		var in_front := true
		for i in 3:
			if i != axis and outside[i] > FACE_MARGIN:
				in_front = false
		if not in_front:
			continue
		var out_local := Vector3.ZERO
		out_local[axis] = signf(local[axis])
		var into_wall := -(wall.global_basis * out_local).normalized()
		var on_face := wall.global_transform * (out_local * half[axis])
		candidates.append(
			[outside[axis], Vector4(into_wall.x, into_wall.y, into_wall.z, into_wall.dot(on_face))]
		)
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var planes: Array[Vector4] = []
	for entry in candidates:
		var plane: Vector4 = entry[1]
		var same := false
		for kept in planes:
			if Vector3(kept.x, kept.y, kept.z).dot(Vector3(plane.x, plane.y, plane.z)) > 0.99:
				same = true
		if not same:
			planes.append(plane)
		if planes.size() == 2:
			break
	return planes


## The plane that cuts a flat card off at the top of the wall it is mounted on: `centre` is a
## point of  the card, `back` the way into the wall (a wall within `reach` along it). Empty when
## no wall is there.
static func top_of_wall_behind(
	centre: Vector3, back: Vector3, reach: float, around: Array[CSGBox3D]
) -> Array[Vector4]:
	for wall in around:
		var inverse := wall.global_transform.affine_inverse()
		var box := AABB(-wall.size * 0.5, wall.size)
		if box.intersects_segment(inverse * centre, inverse * (centre + back.normalized() * reach)):
			var up := wall.global_basis.y.normalized()
			var top := wall.global_transform * Vector3(0.0, wall.size.y * 0.5, 0.0)
			return [Vector4(up.x, up.y, up.z, up.dot(top))]
	return []


## Sets `planes` (up to two) on `material`; the rest are switched off.
static func apply(material: ShaderMaterial, planes: Array[Vector4]) -> void:
	for i in 2:
		var plane := planes[i] if i < planes.size() else Vector4.ZERO
		material.set_shader_parameter(&"clip_a" if i == 0 else &"clip_b", plane)
