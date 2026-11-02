class_name SimWeapons
extends RefCounted
## What the modelled players shoot: the game's own weapons. Every number is read from the
## definitions in `gameplay/weapons/defs/` (`WeaponCatalog`) and priced with `DamageModel`, the
## functions the combat server uses, so the simulator and the night cannot drift apart. What the
## simulator adds is only timing: a trigger pull every `fire_interval`, a reload when the magazine
## is empty.
##
## Not modelled: penetration, and the flare gun's splash on a crowd beyond the zombies on the same
## side.

const START := &"pistol"
## Carried from the first moment: the revolver in hand and the crowbar, which never runs dry.
const START_ARMS: Array[StringName] = [&"pistol", &"crowbar"]

static var _defs: Dictionary[StringName, WeaponDef] = {}


## The definition behind a shop or crane id (`weapon_rifle`) or a catalogue id (`rifle`).
static func def(weapon_id: StringName) -> WeaponDef:
	var key := WeaponCatalog.catalog_id(weapon_id)
	if not _defs.has(key):
		_defs[key] = WeaponCatalog.get_def(key)
	return _defs[key]


## Loads every definition now, so batches run on several threads only ever read the cache.
static func warm() -> void:
	for id in WeaponCatalog.IDS:
		def(id)


## Damage of one trigger pull that lands in `zone` at `distance` metres: every pellet, with the
## weapon's own falloff and zone multiplier.
static func damage(weapon_id: StringName, zone: StringName, distance: float) -> float:
	return damage_of(def(weapon_id), zone, distance)


## The same for a definition in hand: the ones the night derives (a re-cut weapon) are not in
## the catalogue.
static func damage_of(weapon: WeaponDef, zone: StringName, distance: float) -> float:
	return float(weapon.pellets) * DamageModel.damage(weapon, distance, zone)


## Blast damage a neighbour `apart` metres from the burst takes (0 for a weapon without a blast).
static func splash(weapon_id: StringName, apart: float) -> float:
	return DamageModel.splash(def(weapon_id), apart)


static func splash_of(weapon: WeaponDef, apart: float) -> float:
	return DamageModel.splash(weapon, apart)


## Seconds between two trigger pulls.
static func interval(weapon_id: StringName) -> float:
	return def(weapon_id).fire_interval


static func magazine(weapon_id: StringName) -> int:
	return def(weapon_id).magazine_size


static func reload_seconds(weapon_id: StringName) -> float:
	return def(weapon_id).reload_time


## Damage a second on the body at point blank, reloads included: what the player picks by. With a
## `health` (the walker the round sends) it is the health of the zombies killed a second instead:
## shots land whole, so a blow that overshoots the health wastes the rest (a 95 damage rifle against
## 117 health needs two, and does no better than a weapon of 60).
static func sustained_dps(weapon_id: StringName, health: float = 0.0) -> float:
	return sustained_dps_of(def(weapon_id), health)


static func sustained_dps_of(weapon: WeaponDef, health: float = 0.0) -> float:
	return WeaponWorth.sustained_dps(weapon, health)


## Health of zombies a second a loaded weapon kills `distance` metres away, shots landing whole
## against a zombie of `health` (`sustained_dps` with a health, reloads left out).
static func kill_rate_at(weapon_id: StringName, distance: float, health: float) -> float:
	return kill_rate_of(def(weapon_id), distance, health)


static func kill_rate_of(weapon: WeaponDef, distance: float, health: float) -> float:
	var shots := ceilf(health / maxf(damage_of(weapon, &"body", distance), 0.001))
	return health / (shots * weapon.fire_interval)


static func is_melee(weapon_id: StringName) -> bool:
	return def(weapon_id).is_melee()


## Health of zombies a second a melee weapon kills at arm's length, a blow landing whole against a
## zombie of `health` (the damage a second of a blow with none).
static func melee_rate_of(weapon: WeaponDef, health: float = 0.0) -> float:
	return WeaponWorth.melee_rate(weapon, health)


## What a weapon is worth in the hands: a melee weapon by its blows, a firearm by its sustained
## damage, against zombies of `health`. The player gives up the one worth least for a third weapon.
static func worth_of(weapon: WeaponDef, health: float = 0.0) -> float:
	return WeaponWorth.of(weapon, health)


## The melee weapon to fall back on from those carried: the one that kills fastest, the crowbar when
## no other is carried.
static func best_melee(arms: Dictionary, health: float = 0.0) -> StringName:
	var best_id: StringName = &"crowbar"
	var best_rate := melee_rate_of(def(best_id), health)
	for weapon_id: StringName in arms:
		if not is_melee(weapon_id):
			continue
		var rate := melee_rate_of(arms[weapon_id].def(), health)
		if rate > best_rate:
			best_rate = rate
			best_id = weapon_id
	return best_id


## The weapon to take in hand from those carried (`NightSim.SimArm`): the best firearm by
## sustained damage that has any rounds left, else the best melee weapon.
static func best_armed(arms: Dictionary, health: float = 0.0) -> StringName:
	var best_id := best_melee(arms, health)
	var best_dps := -1.0
	for weapon_id: StringName in arms:
		if is_melee(weapon_id) or arms[weapon_id].mag + arms[weapon_id].reserve <= 0:
			continue
		var dps := sustained_dps_of(arms[weapon_id].def(), health)
		if dps > best_dps:
			best_dps = dps
			best_id = weapon_id
	return best_id


## The best weapon among those owned, by sustained damage per second.
static func best(owned: Array[StringName]) -> StringName:
	var best_id := START
	var best_dps := sustained_dps(START)
	for weapon_id in owned:
		var dps := sustained_dps(weapon_id)
		if dps > best_dps:
			best_dps = dps
			best_id = weapon_id
	return best_id
