class_name DownedPose
extends RefCounted
## The downed and revive layers of `PlayerAnimation` (#504; docs/design/animation.md, Downed and
## revive): full-body clips from their own files on the Soldier's rig, each reached through an
## eased weight over everything the standing body does. A downed player lies in Downed_Idle (or
## Downed_Crawl by ground speed, when the crawl's file is there); a teammate holding the revive
## kneels in Revive_Kneel. `PlayerAnimation.set_downed` and `set_reviving` set the states.

const REVIVE_GLB := "res://assets/characters/soldier/revive/soldier_revive.glb"
const REVIVE_SPEC := "res://assets/characters/soldier/revive/clips.json"
const DOWNED_CLIP := &"Downed_Idle"
const REVIVE_CLIP := &"Revive_Kneel"
## The crawl is optional until the maintainer decides what a downed player may do (#505): delete
## its folder and the downed pose stays on Downed_Idle whatever the ground speed.
const CRAWL_GLB := "res://assets/characters/soldier/crawl/soldier_crawl.glb"
const CRAWL_SPEC := "res://assets/characters/soldier/crawl/clips.json"
const CRAWL_CLIP := &"Downed_Crawl"
## How fast the body goes down and gets up, and kneels and stands (per second, exponential).
const DOWNED_BLEND_RATE := 6.0
const KNEEL_BLEND_RATE := 10.0
## The crawl is fully in by this share of its clip's ground speed (Downed_Idle below it), and plays
## at ground speed over the clip's own, within these rates.
const CRAWL_FULL := 0.4
const CRAWL_RATE_MIN := 0.5
const CRAWL_RATE_MAX := 1.6
const DOWNED_BLEND_PARAMETER := &"parameters/downed/blend_amount"
const KNEEL_BLEND_PARAMETER := &"parameters/kneel/blend_amount"
const CRAWL_BLEND_PARAMETER := &"parameters/crawl/blend_amount"
const CRAWL_RATE_PARAMETER := &"parameters/crawl_rate/scale"

## Down (the rules said so) and holding a revive.
var downed := false
var reviving := false
## The eased weights that follow them, and the crawl's under the downed pose.
var downed_blend := 0.0
var kneel_blend := 0.0
var crawl_blend := 0.0
## The crawl clip's ground speed (m/s), 0 when its file is not there.
var crawl_speed := 0.0


## Adds the downed and revive clips (and the crawl, when its file is there) to a Soldier's library:
## any model on the Soldier's rig, the player's own or another player's drawn avatar. Returns their
## clips.json entries ({clip: entry}). Nothing is kept in a static (a static Animation outlives the
## scene tree and is reported leaked at exit).
static func add_clips(anim_player: AnimationPlayer) -> Dictionary:
	var entries := {}
	var library := anim_player.get_animation_library(&"")
	for pair: Array in [[REVIVE_GLB, REVIVE_SPEC], [CRAWL_GLB, CRAWL_SPEC]]:
		if not ResourceLoader.exists(pair[0]):
			continue
		var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pair[1]))
		var holder := (load(pair[0]) as PackedScene).instantiate()
		var source := holder.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for clip: String in spec["clips"]:
			entries[clip] = spec["clips"][clip]
			if not library.has_animation(clip):
				library.add_animation(clip, source.get_animation(clip))
			library.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		holder.free()
	return entries


func has_crawl() -> bool:
	return crawl_speed > 0.0


## Adds the kneel and the downed layers over `below` (the standing body) to `tree`; returns the top
## node to connect on: `downed` over `kneel` over `below`.
func add_nodes(tree: AnimationNodeBlendTree, below: StringName) -> StringName:
	tree.add_node(&"revive_clip", _clip(REVIVE_CLIP))
	tree.add_node(&"kneel", AnimationNodeBlend2.new())
	tree.connect_node(&"kneel", 0, below)
	tree.connect_node(&"kneel", 1, &"revive_clip")
	tree.add_node(&"downed_clip", _clip(DOWNED_CLIP))
	tree.add_node(&"downed", AnimationNodeBlend2.new())
	tree.connect_node(&"downed", 0, &"kneel")
	if has_crawl():
		tree.add_node(&"crawl_clip", _clip(CRAWL_CLIP))
		tree.add_node(&"crawl_rate", AnimationNodeTimeScale.new())
		tree.add_node(&"crawl", AnimationNodeBlend2.new())
		tree.connect_node(&"crawl_rate", 0, &"crawl_clip")
		tree.connect_node(&"crawl", 0, &"downed_clip")
		tree.connect_node(&"crawl", 1, &"crawl_rate")
		tree.connect_node(&"downed", 1, &"crawl")
	else:
		tree.connect_node(&"downed", 1, &"downed_clip")
	return &"downed"


## Eases the weights toward the states (the crawl by ground speed `speed` while down) and puts them
## on the tree.
func advance(tree: AnimationTree, speed: float, delta: float) -> void:
	downed_blend = _ease(downed_blend, 1.0 if downed else 0.0, DOWNED_BLEND_RATE, delta)
	kneel_blend = _ease(kneel_blend, 1.0 if reviving else 0.0, KNEEL_BLEND_RATE, delta)
	tree.set(DOWNED_BLEND_PARAMETER, downed_blend)
	tree.set(KNEEL_BLEND_PARAMETER, kneel_blend)
	if has_crawl():
		var share := speed / crawl_speed if downed else 0.0
		var target := clampf(share / CRAWL_FULL, 0.0, 1.0)
		crawl_blend = _ease(crawl_blend, target, DOWNED_BLEND_RATE, delta)
		tree.set(CRAWL_BLEND_PARAMETER, crawl_blend)
		var rate := clampf(share, CRAWL_RATE_MIN, CRAWL_RATE_MAX)
		tree.set(CRAWL_RATE_PARAMETER, lerpf(1.0, rate, target))


static func _ease(value: float, target: float, rate: float, delta: float) -> float:
	value = lerpf(value, target, 1.0 - exp(-rate * delta))
	return target if absf(value - target) < 0.001 else value


static func _clip(clip_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node
