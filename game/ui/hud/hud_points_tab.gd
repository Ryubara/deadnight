class_name HudPointsTab
extends Control
## The seat-coloured tab behind a player's points when a calling card sits behind their box
## (`HudPlayerBox`): the card shows through behind the badge and the name, and the points, the
## biggest numerals on the screen, stay on the colour of the player's armband, exactly as they are
## in a box with no card. A parallelogram that runs to the box's right edge and takes its cut
## corner. It also draws the strip behind the level and the name (`HudNameTab`): the same colour, so
## the same canvas item, which the night's budget has no room to double.

## How far the tab's left edge leans: the top is this much further right than the bottom.
const SLANT := 9.0

var colour := Color.WHITE:
	set(value):
		if value != colour:
			colour = value
			queue_redraw()
## The strip behind the level and the name, drawn after the tab (box coordinates).
var strip: HudNameTab:
	set(value):
		if strip != null:
			strip.changed.disconnect(queue_redraw)
		strip = value
		if strip != null:
			strip.changed.connect(queue_redraw)
var _outline := PackedVector2Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild)


## Where the tab goes: from `left` (its bottom edge) to the right end of `box`, the box's height.
func place(box: Rect2, left: float) -> void:
	position = Vector2(left, box.position.y)
	size = Vector2(box.end.x - left, box.size.y)
	_rebuild()


func _rebuild() -> void:
	var notch := HudStyle.NOTCH * 0.6
	_outline = PackedVector2Array(
		[
			Vector2(SLANT, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x, size.y - notch),
			Vector2(size.x - notch, size.y),
			Vector2(0.0, size.y),
		]
	)
	queue_redraw()


func _draw() -> void:
	if _outline.size() >= 3:
		draw_colored_polygon(_outline, colour)
	if strip != null and strip.visible and strip.rect.has_area():
		draw_set_transform(-position)
		draw_colored_polygon(strip.outline(), strip.drawn_colour())
		draw_set_transform(Vector2.ZERO)
