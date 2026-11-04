class_name PerkPlay
extends RefCounted
## What going down does to the perks, as the rules settle it: a player who goes down loses some or
## all of the tonics they have had (`PerkTuning.lost_on_down`), and with the tonics the health they
## gave and the weapon the third-weapon perk allowed. The one exception is a player the revive perk
## is about to get up alone (`RevivePlay.can_self_revive`): they lose nothing. Static functions
## that take the rules, like `CranePlay`. `docs/design/perks.md`.
##
## Event: `perks_lost`: player_id, lost (the tonic ids), weapons (the shop ids of the weapons
## given up with the third-weapon perk).
##
## And the drink (#912): a tonic bought is drunk first (`PerkTuning.drink_seconds`) and had when the
## drink ends: `drink_started` at the purchase, `drink_finished` when it is had. Meanwhile a blow
## hurts as ever and the drink goes on; going down spills it (`drink_spilled`): the perk is not
## had and the price is not given back, the genre's rule, and the same whatever `lost_on_down` is
## (a drink that is not down yet is not a perk had).


## A tonic was bought: the drink starts (or, with no drink time, the perk is had at once).
## Returns the purchase's `detail`.
static func start_drink(rules: GameRules, player: PlayerState, item: ShopItem) -> Dictionary:
	var seconds := rules.tuning.perks.drink_seconds
	if seconds <= 0.0:
		rules._events.append_array(_have(rules, player, item.id))
		return {}
	player.drinking = item.id
	player.drink_left = seconds
	rules._emit(&"drink_started", {"player_id": player.id, "item_id": item.id, "seconds": seconds})
	return {"drink": seconds}


## One step of every drink under way: the perk is had when its drink ends.
static func tick(rules: GameRules, delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for player: PlayerState in rules.players.values():
		if player.drinking == &"":
			continue
		player.drink_left -= delta
		if player.drink_left > 0.0:
			continue
		var tonic_id := player.drinking
		player.drinking = &""
		player.drink_left = 0.0
		events.append({"type": &"drink_finished", "player_id": player.id, "item_id": tonic_id})
		events.append_array(_have(rules, player, tonic_id))
	return events


## Whether this player's hands hold a drink.
static func is_drinking(player: PlayerState) -> bool:
	return player != null and player.drinking != &""


## The perk is had: the tonic is on the list and a health tonic raises the most health.
static func _have(rules: GameRules, player: PlayerState, tonic_id: StringName) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	player.tonics.append(tonic_id)
	var item := rules.tuning.economy.item(tonic_id)
	if item != null and item.health_bonus > 0.0:
		events.append(PlayerHealth.raise_max(player, item.health_bonus))
	return events


## A drink under way is spilled by a down: no perk, no refund.
static func _spill(player: PlayerState) -> Array[Dictionary]:
	if player.drinking == &"":
		return []
	var spilled := player.drinking
	player.drinking = &""
	player.drink_left = 0.0
	return [{"type": &"drink_spilled", "player_id": player.id, "item_id": spilled}]


## A player has just gone down: takes away what the tuning says and returns the events.
static func on_down(rules: GameRules, player: PlayerState) -> Array[Dictionary]:
	var events := _spill(player)
	var tuning := rules.tuning
	if player.tonics.is_empty() or tuning.perks.lost_on_down == PerkTuning.Loss.NONE:
		return events
	if RevivePlay.can_self_revive(rules, player):
		return events
	var lost: Array[StringName] = []
	if tuning.perks.lost_on_down == PerkTuning.Loss.LAST:
		lost.append(player.tonics[player.tonics.size() - 1])
	else:
		lost.assign(player.tonics)
	for tonic_id in lost:
		player.tonics.erase(tonic_id)
		var item := tuning.economy.item(tonic_id)
		if item != null and item.effect == ShopItem.Effect.HEALTH:
			player.max_health = maxf(player.max_health - item.health_bonus, 1.0)
	var released := WeaponCarry.trim(rules, player)
	events.append(
		{"type": &"perks_lost", "player_id": player.id, "lost": lost, "weapons": released}
	)
	return events
