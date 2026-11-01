class_name UIFocusRing
extends RefCounted
## The focus ring every component shares: it closes in from a wider gap as `amount` goes 0 to 1.

const LAND_DISTANCE := 10.0

var _tokens: UITokens
var _box := StyleBoxFlat.new()


func _init(tokens: UITokens, radius: int) -> void:
	_tokens = tokens
	_box.anti_aliasing = true
	_box.draw_center = false
	_box.set_border_width_all(tokens.focus_border)
	_box.set_corner_radius_all(radius)


## Draws the ring around `rect` (the thing in focus) on `canvas`. Nothing is drawn at 0.
func draw(canvas: CanvasItem, rect: Rect2, amount: float) -> void:
	if amount <= 0.01:
		return
	var spread := float(_tokens.focus_gap) + (1.0 - amount) * LAND_DISTANCE
	_box.border_color = Color(_tokens.accent_bright, clampf(amount, 0.0, 1.0))
	canvas.draw_style_box(_box, rect.grow(spread))
