class_name DamageModel
extends RefCounted
## What one hit is worth: distance falloff, hit zone, and how many bodies the shot already went
## through. Pure functions of a `WeaponDef` and numbers, so a test pins each rule alone.


## 1.0 up to `falloff_start`, sliding to `min_damage_fraction` at `falloff_end`, flat beyond.
static func falloff(def: WeaponDef, distance: float) -> float:
	if distance <= def.falloff_start:
		return 1.0
	var span := maxf(def.falloff_end - def.falloff_start, 0.001)
	var t := clampf((distance - def.falloff_start) / span, 0.0, 1.0)
	return lerpf(1.0, def.min_damage_fraction, t)


## Damage of one pellet or blow: base x falloff x zone x penetration.
static func damage(def: WeaponDef, distance: float, zone: StringName, passed: int = 0) -> float:
	return (
		def.damage
		* falloff(def, distance)
		* def.zone_multiplier(zone)
		* pow(def.penetration_falloff, passed)
	)


## A blast: full `splash_damage` at the centre, sliding to `splash_min_fraction` at the radius, and
## nothing past it.
static func splash(def: WeaponDef, distance: float) -> float:
	if def.splash_radius <= 0.0 or distance > def.splash_radius:
		return 0.0
	return def.splash_damage * lerpf(1.0, def.splash_min_fraction, distance / def.splash_radius)
