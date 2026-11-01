class_name HudReticle
extends HudPart
## The centre reticle: a small static mark where the shots go (the camera ray, so it never moves
## with the shoulder, the aim or the body). Four ticks round a gap and a dot in the light ink with
## a dark edge. It only draws; hit markers and damage numbers are `HudCrosshair`, drawn over it.
##
## The screen hides it while a menu or the pause card covers the night (`set_shown`), and it
## hides itself while the local player is down.

var style := ReticleStyle.new():
	set(value):
		style = value if value != null else ReticleStyle.new()
		queue_redraw()

var _shown := true


func topics() -> Array[StringName]:
	return [HudState.TEAM]


func refresh() -> void:
	visible = _shown and not state.is_local_downed()


## True when something other than the HUD says the reticle may show (false under a menu).
func set_shown(shown: bool) -> void:
	_shown = shown
	if state != null:
		refresh()
	else:
		visible = shown


## The rectangles of the ticks and the dot, from the centre, in canvas units.
func shapes(centre: Vector2) -> Array[Rect2]:
	var half := style.thickness * 0.5
	var near := style.gap
	var far := style.gap + style.arm_length
	var found: Array[Rect2] = []
	if style.arm_length > 0.0:
		found.append(
			Rect2(centre + Vector2(-half, -far), Vector2(style.thickness, style.arm_length))
		)
		found.append(
			Rect2(centre + Vector2(-half, near), Vector2(style.thickness, style.arm_length))
		)
		found.append(
			Rect2(centre + Vector2(-far, -half), Vector2(style.arm_length, style.thickness))
		)
		found.append(
			Rect2(centre + Vector2(near, -half), Vector2(style.arm_length, style.thickness))
		)
	if style.dot > 0.0:
		found.append(Rect2(centre - Vector2.ONE * style.dot * 0.5, Vector2.ONE * style.dot))
	return found


func _draw() -> void:
	var centre := size * 0.5
	var ink := tokens.ink * style.tint
	ink.a = style.opacity
	var edge := tokens.shadow
	edge.a = maxf(edge.a, 0.85) * style.opacity
	var parts := shapes(centre)
	if style.outline > 0.0:
		for rect in parts:
			draw_rect(rect.grow(style.outline), edge)
	for rect in parts:
		draw_rect(rect, ink)
