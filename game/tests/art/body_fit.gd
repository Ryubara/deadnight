class_name BodyFit
extends RefCounted
## How the dressed Soldier's parts fit together (Deadnight #895), measured on the meshes as Godot
## draws them: CPU-skinned from the skeleton's pose, every near mesh that is shown.
##
## - `see_through`: rays from all round a place on the body (the neck, a wrist, the waist, an
##   ankle). The material culls back faces, so where the first surface a ray meets faces away from
##   it, the eye looks into a shell through an opening and sees what lies behind the body (the
##   back of the mouth through the neck, #895). Counted when no surface facing the ray lies within
##   `DEEP` behind that back face (a cuff over a wrist shows the wrist inside: not counted).
## - `inside`: vertices of one group of bones (a forearm and hand, a hat) that lie inside the
##   surface of another (the trunk, the other hand) deeper than a tolerance: a limb or a garment
##   through the body.
##
## The bodies are a static body each, on physics layers no game body uses, in the world of the
## node given; `prepare` swaps their triangles and waits a physics frame. Docs:
## docs/research/soldier-parts.md, "Fit".

## Layers these probes keep to themselves (the game's bodies use the low ones): set `i` of the
## surfaces prepared at once is on `LAYER_BOTH >> 2i` (both sides) and `LAYER_FRONT >> 2i`.
const LAYER_BOTH := 1 << 30
const LAYER_FRONT := 1 << 29
const MAX_SETS := 4
## A back face is "seen through" when nothing facing the ray lies within this much behind it.
const DEEP := 0.06
## How far behind and in front of a place the rays start and end, metres.
const REACH := 3.0
## How far the two rays that confirm a ray seeing through lie to either side of it, metres.
const NUDGE := 0.0015
## A back face seen through counts for a place when it is within this many radii of it.
const NEAR := 1.25

## The groups of bones a vertex can belong to (by the bone that carries most of its weight).
const GROUPS := {
	"head": ["Head", "Neck"],
	"trunk": ["Torso", "Abdomen", "Hips", "Body", "Shoulder.L", "Shoulder.R"],
	"upper_arm.L": ["UpperArm.L"],
	"upper_arm.R": ["UpperArm.R"],
	"forearm.L": ["LowerArm.L"],
	"forearm.R": ["LowerArm.R"],
	"thigh.L": ["UpperLeg.L"],
	"thigh.R": ["UpperLeg.R"],
	"shin.L": ["LowerLeg.L", "Foot.L"],
	"shin.R": ["LowerLeg.R", "Foot.R"],
}
## The finger bones' prefixes: their vertices are the hand's.
const HAND_PREFIXES := ["Index", "Middle", "Pinky", "Thumb", "Ring", "Palm", "Wrist", "Hand"]

## The posed meshes: [{name, points: PackedVector3Array, indices: PackedInt32Array,
## groups: PackedStringArray}].
var meshes: Array[Dictionary] = []

var _host: Node3D
var _skeleton: Skeleton3D
## Per set of surfaces: [both-sides shape, front-only shape]; the bodies that hold them.
var _shapes: Array[Array] = []
var _bodies: Array[StaticBody3D] = []
## The layers the probes read now (`use_set`).
var _layer_both := LAYER_BOTH
var _layer_front := LAYER_FRONT
var _space: PhysicsDirectSpaceState3D


func _init(host: Node3D, skeleton: Skeleton3D) -> void:
	_host = host
	_skeleton = skeleton
	for i in MAX_SETS:
		var both := ConcavePolygonShape3D.new()
		both.backface_collision = true
		var front := ConcavePolygonShape3D.new()
		front.backface_collision = false
		_shapes.append([both, front])
		_bodies.append(_body(both, LAYER_BOTH >> (2 * i)))
		_bodies.append(_body(front, LAYER_FRONT >> (2 * i)))


func _body(shape: ConcavePolygonShape3D, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)
	_host.add_child(body)
	return body


func free_bodies() -> void:
	for body in _bodies:
		if is_instance_valid(body):
			body.get_parent().remove_child(body)
			body.free()


## The group of a bone by name ("hand.L" for a finger of the left hand, "" for none).
static func group_of_bone(bone: String) -> String:
	for prefix: String in HAND_PREFIXES:
		if bone.begins_with(prefix):
			return "hand." + bone.right(1)
	for group: String in GROUPS:
		if bone in GROUPS[group]:
			return group
	return ""


## Reads every shown near mesh on the skeleton in the skeleton's current pose (or `poses`, bone
## index -> global pose, when given: the pose a modifier set, read at `skeleton_updated`).
func read_pose(poses: Array[Transform3D] = []) -> void:
	meshes.clear()
	var global_poses: Array[Transform3D] = poses
	if global_poses.is_empty():
		for b in _skeleton.get_bone_count():
			global_poses.append(_skeleton.get_bone_global_pose(b))
	for node in _skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or not HandContact.is_near(mi):
			continue
		if mi.skin == null:
			# The seat's armband is the body's; a weapon in the hand (also under the skeleton) is not.
			if _attached_to_armband(mi):
				_add_rigid(mi, global_poses)
		else:
			_add_skinned(mi, global_poses)


func _add_skinned(mi: MeshInstance3D, global_poses: Array[Transform3D]) -> void:
	var skin := mi.skin
	var binds: Array[Transform3D] = []
	var bind_bone := PackedInt32Array()
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = _skeleton.find_bone(skin.get_bind_name(i))
		bind_bone.append(bone)
		binds.append(_skeleton.global_transform * global_poses[bone] * skin.get_bind_pose(i))
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		var influences := bones.size() / maxi(vertices.size(), 1)
		var points := PackedVector3Array()
		points.resize(vertices.size())
		var groups := PackedStringArray()
		groups.resize(vertices.size())
		for v in vertices.size():
			var p := Vector3.ZERO
			var best := -1
			var best_w := -1.0
			var total := 0.0
			for k in influences:
				var w := weights[v * influences + k]
				if w <= 0.0:
					continue
				var bind := bones[v * influences + k]
				p += (binds[bind] * vertices[v]) * w
				total += w
				if w > best_w:
					best_w = w
					best = bind_bone[bind]
			points[v] = p / total if total > 0.0 else mi.global_transform * vertices[v]
			groups[v] = group_of_bone(_skeleton.get_bone_name(best)) if best >= 0 else ""
		meshes.append(
			{"name": String(mi.name), "points": points, "indices": indices, "groups": groups}
		)


func _attached_to_armband(mi: MeshInstance3D) -> bool:
	var parent := mi.get_parent()
	while parent != null and parent != _skeleton:
		if parent.name == CharacterAssembler.ARMBAND_BONE_NODE:
			return true
		parent = parent.get_parent()
	return false


## A mesh that follows a bone by a BoneAttachment3D (the seat's armband), placed from the pose read:
## the attachment itself follows the skeleton a frame late.
func _add_rigid(mi: MeshInstance3D, global_poses: Array[Transform3D]) -> void:
	var group := ""
	var place := mi.global_transform
	var parent := mi.get_parent()
	while parent != null and parent != _skeleton:
		if parent is BoneAttachment3D:
			var attachment := parent as BoneAttachment3D
			group = group_of_bone(attachment.bone_name)
			var bone := _skeleton.find_bone(attachment.bone_name)
			place = (
				_skeleton.global_transform
				* global_poses[bone]
				* attachment.global_transform.affine_inverse()
				* mi.global_transform
			)
			break
		parent = parent.get_parent()
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		var points := PackedVector3Array()
		var groups := PackedStringArray()
		for v in vertices:
			points.append(place * v)
			groups.append(group)
		meshes.append(
			{"name": String(mi.name), "points": points, "indices": indices, "groups": groups}
		)


## The triangles of the meshes read, as a flat list of corners: those whose name passes `keep`
## (every one when it is empty) and whose first corner is in one of `groups` (every one when empty).
func triangles(keep: Array = [], groups: Array = []) -> PackedVector3Array:
	var out := PackedVector3Array()
	for m in meshes:
		if not keep.is_empty() and not _name_kept(String(m.name), keep):
			continue
		var points: PackedVector3Array = m.points
		var indices: PackedInt32Array = m.indices
		var vg: PackedStringArray = m.groups
		for t in indices.size() / 3:
			if not groups.is_empty() and not vg[indices[t * 3]] in groups:
				continue
			# In the mesh's own order: a concave shape's faces front the same way the mesh draws them
			# (checked on a closed ball, test_soldier_watertight.gd).
			out.append(points[indices[t * 3]])
			out.append(points[indices[t * 3 + 1]])
			out.append(points[indices[t * 3 + 2]])
	return out


static func _name_kept(mesh_name: String, keep: Array) -> bool:
	for prefix: String in keep:
		if mesh_name.begins_with(prefix):
			return true
	return false


## Puts `faces` (from `triangles`) in the two probe bodies; await it before probing.
func prepare(faces: PackedVector3Array) -> void:
	await prepare_sets([faces])


## Puts up to `MAX_SETS` surfaces in the probe bodies at once (one physics frame for all of them)
## and reads set 0; `use_set` picks another.
func prepare_sets(sets: Array) -> void:
	assert(sets.size() <= MAX_SETS)
	for i in MAX_SETS:
		var faces: PackedVector3Array = sets[i] if i < sets.size() else PackedVector3Array()
		(_shapes[i][0] as ConcavePolygonShape3D).set_faces(faces)
		(_shapes[i][1] as ConcavePolygonShape3D).set_faces(faces)
	# The bodies' new shapes are in the space's broadphase only after its next full step: with one
	# frame a probe could still meet the last pose's surface (the results depended on the order).
	await _host.get_tree().physics_frame
	await _host.get_tree().physics_frame
	_space = _host.get_world_3d().direct_space_state
	use_set(0)


## Probes read the surface prepared as set `i`.
func use_set(i: int) -> void:
	_layer_both = LAYER_BOTH >> (2 * i)
	_layer_front = LAYER_FRONT >> (2 * i)


## The first hit along a segment on one layer: [distance, position] or [] for none.
func _first(from: Vector3, to: Vector3, layer: int) -> Array:
	var query := PhysicsRayQueryParameters3D.create(from, to, layer)
	query.hit_back_faces = true
	query.hit_from_inside = false
	var hit := _space.intersect_ray(query)
	if hit.is_empty():
		return []
	return [(hit.position as Vector3).distance_to(from), hit.position]


## Rays at `centre` from `azimuths` x `elevations` directions, each over a grid of `grid` x `grid`
## points across `radius`: the places where the eye sees through the body, as positions of the
## back face first met.
func see_through(
	centre: Vector3,
	radius: float,
	grid := 7,
	azimuths := 12,
	elevations: Array = [-60, -25, 5, 35, 65]
) -> PackedVector3Array:
	var out := PackedVector3Array()
	for e: float in elevations:
		for a in azimuths:
			var yaw := TAU * a / azimuths
			var pitch := deg_to_rad(e)
			var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
			var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
			var up := side.cross(dir).normalized()
			for i in grid:
				for j in grid:
					var off := (
						side * radius * (2.0 * i / (grid - 1) - 1.0)
						+ up * radius * (2.0 * j / (grid - 1) - 1.0)
					)
					var hit := _sees_through(centre + off, dir)
					# Only what happens at this place: a ray crosses the whole body, and the faults
					# elsewhere along it belong to the place they are at.
					if (
						not hit.is_empty()
						and (hit[1] as Vector3).distance_to(centre) > radius * NEAR
					):
						continue
					# A ray along an edge or through a corner can slip between two triangles: it
					# counts only when two rays a millimetre to either side see through too.
					if (
						not hit.is_empty()
						and not _sees_through(centre + off + (side + up) * NUDGE, dir).is_empty()
						and not _sees_through(centre + off - (side - up) * NUDGE, dir).is_empty()
					):
						out.append(hit[1])
	return out


## [distance, position] of the back face a ray through `through` along `dir` meets first, when
## nothing facing the ray lies within `DEEP` behind it; [] otherwise.
func _sees_through(through: Vector3, dir: Vector3) -> Array:
	var from := through - dir * REACH
	var to := through + dir * REACH
	var any := _first(from, to, _layer_both)
	if any.is_empty():
		return []
	var front := _first(from, to, _layer_front)
	if front.is_empty() or float(front[0]) > float(any[0]) + DEEP:
		return any
	return []


## How deep a point is inside the surface prepared: the shortest of six axis rays that each meet a
## back face first, or 0 when a ray meets nothing or a front face first (outside, or in an
## opening).
func depth_inside(p: Vector3, reach := 0.5) -> float:
	var deepest := INF
	for dir: Vector3 in [
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK
	]:
		var any := _first(p, p + dir * reach, _layer_both)
		if any.is_empty():
			return 0.0
		var front := _first(p, p + dir * reach, _layer_front)
		if not front.is_empty() and float(front[0]) <= float(any[0]) + 1e-5:
			return 0.0
		deepest = minf(deepest, float(any[0]))
	return deepest


## The vertices of `groups` (in meshes whose names pass `keep`) that lie inside the prepared
## surface deeper than `tolerance`: [{mesh, group, depth, position}], deepest first. `bounds`
## (the prepared surface's box) skips the vertices far from it; `stride` takes every n-th vertex.
func vertices_inside(
	groups: Array, keep: Array, bounds: AABB, tolerance: float, stride := 1
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for m in meshes:
		if not keep.is_empty() and not _name_kept(String(m.name), keep):
			continue
		var points: PackedVector3Array = m.points
		var vg: PackedStringArray = m.groups
		for v in range(0, points.size(), stride):
			if not vg[v] in groups or not bounds.has_point(points[v]):
				continue
			var key := Vector3i(points[v] * 1e4)
			if seen.has(key):
				continue
			seen[key] = true
			var d := depth_inside(points[v])
			if d > tolerance:
				out.append({"mesh": m.name, "group": vg[v], "depth": d, "position": points[v]})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.depth > y.depth)
	return out


## The box round a list of triangle corners.
static func bounds_of(faces: PackedVector3Array) -> AABB:
	if faces.is_empty():
		return AABB()
	var box := AABB(faces[0], Vector3.ZERO)
	for p in faces:
		box = box.expand(p)
	return box


## A bone's place in the world, `along` its length towards `towards` (another bone) when given.
func bone_point(bone: String, towards := "", along := 0.0) -> Vector3:
	var b := _skeleton.find_bone(bone)
	var p := _skeleton.global_transform * _skeleton.get_bone_global_pose(b).origin
	if towards == "":
		return p
	var n := _skeleton.find_bone(towards)
	var q := _skeleton.global_transform * _skeleton.get_bone_global_pose(n).origin
	return p.lerp(q, along)
