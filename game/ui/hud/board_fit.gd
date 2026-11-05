class_name BoardFit
extends RefCounted
## Where the scoreboard's ticket stands while a finger holds the players' column (#1287). The
## ticket is centred over the night, which on a phone is under the right thumb's buttons at the
## smaller interface sizes, and the busiest night (eight people and their bots) is as tall as the
## page. So it stays where it is while nothing of a finger is under it, moves along the screen
## between the buttons and the column of the two sides its rows reach when something is, moves up
## or down the screen to where a button no longer stands at its rows (Ping, under Pause, is such a
## button beside a tall ticket), and shrinks a step at a time, no further than `SMALLEST`, until it
## fits. At each size the place nearest the middle that fits is the one it takes.
## Pure geometry, no nodes: `Hud` gives it the room, the ticket's own size and the boxes to keep
## off.

## Air kept between the ticket and a button or a place, canvas units (the ring's own gap is 42).
const GAP := 24.0
## The least share of its own size the ticket is shrunk to, and each step of the search.
const SMALLEST := 0.5
const STEP := 0.05
## Slack added to a place that is exactly a `GAP` from a box, so that a rounding cannot put it back.
const EDGE := 0.5


## `{scale, shift, drop}`: the ticket's share of its own size, how far along the screen (canvas
## units, to the right) and how far down it is moved from the middle of `room`, so that no box of
## `avoid` is within `GAP` of it and it is inside `room`. `avoid` are the buttons, the weapon places
## and the column in the same units as `room`. At the largest share that has a place, the place
## nearest the middle. When nothing fits, the smallest step, as far along as it can go.
static func fit(room: Rect2, size: Vector2, avoid: Array[Rect2]) -> Dictionary:
	var found := {&"scale": 1.0, &"shift": 0.0, &"drop": 0.0}
	var share := 1.0
	while share >= SMALLEST - 0.001:
		var shown := size * share
		found = {&"scale": share, &"shift": 0.0, &"drop": 0.0}
		if shown.y <= room.size.y:
			var nearest := true
			for top in _tops(room, shown, avoid):
				var limits := _limits(top, shown, room, avoid)
				var here := {
					&"scale": share,
					&"shift": _shift(room, shown, limits),
					&"drop": top - (room.get_center().y - shown.y * 0.5),
				}
				if nearest:
					found = here
					nearest = false
				if limits.y - limits.x - shown.x >= 0.0:
					return here
		share -= STEP
	return found


## The tops a ticket `shown` big can stand at, nearest the middle first: the middle, then just
## below and just above each box of `avoid`, and the room's own top and bottom, all inside `room`.
static func _tops(room: Rect2, shown: Vector2, avoid: Array[Rect2]) -> Array[float]:
	var lowest := room.position.y
	var highest := room.end.y - shown.y
	var middle := room.get_center().y - shown.y * 0.5
	var tops: Array[float] = [clampf(middle, lowest, highest)]
	for place in [lowest, highest]:
		tops.append(place)
	for box in avoid:
		tops.append(box.end.y + GAP + EDGE)
		tops.append(box.position.y - GAP - EDGE - shown.y)
	var inside: Array[float] = []
	for top in tops:
		if top >= lowest - 0.001 and top <= highest + 0.001 and not inside.has(top):
			inside.append(top)
	inside.sort_custom(func(a: float, b: float) -> bool: return absf(a - middle) < absf(b - middle))
	return inside


## The left and right edge (x, y of the result) of the strip across `room` that a ticket `shown`
## big, its top at `top`, has to itself: bounded by the boxes at its height, those left of the
## middle on the left and the others on the right.
static func _limits(top: float, shown: Vector2, room: Rect2, avoid: Array[Rect2]) -> Vector2:
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
