class_name HudNameTab
extends RefCounted
## The seat-coloured strip behind a player's level and name when a calling card sits behind their
## box (`HudPlayerBox`, #1189). The card shows round it and through the box's own corners; the words
## sit on the colour their ink was chosen for, so they have exactly the contrast the design says
## (`HudPlayerBox.MIN_CONTRAST`) at every size, which an outline cannot give on a phone in a night
## (a unit is 0.36 of a pixel there and the outline is about one pixel, as wide as the letters'
## strokes). The right end leans like the points tab's left end, so the two read as one family.
##
## It is not a node: the night's canvas-item budget (tools/perf/budget.json) has no room for one
## more item a box, so `HudPointsTab` draws the strip in its own `_draw`, right behind the words.

signal changed

## How far the right end leans: the top is this much further right than the bottom.
const SLANT := 6.0
## How opaque the strip is: 1.0 hides the card behind the words. A translucent strip is this one
## number (the read of the words is then less than the design's, test_plate_words measures it).
const ALPHA := 1.0

## Where the strip is, in the box's coordinates.
var rect := Rect2():
	set(value):
		if value != rect:
			rect = value
			changed.emit()
var colour := Color.WHITE:
	set(value):
		if value != colour:
			colour = value
			changed.emit()
var visible := false:
	set(value):
		if value != visible:
			visible = value
			changed.emit()


## Puts the strip over `area` (box coordinates).
func place(area: Rect2) -> void:
	rect = area


## The strip's corners in the box's coordinates: the top is the width, the bottom leans in.
func outline() -> PackedVector2Array:
	return PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x - SLANT, rect.end.y),
			Vector2(rect.position.x, rect.end.y),
		]
	)


## The colour the strip is drawn in.
func drawn_colour() -> Color:
	return Color(colour, colour.a * ALPHA)
