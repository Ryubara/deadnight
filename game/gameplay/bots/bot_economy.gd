class_name BotEconomy
extends RefCounted
## What a bot buys, as a pure chooser: the points, the prices and what the bot carries in (a
## `View`); the purchases it would make out, best first (`candidates`). No clock, no server, no
## state but the profile's plan, so a table of cases pins it (`docs/research/bots.md#economy`).
##
## The order is the simulator's player (`NightSim._shop`): the rounds the bot cannot fight without
## (below one magazine of reserve, bought at once, in a round too), the rounds of a short reserve
## (`BotProfile.ammo_floor_mags` magazines), then the things it is saving for in the order of
## `BotProfile.shopping` (doors, wall weapons, the crane, the re-cut, the tonics), and last
## topping the reserves up with what is left once the next thing on the list is paid for. An item
## on the list is passed over when it is not affordable, unless the profile saves for it. Tonics
## are perks (`docs/design/perks.md`): one with no effect is never bought. Grenades come last: a bot
## with fewer than `BotProfile.grenades_wanted` buys a rack's worth once the next thing on the list
## is paid for.
##
## Keeping back a reserve: a fuel can from round `RESERVE_FUEL_FROM` on, so a plan item never leaves
## the bot unable to feed the generator.

## A refill must fill at least this share of the reserve cap (the rules refuse one that fills none:
## `AMMO_FULL`).
const MIN_ROOM := 0.10
## Zombies left in a round at or under which a round has a lull in it (a break always does); the
## share of the round's most dead that also makes one (`BotErrands`).
const CALM_REMAINING := 5
## A gun is worth rounds when its sustained damage is at least this share of the best one carried.
const USEFUL_SHARE := 0.5
## The round from which a fuel can's price is kept back.
const RESERVE_FUEL_FROM := 3
## Points held past this many times the price of the next thing on the list are a glut.
const GLUT := 2.0
## Why a purchase was chosen, in the order the chooser tries them.
const URGENT := &"ammo_urgent"
const FLOOR := &"ammo_floor"
const PLAN := &"plan"
const TOP_OFF := &"top_off"
const PING := &"ping"
const AMMO_PING := &"ammo_ping"
## Metres within which a marked spot counts as the shop's locker.
const LOCKER_SNAP := 1.0
## Metres of walking a metre of height stands for when a door's stand is chosen: a link set in a
## stair has a stand on each side, one a flight up, and the flat-nearest was a walk round the
## whole map for a bot on the other floor.
const RISE_WEIGHT := 8.0
## The most sources of rounds asked for their walk at one choice (the nearest by the straight line
## first), and the metres of walk the stand the bot is heading to is credited with.
const WALK_LOOKS := 4
const HEADING_CREDIT := 6.0

## Sustained damage a second of each catalogue weapon, worked out once (the definitions are fixed).
static var _dps: Dictionary = {}

## The price of the first thing on the list the last `candidates` call found the bot wants (0 when
## none), whether or not it could pay.
var last_next := 0

var _shop: BotShop
var _profile: BotProfile


## One purchase: the shop item, where to stand to make it, the prompt kind that sells it and why.
class Buy:
	extends RefCounted
	var item: StringName = &""
	var kind := ShopItem.Kind.DOOR
	var price := 0
	var stand := Vector3.INF
	var prompt: StringName = &""
	## Ammunition: the weapon whose reserve it fills.
	var weapon: StringName = &""
	var why: StringName = &""

	func is_none() -> bool:
		return item == &""


## What the chooser reads: the bot's own state and the etiquette's verdicts.
class View:
	extends RefCounted
	var points := 0
	var round_number := 1
	var in_break := true
	var remaining := 0
	## Zombies left at or under which a round has a lull (a break always does).
	var calm_at := CALM_REMAINING
	## True when the bot has seen and heard nothing of the dead for a while in this round.
	var lull := false
	## True to read the list as if it were a lull (for the price of what is next).
	var ignore_hour := false
	var here := Vector3.ZERO
	## The carried weapons: catalogue id to `[magazine, reserve, tier]`; the one in hand.
	var arms: Dictionary = {}
	var held: StringName = &""
	## Grenades in the pack.
	var grenades := 0
	var doors_open: Array = []
	## What the bot has bought, by shop item id (the client's count).
	var bought: Dictionary = {}
	## The tonics the bot has now, as the frame's bits (`PerkEffects.mask_of`): a perk lost when it
	## went down is bought again.
	var perks := 0
	## Where the crane stands (its place in the rules' list) and whether it can take a play.
	var crane_spot := 0
	## Whether the break announced a special round (the profile may fill up for it).
	var prepared := false
	## The health of the dead this round sends, when the bot weighs its weapons by it (0: not).
	var zombie_health := 0.0
	var crane_ready := true
	## Doors the etiquette holds the bot back from (a person's claim, a teammate down).
	var blocked: Dictionary = {}
	## A door a person pinged ("buy it"), or empty.
	var pinged: StringName = &""
	## The ammunition spot a person marked ("buy rounds here"), or `Vector3.INF`.
	var ammo_marked := Vector3.INF
	## Items refused lately, to the clock when the bot may try again.
	var denied: Dictionary = {}
	var now := 0.0
	## `Callable(stand: Vector3) -> bool`: true for a place the bot found it cannot walk to lately.
	var avoid := Callable()
	## `Callable(stand: Vector3) -> float`: the metres of walk to a stand on the mesh as it is
	## (`INF` for none), or unset when the bot has no legs to ask (the straight line then).
	var walk := Callable()
	## The ammunition stand the bot is already walking to (`Vector3.INF` for none): it is kept
	## unless another is clearly nearer, so a trip does not turn on every think.
	var heading := Vector3.INF

	func is_avoided(stand: Vector3) -> bool:
		return avoid.is_valid() and bool(avoid.call(stand))

	func is_calm() -> bool:
		return ignore_hour or in_break or lull or remaining <= calm_at

	func is_denied(item_id: StringName) -> bool:
		return denied.get(item_id, -INF) > now

	func firearm_count() -> int:
		var count := 0
		for id: StringName in arms:
			if not WeaponCatalog.get_def(id).is_melee():
				count += 1
		return count


func _init(shop: BotShop, profile: BotProfile) -> void:
	_shop = shop
	_profile = profile


## Every purchase the bot would make now, best first. Empty when it wants nothing it can pay for.
func candidates(view: View) -> Array[Buy]:
	var found: Array[Buy] = []
	var ping := _ping(view)
	if ping != null:
		found.append(ping)
	var marked := _ammo_ping(view)
	if marked != null:
		found.append(marked)
	for weapon in useful(view.arms):
		var urgent := _ammo(view, weapon, 1, URGENT, 0)
		if urgent != null:
			found.append(urgent)
	for weapon in useful(view.arms):
		var floor_buy := _ammo(view, weapon, _floor_mags(view), FLOOR, 0)
		if floor_buy != null:
			found.append(floor_buy)
	var reserve := _fuel_reserve(view)
	var next := next_price(view)
	for item_id in plan(view):
		var buy := _entry(view, _shop.item(item_id))
		if buy == null:
			continue
		if view.blocked.get(item_id, false):
			continue
		if buy.price + reserve <= view.points:
			found.append(buy)
		elif _profile.saves_for.has(item_id):
			break
	last_next = next
	for weapon in useful(view.arms):
		var top := _ammo(view, weapon, 0, TOP_OFF, next)
		if top != null:
			found.append(top)
	var grenades := _grenades(view, next)
	if grenades != null:
		found.append(grenades)
	return found


## The first purchase, or a none (`Buy.is_none`).
func choose(view: View) -> Buy:
	var found := candidates(view)
	return found[0] if not found.is_empty() else Buy.new()


## The item ids the bot is working through: the profile's list, then the doors it lacks in the shop
## table's order.
func plan(_view: View = null) -> Array[StringName]:
	var ids: Array[StringName] = []
	for item_id in _shop.shopping if not _shop.shopping.is_empty() else _profile.shopping:
		ids.append(item_id)
	for door_id in _shop.doors:
		if not ids.has(door_id):
			ids.append(door_id)
	return ids


## What the next thing on the list costs, whether or not the bot can pay now; 0 when the list is
## done. The soak holds a bot's points to twice this.
func next_price(view: View) -> int:
	var hour := view.ignore_hour
	view.ignore_hour = true
	var price := 0
	for item_id in plan(view):
		var buy := _entry(view, _shop.item(item_id))
		if buy != null:
			price = buy.price
			break
	view.ignore_hour = hour
	return price


## What the bot keeps back from the plan's purchases.
func _fuel_reserve(view: View) -> int:
	if _shop.fuel_item == null or view.round_number < RESERVE_FUEL_FROM:
		return 0
	return _shop.fuel_item.price_at(view.round_number)


# --- The list ---


## One entry of the list as a purchase, or null when the bot does not want it now (owned, locked,
## not worth taking, refused lately, nothing to do with it at this hour).
func _entry(view: View, item: ShopItem) -> Buy:
	var buy: Buy = null
	if item != null and not view.is_denied(item.id):
		match item.kind:
			ShopItem.Kind.DOOR:
				buy = _door(view, item)
			ShopItem.Kind.WEAPON:
				buy = _weapon(view, item)
			ShopItem.Kind.CRANE:
				buy = _crane(view, item)
			ShopItem.Kind.UPGRADE:
				buy = _recut(view, item)
			ShopItem.Kind.TONIC:
				buy = _tonic(view, item)
	return buy


func _door(view: View, item: ShopItem) -> Buy:
	if not view.is_calm():
		return null
	if not _shop.unlocked_doors(view.doors_open).has(item.id):
		return null
	var stand := _nearest_point(view, _shop.door_stands.get(item.id, []), RISE_WEIGHT)
	if stand == Vector3.INF:
		return null
	return _buy(view, item, stand, &"door", PLAN)


func _weapon(view: View, item: ShopItem) -> Buy:
	var weapon := WeaponCatalog.catalog_id(item.id)
	if not view.is_calm() or view.arms.has(weapon) or not worth_taking(view, weapon):
		return null
	var stand := _nearest(view, _shop.spots_of(item.id))
	if stand == Vector3.INF:
		return null
	return _buy(view, item, stand, &"weapon", PLAN)


func _crane(view: View, item: ShopItem) -> Buy:
	if not view.is_calm() or not view.crane_ready:
		return null
	var worth := false
	for prize in item.pool:
		var weapon := WeaponCatalog.catalog_id(prize)
		worth = worth or (not view.arms.has(weapon) and worth_taking(view, weapon))
	if not worth:
		return null
	var stands: Array[Dictionary] = []
	for spot in _shop.spots_of(item.id):
		if spot.get("crane_spot", 0) == view.crane_spot:
			stands.append(spot)
	var stand := _nearest(view, stands)
	if stand == Vector3.INF:
		return null
	return _buy(view, item, stand, &"crane", PLAN)


## The re-cut: the weapon in hand is a firearm that has not been re-cut, and the bot has not
## re-cut as many as its profile does.
func _recut(view: View, item: ShopItem) -> Buy:
	if not view.is_calm() or not view.arms.has(view.held):
		return null
	if WeaponCatalog.get_def(view.held).is_melee() or int(view.arms[view.held][2]) > 0:
		return null
	var cut := 0
	for counts: Array in view.arms.values():
		cut += 1 if int(counts[2]) > 0 else 0
	if cut >= _profile.re_cuts:
		return null
	var stand := _nearest(view, _shop.spots_of(item.id))
	if stand == Vector3.INF:
		return null
	return _buy(view, item, stand, &"recut", PLAN)


## A tonic is bought while the bot has not got it, up to the limit, and only one that does
## something (`ShopItem.effect`): a perk lost when the bot went down is bought again.
func _tonic(view: View, item: ShopItem) -> Buy:
	if not view.is_calm() or item.effect == ShopItem.Effect.NONE:
		return null
	var bit := _shop.tonic_order().find(item.id)
	if bit >= 0 and (view.perks & (1 << bit)) != 0:
		return null
	if PerkEffects.mask_count(view.perks) >= _shop.economy.max_tonics:
		return null
	var stand := _nearest(view, _shop.spots_of(item.id))
	if stand == Vector3.INF:
		return null
	return _buy(view, item, stand, &"tonic", PLAN)


## A door someone pinged, bought when it can be paid, whatever the list says.
func _ping(view: View) -> Buy:
	if view.pinged == &"" or view.is_denied(view.pinged):
		return null
	var item := _shop.item(view.pinged)
	if item == null or item.kind != ShopItem.Kind.DOOR or view.blocked.get(item.id, false):
		return null
	var buy := _door(view, item)
	if buy == null or buy.price > view.points:
		return null
	buy.why = PING
	return buy


## Rounds at the locker a person marked, for a gun the bot carries and is short of (under the
## profile's floor of magazines), in a lull; the pinged locker, not the nearest one. Null when the
## mark is no locker of the shop, the bot's hand cannot be fed there, or no gun is short.
func _ammo_ping(view: View) -> Buy:
	if not view.ammo_marked.is_finite() or not view.is_calm():
		return null
	var stand := _locker_at(view, view.ammo_marked)
	if stand == Vector3.INF:
		return null
	for weapon in useful(view.arms):
		if not _locker_sells(view, weapon):
			continue
		var buy := _ammo(view, weapon, _profile.ammo_floor_mags, AMMO_PING, 0, stand)
		if buy != null:
			return buy
	return null


## The shop's locker within `LOCKER_SNAP` of a marked point that the bot can walk to, or INF.
func _locker_at(view: View, point: Vector3) -> Vector3:
	for spot in _shop.spots_by_kind(&"ammo"):
		var at: Vector3 = spot["position"]
		if Vector2(at.x - point.x, at.z - point.z).length() <= LOCKER_SNAP:
			return Vector3.INF if view.is_avoided(at) else at
	return Vector3.INF


# --- Grenades ---


## Grenades from a rack, when the pack is under what the profile wants, there is room, the hour is
## calm and the purchase leaves `keep` points. Null otherwise.
func _grenades(view: View, keep: int) -> Buy:
	var item := _shop.economy.item(&"grenades") if _shop.economy != null else null
	if item == null or view.is_denied(item.id) or not view.is_calm():
		return null
	var count := mini(int(item.amount), _shop.max_grenades - view.grenades)
	if view.grenades >= _profile.grenades_wanted or count <= 0:
		return null
	var price := ceili(float(item.price_at(view.round_number)) * count / item.amount)
	var stand := _nearest(view, _shop.spots_by_kind(&"rack"))
	if stand == Vector3.INF or view.points - price < keep:
		return null
	var buy := Buy.new()
	buy.item = item.id
	buy.kind = ShopItem.Kind.GRENADES
	buy.price = price
	buy.stand = stand
	buy.prompt = &"grenades"
	buy.why = TOP_OFF
	return buy


# --- Rounds ---


## Rounds for `weapon` when its reserve is under `mags` magazines (0: whenever there is room) and
## the purchase leaves `keep` points. Null when the weapon is not worth rounds, the refill would
## fill under a tenth of the cap, nothing sells them or the bot cannot pay.
func _ammo(
	view: View, weapon: StringName, mags: int, why: StringName, keep: int, at := Vector3.INF
) -> Buy:
	var item := _shop.economy.ammo_item_for(weapon)
	if item == null or view.is_denied(item.id):
		return null
	var def := WeaponCatalog.get_def(weapon)
	var reserve := int(view.arms[weapon][1])
	var room := def.reserve_max - reserve
	if (
		not _wants_rounds(view, def, reserve, mags, why)
		or float(room) < float(def.reserve_max) * MIN_ROOM
	):
		return null
	var price := item.ammo_price(view.round_number, mini(room, int(item.amount)))
	var stand := at if at != Vector3.INF else _ammo_stand(view, weapon)
	if view.points - price < keep or stand == Vector3.INF:
		return null
	var buy := Buy.new()
	buy.item = item.id
	buy.kind = ShopItem.Kind.AMMO
	buy.price = price
	buy.stand = stand
	buy.prompt = &"ammo"
	buy.weapon = weapon
	buy.why = why
	return buy


## Whether a reserve of `reserve` rounds is short enough to buy for, at this hour: under `mags`
## magazines (0 for whenever there is room), and for a top-off under the share the profile fills to.
func _wants_rounds(view: View, def: WeaponDef, reserve: int, mags: int, why: StringName) -> bool:
	if (why == FLOOR or why == TOP_OFF) and not view.is_calm():
		return false
	if mags > 0 and reserve >= def.magazine_size * mags:
		return false
	return why != TOP_OFF or reserve < int(float(def.reserve_max) * _topoff(view))


## Magazines of reserve the bot keeps for each gun now: the profile's floor, or the larger one it
## fills up to in the break before a special round (the simulator's `PREPARED_MAGS`).
func _floor_mags(view: View) -> int:
	if view.prepared:
		return maxi(_profile.prepared_mags, _profile.ammo_floor_mags)
	return _profile.ammo_floor_mags


## The share of a gun's reserve limit a top-off fills to: all of it before a special round for a bot
## that prepares for them (the simulator tops up to the limit then, whatever the usual share).
func _topoff(view: View) -> float:
	if view.prepared and _profile.prepared_mags > 0:
		return 1.0
	return _profile.ammo_topoff


## Where rounds for `weapon` are sold: the wall of a weapon the bot owns, or a locker (which sells
## for the weapon in hand, so only when this is the one in hand or the hand holds a blade). The
## nearest by the walk, not the straight line: a locker behind a fence is a long way round.
func _ammo_stand(view: View, weapon: StringName) -> Vector3:
	var sources: Array[Dictionary] = []
	for spot in _shop.spots_by_kind(&"wall"):
		if WeaponCatalog.catalog_id(spot["shop_id"]) == weapon:
			sources.append(spot)
	if _locker_sells(view, weapon):
		sources.append_array(_shop.spots_by_kind(&"ammo"))
	return nearest_by_walk(view, sources)


## The position of the spot with the shortest walk from the bot, among the `WALK_LOOKS` nearest by
## the straight line that it can walk to; the straight line decides when the bot cannot ask (a
## test without legs) and `Vector3.INF` when there is none. A stand the bot is already heading to
## counts `HEADING_CREDIT` metres nearer.
static func nearest_by_walk(view: View, spots: Array[Dictionary]) -> Vector3:
	var near: Array[Dictionary] = []
	for spot in spots:
		if not view.is_avoided(spot["position"]):
			near.append(spot)
	near.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _apart(view.here, a["position"]) < _apart(view.here, b["position"])
	)
	var best := Vector3.INF
	var best_walk := INF
	for spot in near.slice(0, WALK_LOOKS):
		var at: Vector3 = spot["position"]
		var walk := _apart(view.here, at)
		if view.walk.is_valid():
			walk = float(view.walk.call(at))
		if _apart(view.heading, at) < LOCKER_SNAP:
			walk -= HEADING_CREDIT
		if walk < best_walk:
			best_walk = walk
			best = at
	return best


## Whether a locker sells rounds for `weapon`: it sells for the weapon in hand, and a blade in hand
## is put away at the locker (`BotErrands`) for the gun in the pack.
func _locker_sells(view: View, weapon: StringName) -> bool:
	var held_is_blade := view.arms.has(view.held) and WeaponCatalog.get_def(view.held).is_melee()
	return view.held == weapon or held_is_blade


## The carried firearms worth rounds, best first: at least `USEFUL_SHARE` of the best one's
## sustained damage a second (the simulator's rule).
static func useful(arms: Dictionary) -> Array[StringName]:
	var best := 0.0
	for id: StringName in arms:
		best = maxf(best, _rate(id))
	var found: Array[StringName] = []
	for id: StringName in arms:
		if _rate(id) > 0.0 and _rate(id) >= best * USEFUL_SHARE:
			found.append(id)
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return _rate(a) > _rate(b))
	return found


## The sustained damage a second of a firearm (0 for a blade).
static func _rate(id: StringName) -> float:
	if not _dps.has(id):
		var def := WeaponCatalog.get_def(id)
		_dps[id] = 0.0 if def.is_melee() else WeaponWorth.sustained_dps(def)
	return _dps[id]


## Whether a weapon (a catalogue id) is worth taking: a free hand takes anything, full hands only a
## weapon worth `WeaponWorth.REPLACE_GAIN` times the weakest one carried. The hands give up the one
## in hand, so the bot puts the weakest in hand before it pays (`BotErrands`).
static func worth_taking(view: View, weapon: StringName) -> bool:
	var health := view.zombie_health
	if view.arms.size() < WeaponCatalog.CARRY_LIMIT:
		# A bot that weighs by the round puts a free hand against the quick melee it has anyway.
		return (
			health <= 0.0
			or WeaponWorth.beats(WeaponCatalog.get_def(weapon), WeaponCatalog.quick_melee(), health)
		)
	var weakest := weakest_of(view.arms, health)
	return (
		weakest == &""
		or WeaponWorth.beats(WeaponCatalog.get_def(weapon), WeaponCatalog.get_def(weakest), health)
	)


## The carried weapon worth least (a blade by its blows, a gun by its sustained damage), or empty.
static func weakest_of(arms: Dictionary, health := 0.0) -> StringName:
	var weakest: StringName = &""
	var least := INF
	for id: StringName in arms:
		var worth := WeaponWorth.of(WeaponCatalog.get_def(id), health)
		if worth < least:
			least = worth
			weakest = id
	return weakest


# --- Helpers ---


func _buy(view: View, item: ShopItem, stand: Vector3, prompt: StringName, why: StringName) -> Buy:
	var buy := Buy.new()
	buy.item = item.id
	buy.kind = item.kind
	buy.price = item.price_at(view.round_number)
	buy.stand = stand
	buy.prompt = prompt
	buy.why = why
	return buy


## The point of `points` nearest to `from` (flat), or `Vector3.INF`.
static func nearest_to(points: Array, from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_apart := INF
	for point: Vector3 in points:
		var apart := Vector2(from.x - point.x, from.z - point.z).length()
		if apart < best_apart:
			best_apart = apart
			best = point
	return best


## The point nearest to the bot (flat) that it can walk to, or `Vector3.INF`.
static func _nearest_point(view: View, points: Array, rise := 0.0) -> Vector3:
	var spots: Array[Dictionary] = []
	for point: Vector3 in points:
		spots.append({"position": point})
	return _nearest(view, spots, rise)


static func _apart(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length() if a.is_finite() and b.is_finite() else INF


## The position of the spot nearest to the bot (flat) that it can walk to, or `Vector3.INF`.
static func _nearest(view: View, spots: Array[Dictionary], rise := 0.0) -> Vector3:
	var from := view.here
	var best := Vector3.INF
	var best_apart := INF
	for spot in spots:
		if view.is_avoided(spot["position"]):
			continue
		var apart := Vector2(from.x - spot["position"].x, from.z - spot["position"].z).length()
		apart += rise * absf(from.y - spot["position"].y)
		if apart < best_apart:
			best_apart = apart
			best = spot["position"]
	return best
