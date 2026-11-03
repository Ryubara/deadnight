class_name WeaponDef
extends Resource
## One weapon as data: how it hurts, how it handles and how it flies. Every number a weapon has
## lives in a `.tres` of this script (`defs/`), none in code. The server and the client load the
## same file, so a prediction and the authoritative answer use the same numbers.

enum Kind { HITSCAN, PROJECTILE, MELEE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.HITSCAN
## Holding the trigger keeps firing (the client repeats; the server's fire interval is the limit).
@export var automatic: bool = false
## Draws a streak from the muzzle to where the shot ended. Off by default: a hitscan shot is
## instant and shows a flash and an impact, never a visible bullet. A launcher or a ray gun is a
## `PROJECTILE` weapon instead; this flag is for the rare hitscan weapon whose beam should show.
@export var tracer: bool = false

@export_group("Damage")
## Per pellet (hitscan), on a direct hit (projectile) or per swing (melee), on the body zone and
## at point blank.
@export_range(0.0, 500.0, 1.0, "or_greater") var damage: float = 20.0
@export_range(1, 30, 1, "or_greater") var pellets: int = 1
## Half-angle of the cone the pellets fall in, in degrees. 0 is a perfect line.
@export_range(0.0, 30.0, 0.05, "or_greater", "suffix:deg") var spread_deg: float = 0.0
## Full damage up to `falloff_start` metres, sliding linearly to `min_damage_fraction` at
## `falloff_end`, flat beyond it up to `max_range`.
@export_range(0.0, 100.0, 0.5, "or_greater", "suffix:m") var falloff_start: float = 15.0
@export_range(0.0, 1000.0, 0.5, "or_greater", "suffix:m") var falloff_end: float = 40.0
@export_range(0.0, 1.0) var min_damage_fraction: float = 0.5
@export_range(0.0, 1000.0, 0.5, "or_greater", "suffix:m") var max_range: float = 80.0
## How many extra targets a shot passes through, each one weaker (see below).
@export_range(0, 10, 1, "or_greater") var penetration: int = 0
## Damage multiplier applied once per target the shot has already passed through.
@export_range(0.0, 1.0) var penetration_falloff: float = 0.6
## Hit zone name (`Hitbox.HEAD`, `BODY`, `LIMB`) to damage multiplier.
@export var zone_multipliers: Dictionary[StringName, float] = {}

@export_group("Handling")
## Seconds between two shots (melee: between two swings).
@export_range(0.02, 3.0, 0.01, "or_greater", "suffix:s") var fire_interval: float = 0.4
@export_range(1, 200, 1, "or_greater") var magazine_size: int = 8
## Rounds carried when the weapon is given.
@export_range(0, 500, 1, "or_greater") var reserve_start: int = 32
@export_range(0, 1000, 1, "or_greater") var reserve_max: int = 96
@export_range(0.1, 8.0, 0.05, "or_greater", "suffix:s") var reload_time: float = 1.6
## The reload loads one round at a time (a pump's tube): `reload_time` is the whole magazine from
## empty, so each round takes `reload_time / magazine_size`, every round is in the magazine the
## moment it is loaded, and a shot with at least one round in it ends the reload there (#793).
@export var reload_by_round: bool = false
## Extra half-angle of the cone, in degrees, at a full run: the shooter moving widens the spread
## (a belt-fed gun fired from the hip); 0 for a weapon that shoots as true on the move (#793).
@export_range(0.0, 30.0, 0.05, "or_greater", "suffix:deg") var moving_spread_deg: float = 0.0

@export_group("Feel")
## Trauma one shot adds to the shooter's view shake, 0 to 1 (`CameraShake`;
## docs/design/camera-shake.md).
## Heavier weapons kick the view more; 0 is no shake.
@export_range(0.0, 1.0) var shake_trauma: float = 0.3
## Width of the muzzle flash's star in metres (`MuzzleFlash`). 0 draws no flash.
@export_range(0.0, 1.0, 0.01) var flash_size: float = 0.3

@export_group("Projectile")
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:m/s") var projectile_speed: float = 30.0
## Downward acceleration in m/s^2 (a lob falls; a bolt does not).
@export_range(0.0, 40.0, 0.5, "or_greater", "suffix:m/s^2") var projectile_gravity: float = 0.0
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:m") var projectile_radius: float = 0.1
## Seconds before it bursts in the air.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:s") var projectile_lifetime: float = 3.0
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var splash_radius: float = 0.0
## Damage at the burst centre; it slides linearly to `splash_min_fraction` at the radius.
@export_range(0.0, 500.0, 1.0, "or_greater") var splash_damage: float = 0.0
@export_range(0.0, 1.0) var splash_min_fraction: float = 0.25

@export_group("Element")
## What a hit does besides its damage (`ElementDef`): none as shipped; a re-cut weapon may carry one
## (`RecutProfile.element`).
@export var element: ElementDef

@export_group("Lure")
## Metres round a burst within which zombies leave what they chase for the burst point, and the
## seconds they stay (`ZombieLure`); 0 makes no lure. A lure does no damage.
@export_range(0.0, 60.0, 0.5, "or_greater", "suffix:m") var lure_radius: float = 0.0
@export_range(0.0, 60.0, 0.5, "or_greater", "suffix:s") var lure_seconds: float = 0.0

@export_group("Melee")
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m") var melee_range: float = 1.8
## Thickness of the sweep in metres: the shape that is cast is this fat.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:m") var melee_radius: float = 0.35
## How many targets one swing can hit.
@export_range(1, 10, 1, "or_greater") var melee_max_targets: int = 1

## Which re-cut this copy has had: 0 as shipped, 1 after `upgraded`. Not saved with the file.
var tier: int = 0


## This weapon re-cut: a copy with the numbers of its `RecutProfile` (more damage in the pellets and
## the blast, a bigger magazine and reserve, a changed rate or reload), its re-cut name and its
## element. The id stays, so the model, the sounds and the shop still know it. The server's
## `WeaponState` and the balance simulator both make it here. A weapon the spec has no profile for
## comes back as a plain copy one tier up.
func upgraded(spec: UpgradeTuning) -> WeaponDef:
	var copy := duplicate() as WeaponDef
	copy.tier = tier + 1
	var cut := spec.profile_of(id)
	if cut == null:
		return copy
	copy.display_name = cut.name_of(display_name, spec.name_prefix)
	copy.damage = damage * cut.damage_multiplier
	copy.splash_damage = splash_damage * cut.damage_multiplier
	copy.magazine_size = ceili(float(magazine_size) * cut.magazine_multiplier)
	copy.reserve_start = ceili(float(reserve_start) * cut.reserve_multiplier)
	copy.reserve_max = ceili(float(reserve_max) * cut.reserve_multiplier)
	if cut.fire_interval > 0.0:
		copy.fire_interval = cut.fire_interval
	if cut.reload_time > 0.0:
		copy.reload_time = cut.reload_time
	copy.splash_radius = splash_radius * cut.burst_radius_multiplier
	copy.element = cut.element
	return copy


## The damage multiplier of a hit zone; a zone the weapon does not list counts one.
func zone_multiplier(zone: StringName) -> float:
	return zone_multipliers.get(zone, 1.0)


## Seconds one round of a by-round reload takes (`reload_by_round`).
func round_seconds() -> float:
	return reload_time / float(maxi(magazine_size, 1))


## The half-angle of the cone for a shooter moving at `move` (0 standing, 1 at a full run).
func spread_at(move: float) -> float:
	return spread_deg + moving_spread_deg * clampf(move, 0.0, 1.0)


func has_element() -> bool:
	return element != null


func is_lure() -> bool:
	return lure_radius > 0.0 and lure_seconds > 0.0


func is_hitscan() -> bool:
	return kind == Kind.HITSCAN


func is_projectile() -> bool:
	return kind == Kind.PROJECTILE


func is_melee() -> bool:
	return kind == Kind.MELEE


func rounds_per_second() -> float:
	return 1.0 / maxf(fire_interval, 0.001)
