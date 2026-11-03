class_name OrderJudge
extends RefCounted
## Decides whether a person's order to the bots is taken (`BotOrders` keeps it): only a seated
## person who is up may give one, it must be an order that exists, and not twice in half a second.
## The place is the one the person named when it is within ping reach of them, else where they
## stand, put on the walking mesh so a hold is a spot a bot can reach. Everyone hears the answer
## (`bot_order_set`, or `bot_order_refused` with the reason). The answer here is `&""` when the
## order was taken, else why not.

## Set by the server, and again when a test swaps its tuning.
var tuning: NightTuning

var _orders: BotOrders
var _rules: GameRules
var _world: NightWorld
## Player id to body, the server's own dictionary.
var _bodies: Dictionary
var _announce: Callable


func _init(
	p_tuning: NightTuning,
	p_orders: BotOrders,
	p_rules: GameRules,
	p_world: NightWorld,
	p_bodies: Dictionary,
	p_announce: Callable
) -> void:
	tuning = p_tuning
	_orders = p_orders
	_rules = p_rules
	_world = p_world
	_bodies = p_bodies
	_announce = p_announce


## `action` is `{order, at, bot_id}`; `player_id` is the connection it came in on.
func give(player_id: int, action: Dictionary) -> StringName:
	var order := StringName(action.get("order", &""))
	var body := _bodies.get(player_id) as Player
	var reason := &""
	if body == null:
		reason = BotOrders.REASON_NO_SEAT
	elif _is_down(player_id):
		reason = BotOrders.REASON_DOWN
	elif not BotOrders.is_order(order):
		reason = BotOrders.REASON_UNKNOWN
	if reason != &"":
		_announce.call(_orders.refused(player_id, order, reason))
		return reason
	var at := _place(body.global_position, action.get("at", body.global_position))
	var event := _orders.issue(order, player_id, at, int(action.get("bot_id", 0)))
	_announce.call(event)
	return StringName(event.get("reason", &""))


func _is_down(player_id: int) -> bool:
	var state: PlayerState = _rules.players.get(player_id)
	return state == null or state.downed


func _place(here: Vector3, named: Variant) -> Vector3:
	var at := here
	if typeof(named) == TYPE_VECTOR3:
		var point: Vector3 = named
		var apart := Vector2(point.x - here.x, point.z - here.z).length()
		if point.is_finite() and apart <= tuning.ping_range:
			at = point
	var map := _world.map()
	if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
		at = NavigationServer3D.map_get_closest_point(map, at)
	return at
