class_name ProjectorBeam
extends LightFollower
## The projector's beam: an open cone of additive haze from the booth's port to the screen, and a
## bright halo at the port. One mesh of 29 vertices, one draw; the haze is brightest at the lens,
## thins towards the screen and fades at the silhouette so no edge shows. It burns with the screen's
## lamp (`light_path`), flicker and all.

const BEAM_ENERGY := 0.14
const SEGMENTS := 28
const HALO_ENERGY := 1.5
## The haze's brightness at the lens and at the screen.
const NEAR := 1.0
const FAR := 0.12

## The middle of the screen and its size, relative to this node (the lens is the origin).
@export var target_centre := Vector3(0.0, 4.6, -69.7)
@export var target_size := Vector2(32.0, 12.0)

var _material: ShaderMaterial
var _halo: ShaderMaterial


func _ready() -> void:
	var beam := MeshInstance3D.new()
	beam.name = "Haze"
	beam.mesh = _pyramid()
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The haze reaches across the lot: never cull it by its own bounds.
	beam.extra_cull_margin = 80.0
	_material = ShaderMaterial.new()
	_material.shader = load("res://world/drive_in/beam.gdshader")
	beam.material_override = _material
	add_child(beam)
	var halo := get_node_or_null("Halo") as MeshInstance3D
	if halo != null:
		_halo = (halo.material_override as ShaderMaterial).duplicate()
		halo.material_override = _halo
	super._ready()


func _pyramid() -> ArrayMesh:
	# A cone with an elliptical mouth on the screen: smooth normals, so the haze's edge fades with the
	# view angle and no seam shows. Apex at the lens (the origin).
	var half := target_size * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.append(Vector3.ZERO)
	normals.append(Vector3.FORWARD)
	colours.append(Color(NEAR, NEAR, NEAR))
	for i in SEGMENTS:
		var angle := TAU * float(i) / SEGMENTS
		var rim := target_centre + Vector3(cos(angle) * half.x, sin(angle) * half.y, 0.0)
		vertices.append(rim)
		# The cone's outward normal there: across the slope, away from the axis.
		var around := Vector3(-sin(angle) * half.x, cos(angle) * half.y, 0.0).normalized()
		normals.append(rim.cross(around).normalized())
		colours.append(Color(FAR, FAR, FAR))
	for i in SEGMENTS:
		indices.append_array([0, 1 + i, 1 + (i + 1) % SEGMENTS])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply() -> void:
	var f := LotScreen.flicker(phase)
	_material.set_shader_parameter(&"energy", level * (0.6 + 0.4 * f) * BEAM_ENERGY)
	if _halo != null:
		_halo.set_shader_parameter(&"energy", level * f * HALO_ENERGY)
