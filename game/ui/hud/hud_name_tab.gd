class_name HudNameTab
extends Control
## The seat-coloured strip behind a player's level and name when a calling card sits behind their
## box (`HudPlayerBox`, #1189). The card shows round it and through the box's own corners; the words
## sit on the colour their ink was chosen for, so they have exactly the contrast the design says
## (`HudPlayerBox.MIN_CONTRAST`) at every size, which an outline cannot give on a phone in a night
## (a unit is 0.36 of a pixel there and the outline is about one pixel, as wide as the letters'
## strokes). The right end leans like the points tab's left end, so the two read as one family.

## How far the right end leans: the top is this much further right than the bottom.
const SLANT := 6.0

var colour := Color.WHITE:
	set(value):
		if value != colour:
			colour = value
			queue_redraw()
var _outline := PackedVector2Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild)


## Puts the strip over `area` (box coordinates).
func place(area: Rect2) -> void:
	position = area.position
	size = area.size
	_rebuild()


func _rebuild() -> void:
	_outline = PackedVector2Array(
		[
			Vector2.ZERO,
			Vector2(size.x, 0.0),
			Vector2(size.x - SLANT, size.y),
			Vector2(0.0, size.y),
		]
	)
	queue_redraw()


func _draw() -> void:
	if _outline.size() >= 3:
		draw_colored_polygon(_outline, colour)
