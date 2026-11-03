class_name BotShop
extends RefCounted
## What every client has of the shop before the night begins, for a bot that shops, repairs boards
## and looks after the generator: the shop table (prices, what unlocks what, the order the designers
## list the doors in), where to stand to use each door, shop spot, breach, breaker post and fuel
## crate, and the lamps of each circuit. Filled from the built lot and the rules' tuning by
## `LotBotData.fill` and read-only after: a bot learns the price of a thing from this table and
## from the prompt it is shown, never from the rules (`docs/research/bots.md#economy`).

## The shop table and the generator's numbers.
var economy: EconomyTuning
var fuel: FuelTuning
## The round table: the health of the dead a round sends (a bot that weighs its weapons by it,
## `BotProfile.weighs_by_round`).
var rounds: RoundTuning
## Boards a whole barricade holds.
var boards := 1
## Grenades a pack holds (`ExplosiveTuning.max_grenades`).
var max_grenades := 5
## Metres a hand reaches to use a door, a spot, a breach or a breaker, and to buy a fuel can.
var use_reach := 3.2
var fuel_reach := 2.0
## How far the dead must be (metres to the nearest) before an errand begins, and the share of a
## round's dead that, once only that many are left, makes a lull to shop in: the lot's numbers suit
## 100 m of open ground, a small map's overlay (`MapTuning`) sets its own.
var clear_from := BotErrands.CLEAR_FROM
var calm_share := BotErrands.CALM_SHARE
## The health share under which a hurt teammate holds every door back.
var hurt_share := BotErrands.HURT_SHARE
## Whether the team buys the links together (`BotErrands._link`): off on the lot, where the door's
## turn suits 100 m of open ground; a small map's overlay turns it on.
var team_links := false
## What the bot buys, first to last, on this map; empty is the profile's own list
## (`BotProfile.shopping`, written for the lot).
var shopping: Array[StringName] = []
## Doors to buy, in the order of the shop table.
var doors: Array[StringName] = []
## Where to stand to use each door (the middle of each of its slabs), by door id.
var door_stands: Dictionary[StringName, Array] = {}
## The shop spots: `{kind, shop_id, position, crane_spot}` (walls, the crane, lockers, the re-cut
## bench, the soda fountain).
var spots: Array[Dictionary] = []
## The breaches: where to stand to put boards back, and the middle of the gap, by id.
var repair_stands: Dictionary[StringName, Vector3] = {}
var repair_centres: Dictionary[StringName, Vector3] = {}
## The breaker posts: where to stand, the shop door of the area each lights (empty for the field's)
## and the lamps it hangs, by circuit id; the metres a lamp lights.
var circuit_stands: Dictionary[StringName, Vector3] = {}
var circuit_doors: Dictionary[StringName, StringName] = {}
var circuit_lamps: Dictionary[StringName, Array] = {}
var lamp_reach := 12.0
## The fuel crates: where to stand, the shop door of the area, by spot id; the item they sell.
var fuel_stands: Dictionary[StringName, Vector3] = {}
var fuel_doors: Dictionary[StringName, StringName] = {}
var fuel_item: ShopItem

var _tonic_order: Array[StringName] = []


## The tonics' ids in the shop's order, the bits of a frame's `perks` (`PerkEffects.mask_of`): made
## once, because a think asks for it for every tonic on the list.
func tonic_order() -> Array[StringName]:
	if _tonic_order.is_empty() and economy != null:
		_tonic_order = PerkEffects.tonic_ids(economy)
	return _tonic_order


## The shop item with `item_id`, or null.
func item(item_id: StringName) -> ShopItem:
	return economy.item(item_id) if economy != null else null


## The doors that are shut and can be bought now (the door before them is open), in table order.
func unlocked_doors(doors_open: Array) -> Array[StringName]:
	var found: Array[StringName] = []
	for door_id in doors:
		if doors_open.has(door_id):
			continue
		var requires: StringName = economy.item(door_id).requires
		if requires == &"" or doors_open.has(requires):
			found.append(door_id)
	return found


## The spots whose shop id is `shop_id`.
func spots_of(shop_id: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for spot in spots:
		if spot["shop_id"] == shop_id:
			found.append(spot)
	return found


## The spots of `kind` (`ammo` lockers have no shop id).
func spots_by_kind(kind: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for spot in spots:
		if spot["kind"] == kind:
			found.append(spot)
	return found
