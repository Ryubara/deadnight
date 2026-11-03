class_name ZombieModels
extends RefCounted
## The zombie bodies: the seven committed variants (game/assets/characters/zombies/, built by
## tools/blender/build_zombies.py) and the headliner (game/assets/characters/zombie_boss/, built by
## tools/blender/build_boss.py). Every variant has the kit zombie's skeleton and clip names, so
## ZombieRig's one library plays on all of them. Each file holds two skinned meshes: `NEAR_MESH`
## for gameplay distances and `FAR_MESH` past `FAR_FROM` (docs/design/zombies.md).

const DEFAULT := &"walker"
const DIR := "res://assets/characters/zombies/"
## Every look a zombie can be sent in, in the order of the wire format (`ZombieCodec`): a look's
## index is its wire id, so the list only ever grows at its end.
const VARIANTS: Array[StringName] = [
	&"walker", &"greaser", &"usher", &"farmhand", &"runner", &"brute", &"crawler", &"headliner"
]
## Where a look's file is when it is not `DIR/zombie_<look>.glb`.
const PATHS := {&"headliner": "res://assets/characters/zombie_boss/zombie_boss.glb"}
## Looks with their own clips (the `Boss_*` five) and state machine (`ZombieRig`).
const BOSSES: Array[StringName] = [&"headliner"]
## How tall each look stands against the walker, for the hit zones (docs/design/zombies.md; the
## model files already carry it).
const HEIGHTS := {
	&"walker": 1.0,
	&"greaser": 1.02,
	&"usher": 0.97,
	&"farmhand": 1.0,
	&"runner": 1.07,
	&"brute": 1.18,
	&"crawler": 1.0,
	&"headliner": 1.45,
}
## How tall a crawler lies against a walker standing.
const CRAWL_HEIGHT := 0.6
## Looks that move on the ground on their hands: the crawl clip, not the walk.
const CRAWLING: Array[StringName] = [&"crawler"]
const NEAR_MESH := "Zombie_Mesh"
const FAR_MESH := "Zombie_Far"
## The scale every model is drawn at: the style bible's game scale (docs/design/style.md), on top
## of each variant's height. At it the walker stands 1.77 m, the brute 2.09 m, the headliner 2.56 m,
## which is what the hit zones (`Hitbox`) are sized for.
const GAME_SCALE := 1.3
## Metres from the camera at which a zombie swaps to its far mesh.
const FAR_FROM := 18.0


## The wire index of a look; an unknown look is the walker's.
static func look_index(look: StringName) -> int:
	return maxi(VARIANTS.find(look), 0)


static func look_at(index: int) -> StringName:
	return VARIANTS[index] if index >= 0 and index < VARIANTS.size() else DEFAULT


## Where the look's file is.
static func path_of(look: StringName) -> String:
	return PATHS.get(look, DIR + "zombie_%s.glb" % look)


## The look's scene; an unknown name reports an error and gives the walker.
static func scene(look: StringName = DEFAULT) -> PackedScene:
	if look not in VARIANTS:
		push_error("ZombieModels: no variant %s, using %s" % [look, DEFAULT])
		look = DEFAULT
	return load(path_of(look)) as PackedScene


static func height_of(look: StringName) -> float:
	return HEIGHTS.get(look, 1.0)


## How high to aim on the look against a walker: how tall it stands, and a crawler is low. (Not the
## size of its hit zones, which are fitted to each body: `ZombieProfile.hit_scale`.)
static func aim_scale(look: StringName) -> float:
	return height_of(look) * (CRAWL_HEIGHT if crawls(look) else 1.0)


static func is_boss(look: StringName) -> bool:
	return look in BOSSES


static func crawls(look: StringName) -> bool:
	return look in CRAWLING


## Shows the near mesh up close and the far mesh beyond FAR_FROM (a model without them is left).
static func set_detail_ranges(model: Node) -> void:
	var near := model.find_child(NEAR_MESH, true, false) as GeometryInstance3D
	var far := model.find_child(FAR_MESH, true, false) as GeometryInstance3D
	if near != null and far != null:
		near.visibility_range_end = FAR_FROM
		far.visibility_range_begin = FAR_FROM
