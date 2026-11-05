class_name WallTier
extends RefCounted
## Which weapons a wall spot may sell (#858): the weaker guns, on every map, and never a melee
## weapon (#910). A weapon has a wall tier, set on its definition (`WeaponDef.wall_tier`, #972); a
## wall sells up to `MAX_WALL` and everything above it comes only from the prize crane (the box). A
## definition that does not set one is `BOX`, so a gun added to the catalogue is box-only until
## someone decides it may hang on a wall. A melee weapon is `BOX` whatever its definition says: it
## never runs dry, so "weaker" does not apply. The rule is written in `docs/design/weapons.md`
## ("The wall tier"); `test_wall_tier.gd` holds both maps to it.
##
## Not to be confused with a weapon's re-cut tier (`WeaponCatalog.get_def_at`, `UpgradeTuning`).

## Hand weapons and the sidearms: the House Pistol, the revolver and the flare gun.
const HAND := 1
## The older long guns: the double-barrel, the Tommy gun and the hunting rifle (the best of a wall).
const LONG := 2
## Everything above: bought only from the box.
const BOX := 3

## The highest tier a wall spot may sell.
const MAX_WALL := LONG


## The wall tier of a weapon, by catalogue id (`rifle`) or shop id (`weapon_rifle`).
static func tier_of(weapon_id: StringName) -> int:
	if is_melee(weapon_id):
		return BOX
	var id := WeaponCatalog.catalog_id(weapon_id)
	return WeaponCatalog.get_def(id).wall_tier if WeaponCatalog.has(id) else BOX


## Whether a wall spot may sell this weapon.
static func wall_may_sell(weapon_id: StringName) -> bool:
	return tier_of(weapon_id) <= MAX_WALL


## Whether the weapon is a hand weapon (the crowbar, the bat, the axe); none hangs on a wall.
static func is_melee(weapon_id: StringName) -> bool:
	var id := WeaponCatalog.catalog_id(weapon_id)
	return WeaponCatalog.has(id) and WeaponCatalog.get_def(id).is_melee()
