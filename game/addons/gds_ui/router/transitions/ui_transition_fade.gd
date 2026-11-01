class_name UITransitionFade
extends UITransition
## The outgoing screen dims out quickly; the incoming one rises and settles.


func play(ctx: UITransitionContext) -> void:
	var t := ctx.tokens
	if ctx.outgoing != null:
		var out := ctx.outgoing.create_tween()
		UIMotion.apply_ease(out, UITokens.Ease.EXIT)
		out.tween_property(ctx.outgoing, "modulate:a", 0.0, t.dur_fast)
		await out.finished
	ctx.swap()
	if ctx.outgoing != null:
		ctx.outgoing.modulate.a = 1.0
	ctx.incoming.modulate.a = 0.0
	await ctx.stage.get_tree().process_frame
	var tween := UIMotion.fade_in(ctx.incoming)
	await tween.finished
