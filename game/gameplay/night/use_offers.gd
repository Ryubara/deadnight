class_name UseOffers
extends RefCounted
## What the use button would do in reach of a spot, for the offers that need only the world, the
## rules and the night's tuning (`NightServer.use_target` asks them among the shop spots): a door
## to buy, a breach to mend or a breaker post to switch, a fuel can. Each answers a dictionary
## (`kind`, `id` and what the card shows) or `{}`.

## Metres from the floor to the middle of a door's slab (2.4 m doors).
const DOOR_MIDDLE := 1.2


## The shut door in reach that can be bought now (the one before it is open), or `{}`.
static func door(
	world: NightWorld, rules: GameRules, tuning: NightTuning, here: Vector3, sight: UseSight = null
) -> Dictionary:
	for door_id in world.door_ids():
		if rules.is_door_open(door_id):
			continue
		var item := rules.tuning.economy.item(door_id)
		if item.requires != &"" and not rules.is_door_open(item.requires):
			continue
		if UseZones.door_reaches(world, tuning, sight, door_id, here):
			return {"kind": &"door", "id": door_id, "price": rules.price_of(door_id)}
	return {}


## A breach to put a board back across, or a breaker post, in reach of `here`, or `{}`. Of two
## breaches in reach, the one nearest the way `view` looks (flat, unit; zero: the nearest).
static func post(
	world: NightWorld,
	rules: GameRules,
	tuning: NightTuning,
	here: Vector3,
	sight: UseSight = null,
	view := Vector3.ZERO
) -> Dictionary:
	var best := {}
	var best_score := INF
	for id in world.barricade_ids():
		var boards := rules.barricades.boards_of(id)
		if boards >= rules.tuning.barricades.boards:
			continue
		var barricade := world.barricade(id)
		if not UseZones.breach_reaches(world, tuning, sight, barricade, here):
			continue
		var score := _score(here, barricade.centre(), view)
		if score < best_score:
			best_score = score
			best = {"kind": &"repair", "id": id, "boards": boards}
	if not best.is_empty():
		return best
	var post := world.switches.within_reach(here, tuning.use_reach, sight)
	if post == null:
		return {}
	var on: bool = rules.generator.circuits.get(post.circuit_id, false)
	return {"kind": &"circuit", "id": post.circuit_id, "on": on}


## Of the offers in reach (`[{offer, at}]`, `at` the thing's place), the one the player looks at:
## the smallest turn from `view` (flat, unit) to the thing; with no view, the first. `{}` for none.
static func faced(offers: Array[Dictionary], here: Vector3, view: Vector3) -> Dictionary:
	var best := {}
	var best_score := INF
	for entry in offers:
		var score := _score(here, entry["at"], view)
		if score < best_score:
			best_score = score
			best = entry["offer"]
	return best


## The turn (radians) from `view` to `there`, or the flat distance when there is no view.
static func _score(here: Vector3, there: Vector3, view: Vector3) -> float:
	var to := Vector3(there.x - here.x, 0.0, there.z - here.z)
	if view == Vector3.ZERO or to.length() < 0.01:
		return to.length() if view == Vector3.ZERO else 0.0
	return view.angle_to(to)


## The can stand within reach of `here`: what the rules would sell and for how much, or `{}`.
static func fuel(
	world: NightWorld, rules: GameRules, tuning: NightTuning, here: Vector3, sight: UseSight = null
) -> Dictionary:
	var spot := world.fuel.within_reach(here, tuning.fuel_reach, sight)
	if spot == &"":
		return {}
	var item := world.fuel.item_of(spot)
	var offer := rules.tuning.economy.item(item).fuel_offer(
		rules.round_number, rules.generator.space()
	)
	return {
		"kind": &"fuel",
		"id": spot,
		"item": item,
		"price": offer["price"],
		"units": offer["units"],
	}
