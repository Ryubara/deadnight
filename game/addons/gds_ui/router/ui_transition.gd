class_name UITransition
extends RefCounted
## One way to get from one screen to the next. `play` is a coroutine: the router awaits it.
##
## The base is a cut: nothing animates, one frame passes.

enum Kind { CUT, FADE, SLIDE, BURN, IRIS }


## `ctx.incoming` is already in the stage; `ctx.outgoing` may be null (first screen).
func play(ctx: UITransitionContext) -> void:
	ctx.swap()
	await ctx.stage.get_tree().process_frame
