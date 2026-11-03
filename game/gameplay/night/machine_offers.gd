class_name MachineOffers
extends RefCounted
## What the lot's two machines and its grenade rack offer a player in reach, as the prompt
## dictionaries `NightServer.use_target` returns (`docs/design/upgrades.md`):
##
##   the re-cut bench (spot kind `upgrade`):
##     `{kind: recut, id, weapon, price}`   a weapon in hand that can be re-cut, and its price
##     `{kind: recut_done, weapon}`         the weapon in hand is already re-cut
##     `{kind: recut_none, weapon}`         the weapon in hand cannot be (the crowbar)
##   a perk machine (spot kind `perk`, `docs/design/perks.md`):
##     `{kind: tonic, id, name, effect, price, bonus}`  the tonic it pours, not yet had (`effect`
##                                          a `ShopItem.Effect`, `bonus` the health it gives)
##     `{kind: tonic_owned, id, name}`      the player has it
##     `{kind: tonic_full, id, name, limit}` the player carries as many tonics as they may
##   the grenade rack (spot kind `rack`):
##     `{kind: grenades, id, count, price}` the grenades that fit the pack (one purchase's worth
##                                          at most) and their price; nothing when it is full
##
## `recut` and `tonic` are bought with a press of use, like every shop prompt; the others are only
## words on the card. The price is the rules' (`GameRules.price_of`), never the scene's.

const UPGRADE_SPOT := &"upgrade"
const PERK_SPOT := &"perk"
const RACK_SPOT := &"rack"


## The offer of a machine spot, or `{}` when the spot is not a machine's.
static func offer(server: NightServer, player_id: int, spot: Dictionary) -> Dictionary:
	match spot["kind"]:
		UPGRADE_SPOT:
			return _recut(server, player_id, spot["shop_id"])
		PERK_SPOT:
			return _tonic(server, player_id, spot["shop_id"])
		RACK_SPOT:
			return _grenades(server, player_id, spot["shop_id"])
	return {}


## The catalogue weapon a tune-up bought now is for: the one in the buyer's hand, or `&""`.
static func weapon_for(server: NightServer, player_id: int) -> StringName:
	var held := server.combat.weapon_of(player_id)
	return held.def.id if held != null else &""


## What taking a weapon would cost the player's hands: the catalogue id of the weapon in hand it
## replaces when the hands are full and the weapon is not carried yet, else `&""`.
static func replaces(server: NightServer, player_id: int, weapon_id: StringName) -> StringName:
	if server.combat.state_of(player_id, weapon_id) != null:
		return &""
	if server.combat.carried(player_id).size() < PerkEffects.carry_limit(server.rules, player_id):
		return &""
	return weapon_for(server, player_id)


static func _recut(server: NightServer, player_id: int, item_id: StringName) -> Dictionary:
	var weapon := weapon_for(server, player_id)
	if weapon == &"":
		return {}
	var rules := server.rules
	if not rules.tuning.upgrade.allows(weapon):
		return {"kind": &"recut_none", "weapon": weapon}
	if rules.players[player_id].upgraded.has(weapon):
		return {"kind": &"recut_done", "weapon": weapon}
	return {
		"kind": &"recut",
		"id": item_id,
		"weapon": weapon,
		"price": rules.price_of(item_id, player_id),
	}


## The grenades a rack sells: as many as fit the pack, one purchase at most, at their share of the
## price (`ShopCounter` prices a part fill the same way). `{}` when the pack is full.
static func _grenades(server: NightServer, player_id: int, item_id: StringName) -> Dictionary:
	var rules := server.rules
	var item := rules.tuning.economy.item(item_id)
	if item == null or item.kind != ShopItem.Kind.GRENADES:
		return {}
	var count := mini(
		int(item.amount), rules.tuning.explosives.max_grenades - rules.grenades_of(player_id)
	)
	if count <= 0:
		return {}
	return {
		"kind": &"grenades",
		"id": item.id,
		"count": count,
		"price": ceili(float(item.price_at(rules.round_number)) * count / item.amount),
	}


static func _tonic(server: NightServer, player_id: int, item_id: StringName) -> Dictionary:
	var rules := server.rules
	var item := rules.tuning.economy.item(item_id)
	if item == null:
		return {}
	var tonics := rules.players[player_id].tonics
	if tonics.has(item_id):
		return {"kind": &"tonic_owned", "id": item_id, "name": item.display_name}
	if tonics.size() >= rules.tuning.economy.max_tonics:
		return {
			"kind": &"tonic_full",
			"id": item_id,
			"name": item.display_name,
			"limit": rules.tuning.economy.max_tonics,
		}
	return {
		"kind": &"tonic",
		"id": item_id,
		"name": item.display_name,
		"effect": item.effect,
		"price": rules.price_of(item_id, player_id),
		"bonus": item.health_bonus,
	}
