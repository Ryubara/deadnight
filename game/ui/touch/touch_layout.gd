class_name TouchLayout
extends RefCounted
## Where each touch control sits. Pure geometry, no nodes: give it the safe rectangle of the canvas
## (canvas units) and the player's touch scale and it answers a circle per button.
##
## Buttons are placed by their offset from the safe rectangle's bottom right corner, where the
## right thumb rests. The right thumb does Fire, Aim, Jump, Reload and Crouch (#1277), so those five
## are one ring round Fire (`RING_GAP` of air between the rims): the thumb that rests on Fire rolls
## to a neighbour without leaving the screen's corner, and Reload is the one on Fire's left, in the
## same row. Interact, which shows only at something to use, sits one thumb-length out, up and left
## of Reload and no farther from the edge than the buttons that wait for a home: the world markers
## need the column between the HUD's cards and the buttons (#1230). A left-handed layout
## (`mirrored`) is the same layout flipped left to right: offsets from the bottom left corner, the
## stick on the right.
## The HUD's ammo card (bottom right) and prompt card (bottom centre) are kept clear;
## `test_touch_layout` checks that against the busiest HUD.
## Sizes are in canvas units: about 8 to 9 mm on a phone (the canvas is 1080 units high on a screen
## that is 60 to 70 mm high), and no hit area is smaller than `MIN_HIT` radius.

const FIRE := &"fire"
const AIM := &"aim"
const JUMP := &"jump"
const RELOAD := &"reload"
## Crouch (#1277): the simulation acts on `crouch` held; on a phone a tap toggles it, so the right
## thumb is free for Fire and the look again (`TouchControls`).
const CROUCH := &"crouch"
const INTERACT := &"interact"
const PAUSE := &"pause"
const SCOREBOARD := &"scoreboard"
const SHOULDER := &"swap_shoulder"
## Strike (#411, #588, #1285): the quick melee, a blow with whatever is in hand; the button presses
## its action. Like Interact it shows only while it applies, here a dead within reach of the blow
## (`TouchControls.strike_ready`), so it costs the glass nothing the rest of the time. It stands
## where Swap stood, beside Reload.
const STRIKE := &"quick_melee"
## The ping (#642): marks what the crosshair is on for the team; the button presses `ping`. It sits
## on the top edge beside Pause, where the other thumb reaches it between fights; the right thumb's
## corner is full.
const PING := &"ping"
## The bot command wheel (#642): held, it opens the wheel, and the thumb's drag picks an order; the
## button presses `bot_wheel`. It sits on the far right edge, above the ammo card and clear of
## Reload, so it is on screen on a phone's 540 unit high canvas too.
const BOT_WHEEL := &"bot_wheel"

## The centre of Fire, from the bottom right corner (left, up): the thumb's resting place, and the
## middle of the ring the other four buttons of the right thumb stand on.
const FIRE_OFFSET := Vector2(205.0, 350.0)
const FIRE_RADIUS := 100.0
## Air between the rims of Fire and its neighbours: 2 to 3 mm on a phone, a thumb's own width of
## room (`docs/research/mobile-controls.md`, "The right side").
const RING_GAP := 42.0

## Offset from the bottom right corner (left, up) and radius, by button. The order is the order a
## touch tests them in: the contextual button first, so it wins where it overlaps. The ring's
## buttons stand `FIRE_RADIUS + radius + RING_GAP` from Fire's centre, Crouch at 40 degrees below
## straight left, Reload at 8 above it (the same row), Aim at 56 and Jump at 104 (nearly straight
## up); `test_touch_layout` checks the air. Strike stands beside Reload, a thumb's roll out along
## the row from Fire, with the 30 units of air Interact's place needs. Shoulder and the Bots keep
## their old places until the homes the audit names are built (#1275). The weapons and the
## grenades are the HUD's own places, not buttons of this layer (#1280).
const BUTTONS := [
	[INTERACT, Vector2(540.0, 500.0), 80.0],
	[STRIKE, Vector2(575.0, 340.0), 52.0],
	[FIRE, FIRE_OFFSET, FIRE_RADIUS],
	[RELOAD, Vector2(411.0, 379.0), 66.0],
	[AIM, Vector2(325.0, 527.0), 72.0],
	[JUMP, Vector2(154.0, 556.0), 70.0],
	[CROUCH, Vector2(361.0, 219.0), 62.0],
	[SHOULDER, Vector2(545.0, 672.0), 48.0],
	[BOT_WHEEL, Vector2(60.0, 405.0), 40.0],
]
## The buttons whose finger does not look while it drags: the wheel's drag picks an order. Every
## other button of `BUTTONS` is a right button (#1277): a finger on it also turns the view.
const DRAG_OWNERS: Array[StringName] = [BOT_WHEEL]
## Pause sits on the top edge, right of the HUD's left column.
const PAUSE_OFFSET := Vector2(442.0, 80.0)
const PAUSE_RADIUS := 36.0
## The ping button stands under Pause (#1289), in the same column, so the one finger that
## reaches the top edge has Pause above and Ping below with a thumb's room between them. How far
## below is a length on the glass, not in units (`ping_drop`): at least `PING_CENTRES_CSS` CSS
## pixels (9 mm and a little) from Pause's centre, and the hit areas never touch. `PING_DROP` is
## the answer where no fingertip is known (a desktop, a test): 54 CSS px at 0.36 CSS px a unit.
const PING_RADIUS := 36.0
const PING_DROP := 150.0
const PING_CENTRES_CSS := 56.0
## The air kept between Pause's hit area and Ping's, as a share of a fingertip (6 of 44 CSS px).
const PING_HIT_GAP := 6.0 / MenuScale.TAP_PIXELS
## The scoreboard button is held to show the board (it presses the `scoreboard` action while a
## finger is on it). It sits right of Pause, a `ping_drop` away, until the players' column holds the
## board (#1287) and takes the button away: Ping owns the place under Pause.
const SCOREBOARD_RADIUS := 34.0
## The floating stick: its resting place (a faint ring, above the HUD's players column and the
## weapon strip under it), its radius and where it may start.
const STICK_REST := Vector2(330.0, 390.0)
const STICK_RADIUS := 105.0
const STICK_ZONE_WIDTH := 0.45
const STICK_ZONE_TOP := 0.2
## A finger's hit area reaches this far past the drawn button, and is never smaller than MIN_HIT.
## On a touch screen it is never smaller than a fingertip either (`finger`, below).
const HIT_PAD := 24.0
const MIN_HIT := 66.0


## The circles: button id -> {centre, radius, hit, was}. `mirrored` flips it for a left hand.
## `finger` is the least width of a hit area in canvas units (`MenuScale.tap_units`: 44 CSS pixels,
## which is 153 units at an interface size of 0.8 and 122 at 1.0); 0 leaves the areas as they were.
## `was` is the hit area before `finger` (see `button_at`).
static func buttons(
	safe: Rect2, touch_scale: float, mirrored := false, finger := 0.0
) -> Dictionary:
	var found := {}
	for row in BUTTONS:
		var radius: float = row[2] * touch_scale
		var offset: Vector2 = row[1]
		var up := safe.end.y - offset.y * touch_scale
		var across := (
			safe.position.x + offset.x * touch_scale
			if mirrored
			else safe.end.x - offset.x * touch_scale
		)
		found[row[0]] = _circle(Vector2(across, up), radius, finger)
	var pause_radius := PAUSE_RADIUS * touch_scale
	var pause_x := safe.end.x - PAUSE_OFFSET.x if mirrored else safe.position.x + PAUSE_OFFSET.x
	found[PAUSE] = _circle(Vector2(pause_x, safe.position.y + PAUSE_OFFSET.y), pause_radius, finger)
	var drop := ping_drop(touch_scale, finger)
	found[PING] = _circle(
		Vector2(pause_x, safe.position.y + PAUSE_OFFSET.y + drop), PING_RADIUS * touch_scale, finger
	)
	var board_x := pause_x - drop if mirrored else pause_x + drop
	found[SCOREBOARD] = _circle(
		Vector2(board_x, safe.position.y + PAUSE_OFFSET.y), SCOREBOARD_RADIUS * touch_scale, finger
	)
	return found


## How far below Pause's centre Ping's centre stands, canvas units: the most of `PING_CENTRES_CSS`
## CSS pixels (a fingertip is `finger` units for `MenuScale.TAP_PIXELS` of them), Pause's and
## Ping's hit areas with `PING_HIT_GAP` of a fingertip between them, and `PING_DROP` where no
## fingertip is known.
static func ping_drop(touch_scale: float, finger := 0.0) -> float:
	var pause_hit := _hit(PAUSE_RADIUS * touch_scale, finger)
	var ping_hit := _hit(PING_RADIUS * touch_scale, finger)
	return maxf(
		PING_DROP,
		maxf(
			finger * PING_CENTRES_CSS / MenuScale.TAP_PIXELS,
			pause_hit + ping_hit + finger * PING_HIT_GAP
		)
	)


## Where a finger may land to start the move stick, and the side it is on (the left for a right
## hand, the right for a left hand). It starts below `below` (a y of the canvas) when that is
## lower than its own top: the touch layer gives the bottom of Ping's hit area, so a thumb that
## starts the stick never lands on the button above it (#1289).
static func stick_zone(safe: Rect2, mirrored := false, below := -INF) -> Rect2:
	var top := maxf(safe.size.y * STICK_ZONE_TOP, below - safe.position.y)
	var width := safe.size.x * STICK_ZONE_WIDTH
	var left := safe.end.x - width if mirrored else safe.position.x
	return Rect2(Vector2(left, safe.position.y + top), Vector2(width, safe.size.y - top))


static func _circle(centre: Vector2, radius: float, finger: float) -> Dictionary:
	var was := maxf(radius + HIT_PAD, MIN_HIT)
	return {&"centre": centre, &"radius": radius, &"hit": _hit(radius, finger), &"was": was}


## The radius of a hit area: the drawn button and a pad round it, at least `MIN_HIT`, and a
## fingertip's half when `finger` is known.
static func _hit(radius: float, finger: float) -> float:
	return maxf(maxf(radius + HIT_PAD, MIN_HIT), finger * 0.5)


static func stick_rest(safe: Rect2, touch_scale: float, mirrored := false) -> Vector2:
	var corner := Vector2(safe.end.x if mirrored else safe.position.x, safe.end.y)
	return corner + Vector2(-1.0 if mirrored else 1.0, -1.0) * STICK_REST * touch_scale


## The button under `point`, or "" (`skip` lists hidden ones). Who wins a touch where hit areas
## overlap is decided in two steps (#1217):
## 1. The area a button had before `finger` (`was`): the first in `BUTTONS` order wins (Pause, Ping,
##    Scoreboard, then the table's order, the contextual Interact first), exactly as it always did.
##    A touch that pressed a button before presses the same button now.
## 2. The margin `finger` added, which no button owned: the nearest centre wins (a tie goes to the
##    first in order). Growing a button never takes a touch from its neighbour.
static func button_at(point: Vector2, circles: Dictionary, skip: Array = []) -> StringName:
	var order := _order()
	for id: StringName in order:
		if id in skip:
			continue
		var circle: Dictionary = circles[id]
		if point.distance_to(circle[&"centre"]) <= float(circle.get(&"was", circle[&"hit"])):
			return id
	var nearest := &""
	var nearest_gap := INF
	for id: StringName in order:
		if id in skip:
			continue
		var circle: Dictionary = circles[id]
		var gap := point.distance_to(circle[&"centre"])
		if gap <= float(circle[&"hit"]) and gap < nearest_gap:
			nearest = id
			nearest_gap = gap
	return nearest


## Whether a finger that starts on `id` also looks while it drags: every button of the right thumb
## does, so a thumb that has pressed Reload, Jump or Crouch turns the view for the rest of the drag.
static func looks_when_dragged(id: StringName) -> bool:
	if id in DRAG_OWNERS:
		return false
	for row in BUTTONS:
		if row[0] == id:
			return true
	return false


static func _order() -> Array:
	var order: Array = [PAUSE, PING, SCOREBOARD]
	for row in BUTTONS:
		order.append(row[0])
	return order


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
