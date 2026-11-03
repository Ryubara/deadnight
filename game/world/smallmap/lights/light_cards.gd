class_name LightCards
extends RefCounted
## The meshes and materials the small map's light cards are made of: additive quads on the lot's
## `glow.gdshader` and haze on its `beam.gdshader`, so a card builds no GL program the lot does not
## (`docs/research/maps/small-map-art.md`, Lighting and atmosphere). None of them takes a light
## slot: a mesh is lit by at most 8 lights in the Compatibility renderer, and a room keeps one or
## two real lamps.

const GLOW := preload("res://world/drive_in/glow.gdshader")
const BEAM := preload("res://world/drive_in/beam.gdshader")


## A `glow.gdshader` material: a disc (`card` false, the lot's pools and halos) or a soft card.
static func glow(tint: Color, card: bool, settings: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLOW
	material.render_priority = 1
	material.set_shader_parameter(&"tint", tint)
	material.set_shader_parameter(&"card", card)
	for key: String in settings:
		material.set_shader_parameter(StringName(key), settings[key])
	return material


## A haze material on `beam.gdshader` (brightest where the mesh's vertex colour is).
static func haze(tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BEAM
	material.render_priority = 1
	material.set_shader_parameter(&"tint", tint)
	return material


## A card through rows of points: `left[i]` to `right[i]` is row i, V runs 0 (row 0) to 1 (the
## last row) and U 0 (left) to 1 (right). Rows may bend (a shaft that lands half on a wall).
static func strip(left: PackedVector3Array, right: PackedVector3Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var rows := left.size()
	for i in rows:
		var v := float(i) / float(rows - 1)
		var along := left[mini(i + 1, rows - 1)] - left[maxi(i - 1, 0)]
		var normal := (right[i] - left[i]).cross(along).normalized()
		vertices.append_array([left[i], right[i]])
		uvs.append_array([Vector2(0.0, v), Vector2(1.0, v)])
		normals.append_array([normal, normal])
	for i in rows - 1:
		var a := i * 2
		indices.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A flat card from four corners: UV (0, 0) at `a`, (1, 0) at `b`, (1, 1) at `c`, (0, 1) at `d`.
static func card(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> ArrayMesh:
	return strip(PackedVector3Array([a, d]), PackedVector3Array([b, c]))


## An open cone of haze down -Y from a ring of `top_radius` at the origin to one of
## `bottom_radius` `height` below: brightest at the top (`near`), `far` at the bottom, with smooth
## outward normals so the haze fades where its side turns edge-on (the projector beam's manner).
static func cone(
	top_radius: float, bottom_radius: float, height: float, near: float, far: float, sides := 16
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var slope := (bottom_radius - top_radius) / height
	for i in sides:
		var angle := TAU * float(i) / sides
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var normal := (out + Vector3.UP * slope).normalized()
		vertices.append_array([out * top_radius, out * bottom_radius + Vector3.DOWN * height])
		normals.append_array([normal, normal])
		colours.append_array([Color(near, near, near), Color(far, far, far)])
	for i in sides:
		var a := i * 2
		var b := ((i + 1) % sides) * 2
		indices.append_array([a, b, b + 1, a, b + 1, a + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A mesh node for a card or haze: no shadow, and never culled by its own small bounds.
static func node(name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
