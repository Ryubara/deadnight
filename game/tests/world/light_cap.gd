class_name LightCap
extends RefCounted
## What the light-cap suite measures (docs/research/night-environment.md, Lamps and glow): the
## meshes a light can shade, the box each takes up, and whether a light reaches one. The
## Compatibility renderer lights a mesh with at most `limit()` omni and spot lights, so a mesh
## reached by more drops some of them, and a lamp pool flickers when it does.

const DEFAULT_LIMIT := 8
const LIMIT_SETTING := "rendering/limits/opengl/max_lights_per_object"


## The project's cap of lights per mesh (the renderer's own default when the project sets none).
static func limit() -> int:
	return int(ProjectSettings.get_setting(LIMIT_SETTING, DEFAULT_LIMIT))


## Every mesh under `root` a light shades: a `MeshInstance3D` or `MultiMeshInstance3D` with a
## surface that is not unshaded, a shaded `Label3D` or `Sprite3D`, and the root of each CSG tree
## (its children are part of its one mesh). Hidden ones count: a door or a barricade shows later.
static func lit_meshes(root: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		if is_lit(node as GeometryInstance3D):
			found.append(node)
	return found


## Whether `node` is shaded by lights: false for the glow, haze and pool quads that ignore them.
static func is_lit(node: GeometryInstance3D) -> bool:
	if node is CSGShape3D:
		var csg := node as CSGShape3D
		if not csg.is_root_shape():
			return false
		return not _is_unshaded(csg.get("material") as Material)
	if node is Label3D:
		return (node as Label3D).shaded
	if node is Sprite3D:
		return (node as Sprite3D).shaded
	var mesh: Mesh = null
	var surfaces: Array[Material] = []
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		mesh = instance.mesh
		for i in mesh.get_surface_count() if mesh != null else 0:
			surfaces.append(instance.get_active_material(i))
	elif node is MultiMeshInstance3D:
		var multi := (node as MultiMeshInstance3D).multimesh
		mesh = multi.mesh if multi != null else null
		for i in mesh.get_surface_count() if mesh != null else 0:
			surfaces.append(mesh.surface_get_material(i))
	else:
		return false
	var override := node.material_override
	for material in surfaces:
		if not _is_unshaded(override if override != null else material):
			return true
	return false


## The box `node` takes up in the world.
static func bounds(node: GeometryInstance3D) -> AABB:
	return node.global_transform * node.get_aabb()


## Whether `light` can touch `box`: an omni's sphere, a spot's cone (by its box).
static func reaches(light: Light3D, box: AABB) -> bool:
	return LightReach.reaches(light, box)


## The names of the lights in `lights` that reach `box`, as paths from `root`.
static func reaching(root: Node, lights: Array[Light3D], box: AABB) -> Array[String]:
	var names: Array[String] = []
	for light in lights:
		if reaches(light, box):
			names.append(str(root.get_path_to(light)))
	return names


## A material that ignores lights: an unshaded standard material, or a shader that says so.
static func _is_unshaded(material: Material) -> bool:
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		return shader != null and shader.code.contains("unshaded")
	return false
