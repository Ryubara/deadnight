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
## Every look a zombie can be sent in, in the order of the wire format (`ZombieCodec`): the
## variants, then the looks that stand in for one. Append only: an index is a look's wire id.
const LOOKS: Array[StringName] = [
	&"walker", &"greaser", &"usher", &"farmhand", &"runner", &"brute", &"crawler", &"headliner"
]
## How tall each look stands against the walker, for the hit zones (docs/design/zombies.md; the
## model files already carry it). The headliner's is its stand-in's height times the stand-in scale.
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
## Looks with no model of their own yet: the variant that stands in for them, and the scale it is
## drawn at. The headliner is a brute grown to the 2.56 m the boss model is to be, until it comes.
const STAND_INS := {&"headliner": {"variant": &"brute", "scale": 1.23}}
## How tall a crawler lies against a walker standing.
const CRAWL_HEIGHT := 0.6
## Looks that move on the ground on their hands: the crawl clip, not the walk.
const CRAWLING: Array[StringName] = [&"crawler"]
const NEAR_MESH := "Zombie_Mesh"
const FAR_MESH := "Zombie_Far"
## Metres from the camera at which a zombie swaps to its far mesh.
const FAR_FROM := 18.0


## The wire index of a look; an unknown look is the walker's.
static func look_index(look: StringName) -> int:
	return maxi(LOOKS.find(look), 0)


static func look_at(index: int) -> StringName:
	return LOOKS[index] if index >= 0 and index < LOOKS.size() else DEFAULT


## The look's scene; an unknown name reports an error and gives the walker.
static func scene(look: StringName = DEFAULT) -> PackedScene:
	var variant := look
	if STAND_INS.has(look):
		variant = STAND_INS[look]["variant"]
	if variant not in VARIANTS:
		push_error("ZombieModels: no variant %s, using %s" % [look, DEFAULT])
		variant = DEFAULT
	return load(DIR + "zombie_%s.glb" % variant) as PackedScene


## The scale the look's scene is drawn at: 1 for a model of its own.
static func scale_of(look: StringName) -> float:
	return STAND_INS[look]["scale"] if STAND_INS.has(look) else 1.0


static func height_of(look: StringName) -> float:
	return HEIGHTS.get(look, 1.0)


## How high to aim on the look against a walker: how tall it stands, and a crawler is low.
static func aim_scale(look: StringName) -> float:
	return height_of(look) * (CRAWL_HEIGHT if crawls(look) else 1.0)


static func crawls(look: StringName) -> bool:
	return look in CRAWLING


## Shows the near mesh up close and the far mesh beyond FAR_FROM (a model without them is left).
static func set_detail_ranges(model: Node) -> void:
	var near := model.find_child(NEAR_MESH, true, false) as GeometryInstance3D
	var far := model.find_child(FAR_MESH, true, false) as GeometryInstance3D
	if near != null and far != null:
		near.visibility_range_end = FAR_FROM
		far.visibility_range_begin = FAR_FROM
