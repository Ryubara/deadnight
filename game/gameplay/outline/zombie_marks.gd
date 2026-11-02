class_name ZombieMarks
extends Node
## Outlines the last zombies of a round through walls, on this client, so the players can find them.
## It reads only what every frame of the server carries (`phase` and `remaining`, the zombies still
## to spawn plus those alive) and so every client marks the same zombies. While the round is active
## and `remaining` is at most `mark_last`, each zombie that is not dying wears the style's outline;
## when the round ends, a zombie dies or the count rises, it comes off. Nothing is checked per
## zombie or per frame while nobody is marked and the rule says nobody should be.
##
## Tune it live: select this node in the remote scene tree of a running game and change `mark_last`,
## `enabled` or the `style` (colour, thickness, glow).

## The shipped look, one for every marked zombie.
@export var style: OutlineStyle
## The last this many zombies are marked (the rules' `ZombieTuning.mark_last` at the start).
@export_range(0, 40, 1, "suffix:zombies") var mark_last := 3
## Switch for the whole thing.
@export var enabled := true

var _horde: ZombieHorde
## Whether any view wears the outline now.
var _any := false


func setup(horde: ZombieHorde, p_mark_last: int) -> void:
	_horde = horde
	mark_last = p_mark_last
	if style == null:
		style = load(Outline.DEFAULT_STYLE) as OutlineStyle
	# The shaders' materials are made now, not at the first mark in the middle of a night.
	style.chain()


## The rule: whether the zombies are marked in a frame of this phase with this many zombies left.
static func rule(phase: int, remaining: int, last: int) -> bool:
	return phase == GameRules.Phase.ACTIVE and remaining >= 1 and remaining <= last


## Follows one frame (called after the horde has followed its snapshot).
func apply_frame(phase: int, remaining: int) -> void:
	var on := enabled and rule(phase, remaining, mark_last)
	if not on and not _any:
		return
	_any = false
	for view in _horde.views():
		var marked := on and not view.is_dying()
		view.set_outlined(marked, style)
		_any = _any or marked


## How many zombies wear the outline now.
func marked_count() -> int:
	var count := 0
	for view in _horde.views():
		if view.is_outlined():
			count += 1
	return count
