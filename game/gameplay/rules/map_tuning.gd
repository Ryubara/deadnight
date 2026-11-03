class_name MapTuning
extends Resource
## What one map changes of the shared rules table (`default_tuning.tres`, the drive-in lot's): its
## links, the weapons on its walls, its box, its windows and the most dead it stands at once.
## `apply` lays the map over a copy of the shared table, so every number the maps share (rounds,
## health, points, ammunition, zombie types) stays in one place and a map holds only what it
## changes. A map's scene names its overlay in `metadata/tuning` (`MapLayout.tuning_path`); the
## scene's markers (the doors' `shop_id`, the shop spots' `shop_id` and `crane_spot`, the windows'
## `barricade_id`) and these lists must agree, and a test per map fails when they do not
## (`test_smallmap_economy.gd`).
##
## Reasoning for the second map: `docs/design/smallmap.md` (Playing it) and the formula page's rows
## 20 to 26.

## The map's id (`MapRegistry`), for the overlay to be found by.
@export var id: StringName = &""
## The kinds of shop item of the shared table this map does not sell at all. The shop here is the
## map's own list of `items`; ammunition is the one kind the shared table keeps.
@export var dropped_kinds: Array[ShopItem.Kind] = []
## The map's own items: its paid links (`ShopItem.Kind.DOOR`, every one at the same price), the
## weapons on its walls (`WEAPON`) and the box (`CRANE`).
@export var items: Array[ShopItem] = []
## The windows: one `Barricade` in the scene for each id, and how many boards each holds.
@export var barricades: BarricadeTuning = BarricadeTuning.new()
## The box: its places (one on this map) and how it behaves.
@export var crane: CraneTuning = CraneTuning.new()
## The most dead standing at once on this map, whatever the round and the players, on a desktop and
## in the browser alike (the rounds' `alive_cap_ceiling`).
@export_range(1, 300, 1, "or_greater") var alive_cap: int = 24
@export_group("Bots")
## How the bots shop here. The lot's numbers suit 100 m of open ground; here the dead are never
## far: no errand begins with a dead one nearer than `bot_clear_from` metres, a lull to shop in
## comes once `bot_calm_share` of a round's dead are left, and the bot buys in the order of
## `bot_shopping` (the shared profiles' lists name the lot's doors).
@export_range(1.0, 40.0, 0.5, "suffix:m") var bot_clear_from: float = 12.0
@export_range(0.05, 1.0, 0.05) var bot_calm_share: float = 0.25
@export var bot_shopping: Array[StringName] = []
## A hurt teammate holds every link back while their health is under this share of full.
@export_range(0.0, 1.0, 0.05) var bot_hurt_share: float = 0.5
@export_group("")

## What the map calls its links and breaches on the HUD; null for the lot (the HUD's own words).
@export var words: MapWords

## The map's generator: the shared table's when empty, else this one (a map with no generator
## gives a tank that never drains and no circuits).
@export var fuel: FuelTuning


## The shared table `base` with this map laid over it: a copy, `base` is never changed.
func apply(base: RulesTuning) -> RulesTuning:
	var out := base.duplicate(true) as RulesTuning
	var kept: Array[ShopItem] = []
	for item in out.economy.items:
		if not dropped_kinds.has(item.kind):
			kept.append(item)
	for item in items:
		kept.append(item.duplicate() as ShopItem)
	out.economy.items = kept
	out.barricades = barricades.duplicate() as BarricadeTuning
	out.crane = crane.duplicate() as CraneTuning
	out.rounds.alive_cap_ceiling = alive_cap
	out.rounds.web_alive_cap_ceiling = alive_cap
	if fuel != null:
		out.fuel = fuel.duplicate(true) as FuelTuning
	return out


## The paid links of this map, in the order the overlay lists them.
func link_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for item in items:
		if item.kind == ShopItem.Kind.DOOR:
			found.append(item.id)
	return found


## The price every link costs (`P` of the formula page's row 20), or -1 when they differ.
func link_price() -> int:
	var price := -1
	for item in items:
		if item.kind != ShopItem.Kind.DOOR:
			continue
		if price >= 0 and item.price != price:
			return -1
		price = item.price
	return price
