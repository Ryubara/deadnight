class_name ZombieMeshProbe
extends RefCounted
## A zombie's visible body in a pose, for tests: the model as the night draws it (`GAME_SCALE`),
## a clip played to a time, and the near mesh skinned on the CPU with the pose the skeleton has
## then. A ray that finds a triangle here is a shot that touches what the player sees, which is
## what the hit zones (`Hitbox`) must catch. Triangles are in the zombie's own frame: feet at the
## origin, facing +Z (yaw 0), like the zones.

enum Part { HEAD, BODY, ARM, LEG }

## The pieces of the body a hit zone is fitted to: a bone's name decides its piece (the prefix; a
## `.L` or `.R` suffix its side). A zombie faces +Z, so its left is +X.
enum Piece {
	HEAD,
	TONGUE,
	TORSO,
	UPPER_ARM_L,
	FOREARM_L,
	UPPER_ARM_R,
	FOREARM_R,
	THIGH_L,
	SHIN_L,
	THIGH_R,
	SHIN_R
}

const PIECE_OF := {
	"Head": Piece.HEAD,
	"Neck": Piece.HEAD,
	"Eyelid": Piece.HEAD,
	"Tongue": Piece.TONGUE,
	"Body": Piece.TORSO,
	"Hips": Piece.TORSO,
	"Abdomen": Piece.TORSO,
	"Torso": Piece.TORSO,
	"Shoulder": Piece.UPPER_ARM_L,
	"UpperArm": Piece.UPPER_ARM_L,
	"LowerArm": Piece.FOREARM_L,
	"Index": Piece.FOREARM_L,
	"Middle": Piece.FOREARM_L,
	"Pinky": Piece.FOREARM_L,
	"Thumb": Piece.FOREARM_L,
	"UpperLeg": Piece.THIGH_L,
	"LowerLeg": Piece.SHIN_L,
	"Foot": Piece.SHIN_L,
}
## The same piece on the right side.
const RIGHT_OF := {
	Piece.UPPER_ARM_L: Piece.UPPER_ARM_R,
	Piece.FOREARM_L: Piece.FOREARM_R,
	Piece.THIGH_L: Piece.THIGH_R,
	Piece.SHIN_L: Piece.SHIN_R,
}

const EXTRA := &"extra"

var root: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var mesh: MeshInstance3D
## The skinned triangles of the last `pose`, three vertices each, and the part of each triangle.
var vertices := PackedVector3Array()
var parts := PackedInt32Array()
var _tri: TriangleMesh
var _arrays: Array
var _bind_bones := PackedInt32Array()
var _bind_poses: Array[Transform3D] = []
var _vertex_piece := PackedInt32Array()
var _skinned := PackedVector3Array()
var _look: StringName


## The probe of `look`'s model. `host` takes the model into the tree, which the animation needs.
static func make(host: Node, look: StringName) -> ZombieMeshProbe:
	var probe := ZombieMeshProbe.new()
	probe._look = look
	probe.root = Node3D.new()
	host.add_child(probe.root)
	var model := ZombieModels.scene(look).instantiate() as Node3D
	model.scale = Vector3.ONE * ZombieModels.GAME_SCALE
	probe.root.add_child(model)
	probe.player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	probe.skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	probe.mesh = model.find_child(ZombieModels.NEAR_MESH, true, false) as MeshInstance3D
	probe._prepare()
	return probe


## Adds the clips made for Deadnight (`Sprint`, `Tear_Boards`, in `ZombieRig.EXTRA_CLIPS_FILE`) to
## the model's player, as `extra/<name>`.
func use_extra_clips() -> void:
	var scene := (load(ZombieRig.EXTRA_CLIPS_FILE) as PackedScene).instantiate()
	var source := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var library := AnimationLibrary.new()
	for clip in [ZombieRig.SPRINT_CLIP, ZombieRig.TEAR_CLIP, ZombieRig.CRAWL_ATTACK_CLIP]:
		library.add_animation(clip, source.get_animation(clip).duplicate(true))
	player.add_animation_library(EXTRA, library)
	scene.free()


## The length of a clip in seconds.
func length_of(clip: StringName) -> float:
	return player.get_animation(clip).length


## Puts the model at `clip`'s `time` (seconds) and skins the mesh. `lift` is the model's height
## above the feet (the emerging zombie rises).
func pose(clip: StringName, time: float, lift: float = 0.0) -> void:
	player.play(clip)
	player.seek(time, true)
	player.advance(0.0)
	var to_zombie := root.global_transform.affine_inverse() * skeleton.global_transform
	var skin_matrices: Array[Transform3D] = []
	for i in _bind_bones.size():
		skin_matrices.append(
			to_zombie * skeleton.get_bone_global_pose(_bind_bones[i]) * _bind_poses[i]
		)
	var positions: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = _arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = _arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex := bones.size() / positions.size()
	var skinned := PackedVector3Array()
	skinned.resize(positions.size())
	for v in positions.size():
		var at := Vector3.ZERO
		for k in per_vertex:
			var w := weights[v * per_vertex + k]
			if w > 0.0:
				at += (skin_matrices[bones[v * per_vertex + k]] * positions[v]) * w
		skinned[v] = at + Vector3(0, lift, 0)
	_skinned = skinned
	var index: PackedInt32Array = _arrays[Mesh.ARRAY_INDEX]
	vertices.resize(index.size())
	parts.resize(index.size() / 3)
	for i in index.size():
		vertices[i] = skinned[index[i]]
	for t in parts.size():
		parts[t] = _part_of_triangle(index[t * 3], index[t * 3 + 1], index[t * 3 + 2])
	var flat := ArrayMesh.new()
	var data: Array = []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX] = vertices
	flat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	_tri = flat.generate_triangle_mesh()


## The first triangle the ray meets: `{distance, part, point}`, or `{}`.
func ray(origin: Vector3, dir: Vector3) -> Dictionary:
	var hit := _tri.intersect_ray(origin, dir)
	if hit.is_empty():
		return {}
	var at: Vector3 = hit["position"]
	return {
		"distance": origin.distance_to(at),
		"part": parts[hit["face_index"]],
		"point": at,
	}


## Points on the front of the head's upper part, `count` of them spread over it: the forehead and
## the crown a shot from the front can reach. The centres of head triangles in the top fifth of the
## head's height and on its forward half.
func forehead(count: int) -> PackedVector3Array:
	var box := AABB()
	var first := true
	for t in parts.size():
		if parts[t] != Part.HEAD:
			continue
		for k in 3:
			box = (
				AABB(vertices[t * 3 + k], Vector3.ZERO)
				if first
				else box.expand(vertices[t * 3 + k])
			)
			first = false
	var found := PackedVector3Array()
	for t in parts.size():
		if parts[t] != Part.HEAD:
			continue
		var centre := (vertices[t * 3] + vertices[t * 3 + 1] + vertices[t * 3 + 2]) / 3.0
		if centre.y >= box.end.y - box.size.y * 0.2 and centre.z >= box.get_center().z:
			found.append(centre)
	var picked := PackedVector3Array()
	var stride := maxf(float(found.size()) / float(count), 1.0)
	var at := 0.0
	while int(at) < found.size() and picked.size() < count:
		picked.append(found[int(at)])
		at += stride
	return picked


## The box round the posed mesh.
func bounds() -> AABB:
	var box := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		box = box.expand(v)
	return box


## Frees the model.
func free_model() -> void:
	root.get_parent().remove_child(root)
	root.free()


func _prepare() -> void:
	var surface := mesh.mesh.surface_get_arrays(0)
	_arrays = surface
	var skin := mesh.skin
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(i))
		_bind_bones.append(bone)
		_bind_poses.append(skin.get_bind_pose(i))
	var bones: PackedInt32Array = _arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = _arrays[Mesh.ARRAY_WEIGHTS]
	var count: int = (_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per_vertex := bones.size() / count
	_vertex_piece.resize(count)
	for v in count:
		var best := -1.0
		var piece := Piece.TORSO
		for k in per_vertex:
			var w := weights[v * per_vertex + k]
			if w > best:
				best = w
				piece = _piece_of_bone(
					skeleton.get_bone_name(_bind_bones[bones[v * per_vertex + k]])
				)
		_vertex_piece[v] = piece


func _piece_of_bone(bone_name: String) -> int:
	for prefix: String in PIECE_OF:
		if bone_name.begins_with(prefix):
			var piece: int = PIECE_OF[prefix]
			return RIGHT_OF[piece] if bone_name.ends_with(".R") and RIGHT_OF.has(piece) else piece
	return Piece.TORSO


## The posed vertices of one piece of the body (of the last `pose`).
func points(piece: int) -> PackedVector3Array:
	var found := PackedVector3Array()
	for v in _skinned.size():
		if _vertex_piece[v] == piece:
			found.append(_skinned[v])
	return found


## What a piece counts as for a shot: the head, the torso, an arm or a leg.
static func part_of_piece(piece: int) -> int:
	match piece:
		Piece.HEAD, Piece.TONGUE:
			return Part.HEAD
		Piece.TORSO:
			return Part.BODY
		Piece.UPPER_ARM_L, Piece.FOREARM_L, Piece.UPPER_ARM_R, Piece.FOREARM_R:
			return Part.ARM
	return Part.LEG


## The part most of a triangle's vertices belong to (the first vertex's on a tie).
func _part_of_triangle(a: int, b: int, c: int) -> int:
	var pa := part_of_piece(_vertex_piece[a])
	var pb := part_of_piece(_vertex_piece[b])
	var pc := part_of_piece(_vertex_piece[c])
	if pa == pb or pa == pc:
		return pa
	return pb if pb == pc else pa
