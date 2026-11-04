class_name HudXpBar
extends Control
## The level bar of the night report: a track, the part of the level that was already filled when
## the night began (`from`), and the part this night added in the brighter accent (`to` is where
## the night ended). Fractions of the bar, 0 to 1.

const HEIGHT := 16.0
const EDGE := 2.0

var from := 0.0:
	set(value):
		from = clampf(value, 0.0, 1.0)
		queue_redraw()
var to := 0.0:
	set(value):
		to = clampf(value, 0.0, 1.0)
		queue_redraw()

var _tokens := UITokens.active()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = HEIGHT


func _draw() -> void:
	var track := Rect2(Vector2.ZERO, size)
	draw_rect(track, _tokens.shadow)
	var inner := track.grow(-EDGE)
	var before := Rect2(inner.position, Vector2(inner.size.x * minf(from, to), inner.size.y))
	var gained := Rect2(
		inner.position + Vector2(before.size.x, 0.0),
		Vector2(inner.size.x * (to - minf(from, to)), inner.size.y)
	)
	draw_rect(before, _tokens.accent.darkened(0.35))
	draw_rect(gained, _tokens.accent_bright)
	draw_rect(track, _tokens.ink_muted, false, 1.0)
