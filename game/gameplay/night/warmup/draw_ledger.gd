class_name DrawLedger
extends RefCounted
## A list of what a scene tree draws, as plain strings: one for each kind of mesh with each kind of
## material, and one for each kind of light. In the Compatibility renderer a GL program is built the
## first time a mesh of some kind is drawn with some material under some lights, so two things with
## the same string cost nothing more once one of them has been drawn (the measurements are in
## `docs/research/first-use-hitches.md`).
##
## Hidden nodes are not counted: they draw nothing.
##
## The warm-up records its own tree frame after frame; a test records a night being played and
## fails when the night drew something the warm-up never did.

const MATERIAL_PROPERTIES: Array[StringName] = [
	&"shading_mode",
	&"transparency",
	&"blend_mode",
	&"cull_mode",
	&"depth_draw_mode",
	&"no_depth_test",
	&"billboard_mode",
	&"vertex_color_use_as_albedo",
	&"emission_enabled",
	&"normal_enabled",
	&"rim_enabled",
	&"disable_receive_shadows",
	&"fixed_size",
	&"use_point_size",
	&"proximity_fade_enabled",
	&"distance_fade_mode",
	&"specular_mode",
	&"diffuse_mode",
	&"grow",
]

## Each string seen so far, and how many nodes had it the first time.
var seen: Dictionary[String, int] = {}


## Notes everything under `root` (the root included).
func record(root: Node) -> void:
	for string in strings_of(root):
		if not seen.has(string):
			seen[string] = 1


func has(string: String) -> bool:
	return seen.has(string)


## The strings in `strings` that were never recorded.
func missing(strings: Dictionary[String, int]) -> Array[String]:
	var absent: Array[String] = []
	for string in strings:
		if not seen.has(string):
			absent.append(string)
	absent.sort()
	return absent


## What `root` and everything below it draws, as strings.
static func strings_of(root: Node) -> Dictionary[String, int]:
	var found: Dictionary[String, int] = {}
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	for node in nodes:
		# A parked zombie or a spent effect is hidden and draws nothing.
		if node is Node3D and not (node as Node3D).is_visible_in_tree():
			continue
		if node is Light3D:
			found[_light(node as Light3D)] = 1
		elif node is GeometryInstance3D:
			for string in _geometry(node as GeometryInstance3D):
				found[string] = 1
	return found


static func _light(light: Light3D) -> String:
	var kind := (
		"omni" if light is OmniLight3D else ("spot" if light is SpotLight3D else "directional")
	)
	return "light:%s%s" % [kind, ":shadow" if light.shadow_enabled else ""]


static func _geometry(node: GeometryInstance3D) -> Array[String]:
	var kind := _kind(node)
	var materials: Array[Material] = []
	if node.material_override != null:
		materials.append(node.material_override)
	elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var material := (node as MeshInstance3D).get_active_material(surface)
			if material != null:
				materials.append(material)
		if (
			mesh.get_surface_count() == 0
			and mesh is PrimitiveMesh
			and (mesh as PrimitiveMesh).material != null
		):
			materials.append((mesh as PrimitiveMesh).material)
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		var multimesh_mesh := (node as MultiMeshInstance3D).multimesh.mesh
		if multimesh_mesh != null:
			for surface in multimesh_mesh.get_surface_count():
				var material := multimesh_mesh.surface_get_material(surface)
				if material != null:
					materials.append(material)
	elif node is CSGShape3D and (node as CSGShape3D).material != null:
		materials.append((node as CSGShape3D).material)
	if node.material_overlay != null:
		materials.append(node.material_overlay)
	var strings: Array[String] = []
	if materials.is_empty():
		strings.append("%s|default" % kind)
	for material in materials:
		strings.append("%s|%s" % [kind, material_key(material)])
	return strings


## How the mesh reaches the program: skinned, instanced many times, text, or a plain mesh.
static func _kind(node: GeometryInstance3D) -> String:
	if node is MultiMeshInstance3D:
		return "multimesh"
	if node is Label3D:
		return "label3d"
	if node is MeshInstance3D and (node as MeshInstance3D).skin != null:
		return "skinned"
	if node is CSGShape3D:
		return "csg"
	return "mesh"


## What decides a material's program: its shader's file, or for a standard material the settings
## that change the shader the engine writes for it.
static func material_key(material: Material) -> String:
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		return "shader:%s" % (shader.resource_path if shader != null else "none")
	if material is BaseMaterial3D:
		var parts: Array[String] = []
		for property in MATERIAL_PROPERTIES:
			parts.append(str(material.get(property)))
		var base := material as BaseMaterial3D
		for texture in [
			BaseMaterial3D.TEXTURE_ALBEDO,
			BaseMaterial3D.TEXTURE_EMISSION,
			BaseMaterial3D.TEXTURE_NORMAL
		]:
			parts.append("t" if base.get_texture(texture) != null else "-")
		return "standard:" + ",".join(parts)
	return "other:%s" % material.get_class()
