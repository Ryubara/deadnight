class_name ZombieModels
extends RefCounted
## The zombie bodies: the seven committed variants (game/assets/characters/zombies/, built by
## tools/blender/build_zombies.py). Every variant has the kit zombie's skeleton and clip names, so
## ZombieRig's one library plays on all of them. Each file holds two skinned meshes: `NEAR_MESH`
## for gameplay distances and `FAR_MESH` past `FAR_FROM` (docs/design/zombies.md).

const DEFAULT := &"walker"
const DIR := "res://assets/characters/zombies/"
const VARIANTS: Array[StringName] = [
	&"walker", &"greaser", &"usher", &"farmhand", &"runner", &"brute", &"crawler"
]
const NEAR_MESH := "Zombie_Mesh"
const FAR_MESH := "Zombie_Far"
## Metres from the camera at which a zombie swaps to its far mesh.
const FAR_FROM := 18.0


## The variant's scene; an unknown name reports an error and gives the walker.
static func scene(variant: StringName = DEFAULT) -> PackedScene:
	if variant not in VARIANTS:
		push_error("ZombieModels: no variant %s, using %s" % [variant, DEFAULT])
		variant = DEFAULT
	return load(DIR + "zombie_%s.glb" % variant) as PackedScene


## Shows the near mesh up close and the far mesh beyond FAR_FROM (a model without them is left).
static func set_detail_ranges(model: Node) -> void:
	var near := model.find_child(NEAR_MESH, true, false) as GeometryInstance3D
	var far := model.find_child(FAR_MESH, true, false) as GeometryInstance3D
	if near != null and far != null:
		near.visibility_range_end = FAR_FROM
		far.visibility_range_begin = FAR_FROM
