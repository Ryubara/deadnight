class_name UITransitionSlide
extends UITransition
## Both screens slide, the old one at a third of the distance and dimmed (parallax).
## Pop runs the other way.

const PARALLAX := 0.33
const DIM := Color(0.45, 0.45, 0.5)


func play(ctx: UITransitionContext) -> void:
	var t := ctx.tokens
	var width := ctx.stage.size.x
	var dir := -1.0 if ctx.reverse else 1.0
	ctx.incoming.show()
	ctx.incoming.position.x = width * dir
	var tween := ctx.stage.create_tween().set_parallel(true)
	UIMotion.apply_ease(tween, UITokens.Ease.EMPHASIZED)
	tween.tween_property(ctx.incoming, "position:x", 0.0, t.dur_screen)
	if ctx.outgoing != null:
		tween.tween_property(ctx.outgoing, "position:x", -width * dir * PARALLAX, t.dur_screen)
		tween.tween_property(ctx.outgoing, "modulate", DIM, t.dur_screen)
	await tween.finished
	ctx.swap()
	if ctx.outgoing != null:
		ctx.outgoing.position.x = 0.0
		ctx.outgoing.modulate = Color.WHITE
