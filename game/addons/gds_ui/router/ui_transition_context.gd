class_name UITransitionContext
extends RefCounted
## What a transition may touch: the stage the screens live in, the overlay above it, and the two
## screens. `reverse` is true when going back (pop), so a slide runs the other way.

var stage: Control
var overlay: ColorRect
var outgoing: Control
var incoming: Control
var reverse := false
## Where a shader transition opens or closes, in 0..1 stage coordinates (the focused button).
var origin := Vector2(0.5, 0.5)
var tokens: UITokens


## Hides the outgoing screen and shows the incoming one.
func swap() -> void:
	if outgoing != null:
		outgoing.hide()
	incoming.show()
