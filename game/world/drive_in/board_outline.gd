class_name BoardOutline
extends MeshInstance3D
## The ghost of every board a barricade is missing: one faint plank outline where each torn board
## was, and nothing where the board is back (docs/design/map.md, Breaches). Every repairable entry
## on both maps (the second map's windows and breach, the drive-in's fence breaches) shows the same,
## because it is drawn by the `Barricade` from its own boards, not by whatever lighting the window
## happens to have.
##
## One mesh a barricade, rebuilt from at most five quads when the count changes, and one material
## for all of them (`board_outline.gdshader`): a barricade whose boards are all up draws nothing,
## and a torn one costs one draw call. The quad of a board is the front face of its mesh's box (the
## room side, +Z of the barricade), a hair in front, so it sits where the board's own face would.

const SHADER := preload("res://world/drive_in/board_outline.gdshader")
## The moon's colour (`#9db4e8`, the lot's), and how strongly the frame is drawn.
const COLOUR := Color(0.616, 0.706, 0.91)
const ENERGY := 0.3
## How far in front of the board's face the quad sits (m): the mended board's face never fights it.
const LIFT := 0.006

static var _material: ShaderMaterial

## Each board's front face in the barricade's space (four corners, clockwise from the top left
## looking at it from the room), and the face's size in metres; empty for a board with no mesh.
var _faces: Array[PackedVector3Array] = []
var _sizes: Array[Vector2] = []
var _missing_from := -1


## The shared material (made the first time).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.render_priority = 1
		_material.set_shader_parameter(&"tint", COLOUR)
		_material.set_shader_parameter(&"energy", ENERGY)
	return _material


func _init() -> void:
	name = "Outline"
	material_override = material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Takes the faces of the boards, lowest first: each board's mesh and the mesh's transform in the
## barricade's space.
func set_boards(meshes: Array[MeshInstance3D], in_barricade: Array[Transform3D]) -> void:
	_faces.clear()
	_sizes.clear()
	for i in meshes.size():
		var corners := PackedVector3Array()
		var size := Vector2.ZERO
		if meshes[i] != null and meshes[i].mesh != null:
			var box := meshes[i].mesh.get_aabb()
			var front := box.position.z + box.size.z + LIFT
			var top := box.position.y + box.size.y
			for corner in [
				Vector2(box.position.x, top),
				Vector2(box.position.x + box.size.x, top),
				Vector2(box.position.x + box.size.x, box.position.y),
				Vector2(box.position.x, box.position.y),
			]:
				corners.append(in_barricade[i] * Vector3(corner.x, corner.y, front))
			size = Vector2(box.size.x, box.size.y)
		_faces.append(corners)
		_sizes.append(size)
	_missing_from = -1


## Draws the outline of every board from `up` on (the boards below it are up).
func show_missing(up: int) -> void:
	if up == _missing_from:
		return
	_missing_from = up
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var sizes := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(maxi(up, 0), _faces.size()):
		var corners := _faces[i]
		if corners.size() != 4:
			continue
		var first := vertices.size()
		var normal := (corners[1] - corners[0]).cross(corners[3] - corners[0]).normalized()
		vertices.append_array(corners)
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		for _corner in 4:
			sizes.append(_sizes[i])
			normals.append(normal)
		indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])
	if vertices.is_empty():
		mesh = null
		visible = false
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = sizes
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = built
	visible = true


## How many boards' outlines are drawn now.
func quads() -> int:
	return mesh.surface_get_array_len(0) / 4 if mesh != null and visible else 0


## The front face of board `index` in the barricade's space (four corners), or empty.
func face(index: int) -> PackedVector3Array:
	return _faces[index]
