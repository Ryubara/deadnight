class_name HandContact
extends RefCounted
## Measures how the Soldier's hands meet the weapon they hold (Deadnight #460): for each part of a
## hand (a finger's tip, its middle, the thumb, the palm), the signed distance in metres from its
## skin to the weapon's surface, negative where the skin is inside the weapon. The skin is the
## skinned mesh as drawn (CPU-skinned here from the skeleton's current pose), the weapon its
## triangles. Read it at `Skeleton3D.skeleton_updated`: after the frame the skeleton hands the
## clip's pose back and the modifiers' work is gone.
##
## Docs: docs/design/animation.md, "Grips".

## The hand parts, by the bone that carries most of a vertex's weight. `%s` is the side, R or L.
const PARTS := {
	"index_tip": ["Index3.%s"],
	"index_mid": ["Index2.%s"],
	"middle_tip": ["Middle3.%s"],
	"middle_mid": ["Middle2.%s"],
	"pinky_tip": ["Pinky3.%s"],
	"pinky_mid": ["Pinky2.%s"],
	"thumb_tip": ["Thumb2.%s"],
	"thumb_base": ["Thumb1.%s"],
	"palm": ["Index1.%s", "Middle1.%s", "Pinky1.%s"],
}
## A vertex counts for a part when its main bone carries at least this share of its weight.
const MIN_WEIGHT := 0.5
## Triangles farther than this from the hand (metres, in the world) are not looked at.
const MARGIN := 0.08

var _skeleton: Skeleton3D
## Per side: {part: PackedInt32Array of [mesh index, vertex index] pairs flattened}.
var _parts := {"R": {}, "L": {}}
## The skinned meshes: [{instance, vertices, bones, weights, influences, binds}].
var _meshes: Array[Dictionary] = []
## The weapon: local triangles, their component, the component bounds.
var _weapon: Node3D
var _tris := PackedVector3Array()
var _tri_component := PackedInt32Array()
var _component_tris: Array[PackedInt32Array] = []
var _component_bounds: Array[AABB] = []
## Each triangle's bounds, low and high corners.
var _tri_low := PackedVector3Array()
var _tri_high := PackedVector3Array()


func _init(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	for mi in _skinned_meshes(skeleton):
		_add_mesh(mi)


## Every visible skinned mesh on the skeleton (the Soldier's parts: the hands are in the torso).
static func _skinned_meshes(skeleton: Skeleton3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin != null and mi.mesh != null and mi.is_visible_in_tree():
			out.append(mi)
	return out


func _add_mesh(mi: MeshInstance3D) -> void:
	var arrays := mi.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones.is_empty() or vertices.is_empty():
		return
	var influences := bones.size() / vertices.size()
	var skin := mi.skin
	var binds := PackedInt32Array()
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = _skeleton.find_bone(skin.get_bind_name(i))
		binds.append(bone)
	var index := _meshes.size()
	(
		_meshes
		. append(
			{
				"instance": mi,
				"vertices": vertices,
				"bones": bones,
				"weights": weights,
				"influences": influences,
				"binds": binds,
			}
		)
	)
	for side in ["R", "L"]:
		var by_bone := {}
		for part: String in PARTS:
			for pattern: String in PARTS[part]:
				by_bone[_skeleton.find_bone(pattern % side)] = part
		var seen := {}
		for v in vertices.size():
			# glTF splits a vertex at every seam; one copy is enough to measure.
			var key := Vector3i(
				roundi(vertices[v].x * 1e5),
				roundi(vertices[v].y * 1e5),
				roundi(vertices[v].z * 1e5)
			)
			if seen.has(key):
				continue
			seen[key] = true
			var best := -1
			var best_w := 0.0
			for k in influences:
				var w := weights[v * influences + k]
				if w > best_w:
					best_w = w
					best = binds[bones[v * influences + k]]
			if best_w < MIN_WEIGHT or not by_bone.has(best):
				continue
			var part: String = by_bone[best]
			if not _parts[side].has(part):
				_parts[side][part] = PackedInt32Array()
			_parts[side][part].append_array([index, v])


## Sets the weapon measured against: its mesh triangles (every MeshInstance3D under it), in its
## own space, split into the closed pieces it is built from (inside means inside any piece).
func set_weapon(weapon: Node3D) -> void:
	_weapon = weapon
	_tris = PackedVector3Array()
	_tri_component = PackedInt32Array()
	_component_tris.clear()
	_component_bounds.clear()
	_tri_low = PackedVector3Array()
	_tri_high = PackedVector3Array()
	if weapon == null:
		return
	var inverse := weapon.global_transform.affine_inverse()
	for node in [weapon] + weapon.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var to_weapon := inverse * mi.global_transform
		for s in mi.mesh.get_surface_count():
			_add_surface(mi.mesh.surface_get_arrays(s), to_weapon)
	for t in _tris.size() / 3:
		var a := _tris[t * 3]
		var b := _tris[t * 3 + 1]
		var c := _tris[t * 3 + 2]
		_tri_low.append(a.min(b).min(c))
		_tri_high.append(a.max(b).max(c))


func _add_surface(arrays: Array, to_weapon: Transform3D) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices = PackedInt32Array(range(vertices.size()))
	# Weld split vertices by place, then join triangles that share one into pieces.
	var welded := {}
	var ids := PackedInt32Array()
	ids.resize(vertices.size())
	for i in vertices.size():
		var p := to_weapon * vertices[i]
		var key := Vector3i(roundi(p.x * 1e5), roundi(p.y * 1e5), roundi(p.z * 1e5))
		if not welded.has(key):
			welded[key] = welded.size()
		ids[i] = welded[key]
	var parent := PackedInt32Array(range(welded.size()))
	for t in indices.size() / 3:
		var a := _find(parent, ids[indices[t * 3]])
		for k in [1, 2]:
			var b := _find(parent, ids[indices[t * 3 + k]])
			if a != b:
				parent[b] = a
	var component_of := {}
	for t in indices.size() / 3:
		var root := _find(parent, ids[indices[t * 3]])
		if not component_of.has(root):
			component_of[root] = _component_tris.size()
			_component_tris.append(PackedInt32Array())
			_component_bounds.append(AABB())
		var c: int = component_of[root]
		var tri := _tris.size() / 3
		var first := true if _component_tris[c].is_empty() else false
		for k in 3:
			var p := to_weapon * vertices[indices[t * 3 + k]]
			_tris.append(p)
			if first and k == 0:
				_component_bounds[c] = AABB(p, Vector3.ZERO)
			else:
				_component_bounds[c] = _component_bounds[c].expand(p)
		_tri_component.append(c)
		_component_tris[c].append(tri)


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


## The parts' skin vertices of `side` in the world, as the skeleton holds them now:
## {part: PackedVector3Array}.
func skin_points(side: String, only: Array = []) -> Dictionary:
	var out := {}
	var poses := {}
	for part: String in _parts[side]:
		if not only.is_empty() and part not in only:
			continue
		var list: PackedInt32Array = _parts[side][part]
		var points := PackedVector3Array()
		for i in list.size() / 2:
			points.append(_skin(list[i * 2], list[i * 2 + 1], poses))
		out[part] = points
	return out


func _skin(mesh: int, v: int, poses: Dictionary) -> Vector3:
	var m: Dictionary = _meshes[mesh]
	var influences: int = m.influences
	var bones: PackedInt32Array = m.bones
	var weights: PackedFloat32Array = m.weights
	var binds: PackedInt32Array = m.binds
	var mi: MeshInstance3D = m.instance
	var rest: Vector3 = m.vertices[v]
	var sum := Vector3.ZERO
	for k in influences:
		var w := weights[v * influences + k]
		if w <= 0.0:
			continue
		var bind := bones[v * influences + k]
		var key := mesh * 1000 + bind
		if not poses.has(key):
			poses[key] = (_skeleton.get_bone_global_pose(binds[bind]) * mi.skin.get_bind_pose(bind))
		sum += w * ((poses[key] as Transform3D) * rest)
	return _skeleton.global_transform * sum


## The signed distance (metres, in the world) from each part of a hand to the weapon:
## {part: {"distance": float, "point": Vector3 (the part's skin point nearest the weapon)}}.
## A part farther than `MARGIN` reads `MARGIN`.
func measure(side: String) -> Dictionary:
	return measure_parts(side, [])


## `measure` for some parts only (all of them when `only` is empty).
func measure_parts(side: String, only: Array) -> Dictionary:
	var out := {}
	if _weapon == null or _tris.is_empty():
		return out
	var inverse := _weapon.global_transform.affine_inverse()
	var scale := _weapon.global_basis.get_scale().x
	var margin := MARGIN / scale
	var points := skin_points(side, only)
	# Only triangles near the hand are looked at.
	var bounds := AABB()
	var first := true
	for part: String in points:
		for p: Vector3 in points[part]:
			var q := inverse * p
			bounds = AABB(q, Vector3.ZERO) if first else bounds.expand(q)
			first = false
	bounds = bounds.grow(margin)
	var near := PackedInt32Array()
	var low := bounds.position
	var high := bounds.end
	for t in _tri_low.size():
		var a := _tri_low[t]
		var b := _tri_high[t]
		if (
			a.x <= high.x
			and b.x >= low.x
			and a.y <= high.y
			and b.y >= low.y
			and a.z <= high.z
			and b.z >= low.z
		):
			near.append(t)
	for part: String in points:
		var best := INF
		var best_point := Vector3.ZERO
		for p: Vector3 in points[part]:
			var d := _signed_distance(inverse * p, near, margin)
			if d < best:
				best = d
				best_point = p
		out[part] = {"distance": best * scale, "point": best_point}
	return out


## The signed distance from `q` (weapon space) to the weapon: negative inside a piece.
func _signed_distance(q: Vector3, near: PackedInt32Array, margin: float) -> float:
	var nearest := margin
	for t in near:
		# The box's distance bounds the triangle's: skip it when it cannot be nearer.
		var outside := (_tri_low[t] - q).max(q - _tri_high[t]).max(Vector3.ZERO)
		if outside.length_squared() >= nearest * nearest:
			continue
		var d := q.distance_to(
			_closest_on_triangle(q, _tris[t * 3], _tris[t * 3 + 1], _tris[t * 3 + 2])
		)
		nearest = minf(nearest, d)
	var depth := 0.0
	for c in _component_tris.size():
		if not _component_bounds[c].grow(1e-4).has_point(q):
			continue
		if _inside(q, c):
			var to_surface := INF
			for t in _component_tris[c]:
				to_surface = minf(
					to_surface,
					q.distance_to(
						_closest_on_triangle(q, _tris[t * 3], _tris[t * 3 + 1], _tris[t * 3 + 2])
					)
				)
			depth = maxf(depth, to_surface)
	return -depth if depth > 0.0 else nearest


## Whether `q` is inside the closed piece `c`: an odd number of crossings along a ray.
func _inside(q: Vector3, c: int) -> bool:
	var direction := Vector3(0.5773, 0.5774, 0.5776).normalized()
	var crossings := 0
	for t in _component_tris[c]:
		if _ray_hits(q, direction, _tris[t * 3], _tris[t * 3 + 1], _tris[t * 3 + 2]):
			crossings += 1
	return crossings % 2 == 1


static func _ray_hits(
	origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3
) -> bool:
	var e1 := b - a
	var e2 := c - a
	var p := direction.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 1e-12:
		return false
	var s := origin - a
	var u := s.dot(p) / det
	if u < 0.0 or u > 1.0:
		return false
	var q := s.cross(e1)
	var v := direction.dot(q) / det
	if v < 0.0 or u + v > 1.0:
		return false
	return e2.dot(q) / det > 0.0


## The closest point to `p` on the triangle `a b c` (Ericson, Real-Time Collision Detection 5.1.5).
static func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


## The skinned meshes as posed and the weapon's triangles, in the world, as an OBJ file (objects
## `body_*` and `weapon`), for close renders (`tools/blender/render_grips.py`).
func dump_obj(path: String) -> void:
	var lines := PackedStringArray()
	var base := 1
	for m in _meshes:
		var mi: MeshInstance3D = m.instance
		var arrays := mi.mesh.surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = m.vertices
		var poses := {}
		lines.append("o body_%s" % mi.name)
		for v in vertices.size():
			var p := _skin(_meshes.find(m), v, poses)
			lines.append("v %f %f %f" % [p.x, p.y, p.z])
		for t in indices.size() / 3:
			lines.append(
				(
					"f %d %d %d"
					% [base + indices[t * 3], base + indices[t * 3 + 1], base + indices[t * 3 + 2]]
				)
			)
		base += vertices.size()
	if _weapon != null:
		lines.append("o weapon")
		for p in _tris:
			var w := _weapon.global_transform * p
			lines.append("v %f %f %f" % [w.x, w.y, w.z])
		for t in _tris.size() / 3:
			lines.append("f %d %d %d" % [base + t * 3, base + t * 3 + 1, base + t * 3 + 2])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(String.chr(10).join(lines))
