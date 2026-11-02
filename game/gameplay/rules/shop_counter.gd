class_name ShopCounter
extends RefCounted
## The shop's till, as the rules run it: price a purchase, check it can be made, and hand over what
## was bought. Static functions that take the rules (the same shape as `CranePlay`), so the rules
## stay one file's worth of state and no reference cycle is made. `GameRules._buy` does the
## paying and the events; the item kinds are `ShopItem.Kind`.


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
	## UPGRADE: the weapon (a catalogue id) the buyer holds.
	var weapon: StringName = &""


## The quote for `item_id` for this player now. `rounds` is the room an ammunition purchase has
## (`RulesAction.buy`), `weapon` the weapon a re-cut is for, or the weapon in hand a bought weapon
## replaces when the hands are full.
static func quote(
	rules: GameRules, player_id: int, item_id: StringName, rounds: int, weapon: StringName
) -> Quote:
	var result := Quote.new()
	var player := rules.players.get(player_id) as PlayerState
	var item := rules.tuning.economy.item(item_id)
	if rules.phase != GameRules.Phase.BREAK and rules.phase != GameRules.Phase.ACTIVE:
		result.result = GameRules.BuyResult.WRONG_PHASE
	elif player == null:
		result.result = GameRules.BuyResult.UNKNOWN_PLAYER
	elif player.downed:
		result.result = GameRules.BuyResult.PLAYER_DOWNED
	elif item == null:
		result.result = GameRules.BuyResult.UNKNOWN_ITEM
	else:
		result.item = item
		result.price = price(rules, item, player)
		result.rounds_offered = rounds
		result.weapon = weapon
		result.result = _check(rules, player, result)
	if result.result == GameRules.BuyResult.OK and player.points < result.price:
		result.result = GameRules.BuyResult.NOT_ENOUGH_POINTS
	return result


## What this player pays for the item at the start of the quote: its price this round, and for a
## re-cut the step for each weapon they have re-cut already.
static func price(rules: GameRules, item: ShopItem, player: PlayerState) -> int:
	var cost := item.price_at(rules.round_number)
	if item.kind == ShopItem.Kind.UPGRADE:
		cost += rules.tuning.upgrade.price_step * (player.upgraded.size() + player.recuts_lost)
	return cost


## Hands over what was bought; returns what the event's `detail` should say.
static func grant(rules: GameRules, player: PlayerState, bought: Quote) -> Dictionary:
	var item := bought.item
	var detail := {}
	match item.kind:
		ShopItem.Kind.DOOR:
			rules.doors_open.append(item.id)
			rules._emit(&"door_opened", {"door_id": item.id})
		ShopItem.Kind.WEAPON:
			var released := WeaponCarry.take(rules, player, item.id, bought.weapon)
			detail = {"weapon": item.id, "released": released}
		ShopItem.Kind.CRANE:
			detail = CranePlay.start(rules, player, bought.price)
		ShopItem.Kind.TONIC:
			player.tonics.append(item.id)
			if item.health_bonus > 0.0:
				rules._events.append(PlayerHealth.raise_max(player, item.health_bonus))
		ShopItem.Kind.UPGRADE:
			player.upgraded.append(bought.weapon)
			detail = {"upgrade": bought.weapon}
		ShopItem.Kind.FUEL:
			detail = {"fuel": rules.generator.add_fuel(bought.fuel_added)}
		ShopItem.Kind.GRENADES:
			rules._set_grenades(player, player.grenades + bought.grenades_added, &"purchase")
			detail = {"grenades": bought.grenades_added}
		ShopItem.Kind.AMMO:
			detail = {"ammo": item.weapon, "rounds": bought.ammo_added}
	return detail


## Whether the item can be sold to this player at all, ignoring their points. A fuel, grenade or
## ammunition quote also gets its real price: you pay only for the room.
static func _check(rules: GameRules, player: PlayerState, bought: Quote) -> GameRules.BuyResult:
	var item := bought.item
	var tuning := rules.tuning
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
			elif player.tonics.size() >= tuning.economy.max_tonics:
				result = GameRules.BuyResult.LIMIT_REACHED
		ShopItem.Kind.UPGRADE:
			if not tuning.upgrade.allows(bought.weapon):
				result = GameRules.BuyResult.NO_WEAPON
			elif player.upgraded.has(bought.weapon):
				result = GameRules.BuyResult.ALREADY_OWNED
		ShopItem.Kind.GRENADES:
			var room := tuning.explosives.max_grenades - player.grenades
			if room <= 0:
				result = GameRules.BuyResult.LIMIT_REACHED
			else:
				bought.grenades_added = mini(int(item.amount), room)
				bought.price = ceili(float(bought.price) * bought.grenades_added / item.amount)
		ShopItem.Kind.AMMO:
			# The weapon's reserve is the combat server's: the buyer says how many rounds fit
			# (none given: all of them) and the rules price exactly those.
			var fit := int(item.amount)
			if bought.rounds_offered >= 0:
				fit = mini(bought.rounds_offered, fit)
			if fit <= 0:
				result = GameRules.BuyResult.AMMO_FULL
			else:
				bought.ammo_added = fit
				bought.price = item.ammo_price(rules.round_number, fit)
		ShopItem.Kind.FUEL:
			var offer := item.fuel_offer(rules.round_number, rules.generator.space())
			if offer["units"] <= 0.0:
				result = GameRules.BuyResult.TANK_FULL
			else:
				bought.fuel_added = offer["units"]
				bought.price = offer["price"]
	return result
