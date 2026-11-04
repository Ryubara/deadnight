class_name AutopilotSetup
extends RefCounted
## Gives an `Autopilot` what it needs of the lot and the rules: the doors and their prices, the shop
## spots and the prices of the weapons, rounds, re-cut and tonic, the breaches, the breaker posts
## and the fuel crates. A night with the autopilot (`Night`) and a seat played by it in a soak or a
## suite (`SeatedNight.seat`) are set up here alike: an autopilot made bare never walks to a shop,
## so it runs dry and stays dry (#998).

## How far past the low-tank line (a fraction of a full tank) the bot waits before it lights an
## area again.
const RESUME_MARGIN := 0.15


## Fills `pilot` from `world`, the rules' `tuning` (the table the night plays by, the map's overlay
## on it) and the `night_tuning` (revive reach; the shipped one when null).
static func configure(
	pilot: Autopilot, world: NightWorld, tuning: RulesTuning, night_tuning: NightTuning = null
) -> void:
	var reach := (night_tuning if night_tuning != null else NightTuning.shipped()).revive_reach
	for item in tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			pilot.prices[item.id] = item.price
			pilot.order.append(item.id)
	pilot.spots = world.shop_spots()
	for item in tuning.economy.items:
		match item.kind:
			ShopItem.Kind.WEAPON, ShopItem.Kind.CRANE:
				pilot.prices_of_goods[item.id] = item.price
				pilot.wanted.append(item.id)
				if item.kind == ShopItem.Kind.CRANE:
					pilot.crane_pool.assign(item.pool)
			ShopItem.Kind.AMMO:
				pilot.ammo_prices[item.weapon] = item.price
			ShopItem.Kind.UPGRADE:
				pilot.recut_price = item.price
			ShopItem.Kind.TONIC:
				if item.health_bonus > 0.0:
					pilot.tonic_price = item.price
					pilot.tonic_id = item.id
	pilot.wanted.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return pilot.prices_of_goods[a] < pilot.prices_of_goods[b]
	)
	pilot.whole_boards = tuning.barricades.boards
	pilot.switches.capacity = tuning.fuel.capacity
	pilot.switches.save_below = tuning.fuel.low_fraction
	pilot.switches.resume_above = tuning.fuel.low_fraction + RESUME_MARGIN
	for circuit_id in world.switches.circuit_ids():
		pilot.switches.goals[circuit_id] = world.switches.standing_point(circuit_id)
		pilot.switches.doors[circuit_id] = world.switches.door_of(circuit_id)
	pilot.revive.reach = reach
	pilot.revive.seconds = tuning.health.revive_seconds
	pilot.fuel.capacity = tuning.fuel.capacity
	pilot.fuel.refuel_at = tuning.fuel.low_fraction
	pilot.fuel.fill_to = tuning.fuel.low_fraction + RESUME_MARGIN
	for item in tuning.economy.items:
		if item.kind == ShopItem.Kind.FUEL:
			pilot.fuel.item = item
	for id in world.fuel.ids():
		pilot.fuel.goals[id] = world.fuel.standing_point(id)
		pilot.fuel.doors[id] = world.fuel.door_of(id)
	for id in world.barricade_ids():
		pilot.repair_goals[id] = world.repair_spot(id)
	for door_id in pilot.order:
		var points := world.door_points(door_id)
		if not points.is_empty():
			pilot.door_goals[door_id] = points[0]
