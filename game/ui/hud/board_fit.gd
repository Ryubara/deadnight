class_name BoardFit
extends RefCounted
## Where the scoreboard's ticket stands while a finger holds the players' column (#1287). The
## ticket is centred over the night, which on a phone is under the right thumb's buttons at the
## smaller interface sizes, and the busiest night (eight people and their bots) is as tall as the
## page. So it stays where it is while nothing of a finger is under it, moves along the screen
## between the buttons and the column of the two sides its rows reach when something is, and shrinks
## a step at a time, no further than `SMALLEST`, until it fits.
## Pure geometry, no nodes: `Hud` gives it the room, the ticket's own size and the boxes to keep
## off.

## Air kept between the ticket and a button or a place, canvas units (the ring's own gap is 42).
const GAP := 24.0
## The least share of its own size the ticket is shrunk to, and each step of the search.
const SMALLEST := 0.5
const STEP := 0.05


## `{scale, shift}`: the ticket's share of its own size and how far along the screen (canvas units,
## to the right) it is moved from the middle of `room`, so that no box of `avoid` is within `GAP` of
## it. `avoid` are the buttons, the weapon places and the column in the same units as `room`. When
## nothing fits, the smallest step, as far along as it can go.
static func fit(room: Rect2, size: Vector2, avoid: Array[Rect2]) -> Dictionary:
	var found := {&"scale": 1.0, &"shift": 0.0}
	var share := 1.0
	while share >= SMALLEST - 0.001:
		var shown := size * share
		var limits := _limits(room, shown, avoid)
		var reach := limits.y - limits.x - shown.x
		found = {&"scale": share, &"shift": _shift(room, shown, limits)}
		if reach >= 0.0 and shown.y <= room.size.y:
			return found
		share -= STEP
	return found


## The left and right edge (x, y of the result) of the strip across `room` that a ticket `shown`
## big, centred up and down, has to itself: bounded by the boxes at its height, those left of the
## middle on the left and the others on the right.
static func _limits(room: Rect2, shown: Vector2, avoid: Array[Rect2]) -> Vector2:
	var top := room.get_center().y - shown.y * 0.5
	var left := room.position.x
	var right := room.end.x
	var middle := room.get_center().x
	for box in avoid:
		if box.end.y + GAP <= top or box.position.y - GAP >= top + shown.y:
			continue
		if box.get_center().x < middle:
			left = maxf(left, box.end.x + GAP)
		else:
			right = minf(right, box.position.x - GAP)
	return Vector2(left, right)


## How far from the middle of `room` a ticket `shown` big stands inside `limits`: none when the
## middle is clear, the nearest place in them when it is not (the strip's middle when too narrow).
static func _shift(room: Rect2, shown: Vector2, limits: Vector2) -> float:
	var middle := room.get_center().x
	if limits.y - limits.x < shown.x:
		return (limits.x + limits.y) * 0.5 - middle
	return clampf(middle, limits.x + shown.x * 0.5, limits.y - shown.x * 0.5) - middle
