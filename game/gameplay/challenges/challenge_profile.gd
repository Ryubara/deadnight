class_name ChallengeProfile
extends RefCounted
## One player's challenge state: the dailies they hold (today's and the banked), their three
## Concession Orders, and the lifetime totals the milestones read. Plain data that round-trips
## through `to_dict` / `from_dict` (the save, `ChallengeSave`); it holds facts and derives the
## rest, so retuning a target or adding a milestone step needs no migration.
##
## The rules (docs/design/progression.md#daily-challenges-orders-and-milestones):
## - A day deals three dailies (`DailyRotation`). At the next day the finished ones leave and the
##   unfinished ones bank, up to three; a fourth retires the oldest. Banked dailies keep counting.
## - Three orders are open at a time, no timer. A finished order is replaced when the night is
##   settled; a player may swap one for another at any time, free, losing only its own progress.
## - Milestones are ladders over lifetime totals; the rung reached is derived, never stored.
## - `apply` advances everything the stat touches and answers what moved, for the prompt.

const SCHEMA_VERSION := 1
const BANK_LIMIT := 3
const ORDER_SLOTS := 3
## An order finished lately is not dealt again at once.
const RECENT_ORDERS := 3
## A challenge this small prompts only when done: a quarter of 3 is no step worth saying.
const MIN_TARGET_FOR_CHECKPOINTS := 4
const CHECKPOINTS: Array[int] = [25, 50, 75, 100]
const SEED_MASK := 0x7fffffff

## The last day dailies were dealt for (-1: never).
var dealt_day := -1
## Each: `{id, day (dealt), progress}`. Today's first, then the banked, newest first (the oldest is
## last, and retires first).
var dailies: Array[Dictionary] = []
## Each: `{id, progress}`; at most `ORDER_SLOTS`.
var orders: Array[Dictionary] = []
var order_seed := 1
var order_draws := 0
var recent_orders: Array[StringName] = []
## Lifetime totals by stat (a best stat holds the most reached).
var lifetime: Dictionary = {}
## How many dailies and orders were ever finished: `{daily, order}`.
var finished := {"daily": 0, "order": 0}
## Counts saves, for the backend's optimistic concurrency later.
var revision := 0


## A fresh profile; `p_order_seed` picks which orders it is dealt (a small number).
static func fresh(p_order_seed: int = 1) -> ChallengeProfile:
	var profile := ChallengeProfile.new()
	profile.order_seed = p_order_seed & SEED_MASK
	return profile


## How many of the quarter marks a move from `before` to `after` of `target` crossed, as the
## highest percent (25, 50, 75 or 100), or 0. Small targets only have 100.
static func checkpoint_crossed(before: int, after: int, target: int) -> int:
	var best := 0
	var marks: Array[int] = [100]
	if target >= MIN_TARGET_FOR_CHECKPOINTS:
		marks = CHECKPOINTS
	for mark in marks:
		if before * 100 < mark * target and after * 100 >= mark * target:
			best = mark
	return best


# --- Dealing ---


## Moves to `day`: finished dailies go, unfinished ones bank (the oldest retired past the limit),
## and the day's three are dealt (a banked one dealt again is today's, its progress kept). Also
## drops anything the catalogue no longer has and fills the order slots. Answers the ids retired.
func refresh(catalog: ChallengeCatalog, day: int) -> Array[StringName]:
	_prune(catalog)
	fill_orders(catalog)
	if day <= dealt_day:
		return []
	var today := DailyRotation.deal(catalog, day)
	var open: Array[Dictionary] = []
	for entry in dailies:
		if not _is_done(entry, catalog):
			open.append(entry)
	var banked: Array[Dictionary] = []
	var next: Array[Dictionary] = []
	for id in today:
		var carried := _take(open, id)
		next.append({"id": id, "day": day, "progress": int(carried.get("progress", 0))})
	banked.assign(open)
	var retired: Array[StringName] = []
	while banked.size() > BANK_LIMIT:
		retired.append(StringName(banked.pop_back()["id"]))
	next.append_array(banked)
	dailies = next
	dealt_day = day
	return retired


## Tops the order slots up from the pool. Never deals two of one, and not one finished lately
## unless nothing else is left.
func fill_orders(catalog: ChallengeCatalog) -> void:
	while orders.size() < ORDER_SLOTS:
		var id := _draw_order(catalog, &"")
		if id == &"":
			return
		orders.append({"id": id, "progress": 0})


## Replaces the order in `slot` with another from the pool (free, unlimited); its progress goes.
func swap_order(catalog: ChallengeCatalog, slot: int) -> bool:
	if slot < 0 or slot >= orders.size():
		return false
	var replacement := _draw_order(catalog, StringName(orders[slot]["id"]))
	if replacement == &"":
		return false
	orders[slot] = {"id": replacement, "progress": 0}
	return true


## Replaces the orders that are done with new ones; call it when a night is over and on load.
func settle(catalog: ChallengeCatalog) -> void:
	var keep: Array[Dictionary] = []
	for entry in orders:
		if _is_done(entry, catalog):
			recent_orders.append(StringName(entry["id"]))
			while recent_orders.size() > RECENT_ORDERS:
				recent_orders.pop_front()
		else:
			keep.append(entry)
	orders = keep
	fill_orders(catalog)


func _draw_order(catalog: ChallengeCatalog, also_not: StringName) -> StringName:
	var open: Array[StringName] = []
	for entry in orders:
		open.append(StringName(entry["id"]))
	var pool: Array[ChallengeDef] = catalog.of_family(ChallengeDef.Family.ORDER)
	var fresh_pool: Array[ChallengeDef] = pool.filter(
		func(def: ChallengeDef) -> bool:
			return def.id != also_not and not open.has(def.id) and not recent_orders.has(def.id)
	)
	if fresh_pool.is_empty():
		fresh_pool = pool.filter(
			func(def: ChallengeDef) -> bool: return def.id != also_not and not open.has(def.id)
		)
	if fresh_pool.is_empty():
		return &""
	var rng := RandomNumberGenerator.new()
	rng.seed = (order_seed * 7919 + order_draws) & SEED_MASK
	order_draws += 1
	return fresh_pool[rng.randi_range(0, fresh_pool.size() - 1)].id


func _prune(catalog: ChallengeCatalog) -> void:
	dailies = dailies.filter(func(e: Dictionary) -> bool: return catalog.has(e["id"]))
	orders = orders.filter(func(e: Dictionary) -> bool: return catalog.has(e["id"]))


func _take(entries: Array[Dictionary], id: StringName) -> Dictionary:
	for i in entries.size():
		if entries[i]["id"] == id:
			return entries.pop_at(i)
	return {}


func _is_done(entry: Dictionary, catalog: ChallengeCatalog) -> bool:
	var def := catalog.get_def(StringName(entry["id"]))
	return def != null and int(entry["progress"]) >= def.target


# --- Counting ---


## A night moved `stat` to `value` (its count this night), `delta` more than before. Advances every
## daily and order that counts it and the milestones over it. Answers one dictionary per thing
## that moved: `{id, family, text, before, after, target, checkpoint, completed, rung, rungs}`
## (`checkpoint` is 25/50/75/100 when a quarter mark was crossed, else 0; `rung` is the milestone
## step just reached, else 0).
func apply(
	catalog: ChallengeCatalog, stat: StringName, value: int, delta: int
) -> Array[Dictionary]:
	var moved: Array[Dictionary] = []
	for entry in dailies:
		_advance(catalog, entry, stat, value, delta, moved)
	for entry in orders:
		_advance(catalog, entry, stat, value, delta, moved)
	var before := int(lifetime.get(stat, 0))
	var after := maxi(before, value) if ChallengeStats.is_best(stat) else before + delta
	lifetime[stat] = after
	if after != before:
		for def in catalog.of_family(ChallengeDef.Family.MILESTONE):
			if def.stat == stat:
				_climb(def, before, after, moved)
	return moved


func _advance(
	catalog: ChallengeCatalog,
	entry: Dictionary,
	stat: StringName,
	value: int,
	delta: int,
	moved: Array[Dictionary]
) -> void:
	var def := catalog.get_def(StringName(entry["id"]))
	if def == null or def.stat != stat:
		return
	var before := int(entry["progress"])
	if before >= def.target:
		return
	var after := before + delta if def.mode == ChallengeDef.Mode.TOTAL else maxi(before, value)
	if after == before:
		return
	entry["progress"] = after
	var done := after >= def.target
	if done:
		var kind := "daily" if def.family == ChallengeDef.Family.DAILY else "order"
		finished[kind] = int(finished[kind]) + 1
	(
		moved
		. append(
			{
				"id": def.id,
				"family": def.family,
				"text": def.words(),
				"before": before,
				"after": mini(after, def.target),
				"target": def.target,
				"checkpoint": checkpoint_crossed(before, after, def.target),
				"completed": done,
				"rung": 0,
				"rungs": 0,
			}
		)
	)


func _climb(def: ChallengeDef, before: int, after: int, moved: Array[Dictionary]) -> void:
	var was := rung_of(def, before)
	var now := rung_of(def, after)
	if now <= was:
		return
	(
		moved
		. append(
			{
				"id": def.id,
				"family": def.family,
				"text": def.words(def.steps[now - 1]),
				"before": before,
				"after": after,
				"target": def.steps[now - 1],
				"checkpoint": 0,
				"completed": now == def.steps.size(),
				"rung": now,
				"rungs": def.steps.size(),
			}
		)
	)


## How many steps of a ladder a lifetime `value` has reached.
static func rung_of(def: ChallengeDef, value: int) -> int:
	var rung := 0
	for step in def.steps:
		if value >= step:
			rung += 1
	return rung


# --- The save ---


func to_dict() -> Dictionary:
	return {
		"dealt_day": dealt_day,
		"dailies": dailies.map(_entry_out),
		"orders": orders.map(_entry_out),
		"order_seed": order_seed,
		"order_draws": order_draws,
		"recent_orders": recent_orders.map(func(id: StringName) -> String: return String(id)),
		"lifetime": _strings(lifetime),
		"finished": finished.duplicate(),
		"revision": revision,
	}


## Reads a dictionary written by `to_dict` (version 1). A wrong or missing field falls back to its
## starting value, a malformed entry is dropped: a damaged save never breaks a night.
static func from_dict(data: Dictionary) -> ChallengeProfile:
	var profile := ChallengeProfile.new()
	profile.dealt_day = int(data.get("dealt_day", -1))
	profile.order_seed = int(data.get("order_seed", 1)) & SEED_MASK
	profile.order_draws = maxi(0, int(data.get("order_draws", 0)))
	profile.revision = maxi(0, int(data.get("revision", 0)))
	for entry: Variant in _list(data.get("dailies")):
		if entry is Dictionary and entry.has("id"):
			(
				profile
				. dailies
				. append(
					{
						"id": StringName(entry["id"]),
						"day": int(entry.get("day", profile.dealt_day)),
						"progress": maxi(0, int(entry.get("progress", 0))),
					}
				)
			)
	for entry: Variant in _list(data.get("orders")):
		if entry is Dictionary and entry.has("id") and profile.orders.size() < ORDER_SLOTS:
			profile.orders.append(
				{"id": StringName(entry["id"]), "progress": maxi(0, int(entry.get("progress", 0)))}
			)
	for id: Variant in _list(data.get("recent_orders")):
		profile.recent_orders.append(StringName(str(id)))
	var totals: Variant = data.get("lifetime")
	if totals is Dictionary:
		for stat: Variant in totals:
			profile.lifetime[StringName(str(stat))] = maxi(0, int(totals[stat]))
	var done: Variant = data.get("finished")
	if done is Dictionary:
		profile.finished["daily"] = maxi(0, int(done.get("daily", 0)))
		profile.finished["order"] = maxi(0, int(done.get("order", 0)))
	return profile


## An entry with its id as a plain string, as JSON wants it.
static func _entry_out(entry: Dictionary) -> Dictionary:
	var out := entry.duplicate()
	out["id"] = String(entry["id"])
	return out


static func _list(value: Variant) -> Array:
	return value if value is Array else []


static func _strings(source: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in source:
		out[String(key)] = source[key]
	return out
