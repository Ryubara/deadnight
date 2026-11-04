class_name DrinkLayer
extends RefCounted
## The perk drink's layer of `PlayerAnimation` (#912, docs/design/animation.md, "Drink"):
## `Drink_Perk`, from its own file, over the repair layer and under a down, played at the pace of
## the rules' drink (its seconds), with the perk's bottle (`PerkBottle`) on the hand mount. Its
## events show the bottle, pop the cap, gulp and throw the bottle away; `weapon_hidden` and
## `weapon_visible` put the gun away and bring it back (`holds_weapon` keeps it away between).

const GLB := "res://assets/characters/soldier/drink/soldier_drink.glb"
const SPEC := "res://assets/characters/soldier/drink/clips.json"
const CLIP := &"Drink_Perk"
## How fast the layer fades in and out (per second, exponential).
const BLEND_RATE := 18.0
const SEEK_PARAMETER := &"parameters/drink_seek/seek_request"
const BLEND_PARAMETER := &"parameters/drink/blend_amount"

var bottle: PerkBottle
var drinking := false
## Where the clip is, in its own seconds, and the layer's weight now (0 the other arms, 1 the
## drink).
var time := 0.0
var blend := 0.0
## Whether the drink still keeps the weapon put away (until the clip's `weapon_visible`).
var holds_weapon := false
var _scale := 1.0
var _length := 2.5


## The bottle goes on `mount`, the hand's, hidden until the clip shows it.
func _init(mount: Node3D) -> void:
	bottle = PerkBottle.new()
	mount.add_child(bottle)


## Adds the layer's nodes over the node `below`; returns the node the arms are read from.
static func add_nodes(tree: AnimationNodeBlendTree, below: StringName) -> StringName:
	var clip := AnimationNodeAnimation.new()
	clip.animation = CLIP
	tree.add_node(&"drink_clip", clip)
	tree.add_node(&"drink_seek", AnimationNodeTimeSeek.new())
	tree.add_node(&"drink", AnimationNodeBlend2.new())
	tree.connect_node(&"drink_seek", 0, &"drink_clip")
	tree.connect_node(&"drink", 0, below)
	tree.connect_node(&"drink", 1, &"drink_seek")
	return &"drink"


## A drink of `tonic_id` starts: the clip (`length` of its own seconds) stretched to `seconds`.
func start(tonic_id: StringName, seconds: float, length: float, tree: AnimationTree) -> void:
	drinking = true
	holds_weapon = true
	time = 0.0
	_length = length
	_scale = length / maxf(seconds, 0.05)
	bottle.fill(tonic_id)
	tree.set(SEEK_PARAMETER, 0.0)


## Ends the drink at once (`spilled`: the drinker went down, the bottle falls from the hand).
## Returns whether one was under way.
func stop(spilled: bool) -> bool:
	if not drinking:
		return false
	drinking = false
	holds_weapon = false
	if spilled:
		bottle.drop()
	else:
		bottle.visible = false
	return true


## Moves the clip on by `delta` at the drink's pace and eases the layer; steps what was thrown.
## Returns the clip's seconds passed, (from, to), for its events (the same twice when none).
func advance(delta: float, tree: AnimationTree) -> Vector2:
	var passed := Vector2(time, time)
	if drinking:
		time = minf(time + delta * _scale, _length)
		passed.y = time
		tree.set(SEEK_PARAMETER, time)
	var target := 1.0 if drinking else 0.0
	blend = lerpf(blend, target, 1.0 - exp(-BLEND_RATE * delta))
	if absf(blend - target) < 0.001:
		blend = target
	tree.set(BLEND_PARAMETER, blend)
	bottle.step(delta)
	return passed


## Whether the clip has reached its end.
func ended() -> bool:
	return drinking and time >= _length


## One of the clip's own events; the bottle is thrown away to the right of `body`.
func on_event(event: String, body: Node3D) -> void:
	match event:
		"bottle_visible":
			bottle.visible = drinking
		"cap_off":
			bottle.pop_cap()
		"drink":
			bottle.gulp()
		"discard":
			var basis := body.global_basis.orthonormalized()
			bottle.discard(basis.x, basis.z)
