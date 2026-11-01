class_name AutopilotFuel
extends RefCounted
## When the bot buys fuel. It sees what a client sees: the frame's tank, round and doors open, its
## points, and the prompt at a spot. The rule is the one a player would use: when the tank has
## fallen to the low line and it can pay for a can, it walks to the nearest fuel spot whose area is
## open and buys, and it keeps buying until the tank is back above `fill_to` (a can adds 25 units,
## so a tank at the low line takes one) or it can pay no more. `AutopilotSwitches` puts circuits
## out at the same line; this is the other half of the same care for the generator.

## Fractions of a full tank: at or below `refuel_at` it goes to buy; it stops above `fill_to`.
var refuel_at := 0.25
var fill_to := 0.4
## Units in a full tank.
var capacity := 100.0
## The fuel item it buys (a `ShopItem` of kind FUEL), for the price at a round.
var item: ShopItem
## Where to stand to buy at each spot, and the shop door of the area it is in.
var goals: Dictionary[StringName, Vector3] = {}
var doors: Dictionary[StringName, StringName] = {}

var _buying := false


## What a can costs now, in points (the full price: the bot goes when the tank has room for a
## whole can).
func price(frame: Dictionary) -> int:
	return item.price_at(int(frame.get("round", 1))) if item != null else 1 << 30


## Whether the bot wants a can now: the tank is low (or it is already filling up) and the bot can
## pay for one.
func wants(frame: Dictionary, points: int) -> bool:
	var fraction: float = frame.get("fuel", capacity) / capacity
	if fraction <= refuel_at:
		_buying = true
	elif fraction > fill_to:
		_buying = false
	return _buying and points >= price(frame)


## Whether to press `use` at the spot the frame's `prompt` shows: wanted, and the tank has room.
func wants_use(prompt: Dictionary, frame: Dictionary, points: int) -> bool:
	return (
		prompt.get("kind", &"") == &"fuel"
		and float(prompt.get("units", 0.0)) > 0.0
		and wants(frame, points)
	)


## The standing place of the nearest spot worth a trip from `here`, or `Vector3.INF` for none.
func next_goal(frame: Dictionary, here: Vector3, points: int) -> Vector3:
	if not wants(frame, points):
		return Vector3.INF
	var best := Vector3.INF
	var best_distance := INF
	for id in goals:
		var door: StringName = doors.get(id, &"")
		if door != &"" and not frame.get("doors", []).has(door):
			continue
		var distance := Vector2(here.x - goals[id].x, here.z - goals[id].z).length()
		if distance < best_distance:
			best_distance = distance
			best = goals[id]
	return best
