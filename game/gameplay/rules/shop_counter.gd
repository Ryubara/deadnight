class_name ShopCounter
extends RefCounted
## The shop, as the rules run it: pricing, the checks that refuse a purchase, and handing the goods
## over, in static functions that take the rules so no reference cycle is made (as `CranePlay`
## does). Every result is a `GameRules.BuyResult`; a refusal is a `purchase_denied` event and costs
## nothing. A downed player cannot buy anything.


## A priced, checked purchase that has not happened yet.
class Quote:
	extends RefCounted
	var result: GameRules.BuyResult = GameRules.BuyResult.OK
	var item: ShopItem
	var price: int = 0
	var fuel_added: float = 0.0
	var grenades_added: int = 0
	var rounds_offered: int = -1
	var ammo_added: int = 0


## `player_id` buys `item_id` (for ammunition, `rounds` fit in the reserve; -1 means all of them).
static func buy(rules: GameRules, player_id: int, item_id: StringName, rounds: int = -1) -> void:
	var quote := quote_for(rules, player_id, item_id, rounds)
	if quote.result != GameRules.BuyResult.OK:
		rules._emit(
			&"purchase_denied", {"player_id": player_id, "item_id": item_id, "result": quote.result}
		)
		return
	var player: PlayerState = rules.players[player_id]
	player.points -= quote.price
	player.points_spent += quote.price
	(
		rules
		. _emit(
			&"points_changed",
			{
				"player_id": player_id,
				"total": player.points,
				"delta": -quote.price,
				"reason": &"purchase",
			}
		)
	)
	var detail := _grant(rules, player, quote)
	rules._emit(
		&"purchase_made",
		{"player_id": player_id, "item_id": item_id, "price": quote.price, "detail": detail}
	)
	if quote.item.kind == ShopItem.Kind.CRANE:
		(
			rules
			. _emit(
				&"crane_spin_started",
				{
					"player_id": player_id,
					"spot": rules.crane.spot,
					"seconds": rules.tuning.crane.spin_seconds,
					"plays": rules.crane.plays,
				}
			)
		)


## What buying would cost and whether it would work, changing nothing.
static func quote_for(
	rules: GameRules, player_id: int, item_id: StringName, rounds: int = -1
) -> Quote:
	var quote := Quote.new()
	var player := rules.players.get(player_id) as PlayerState
	var item := rules.tuning.economy.item(item_id)
	if rules.phase != GameRules.Phase.BREAK and rules.phase != GameRules.Phase.ACTIVE:
		quote.result = GameRules.BuyResult.WRONG_PHASE
	elif player == null:
		quote.result = GameRules.BuyResult.UNKNOWN_PLAYER
	elif player.downed:
		quote.result = GameRules.BuyResult.PLAYER_DOWNED
	elif item == null:
		quote.result = GameRules.BuyResult.UNKNOWN_ITEM
	else:
		quote.item = item
		quote.price = item.price_at(rules.round_number)
		quote.rounds_offered = rounds
		quote.result = _check_item(rules, player, quote)
	if quote.result == GameRules.BuyResult.OK and player.points < quote.price:
		quote.result = GameRules.BuyResult.NOT_ENOUGH_POINTS
	return quote


## Whether the item can be sold to this player at all, ignoring their points. A fuel quote also gets
## its real price: you pay only for the room in the tank.
static func _check_item(rules: GameRules, player: PlayerState, quote: Quote) -> GameRules.BuyResult:
	var item := quote.item
	var result := GameRules.BuyResult.OK
	match item.kind:
		ShopItem.Kind.DOOR:
			if rules.doors_open.has(item.id):
				result = GameRules.BuyResult.ALREADY_OWNED
			elif item.requires != &"" and not rules.doors_open.has(item.requires):
				result = GameRules.BuyResult.LOCKED
		ShopItem.Kind.WEAPON:
			if player.weapons.has(item.id):
				result = GameRules.BuyResult.ALREADY_OWNED
		ShopItem.Kind.CRANE:
			if item.pool_without(player.weapons).is_empty():
				result = GameRules.BuyResult.ALREADY_OWNED
			elif not rules.crane.is_ready():
				result = GameRules.BuyResult.CRANE_BUSY
		ShopItem.Kind.TONIC:
			if player.tonics.has(item.id):
				result = GameRules.BuyResult.ALREADY_OWNED
			elif player.tonics.size() >= rules.tuning.economy.max_tonics:
				result = GameRules.BuyResult.LIMIT_REACHED
		ShopItem.Kind.GRENADES:
			var room := rules.tuning.explosives.max_grenades - player.grenades
			if room <= 0:
				result = GameRules.BuyResult.LIMIT_REACHED
			else:
				quote.grenades_added = mini(int(item.amount), room)
				quote.price = ceili(float(quote.price) * quote.grenades_added / item.amount)
		ShopItem.Kind.AMMO:
			# The weapon's reserve is the combat server's: the buyer says how many rounds fit
			# (none given: all of them) and the rules price exactly those.
			var fit := int(item.amount)
			if quote.rounds_offered >= 0:
				fit = mini(quote.rounds_offered, fit)
			if fit <= 0:
				result = GameRules.BuyResult.AMMO_FULL
			else:
				quote.ammo_added = fit
				quote.price = item.ammo_price(rules.round_number, fit)
		ShopItem.Kind.FUEL:
			var offer := item.fuel_offer(rules.round_number, rules.generator.space())
			if offer["units"] <= 0.0:
				result = GameRules.BuyResult.TANK_FULL
			else:
				quote.fuel_added = offer["units"]
				quote.price = offer["price"]
	return result


## Hands over what was bought; returns what the event's `detail` should say.
static func _grant(rules: GameRules, player: PlayerState, quote: Quote) -> Dictionary:
	var item := quote.item
	match item.kind:
		ShopItem.Kind.DOOR:
			rules.doors_open.append(item.id)
			rules._emit(&"door_opened", {"door_id": item.id})
		ShopItem.Kind.WEAPON:
			player.weapons.append(item.id)
			return {"weapon": item.id}
		ShopItem.Kind.CRANE:
			return CranePlay.start(rules, player, quote.price)
		ShopItem.Kind.TONIC:
			player.tonics.append(item.id)
		ShopItem.Kind.FUEL:
			return {"fuel": rules.generator.add_fuel(quote.fuel_added)}
		ShopItem.Kind.GRENADES:
			rules._set_grenades(player, player.grenades + quote.grenades_added, &"purchase")
			return {"grenades": quote.grenades_added}
		ShopItem.Kind.AMMO:
			return {"ammo": item.weapon, "rounds": quote.ammo_added}
	return {}
