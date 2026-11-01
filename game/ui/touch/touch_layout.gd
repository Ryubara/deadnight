class_name TouchLayout
extends RefCounted
## Where each touch control sits. Pure geometry, no nodes: give it the safe rectangle of the canvas
## (canvas units) and the player's touch scale and it answers a circle per button.
##
## Buttons are placed by their offset from the safe rectangle's bottom right corner, where the
## right thumb rests, in an arc round Fire. The HUD's ammo card (bottom right) and prompt card
## (bottom centre) are kept clear; `test_touch_layout` checks that against the busiest HUD.
## Sizes are in canvas units: about 8 to 9 mm on a phone (the canvas is 1080 units high on a screen
## that is 60 to 70 mm high), and no hit area is smaller than `MIN_HIT` radius.

const FIRE := &"fire"
const AIM := &"aim"
const JUMP := &"jump"
const RELOAD := &"reload"
const SWAP := &"swap_weapon"
const GRENADE := &"throw_grenade"
const INTERACT := &"interact"
const PAUSE := &"pause"

## Offset from the bottom right corner (left, up) and radius, by button. The order is the order a
## touch tests them in: the contextual button first, so it wins where it overlaps.
const BUTTONS := [
	[INTERACT, Vector2(415.0, 350.0), 86.0],
	[FIRE, Vector2(205.0, 350.0), 100.0],
	[AIM, Vector2(320.0, 520.0), 70.0],
	[RELOAD, Vector2(115.0, 525.0), 62.0],
	[SWAP, Vector2(515.0, 475.0), 56.0],
	[JUMP, Vector2(360.0, 150.0), 70.0],
	[GRENADE, Vector2(520.0, 165.0), 56.0],
]
## Pause sits on the top edge, right of the HUD's left column.
const PAUSE_OFFSET := Vector2(442.0, 80.0)
const PAUSE_RADIUS := 36.0
## The floating stick: its resting place (a faint ring), its radius and where it may start.
const STICK_REST := Vector2(330.0, 330.0)
const STICK_RADIUS := 105.0
const STICK_ZONE_WIDTH := 0.45
const STICK_ZONE_TOP := 0.2
## A finger's hit area reaches this far past the drawn button, and is never smaller than MIN_HIT.
const HIT_PAD := 24.0
const MIN_HIT := 66.0


## The circles: button id -> {centre, radius, hit}.
static func buttons(safe: Rect2, touch_scale: float) -> Dictionary:
	var corner := safe.end
	var found := {}
	for row in BUTTONS:
		var radius: float = row[2] * touch_scale
		found[row[0]] = _circle(corner - (row[1] as Vector2) * touch_scale, radius)
	var pause_radius := PAUSE_RADIUS * touch_scale
	found[PAUSE] = _circle(
		Vector2(safe.position.x + PAUSE_OFFSET.x, safe.position.y + PAUSE_OFFSET.y), pause_radius
	)
	return found


static func _circle(centre: Vector2, radius: float) -> Dictionary:
	return {&"centre": centre, &"radius": radius, &"hit": maxf(radius + HIT_PAD, MIN_HIT)}


## Where a finger may land to start the move stick: the left of the screen below the top fifth.
static func stick_zone(safe: Rect2) -> Rect2:
	var top := safe.size.y * STICK_ZONE_TOP
	return Rect2(
		safe.position + Vector2(0.0, top),
		Vector2(safe.size.x * STICK_ZONE_WIDTH, safe.size.y - top)
	)


static func stick_rest(safe: Rect2, touch_scale: float) -> Vector2:
	return Vector2(safe.position.x, safe.end.y) + Vector2(1.0, -1.0) * STICK_REST * touch_scale


## The button under `point`, or "" (the first in `BUTTONS` order wins; `skip` lists hidden ones).
static func button_at(point: Vector2, circles: Dictionary, skip: Array = []) -> StringName:
	var order: Array = [PAUSE]
	for row in BUTTONS:
		order.append(row[0])
	for id: StringName in order:
		if id in skip:
			continue
		var circle: Dictionary = circles[id]
		if point.distance_to(circle[&"centre"]) <= float(circle[&"hit"]):
			return id
	return &""


## The safe rectangle of a canvas: the whole canvas less the insets (left, top, right, bottom).
static func safe_rect(canvas: Vector2, insets: Vector4) -> Rect2:
	var origin := Vector2(insets.x, insets.y)
	var end := canvas - Vector2(insets.z, insets.w)
	return Rect2(origin, (end - origin).max(Vector2.ONE))


## Insets in canvas units from the platform's safe rectangle in screen pixels (a notch, rounded
## corners, the home bar), the screen size in pixels and the canvas size.
static func insets_from(safe_px: Rect2i, screen_px: Vector2i, canvas: Vector2) -> Vector4:
	if screen_px.x <= 0 or screen_px.y <= 0 or safe_px.size == Vector2i.ZERO:
		return Vector4.ZERO
	var k := Vector2(canvas.x / screen_px.x, canvas.y / screen_px.y)
	return Vector4(
		maxf(safe_px.position.x * k.x, 0.0),
		maxf(safe_px.position.y * k.y, 0.0),
		maxf((screen_px.x - safe_px.end.x) * k.x, 0.0),
		maxf((screen_px.y - safe_px.end.y) * k.y, 0.0)
	)
