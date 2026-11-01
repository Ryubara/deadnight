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
	var weapon := def(weapon_id)
	return float(weapon.pellets) * DamageModel.damage(weapon, distance, zone)


## Blast damage a neighbour `apart` metres from the burst takes (0 for a weapon without a blast).
static func splash(weapon_id: StringName, apart: float) -> float:
	return DamageModel.splash(def(weapon_id), apart)


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
	var weapon := def(weapon_id)
	var cycle := float(weapon.magazine_size) * weapon.fire_interval + weapon.reload_time
	var per_shot := damage(weapon_id, &"body", 0.0)
	if health <= 0.0:
		return per_shot * float(weapon.magazine_size) / cycle
	var shots := ceilf(health / maxf(per_shot, 0.001))
	return health * float(weapon.magazine_size) / shots / cycle


## Health of zombies a second a loaded weapon kills `distance` metres away, shots landing whole
## against a zombie of `health` (`sustained_dps` with a health, reloads left out).
static func kill_rate_at(weapon_id: StringName, distance: float, health: float) -> float:
	var shots := ceilf(health / maxf(damage(weapon_id, &"body", distance), 0.001))
	return health / (shots * interval(weapon_id))


static func is_melee(weapon_id: StringName) -> bool:
	return def(weapon_id).is_melee()


## The weapon to take in hand from those carried (`NightSim.SimArm`): the best firearm by
## sustained damage that has any rounds left, else the crowbar.
static func best_armed(arms: Dictionary, health: float = 0.0) -> StringName:
	var best_id: StringName = &"crowbar"
	var best_dps := -1.0
	for weapon_id: StringName in arms:
		if is_melee(weapon_id) or arms[weapon_id].mag + arms[weapon_id].reserve <= 0:
			continue
		var dps := sustained_dps(weapon_id, health)
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
