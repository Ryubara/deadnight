class_name BotArsenal
extends RefCounted
## What a bot does with the weapons it carries: which to hold, when to reload and when to put the
## gun away for the crowbar. A weapon is ranked by the damage it does a second to a zombie at the
## range of the fight (`WeaponWorth.sustained_dps`, reloads included, scaled by the falloff of the
## distance), the same ranking the balance simulator's players use, so the bot and the model tell
## the same story. Pure: the frame's `me` entry, the weapon in hand and two distances in; a plan
## out.
##
## - A forced reload when the magazine is dry and there is reserve; but with a zombie close and
##   another gun loaded, the swap is quicker than the reload, so the bot swaps.
## - A tactical reload when the magazine is low and nothing is near (`LOW_MAGAZINE`, `RELOAD_SAFE`),
##   and a top-up in a lull when it is not full (`TOP_UP_BELOW`, `LULL`).
## - The flare gun is put away for a loaded gun as soon as it is in hand (it is held for one shot).
## - A swap to the better loaded weapon when it is `SWITCH_GAIN` times better at this range, and to
##   whatever has rounds when the weapon in hand has none (a gun with rounds in reserve only counts:
##   it is reloaded once in hand); the crowbar when every gun is dry.

## Metres from a zombie inside which a tactical reload waits.
const RELOAD_SAFE := 8.0
## Share of a magazine under which a quiet moment is used to reload, and the share a lull tops it
## up to; the metres with nothing near that make a lull.
const LOW_MAGAZINE := 0.3
const TOP_UP_BELOW := 0.7
const LULL := 16.0
## The distance at which a dry gun is swapped rather than reloaded, when another weapon is loaded.
const SWAP_INSTEAD := 4.5
## How many times better a loaded weapon must be to be taken in place of one that has rounds
## (`NightSim.SWITCH_GAIN`).
const SWITCH_GAIN := 1.4
## Seconds a swap is not asked for again.
const SWAP_PAUSE := 0.6


## What to do now: `reload` and `swap` are button edges.
class Plan:
	extends RefCounted
	var reload := false
	var swap := false
	## True when no firearm has a round left, so a melee swing is all the bot can do.
	var dry := false


## Plans one think. `distance` is how far the zombie it fights is (INF for none), `threat` how
## far the nearest one is.
static func plan(me: Dictionary, held: WeaponDef, distance: float, threat: float) -> Plan:
	var out := Plan.new()
	if held == null:
		return out
	var arms: Dictionary = me.get("arms", {})
	var reloading: bool = me.get("reloading", false)
	var ammo: int = me.get("ammo", 0)
	var reserve: int = me.get("reserve", 0)
	var here_range := distance if distance < INF else 0.0
	out.dry = not has_rounds(arms)
	var best := best_loaded(arms, held, here_range)
	if held.is_lure():
		# The flare gun is a tool for one shot (`BotFlare`), not a gun for the fight: put it away
		# for a loaded gun (or the blade) as soon as it is in hand and no flare is ordered.
		out.swap = best != &"" or melee_in(arms, held) != &""
		out.reload = not out.swap and ammo <= 0 and reserve > 0 and not reloading
		return out
	if held.is_melee():
		# Take a gun that can fire, whenever one can (it hits from afar); a gun with no magazine
		# but rounds in reserve is taken too when nothing is near enough to need the blow.
		if best != &"" or (reserve_gun(arms, held) != &"" and threat > RELOAD_SAFE):
			out.swap = true
		return out
	if reloading:
		return out
	if ammo <= 0:
		var other := best != &"" or melee_in(arms, held) != &""
		if reserve > 0 and not (other and threat <= SWAP_INSTEAD):
			out.reload = true
		else:
			# Nothing loaded to swap to: a gun with rounds only in reserve is taken to be reloaded,
			# rather than standing with an empty one in hand (the nightly soak found bots doing so).
			out.swap = other or (reserve <= 0 and reserve_gun(arms, held) != &"")
		return out
	if best != &"" and best != held.id and _better(best, held, here_range):
		out.swap = true
		return out
	if reserve > 0:
		var share := float(ammo) / float(maxi(held.magazine_size, 1))
		if share < LOW_MAGAZINE and threat > RELOAD_SAFE:
			out.reload = true
		elif share < TOP_UP_BELOW and threat > LULL:
			out.reload = true
	return out


## Whether any firearm carried has a round, in the magazine or in reserve (the flare gun is no
## firearm for the fight).
static func has_rounds(arms: Dictionary) -> bool:
	for id: StringName in arms:
		var def := WeaponCatalog.get_def(id)
		if def.is_melee() or def.is_lure():
			continue
		var counts: Array = arms[id]
		if int(counts[0]) + int(counts[1]) > 0:
			return true
	return false


## The carried firearm (not `held`) with a loaded magazine that does the most to a zombie
## `distance` away, or empty.
static func best_loaded(arms: Dictionary, held: WeaponDef, distance: float) -> StringName:
	var best := &""
	var best_worth := 0.0
	for id: StringName in arms:
		if id == held.id:
			continue
		var def := WeaponCatalog.get_def(id)
		var counts: Array = arms[id]
		if def.is_melee() or def.is_lure() or int(counts[0]) <= 0:
			continue
		var worth := worth_at(def, distance)
		if worth > best_worth:
			best_worth = worth
			best = id
	return best


## A carried firearm (not `held`) with rounds in reserve only (an empty magazine).
static func reserve_gun(arms: Dictionary, held: WeaponDef) -> StringName:
	for id: StringName in arms:
		var def := WeaponCatalog.get_def(id)
		if id == held.id or def.is_melee() or def.is_lure():
			continue
		var counts: Array = arms[id]
		if int(counts[0]) <= 0 and int(counts[1]) > 0:
			return id
	return &""


## The carried melee weapon that is not `held`, or empty.
static func melee_in(arms: Dictionary, held: WeaponDef) -> StringName:
	for id: StringName in arms:
		if id != held.id and WeaponCatalog.get_def(id).is_melee():
			return id
	return &""


## Damage a second `def` does to a zombie `distance` metres away (reloads in, falloff of the range).
static func worth_at(def: WeaponDef, distance: float) -> float:
	var near := DamageModel.damage(def, 0.0, &"body")
	var far := DamageModel.damage(def, distance, &"body")
	return WeaponWorth.of(def) * far / maxf(near, 0.001)


static func _better(id: StringName, held: WeaponDef, distance: float) -> bool:
	return worth_at(WeaponCatalog.get_def(id), distance) >= worth_at(held, distance) * SWITCH_GAIN
