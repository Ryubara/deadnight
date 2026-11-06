class_name ChallengeFit
extends RefCounted
## Where the challenge prompt's card stands (#1299). It stands on the left edge at its usual
## height; where something is in the way (the players' column grown up to meet it, eight players
## and the strip a fingertip high under them on a phone) it takes the nearest free place at the
## same width or a narrower one: beside the column, its words wrapping onto another line, as high
## or as low as the free ground allows. Pure geometry, no nodes: `Hud` gives it the room, the
## usual place and the boxes to keep off.

## How far the search moves the card from its usual height at a time, canvas units.
const STEP := 8.0


## The card's rectangle in `room`'s units. `top` is its usual height; `lefts` the x's it may start
## at, the usual one first (the column's right edge is another); `widths` the widths it may have,
## widest first; `height_at` (a width, the card's height at it). `hard` are the boxes it never
## stands over (the cards that stay up, the buttons, the middle of the screen) and `soft` those
## that come and go (a feed's rows, the banner, a card of the lane, the gains), each already given
## the air it needs. The first place that is inside `room` and clear of every box, nearest to `top`
## (a place below before the one the same distance above), the widest, the furthest left; when
## there is none, the first clear of the hard boxes alone; when there is none, the usual place at
## the widest width.
static func place(
	room: Rect2,
	top: float,
	lefts: Array[float],
	widths: Array[float],
	height_at: Callable,
	hard: Array[Rect2],
	soft: Array[Rect2]
) -> Rect2:
	var heights: Array[float] = []
	for width in widths:
		heights.append(float(height_at.call(width)))
	var both := hard + soft
	for avoid in [both, hard]:
		var found := _search(room, top, lefts, widths, heights, avoid)
		if found.size != Vector2.ZERO:
			return found
	return Rect2(lefts[0], top, widths[0], heights[0])


static func _search(
	room: Rect2,
	top: float,
	lefts: Array[float],
	widths: Array[float],
	heights: Array[float],
	avoid: Array[Rect2]
) -> Rect2:
	var steps := int(ceilf(room.size.y / STEP))
	for step in steps + 1:
		for direction in [1.0, -1.0]:
			if step == 0 and direction < 0.0:
				continue
			var y: float = top + direction * float(step) * STEP
			for left in lefts:
				for i in widths.size():
					var rect := Rect2(left, y, widths[i], heights[i])
					if room.encloses(rect) and not hits(rect, avoid):
						return rect
	return Rect2()


## Whether `rect` meets any of `boxes`.
static func hits(rect: Rect2, boxes: Array[Rect2]) -> bool:
	for box in boxes:
		if rect.intersects(box):
			return true
	return false
