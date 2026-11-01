class_name UITransitionShader
extends UITransition
## A drive-in transition drawn by a shader on the overlay: it closes over the old screen,
## the screens swap behind it, then it opens on the new one.
##
## The shaders are procedural and never read the screen, so they work the same in the
## Compatibility renderer and in a web build.

## Each half runs this long relative to the token `dur_screen`.
const HALF_SCALE := 1.2

var shader: Shader


func _init(shader_resource: Shader = null) -> void:
	shader = shader_resource


func play(ctx: UITransitionContext) -> void:
	var material := ShaderMaterial.new()
	material.shader = shader
	var aspect := ctx.stage.size.x / maxf(ctx.stage.size.y, 1.0)
	material.set_shader_parameter(&"origin", ctx.origin)
	material.set_shader_parameter(&"aspect", aspect)
	material.set_shader_parameter(&"max_dist", _farthest_corner(ctx.origin, aspect))
	ctx.overlay.material = material
	ctx.overlay.color = Color.WHITE
	await _sweep(ctx, material, false)
	ctx.swap()
	await _sweep(ctx, material, true)
	ctx.overlay.hide()
	ctx.overlay.material = null


func _sweep(ctx: UITransitionContext, material: ShaderMaterial, reveal: bool) -> void:
	material.set_shader_parameter(&"reveal", 1.0 if reveal else 0.0)
	material.set_shader_parameter(&"progress", 0.0)
	ctx.overlay.show()
	# Closing starts slowly and speeds up; opening starts fast and settles. Either way the
	# screen is never left idle (cubic tails would hold on black or on nothing for frames).
	var tween := ctx.stage.create_tween().set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT if reveal else Tween.EASE_IN)
	tween.tween_method(
		func(value: float) -> void: material.set_shader_parameter(&"progress", value),
		0.0,
		1.0,
		ctx.tokens.dur_screen * HALF_SCALE
	)
	await tween.finished


static func _farthest_corner(origin: Vector2, aspect: float) -> float:
	var far := 0.0
	for corner in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]:
		far = maxf(far, ((corner - origin) * Vector2(aspect, 1.0)).length())
	return far
