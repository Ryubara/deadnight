class_name BotOrderLink
extends RefCounted
## The one place the wheel meets `BotOrders` (#641): it gives an order for the person and reads the
## order that stands. A seam so the wheel can be proved with a stub: tests set `issuer` and
## `reader`, and the night's wiring (`for_night`) points them at `night.bot_orders`.

## (order: StringName, issuer_id: int, at: Vector3) -> Dictionary: the command sent, `{}` when the
## order was refused before it left (an unknown order, a position that is not finite).
var issuer := Callable()
## (frame: Dictionary) -> StringName: the standing order of the team in a frame of the night, ""
## when the night cannot say (the wheel then keeps the order it gave last).
var reader := Callable()


## The link of a night: orders go through `night.bot_orders.issue`, and the standing order is read
## from the frame by `BotOrders.current`.
static func for_night(night: Node) -> BotOrderLink:
	var link := BotOrderLink.new()
	link.issuer = func(order: StringName, issuer_id: int, at: Vector3) -> Dictionary:
		var orders: Object = night.get(&"bot_orders")
		if orders == null:
			return {}
		return orders.call(&"issue", order, issuer_id, at)
	link.reader = func(frame: Dictionary) -> StringName:
		var script: Script = _orders_script()
		if script == null:
			return &""
		var answer: Dictionary = script.call(&"current", frame)
		return answer.get(&"order", &"")
	return link


## Gives `order` for the person `issuer_id`, standing at `at`. Returns what was sent ({} when
## nothing was).
func issue(order: StringName, issuer_id: int, at: Vector3) -> Dictionary:
	if not issuer.is_valid():
		return {}
	return issuer.call(order, issuer_id, at)


## The standing order in `frame`, or "".
func current(frame: Dictionary) -> StringName:
	if not reader.is_valid() or frame.is_empty():
		return &""
	return reader.call(frame)


static func _orders_script() -> Script:
	var path := "res://gameplay/bots/bot_orders.gd"
	return load(path) as Script if ResourceLoader.exists(path) else null
