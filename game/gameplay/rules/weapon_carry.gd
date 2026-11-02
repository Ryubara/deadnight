class_name WeaponCarry
extends RefCounted
## What a player carries (#410): at most `WeaponCatalog.CARRY_LIMIT` weapons, melee ones included.
## A weapon bought or taken from the crane with the hands full replaces the weapon in hand, which is
## disposed of, not dropped: it goes back into the pool, so the wall sells it and the crane gives it
## again. `PlayerState.weapons` is the list, in shop ids, the oldest first. The combat server keeps
## its own copy of the loadout and replaces the same weapon, the one the server found in hand.


## Puts `shop_id` among the weapons `player` carries. Full hands release the one whose catalogue id
## is `held` (the oldest when that is not carried). Returns the shop id released, or `&""`.
static func take(
	rules: GameRules, player: PlayerState, shop_id: StringName, held: StringName
) -> StringName:
	var released := &""
	if player.weapons.size() >= WeaponCatalog.CARRY_LIMIT:
		released = _in_hand(player, held)
		player.weapons.erase(released)
		_forget_recut(player, WeaponCatalog.catalog_id(released))
	player.weapons.append(shop_id)
	if released != &"":
		(
			rules
			. _emit(
				&"weapon_released",
				{"player_id": player.id, "weapon": released, "taken": shop_id},
			)
		)
	return released


## The carried weapon (a shop id) whose catalogue id is `held`, or the oldest one.
static func _in_hand(player: PlayerState, held: StringName) -> StringName:
	for shop_id in player.weapons:
		if WeaponCatalog.catalog_id(shop_id) == held:
			return shop_id
	return player.weapons[0]


## A re-cut weapon that is gone takes its re-cut with it; a fresh one can be re-cut again, and the
## price step of the next re-cut still counts it.
static func _forget_recut(player: PlayerState, weapon_id: StringName) -> void:
	if player.upgraded.has(weapon_id):
		player.upgraded.erase(weapon_id)
		player.recuts_lost += 1
