class_name TouchDoubleTap
extends RefCounted
## Two quick taps on free ground press `swap_shoulder` (#1288): the camera changes shoulder. The
## verb is a fight verb but a rare one (a corner, a wall), so it has no button on the glass.
##
## A tap is a touch that lifts in under `TAP_SECONDS` and never moved `slop` or more from where it
## landed (`TouchSlop`, 10 CSS pixels, so it is the same thumb on every phone); the second lands
## within `GAP_SECONDS` of the first one's lift. Times are real seconds, handed in by the caller.
## Two taps in a row are never a look, so the first adds no delay to anything: the layer only holds
## back a touch's look while it can still be a tap, and lets the whole of it out the moment it is
## not (`TouchControls`). Any other touch (a button, the stick, a HUD place) and any look drag
## ends the chain, so "two in a row" means two in a row.
##
## It knows nothing of nodes: `TouchControls` tells it each touch of free ground, so a test can
## step it with a clock of its own.

## The action pressed, held at least `TouchTuning.min_hold` like any button's.
const ACTION := &"swap_shoulder"
## A touch that lasts this long or longer is a look or a rest, not a tap.
const TAP_SECONDS := 0.25
## Longest wait from the first tap's lift to the second one's landing.
const GAP_SECONDS := 0.35

## When the first tap lifted, or -INF when none is waiting for a second.
var _lifted_at := -INF
## By finger: {at, from}, a touch that is still a tap so far.
var _fingers := {}


## A finger landed on free ground at `point`.
func press(index: int, point: Vector2, now: float) -> void:
	_fingers[index] = {&"at": now, &"from": point, &"follows": now - _lifted_at <= GAP_SECONDS}


## Whether the finger `index` is still a tap at `point` and `now`: under `TAP_SECONDS` since it
## landed and under `slop` (canvas units) from where it landed. Once it is not, the touch is a look
## and the chain is over (`drop`).
func is_tap(index: int, point: Vector2, now: float, slop: float) -> bool:
	if not _fingers.has(index):
		return false
	var finger: Dictionary = _fingers[index]
	return now - float(finger[&"at"]) < TAP_SECONDS and point.distance_to(finger[&"from"]) < slop


## The finger `index` is a look, not a tap: it ends the chain.
func drop(index: int) -> void:
	_fingers.erase(index)
	interrupt()


## The finger `index` lifted. True when this tap is the second of a double tap.
func release(index: int, now: float) -> bool:
	if not _fingers.has(index):
		return false
	var finger: Dictionary = _fingers[index]
	_fingers.erase(index)
	if now - float(finger[&"at"]) >= TAP_SECONDS:
		interrupt()
		return false
	if finger[&"follows"]:
		interrupt()
		return true
	_lifted_at = now
	return false


## Something else was touched (a button, the stick, a HUD place) or looked: a tap that waits for its
## second is forgotten.
func interrupt() -> void:
	_lifted_at = -INF


## Every finger lifted at once (the layer went down): nothing waits.
func reset() -> void:
	_fingers.clear()
	interrupt()


## True while a first tap waits for its second (a test reads it).
func is_waiting() -> bool:
	return _lifted_at > -INF
