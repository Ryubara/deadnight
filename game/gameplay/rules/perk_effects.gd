class_name PerkEffects
extends RefCounted
## What the perks a player has had do, read from the rules' tuning (`ShopItem.effect`,
## `PerkTuning`).
## Plain static functions with no state: the combat server, the revive channel, the rules and the
## balance simulator all ask the same questions here, so a perk means one thing everywhere.
## `docs/design/perks.md`.


## Whether the player has had a perk with this effect.
static func has(rules: GameRules, player_id: int, effect: ShopItem.Effect) -> bool:
	return has_in(rules.tuning, rules.players.get(player_id), effect)


## The same, for a player state and a tuning (no rules object needed).
static func has_in(tuning: RulesTuning, player: PlayerState, effect: ShopItem.Effect) -> bool:
	if player == null:
		return false
	for tonic_id in player.tonics:
		var item := tuning.economy.item(tonic_id)
		if item != null and item.effect == effect:
			return true
	return false


## The wait between shots is this many times the weapon's own (1 without the perk).
static func fire_interval_scale(rules: GameRules, player_id: int) -> float:
	if rules != null and has(rules, player_id, ShopItem.Effect.FIRE_RATE):
		return 1.0 / rules.tuning.perks.fire_rate_multiplier
	return 1.0


## A reload takes this many times the weapon's own time (1 without the perk).
static func reload_time_scale(rules: GameRules, player_id: int) -> float:
	if rules != null and has(rules, player_id, ShopItem.Effect.RELOAD_SPEED):
		return rules.tuning.perks.reload_time_scale
	return 1.0


## How many weapons the player carries at most.
static func carry_limit(rules: GameRules, player_id: int) -> int:
	if rules != null and has(rules, player_id, ShopItem.Effect.EXTRA_WEAPON):
		return WeaponCatalog.CARRY_LIMIT + rules.tuning.perks.extra_weapons
	return WeaponCatalog.CARRY_LIMIT


## The seconds this player holds a revive for (the reviver's perk counts, not the downed one's).
static func revive_seconds(rules: GameRules, reviver_id: int) -> float:
	var seconds := rules.tuning.health.revive_seconds
	if reviver_id > 0 and has(rules, reviver_id, ShopItem.Effect.REVIVE):
		return seconds * rules.tuning.perks.revive_time_scale
	return seconds


## The perks as bits for the frame: bit `i` is the `i`th tonic item of the shop's list.
static func mask_of(rules: GameRules, player_id: int) -> int:
	var player: PlayerState = rules.players.get(player_id)
	if player == null:
		return 0
	var bits := 0
	var order := tonic_ids(rules.tuning.economy)
	for tonic_id in player.tonics:
		var at := order.find(tonic_id)
		if at >= 0:
			bits |= 1 << at
	return bits


## The tonic items of the shop in the shop's order (what a mask's bits mean).
static func tonic_ids(economy: EconomyTuning) -> Array[StringName]:
	var ids: Array[StringName] = []
	for item in economy.items:
		if item.kind == ShopItem.Kind.TONIC:
			ids.append(item.id)
	return ids


## Whether the bit of `tonic_id` is set in a frame's `perks` mask.
static func mask_has(economy: EconomyTuning, mask: int, tonic_id: StringName) -> bool:
	var at := tonic_ids(economy).find(tonic_id)
	return at >= 0 and (mask & (1 << at)) != 0


## How many tonics a frame's `perks` mask holds.
static func mask_count(mask: int) -> int:
	var count := 0
	while mask != 0:
		count += mask & 1
		mask >>= 1
	return count
