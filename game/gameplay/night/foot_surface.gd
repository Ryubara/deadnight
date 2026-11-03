class_name FootSurface
extends RefCounted
## What a player stands on, for the sound of their steps: the lot's ground is boxes painted with a
## material whose pattern is a texture (`assets/lot/textures/`), so a gravel yard and an asphalt
## field are told apart by the ray that finds the floor under a foot and the pattern of its
## material. Everything that is not gravel steps like asphalt: concrete, tile and planks are all
## hard ground, and the two files are the two sounds the game has, but for wood: a floor that says
## so with metadata (the second map's stairs and upper floor) steps with the hollow knock of a
## plank over a gap. A floor can say it outright with metadata `surface` (`"asphalt"`, `"gravel"` or
## `"wood"`); the pattern of its material decides only gravel (the lot's wood-patterned crates and
## fences are not floors).

const ASPHALT := &"asphalt"
const GRAVEL := &"gravel"
const WOOD := &"wood"
const SURFACES: Array[StringName] = [ASPHALT, GRAVEL, WOOD]
## The pattern texture's name that makes ground gravel.
const GRAVEL_PATTERN := "gravel"
## The ray starts this far above the foot (clear of the floor it stands on) and ends this far below.
const RAY_UP := 0.4
const RAY_DOWN := 0.8
## Physics layer of the lot's ground (the default layer, where every box of the greybox sits).
const GROUND_MASK := PhysicsLayers.WORLD | PhysicsLayers.BODY

## The surface found for each collider, by instance id: a floor's material does not change.
var _cache: Dictionary[int, StringName] = {}


## The surface under `at` (a point at the feet), asphalt when there is nothing under it.
func at(space: PhysicsDirectSpaceState3D, point: Vector3, exclude: Array[RID] = []) -> StringName:
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * RAY_UP, point + Vector3.DOWN * RAY_DOWN, GROUND_MASK
	)
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit["collider"] is Object:
		return ASPHALT
	var floor_node := hit["collider"] as Object
	var key := floor_node.get_instance_id()
	if not _cache.has(key):
		_cache[key] = surface_of(floor_node)
	return _cache[key]


## What a floor object sounds like: its `surface` metadata, else its material's pattern.
static func surface_of(floor_node: Object) -> StringName:
	if floor_node.has_meta(&"surface"):
		return StringName(floor_node.get_meta(&"surface"))
	var material: Material = null
	if floor_node is GeometryInstance3D:
		material = (floor_node as GeometryInstance3D).material_override
	if material == null and floor_node.get(&"material") is Material:
		material = floor_node.get(&"material")
	return of_material(material)


static func of_material(material: Material) -> StringName:
	if material is ShaderMaterial:
		var pattern: Variant = (material as ShaderMaterial).get_shader_parameter(&"pattern")
		if pattern is Resource and (pattern as Resource).resource_path.contains(GRAVEL_PATTERN):
			return GRAVEL
	return ASPHALT
