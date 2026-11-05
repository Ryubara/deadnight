class_name BotWheel
extends RefCounted
## The bot command wheel as plain data: what is held, where the pointer is and which order it is on.
## Holding the wheel's key or button starts it; after `OPEN_AFTER` seconds it is open
## (a tap never is); the pointer (a mouse's motion, the right stick) picks one of
## three orders by direction; letting go on an order gives it, letting go in the middle or before it
## opened gives nothing. No nodes, no clock of its own: the driver calls `advance`, so a test steps
## it by hand (`BotWheelDriver` feeds it, `HudBotWheel` draws it).

const FOLLOW := &"follow"
const ROAM := &"roam"
const HOLD := &"hold"
## The orders, in the order they stand round the wheel, clockwise from the top.
const ORDERS: Array[StringName] = [FOLLOW, ROAM, HOLD]
## What the wheel and the HUD call each order, and a line under the name.
const NAMES := {FOLLOW: "FOLLOW", ROAM: "ROAM", HOLD: "HOLD"}
const CAPTIONS := {FOLLOW: "STICK WITH ME", ROAM: "FAN OUT", HOLD: "STAY HERE"}
## What the HUD says briefly after the order changed: the state the bots are in, never a line that
## reads as an order to the player ("HOLD HERE" at the top right, #1275).
const NOTICES := {
	FOLLOW: "BOTS: FOLLOWING YOU",
	ROAM: "BOTS: ROAMING",
	HOLD: "BOTS: HOLDING POSITION",
}
## The standing order of a team that was never told one (`BotOrders`'s default).
const DEFAULT_ORDER := ROAM

## Seconds the wheel must be held before it opens: a tap on its key does nothing.
const OPEN_AFTER := 0.18
## The pointer is in the middle (no order) under this share of the wheel's reach.
const CENTRE := 0.3
## Mouse motion (canvas units) that takes the pointer from the middle to the rim.
const MOUSE_REACH := 120.0
## Seconds the wheel takes to grow open, for the drawing.
const GROW_SECONDS := 0.12

## The order that stands now (what the wheel marks, what the HUD said last).
var current: StringName = DEFAULT_ORDER
## The pointer: inside the unit disc, x right and y down, 0 in the middle.
var pointer := Vector2.ZERO
## Seconds held, from the press.
var held_for := 0.0
## 0 closed to 1 fully grown, for the drawing.
var growth := 0.0

var _holding := false
var _opened := false


## The order the pointer is on: the entry whose direction it points to, or "" in the middle.
static func entry_at(at: Vector2) -> StringName:
	if at.length() < CENTRE:
		return &""
	# Clockwise from straight up.
	var angle := fposmod(atan2(at.x, -at.y), TAU)
	var sector := TAU / float(ORDERS.size())
	return ORDERS[int(roundf(angle / sector)) % ORDERS.size()]


## The order after `order` in the wheel's round (Follow, Roam, Hold, Follow...): what a tap on the
## touch screen's tag gives. An unknown order is followed by the first.
static func next_after(order: StringName) -> StringName:
	return ORDERS[(ORDERS.find(order) + 1) % ORDERS.size()]


## The direction (unit, x right and y down) the entry stands in.
static func direction_of(order: StringName) -> Vector2:
	var angle := TAU / float(ORDERS.size()) * float(ORDERS.find(order))
	return Vector2(sin(angle), -cos(angle))


## The wheel's key or button went down.
func press() -> void:
	_holding = true
	_opened = false
	held_for = 0.0
	pointer = Vector2.ZERO


## True from the press to the release or the cancel.
func is_holding() -> bool:
	return _holding


## True once it has been held long enough to show and to give an order.
func is_open() -> bool:
	return _holding and _opened


## Time passes while held; it opens when `OPEN_AFTER` is over. `growth` follows, shrinking again
## once it is let go.
func advance(delta: float) -> void:
	if _holding:
		held_for += delta
		if not _opened and held_for >= OPEN_AFTER:
			_opened = true
	var rate := delta / GROW_SECONDS
	growth = clampf(growth + (rate if is_open() else -rate), 0.0, 1.0)


## A mouse moved (canvas units): the pointer goes with it, up to the rim.
func move_by(relative: Vector2) -> void:
	if _holding:
		pointer = (pointer + relative / MOUSE_REACH).limit_length(1.0)


## The pointer is where a stick or a finger puts it (inside the unit disc).
func point_at(at: Vector2) -> void:
	if _holding:
		pointer = at.limit_length(1.0)


## The order under the pointer; "" while closed or in the middle.
func hovered() -> StringName:
	return entry_at(pointer) if is_open() else &""


## The wheel was let go: the order it was on, or "" for a tap, the middle or a cancel. The standing
## order becomes the one given.
func release() -> StringName:
	var order := hovered()
	cancel()
	if order != &"":
		current = order
	return order


## Drops the hold with no order (the night paused, the controls went off).
func cancel() -> void:
	_holding = false
	_opened = false
	pointer = Vector2.ZERO
	held_for = 0.0
