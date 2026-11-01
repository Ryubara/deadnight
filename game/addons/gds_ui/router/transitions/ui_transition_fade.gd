class_name UITransitionFade
extends UITransition
## The outgoing screen dims out quickly; the incoming one rises and settles.


func play(ctx: UITransitionContext) -> void:
	var t := ctx.tokens
	if ctx.has_outgoing():
		var out := ctx.stage.create_tween()
		UIMotion.apply_ease(out, UITokens.Ease.EXIT)
		out.tween_property(ctx.outgoing, "modulate:a", 0.0, t.dur_fast)
		await out.finished
	ctx.swap()
	if ctx.has_outgoing():
		ctx.outgoing.modulate.a = 1.0
	if not is_instance_valid(ctx.incoming):
		return
	ctx.incoming.modulate.a = 0.0
	await ctx.stage.get_tree().process_frame
	if not is_instance_valid(ctx.incoming):
		return
	var tween := UIMotion.fade_in(ctx.incoming, 0.0, ctx.stage)
	await tween.finished
