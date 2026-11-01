class_name UITransitionSlide
extends UITransition
## Push: the new screen slides in from the right over the old one, which moves a third of the
## way left and dims (parallax). Pop is the same film played backwards: the leaving screen slides
## off to the right over the old one, which moves in from a third of the way left and brightens.
## The entering screen is on top for a push and the leaving screen for a pop.


func play(ctx: UITransitionContext) -> void:
	var t := ctx.tokens
	var width := ctx.stage.size.x
	var has_outgoing := ctx.has_outgoing()
	var tween := ctx.stage.create_tween().set_parallel(true)
	UIMotion.apply_ease(tween, UITokens.Ease.EMPHASIZED)
	ctx.incoming.show()
	if ctx.reverse:
		ctx.incoming.position.x = -width * t.slide_parallax
		ctx.incoming.modulate = t.slide_dim
		tween.tween_property(ctx.incoming, "position:x", 0.0, t.dur_screen)
		tween.tween_property(ctx.incoming, "modulate", Color.WHITE, t.dur_screen)
		if has_outgoing:
			tween.tween_property(ctx.outgoing, "position:x", width, t.dur_screen)
		ctx.raise(ctx.outgoing)
	else:
		ctx.incoming.position.x = width
		tween.tween_property(ctx.incoming, "position:x", 0.0, t.dur_screen)
		if has_outgoing:
			tween.tween_property(
				ctx.outgoing, "position:x", -width * t.slide_parallax, t.dur_screen
			)
			tween.tween_property(ctx.outgoing, "modulate", t.slide_dim, t.dur_screen)
		ctx.raise(ctx.incoming)
	await tween.finished
	ctx.swap()
	if ctx.has_outgoing():
		ctx.outgoing.position.x = 0.0
		ctx.outgoing.modulate = Color.WHITE
	if is_instance_valid(ctx.incoming):
		ctx.incoming.position.x = 0.0
		ctx.incoming.modulate = Color.WHITE
