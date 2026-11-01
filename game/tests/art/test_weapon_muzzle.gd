extends GdUnitTestSuite
## Every firearm model carries a `Muzzle` node at the centre of its barrel's open end, its -Z out
## of the barrel (Godot forward), so the flash and the shot leave the barrel, not a fixed offset
## from the body (docs/design/style.md, "Attachment points"). Melee weapons and the grenade have
## none. Both levels of detail carry it at the same place.

const DIR := "res://assets/weapons/"
## Every weapon folder is listed in one of the two, so a new model has to say whether it shoots.
const FIREARMS: Array[String] = [
	"lever_rifle", "double_shotgun", "revolver", "tommy_gun", "flare_gun"
]
const NOT_FIREARMS: Array[String] = ["baseball_bat", "fire_axe", "grenade", "hammer", "crowbar"]
const MUZZLE := "Muzzle"
## How far the marker may sit from the bounding box's front face along the barrel (metres).
const FACE_TOLERANCE := 0.01
## How far off the barrel axis its -Z may point (degrees).
const ANGLE_TOLERANCE := 1.0
## A barrel end must have mesh within this distance across the barrel (half the double shotgun's
## barrel spacing plus a barrel's radius), so the marker is on a barrel, not beside the gun.
const ON_BARREL := 0.06
## How far apart the held and far levels may put it (metres).
const LOD_TOLERANCE := 0.001


func _instance(path: String) -> Node3D:
	var scene: PackedScene = load(path)
	assert_object(scene).is_not_null()
	var node: Node3D = scene.instantiate()
	add_child(node)
	return auto_free(node)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in node.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


## The combined bounds of every mesh, in the weapon scene's own space.
func _bounds(weapon: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var to_root := weapon.global_transform.affine_inverse()
	for m in _meshes(weapon):
		var b := to_root * m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## The barrel direction: along the longest side of the bounds, toward the end further from the
## origin (the grip).
func _barrel_axis(box: AABB) -> Vector3:
	var i := box.get_longest_axis_index()
	var axis := Vector3.ZERO
	axis[i] = 1.0 if absf(box.end[i]) > absf(box.position[i]) else -1.0
	return axis


func _muzzle(weapon: Node3D) -> Node3D:
	return weapon.find_child(MUZZLE, true, false) as Node3D


func _local(weapon: Node3D, node: Node3D) -> Transform3D:
	return weapon.global_transform.affine_inverse() * node.global_transform


func _paths(weapon: String) -> Array[String]:
	return [DIR + "%s/%s.glb" % [weapon, weapon], DIR + "%s/%s_far.glb" % [weapon, weapon]]


func test_every_weapon_model_says_whether_it_is_a_firearm() -> void:
	for folder in DirAccess.get_directories_at(DIR):
		(
			assert_bool(folder in FIREARMS or folder in NOT_FIREARMS)
			. override_failure_message("%s is in neither FIREARMS nor NOT_FIREARMS" % folder)
			. is_true()
		)


func test_every_firearm_has_one_muzzle_under_its_root() -> void:
	for weapon in FIREARMS:
		for path in _paths(weapon):
			var gun := _instance(path)
			var found := gun.find_children(MUZZLE, "", true, false)
			(
				assert_int(found.size())
				. override_failure_message("%s: %d Muzzle nodes" % [path, found.size()])
				. is_equal(1)
			)
			if found.size() != 1:
				continue
			var muzzle := found[0] as Node3D
			assert_object(muzzle).is_not_null()
			# Parented to the weapon (its mesh node or the scene root), so it moves with the gun.
			var parent := muzzle.get_parent()
			(
				assert_bool(parent == gun or parent.get_parent() == gun)
				. override_failure_message("%s: Muzzle hangs under %s" % [path, parent.name])
				. is_true()
			)


func test_the_muzzle_sits_at_the_barrel_end_and_points_out() -> void:
	for weapon in FIREARMS:
		for path in _paths(weapon):
			var gun := _instance(path)
			var muzzle := _muzzle(gun)
			assert_object(muzzle).override_failure_message("%s has no Muzzle" % path).is_not_null()
			if muzzle == null:
				continue
			var box := _bounds(gun)
			var axis := _barrel_axis(box)
			var i := box.get_longest_axis_index()
			var t := _local(gun, muzzle)
			var front: float = box.end[i] if axis[i] > 0 else box.position[i]
			(
				assert_float(absf(t.origin[i] - front))
				. override_failure_message(
					"%s: Muzzle at %.4f, the front face at %.4f" % [path, t.origin[i], front]
				)
				. is_less_equal(FACE_TOLERANCE)
			)
			var forward := -t.basis.z.normalized()
			var angle := rad_to_deg(forward.angle_to(axis))
			(
				assert_float(angle)
				. override_failure_message(
					(
						"%s: Muzzle -Z is %s, %.2f degrees off the barrel %s"
						% [path, forward, angle, axis]
					)
				)
				. is_less_equal(ANGLE_TOLERANCE)
			)
			# Unit scale, so a flash parented to it is not resized.
			assert_vector(t.basis.get_scale()).is_equal_approx(Vector3.ONE, Vector3.ONE * 0.001)
			(
				assert_float(_nearest_end_vertex(gun, t.origin, axis))
				. override_failure_message(
					"%s: no barrel end within %.2f m of the Muzzle" % [path, ON_BARREL]
				)
				. is_less_equal(ON_BARREL)
			)


## The distance across the barrel from `at` to the nearest vertex lying within the face tolerance
## of `at` along the barrel.
func _nearest_end_vertex(gun: Node3D, at: Vector3, axis: Vector3) -> float:
	var best := INF
	var to_root := gun.global_transform.affine_inverse()
	for m in _meshes(gun):
		var xf := to_root * m.global_transform
		for s in m.mesh.get_surface_count():
			var verts: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var d := xf * v - at
				var along := d.dot(axis)
				if absf(along) <= FACE_TOLERANCE:
					best = minf(best, (d - axis * along).length())
	return best


func test_the_held_and_far_levels_put_the_muzzle_in_one_place() -> void:
	for weapon in FIREARMS:
		var paths := _paths(weapon)
		var near := _muzzle(_instance(paths[0]))
		var far := _muzzle(_instance(paths[1]))
		assert_object(near).is_not_null()
		assert_object(far).is_not_null()
		if near == null or far == null:
			continue
		var a := _local(near.owner as Node3D, near)
		var b := _local(far.owner as Node3D, far)
		assert_vector(a.origin).is_equal_approx(b.origin, Vector3.ONE * LOD_TOLERANCE)
		assert_float(rad_to_deg((-a.basis.z).angle_to(-b.basis.z))).is_less_equal(ANGLE_TOLERANCE)


func test_melee_weapons_and_the_grenade_have_no_muzzle() -> void:
	for weapon in NOT_FIREARMS:
		for path in _paths(weapon):
			(
				assert_object(_muzzle(_instance(path)))
				. override_failure_message("%s has a Muzzle" % path)
				. is_null()
			)


func test_the_hammer_carries_its_face_on_both_levels() -> void:
	# A tool's striking point is a node too: the repair hammer's `Face`, at the centre of the face
	# (the far end of the bounds along -X), its -Z out of the face, the same on both levels.
	var at: Array[Vector3] = []
	for file in ["hammer.glb", "hammer_far.glb"]:
		var hammer := _instance(DIR + "hammer/" + file)
		var face := hammer.find_child("Face", true, false) as Node3D
		assert_object(face).is_not_null()
		var local := hammer.global_transform.affine_inverse() * face.global_transform
		var box := _bounds(hammer)
		assert_float(local.origin.x).is_less(0.0)
		assert_float(absf(local.origin.x - box.position.x)).is_less(0.01)
		var forward := -local.basis.z.normalized()
		assert_float(rad_to_deg(forward.angle_to(Vector3.LEFT))).is_less(ANGLE_TOLERANCE)
		assert_object(hammer.find_child(MUZZLE, true, false)).is_null()
		at.append(local.origin)
	assert_float(at[0].distance_to(at[1])).is_less(LOD_TOLERANCE)
