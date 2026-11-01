class_name SimWeapons
extends RefCounted
## What the modelled players shoot: the game's own weapons. Every number is read from the
## definitions in `gameplay/weapons/defs/` (`WeaponCatalog`) and priced with `DamageModel`, the
## functions the combat server uses, so the simulator and the night cannot drift apart. What the
## simulator adds is only timing: a trigger pull every `fire_interval`, a reload when the magazine
## is empty.
##
## Not modelled: ammunition left (the night resupplies every round and #152 will replace that),
## penetration, and the flare gun's splash on a crowd beyond the zombies on the same side.

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


## Damage a second on the body at point blank, reloads included: what the player picks by.
static func sustained_dps(weapon_id: StringName) -> float:
	var weapon := def(weapon_id)
	var cycle := float(weapon.magazine_size) * weapon.fire_interval + weapon.reload_time
	return damage(weapon_id, &"body", 0.0) * float(weapon.magazine_size) / cycle


static func is_melee(weapon_id: StringName) -> bool:
	return def(weapon_id).is_melee()


## The weapon to take in hand from those carried (`NightSim.SimArm`): the best firearm by
## sustained damage that has any rounds left, else the crowbar.
static func best_armed(arms: Dictionary) -> StringName:
	var best_id: StringName = &"crowbar"
	var best_dps := -1.0
	for weapon_id: StringName in arms:
		if is_melee(weapon_id) or arms[weapon_id].mag + arms[weapon_id].reserve <= 0:
			continue
		var dps := sustained_dps(weapon_id)
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
