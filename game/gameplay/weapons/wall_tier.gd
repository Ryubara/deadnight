class_name WallTier
extends RefCounted
## Which weapons a wall spot may sell (#858): the weaker guns, on every map. A weapon has a wall
## tier; a wall sells up to `MAX_WALL` and everything above it comes only from the prize crane
## (the box). A weapon this table does not name is `BOX`, so a gun added to the catalogue is
## box-only until someone decides it may hang on a wall. The rule is written in
## `docs/design/weapons.md` ("The wall tier"); `test_wall_tier.gd` holds both maps to it.
##
## Not to be confused with a weapon's re-cut tier (`WeaponCatalog.get_def_at`, `UpgradeTuning`).

## Hand weapons and the sidearm: the start weapon and the blades, the flare gun.
const HAND := 1
## The older long guns: the double-barrel, the Tommy gun and the hunting rifle (the best of a wall).
const LONG := 2
## Everything above: bought only from the box.
const BOX := 3

## The highest tier a wall spot may sell.
const MAX_WALL := LONG

## The weapons that have a wall tier, by catalogue id. Every other id is `BOX`.
const TIERS: Dictionary[StringName, int] = {
	&"house_pistol": HAND,
	&"pistol": HAND,
	&"crowbar": HAND,
	&"baseball_bat": HAND,
	&"fire_axe": HAND,
	&"flare_gun": HAND,
	&"shotgun": LONG,
	&"smg": LONG,
	&"rifle": LONG,
}


## The wall tier of a weapon, by catalogue id (`rifle`) or shop id (`weapon_rifle`).
static func tier_of(weapon_id: StringName) -> int:
	return TIERS.get(WeaponCatalog.catalog_id(weapon_id), BOX)


## Whether a wall spot may sell this weapon.
static func wall_may_sell(weapon_id: StringName) -> bool:
	return tier_of(weapon_id) <= MAX_WALL
