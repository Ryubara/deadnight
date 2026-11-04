class_name WeaponWorth
extends RefCounted
## What a weapon is worth in a player's hands, for the players that decide for themselves which
## two to carry (the balance simulator's, the autopilot): a melee weapon by its blows, a firearm by
## its sustained damage (reloads included). A third weapon replaces the one in hand, so a player
## takes it only when it beats what it would give up by `REPLACE_GAIN`; without that margin a
## small difference (that comes and goes with the round's health) makes them buy in circles.

## A weapon replaces another only when it is worth this many times more.
const REPLACE_GAIN := 1.5
## The health a freeze is rated against when no zombie is named (a round-10 walker's): a weapon
## whose hit freezes needs two pulls to kill whatever it meets, so each pull is worth half of it.
const SHATTER_HEALTH := 200.0


## The worth of `weapon` against zombies of `health` (0: the damage a second on the body at point
## blank, shots landing whole or not).
static func of(weapon: WeaponDef, health: float = 0.0) -> float:
	if weapon.is_melee():
		return melee_rate(weapon, health)
	return sustained_dps(weapon, health)


## Damage a second on the body at point blank, reloads included. With a `health` it is the health
## of the zombies killed a second instead: shots land whole, so a blow that overshoots the health
## wastes the rest (a 95 damage rifle against 117 health needs two, and does no better than a
## weapon of 60). A weapon whose hit freezes (`shatters`) kills in two pulls at most: the freeze,
## and the hit on the frozen body (any weapon's, but the one in hand is the one rated). A weapon
## whose element burns (`ElementDef.burn_dps`) leaves the burn to finish what the pull left: the
## health to fight for is that much less, and without a health the burn counts for the seconds
## before the next pull restarts it (a fire does not stack, so a stream of pulls on one zombie
## gets no more than that of it).
static func sustained_dps(weapon: WeaponDef, health: float = 0.0) -> float:
	var cycle := float(weapon.magazine_size) * weapon.fire_interval + weapon.reload_time
	var per_shot := _per_pull(weapon)
	if health <= 0.0:
		per_shot += burn_between_pulls(weapon)
		if shatters(weapon):
			per_shot = maxf(per_shot, SHATTER_HEALTH / 2.0)
		return per_shot * float(weapon.magazine_size) / cycle
	var shots := ceilf(maxf(health - burn_total(weapon), 0.0) / maxf(per_shot, 0.001))
	shots = maxf(shots, 1.0)
	if shatters(weapon):
		shots = minf(shots, 2.0)
	return health * float(weapon.magazine_size) / shots / cycle


## Whether a hit of this weapon leaves the zombie in a status that any hit kills
## (`StatusDef.shatters`).
static func shatters(weapon: WeaponDef) -> bool:
	if not weapon.has_status():
		return false
	var status := StatusCatalog.get_def(weapon.status)
	return status != null and status.shatters


## The damage one burn of this weapon's element does (`ElementDef.burn_total`), 0 for none.
static func burn_total(weapon: WeaponDef) -> float:
	return weapon.element.burn_total() if weapon.has_element() else 0.0


## The burn's damage one pull adds on a zombie the next pull reaches again: the fire runs only until
## that pull restarts it, so a rapid weapon gets less of it than a slow one.
static func burn_between_pulls(weapon: WeaponDef) -> float:
	if not weapon.has_element() or not weapon.element.has_burn():
		return 0.0
	return weapon.element.burn_dps * minf(weapon.element.burn_seconds, weapon.fire_interval)


## Health of zombies a second a melee weapon kills at arm's length, a blow landing whole against a
## zombie of `health` (the damage a second of a blow with none).
static func melee_rate(weapon: WeaponDef, health: float = 0.0) -> float:
	var per_blow := maxf(_per_pull(weapon), 0.001)
	if health <= 0.0:
		return per_blow / weapon.fire_interval
	return health / (ceilf(health / per_blow) * weapon.fire_interval)


## Whether `offered` is worth taking in place of `given_up`.
static func beats(offered: WeaponDef, given_up: WeaponDef, health: float = 0.0) -> bool:
	return of(offered, health) > of(given_up, health) * REPLACE_GAIN


## Damage of one trigger pull on the body at point blank: every pellet.
static func _per_pull(weapon: WeaponDef) -> float:
	return float(weapon.pellets) * DamageModel.damage(weapon, 0.0, &"body")
