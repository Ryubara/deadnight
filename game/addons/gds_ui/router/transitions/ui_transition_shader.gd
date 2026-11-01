class_name UITransitionShader
extends UITransition
## A transition drawn by a shader on the overlay (the shipped ones are a film burn and a projector
## iris): it closes over the old screen, the screens swap behind it, then it opens on the new one.
## The shader's colours come from the tokens (`feed_tokens`).
##
## The shaders are procedural and never read the screen, so they work the same in the
## Compatibility renderer and in a web build.

var shader: Shader
## Where the closing half stops, 0 to 1 of the shader's `progress`. A shader that already covers
## the whole screen a little before 1 (the burn) stops there, so the screen is not held black.
var close_to := 1.0
## Where the opening half starts, for a shader that shows nothing new before this point.
var reveal_from := 0.0


func _init(shader_resource: Shader = null, close_end := 1.0, reveal_start := 0.0) -> void:
	shader = shader_resource
	close_to = close_end
	reveal_from = reveal_start


func play(ctx: UITransitionContext) -> void:
	var material := ShaderMaterial.new()
	material.shader = shader
	feed_tokens(material, ctx.tokens)
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
	var from := reveal_from if reveal else 0.0
	var to := 1.0 if reveal else close_to
	material.set_shader_parameter(&"progress", from)
	ctx.overlay.show()
	# Closing starts slowly and speeds up; opening starts fast and settles. Either way the
	# screen is never left idle (cubic tails would hold on black or on nothing for frames).
	var tween := ctx.stage.create_tween().set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT if reveal else Tween.EASE_IN)
	tween.tween_method(
		func(value: float) -> void: material.set_shader_parameter(&"progress", value),
		from,
		to,
		ctx.tokens.dur_screen * ctx.tokens.shader_half_scale * (to - from)
	)
	await tween.finished


## Sets every uniform of the material's shader that is named like a colour token (`burn_flame`,
## `iris_rim`, ...) to that token's value, so a shader takes its palette from the tokens and a
## game's own shader does the same by naming a uniform after a token. Other uniforms are left alone.
static func feed_tokens(material: ShaderMaterial, tokens: UITokens) -> void:
	if material.shader == null or tokens == null:
		return
	for uniform in material.shader.get_shader_uniform_list():
		var uniform_name := StringName(uniform["name"])
		var value: Variant = tokens.get(uniform_name)
		if value is Color:
			material.set_shader_parameter(uniform_name, value)


static func _farthest_corner(origin: Vector2, aspect: float) -> float:
	var far := 0.0
	for corner in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]:
		far = maxf(far, ((corner - origin) * Vector2(aspect, 1.0)).length())
	return far
