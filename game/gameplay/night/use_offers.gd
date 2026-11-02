class_name UseOffers
extends RefCounted
## What the use button would do in reach of a spot, for the offers that need only the world, the
## rules and the night's tuning (`NightServer.use_target` asks them among the shop spots): a door
## to buy, a breach to mend or a breaker post to switch, a fuel can. Each answers a dictionary
## (`kind`, `id` and what the card shows) or `{}`.


## The shut door in reach that can be bought now (the one before it is open), or `{}`.
static func door(
	world: NightWorld, rules: GameRules, tuning: NightTuning, here: Vector3
) -> Dictionary:
	for door_id in world.door_ids():
		if rules.is_door_open(door_id):
			continue
		var item := rules.tuning.economy.item(door_id)
		if item.requires != &"" and not rules.is_door_open(item.requires):
			continue
		for point in world.door_points(door_id):
			if _flat(here, point) <= tuning.use_reach:
				return {"kind": &"door", "id": door_id, "price": rules.price_of(door_id)}
	return {}


## A breach to put a board back across, or a breaker post, in reach of `here`, or `{}`.
static func post(
	world: NightWorld, rules: GameRules, tuning: NightTuning, here: Vector3
) -> Dictionary:
	for id in world.barricade_ids():
		var boards := rules.barricades.boards_of(id)
		if boards >= rules.tuning.barricades.boards:
			continue
		var barricade := world.barricade(id)
		var near := _flat(here, barricade.centre()) <= tuning.use_reach
		if barricade.depth_of(here) > 0.0 and near:
			return {"kind": &"repair", "id": id, "boards": boards}
	var post := world.switches.within_reach(here, tuning.use_reach)
	if post == null:
		return {}
	var on: bool = rules.generator.circuits.get(post.circuit_id, false)
	return {"kind": &"circuit", "id": post.circuit_id, "on": on}


## The can stand within reach of `here`: what the rules would sell and for how much, or `{}`.
static func fuel(
	world: NightWorld, rules: GameRules, tuning: NightTuning, here: Vector3
) -> Dictionary:
	var spot := world.fuel.within_reach(here, tuning.fuel_reach)
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


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
