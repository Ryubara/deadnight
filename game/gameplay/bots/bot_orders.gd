class_name BotOrders
extends RefCounted
## The standing orders of a team's bots (`docs/research/bots.md#orders-follow-roam-and-hold-641`).
## A person gives one with the command wheel (or any other control) through `issue`; the server
## keeps the order, tells everyone (`bot_order_set`) and puts it in every frame (`bot_orders`),
## and each bot reads it from the frame like any other client reads the night. Plain data, no
## clock of its own beyond the `delta` that `step` is given.
##
## - `ROAM` (the default): the bot does its own thing, and comes to a person only for a revive or a
##   ping;
## - `FOLLOW`: the bot sticks with the person who gave the order;
## - `HOLD`: the bot stays at the spot the order was given and fights from there, leaving only to
##   revive.
##
## There is one order for the team's bots. An order given to one bot (`bot_id`) beats the team's for
## that bot until the next team order. The same class serves both ends: on a client, `sender` is set
## (the link's `send`) and `issue` puts one command on the wire; on the server `sender` is not set
## and `issue` keeps the order and answers with the event to send.

const FOLLOW := &"follow"
const ROAM := &"roam"
const HOLD := &"hold"
## The orders in wire order (`NetWire.order` sends the index).
const ORDERS: Array[StringName] = [FOLLOW, ROAM, HOLD]
const DEFAULT := ROAM

## The action a client sends and the events and the frame key the server answers with. (A bot never
## names the night server, so the server's own constant is this one.)
const ACTION := &"order"
const EVENT_SET := &"bot_order_set"
const EVENT_REFUSED := &"bot_order_refused"
const FRAME_KEY := "bot_orders"

## Why an order was refused.
const REASON_UNKNOWN := &"unknown"
const REASON_TOO_SOON := &"too_soon"
const REASON_DOWN := &"down"
const REASON_NO_SEAT := &"no_seat"
const REASON_BAD_POSITION := &"bad_position"

## Seconds before the same person may give another order (a held key is not a flood).
const GAP := 0.5

## Where a client sends the command: `Callable(action: Dictionary)`. Unset on the server.
var sender := Callable()

var _team: Dictionary = {}
var _bots: Dictionary = {}
var _wait: Dictionary = {}


## True for one of the three orders.
static func is_order(order: StringName) -> bool:
	return ORDERS.has(order)


## The command that gives `order` (`bot_id` 0 for the team's bots) as plain data: what `issue`
## sends.
static func command(order: StringName, at: Vector3, bot_id := 0) -> Dictionary:
	return {"type": ACTION, "order": order, "at": at, "bot_id": bot_id}


## The order in force for `bot_id` (0 for the team's) in `frame`: `{order, issuer_id, at}`. Always
## an answer: before any order was given it is `ROAM`, from nobody, at nowhere.
static func current(frame: Dictionary, bot_id := 0) -> Dictionary:
	var block: Dictionary = frame.get(FRAME_KEY, {})
	var one: Dictionary = (block.get("bots", {}) as Dictionary).get(bot_id, {})
	if bot_id != 0 and not one.is_empty():
		return one
	var team: Dictionary = block.get("team", {})
	if not team.is_empty():
		return team
	return {"order": DEFAULT, "issuer_id": 0, "at": Vector3.INF}


## Gives the order, as `issuer_id` standing at `at`, to the team's bots or (with `bot_id`) to one.
## On a client: sends the command and returns it (`{}`, nothing sent, for an order that cannot be).
## On the server: keeps it and returns the `bot_order_set` event (or a `bot_order_refused` one).
func issue(order: StringName, issuer_id: int, at: Vector3, bot_id := 0) -> Dictionary:
	if not is_order(order):
		return {} if sender.is_valid() else _refused(issuer_id, order, REASON_UNKNOWN)
	if not at.is_finite():
		return {} if sender.is_valid() else _refused(issuer_id, order, REASON_BAD_POSITION)
	if sender.is_valid():
		var action := command(order, at, bot_id)
		sender.call(action)
		return action
	if _wait.get(issuer_id, 0.0) > 0.0:
		return _refused(issuer_id, order, REASON_TOO_SOON)
	_wait[issuer_id] = GAP
	var kept := {"order": order, "issuer_id": issuer_id, "at": at}
	if bot_id == 0:
		_team = kept
		# The team's order is the newest: a bot's own earlier word is over.
		_bots.clear()
	else:
		_bots[bot_id] = kept
	return {"type": EVENT_SET, "order": order, "issuer_id": issuer_id, "at": at, "bot_id": bot_id}


## Time passes (the server's step): a person may give another order after `GAP`.
func step(delta: float) -> void:
	for issuer_id in _wait.keys():
		_wait[issuer_id] = maxf(float(_wait[issuer_id]) - delta, 0.0)


## The refusal event of an order that cannot be given (`player_id` is who asked).
func refused(player_id: int, order: StringName, reason: StringName) -> Dictionary:
	return _refused(player_id, order, reason)


## A bot's seat was left: its own order goes with it.
func forget_bot(bot_id: int) -> void:
	_bots.erase(bot_id)


## A person's seat was left: what they were waiting for goes (the bots notice that their follow is
## gone from the frame and roam; a hold stays).
func forget_issuer(issuer_id: int) -> void:
	_wait.erase(issuer_id)


## The orders for the frame: `{team: {order, issuer_id, at}, bots: {bot id: {...}}}`, either empty.
func to_frame() -> Dictionary:
	return {"team": _team.duplicate(), "bots": _bots.duplicate(true)}


## The order in force for `bot_id` on the server (the same answer a bot reads from the frame).
func order_for(bot_id := 0) -> Dictionary:
	return current({FRAME_KEY: to_frame()}, bot_id)


func _refused(player_id: int, order: StringName, reason: StringName) -> Dictionary:
	return {"type": EVENT_REFUSED, "player_id": player_id, "order": order, "reason": reason}
