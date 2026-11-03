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


## A player has just gone down: takes away what the tuning says and returns the events.
static func on_down(rules: GameRules, player: PlayerState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
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
