class_name ZombieProfile
extends RefCounted
## What makes one zombie a walker, a brute or the headliner once it is on the lot: the numbers the
## rules chose for its type (`ZombieType`, carried by `zombie_spawn_requested`) that the simulation
## acts on. Plain data, set when the zombie spawns and again when a blast takes its legs. The
## simulation never names a type; it reads these fields.

## The type id (`walker`, `brute`, ...), as the rules know it.
var type: StringName = &"walker"
## The model it is drawn in (a `ZombieModels` look).
var look: StringName = ZombieModels.DEFAULT
## Health a landed blow takes from a player.
var damage: float = 0.0
## Metres a landed blow throws the player back.
var knockback: float = 0.0
## Seconds from the start of a swing to the blow: the walker's ordinary windup, or the type's
## telegraph when it has one.
var windup: float = 0.0
## How fast it pulls boards off a barrier, against a walker's 1. (There is no barrier in the night
## yet; the field is carried so the barrier work reads it from here.)
var barrier_speed: float = 1.0
## How hard it is to land a shot on it, against a walker's 1. Scales the hit zones.
var hit_chance: float = 1.0


## The plain zombie of `tuning`: the numbers a zombie has when the rules say nothing more.
static func plain(tuning: ZombieTuning) -> ZombieProfile:
	var profile := ZombieProfile.new()
	profile.damage = tuning.strike_damage
	profile.windup = tuning.windup_seconds
	return profile


## From a `zombie_spawn_requested` event; a field the event leaves out keeps the plain value.
static func from_event(event: Dictionary, tuning: ZombieTuning) -> ZombieProfile:
	var profile := plain(tuning)
	profile.type = event.get("zombie_type", profile.type)
	profile.look = event.get("look", profile.type)
	profile.damage = event.get("damage", profile.damage)
	profile.knockback = event.get("knockback", 0.0)
	profile.barrier_speed = event.get("barrier_speed", 1.0)
	profile.hit_chance = event.get("hit_chance", 1.0)
	var telegraph: float = event.get("telegraph_seconds", 0.0)
	if telegraph > 0.0:
		profile.windup = telegraph
	return profile


## From a type, for a zombie that changed into it (a walker whose legs went becomes a crawler).
static func from_type(type: ZombieType, look: StringName, tuning: ZombieTuning) -> ZombieProfile:
	return from_event(
		{
			"zombie_type": type.id,
			"look": look,
			"damage": type.damage,
			"knockback": type.knockback,
			"telegraph_seconds": type.telegraph_seconds,
			"barrier_speed": type.barrier_speed,
			"hit_chance": type.hit_chance,
		},
		tuning
	)


## The size of its hit zones against the walker's: its hit chance, and how tall its model stands.
func hit_scale() -> float:
	return hit_chance * ZombieModels.height_of(look)
