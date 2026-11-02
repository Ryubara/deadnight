class_name MachineOffers
extends RefCounted
## What the lot's two machines offer a player in reach, as the prompt dictionaries
## `NightServer.use_target` returns (`docs/design/upgrades.md`):
##
##   the re-cut bench (spot kind `upgrade`):
##     `{kind: recut, id, weapon, price}`   a weapon in hand that can be re-cut, and its price
##     `{kind: recut_done, weapon}`         the weapon in hand is already re-cut
##     `{kind: recut_none, weapon}`         the weapon in hand cannot be (the crowbar)
##   the soda fountain (spot kind `perk`):
##     `{kind: tonic, id, price, bonus}`    the tonic the fountain pours, not yet had
##     `{kind: tonic_owned, id}`            the player has it
##
## `recut` and `tonic` are bought with a press of use, like every shop prompt; the others are only
## words on the card. The price is the rules' (`GameRules.price_of`), never the scene's.

const UPGRADE_SPOT := &"upgrade"
const PERK_SPOT := &"perk"


## The offer of a machine spot, or `{}` when the spot is not a machine's.
static func offer(server: NightServer, player_id: int, spot: Dictionary) -> Dictionary:
	match spot["kind"]:
		UPGRADE_SPOT:
			return _recut(server, player_id, spot["shop_id"])
		PERK_SPOT:
			return _tonic(server, player_id, spot["shop_id"])
	return {}


## The catalogue weapon a tune-up bought now is for: the one in the buyer's hand, or `&""`.
static func weapon_for(server: NightServer, player_id: int) -> StringName:
	var held := server.combat.weapon_of(player_id)
	return held.def.id if held != null else &""


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


static func _tonic(server: NightServer, player_id: int, item_id: StringName) -> Dictionary:
	var rules := server.rules
	var item := rules.tuning.economy.item(item_id)
	if item == null:
		return {}
	if rules.players[player_id].tonics.has(item_id):
		return {"kind": &"tonic_owned", "id": item_id}
	return {
		"kind": &"tonic",
		"id": item_id,
		"price": rules.price_of(item_id, player_id),
		"bonus": item.health_bonus,
	}
