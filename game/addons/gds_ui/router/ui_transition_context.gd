class_name UITransitionContext
extends RefCounted
## What a transition may touch: the stage the screens live in, the overlay above it, and the two
## screens. `reverse` is true when going back (pop), so a slide runs the other way.
##
## Either screen can be freed while a transition runs (a game-over handler, a disconnect), so a
## transition checks `has_outgoing()` / `is_instance_valid(incoming)` after every await and binds
## its tweens to `stage`, never to a screen: a tween bound to a freed node is killed and its
## `finished` signal never fires.

var stage: Control
var overlay: ColorRect
var outgoing: Control
var incoming: Control
var reverse := false
## Where a shader transition opens or closes, in 0..1 stage coordinates (the focused button).
var origin := Vector2(0.5, 0.5)
var tokens: UITokens


## Whether there is an outgoing screen that is still alive (it may be freed mid-transition).
func has_outgoing() -> bool:
	return is_instance_valid(outgoing)


## Hides the outgoing screen and shows the incoming one. Either may have been freed meanwhile.
func swap() -> void:
	if has_outgoing():
		outgoing.hide()
	if is_instance_valid(incoming):
		incoming.show()


## Draws `screen` above its siblings: later children are drawn on top.
func raise(screen: Control) -> void:
	if is_instance_valid(screen) and screen.get_parent() == stage:
		stage.move_child(screen, -1)
