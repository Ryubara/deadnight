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
@export var damage: float = 20.0
@export var pellets: int = 1
## Half-angle of the cone the pellets fall in, in degrees. 0 is a perfect line.
@export var spread_deg: float = 0.0
## Full damage up to `falloff_start` metres, sliding linearly to `min_damage_fraction` at
## `falloff_end`, flat beyond it up to `max_range`.
@export var falloff_start: float = 15.0
@export var falloff_end: float = 40.0
@export_range(0.0, 1.0) var min_damage_fraction: float = 0.5
@export var max_range: float = 80.0
## How many extra targets a shot passes through, each one weaker (see below).
@export var penetration: int = 0
## Damage multiplier applied once per target the shot has already passed through.
@export_range(0.0, 1.0) var penetration_falloff: float = 0.6
## Hit zone name (`Hitbox.HEAD`, `BODY`, `LIMB`) to damage multiplier.
@export var zone_multipliers: Dictionary[StringName, float] = {}

@export_group("Handling")
## Seconds between two shots (melee: between two swings).
@export var fire_interval: float = 0.4
@export var magazine_size: int = 8
## Rounds carried when the weapon is given.
@export var reserve_start: int = 32
@export var reserve_max: int = 96
@export var reload_time: float = 1.6

@export_group("Feel")
## Trauma one shot adds to the shooter's view shake, 0 to 1 (`CameraShake`;
## docs/design/camera-shake.md).
## Heavier weapons kick the view more; 0 is no shake.
@export_range(0.0, 1.0) var shake_trauma: float = 0.3
## Width of the muzzle flash's star in metres (`MuzzleFlash`). 0 draws no flash.
@export_range(0.0, 1.0, 0.01) var flash_size: float = 0.3

@export_group("Projectile")
@export var projectile_speed: float = 30.0
## Downward acceleration in m/s^2 (a lob falls; a bolt does not).
@export var projectile_gravity: float = 0.0
@export var projectile_radius: float = 0.1
## Seconds before it bursts in the air.
@export var projectile_lifetime: float = 3.0
@export var splash_radius: float = 0.0
## Damage at the burst centre; it slides linearly to `splash_min_fraction` at the radius.
@export var splash_damage: float = 0.0
@export_range(0.0, 1.0) var splash_min_fraction: float = 0.25

@export_group("Melee")
@export var melee_range: float = 1.8
## Thickness of the sweep in metres: the shape that is cast is this fat.
@export var melee_radius: float = 0.35
## How many targets one swing can hit.
@export var melee_max_targets: int = 1


## The damage multiplier of a hit zone; a zone the weapon does not list counts one.
func zone_multiplier(zone: StringName) -> float:
	return zone_multipliers.get(zone, 1.0)


func is_hitscan() -> bool:
	return kind == Kind.HITSCAN


func is_projectile() -> bool:
	return kind == Kind.PROJECTILE


func is_melee() -> bool:
	return kind == Kind.MELEE


func rounds_per_second() -> float:
	return 1.0 / maxf(fire_interval, 0.001)
