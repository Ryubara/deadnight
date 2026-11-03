class_name ZombieType
extends Resource
## One kind of zombie, as data: what it is made of, how it moves and hits, what it pays and when it
## shows up. The rules read these and put the result into `zombie_spawn_requested`; the zombie
## behaviour and the world read the same fields from the event, so no code knows a type by name.
##
## Multipliers are on the round's value (`RoundTuning.health_for_round`, `speed_for_round`), so
## every type scales with the night. The looks are the variants of docs/design/zombies.md.

## The id the events carry (`walker`, `runner`, `brute`, `crawler`, `headliner`).
@export var id: StringName = &""
## Model variants this type may wear; the world shows the spawn event's `look`. A boss names its own
## (the blender-artist makes it).
@export var looks: Array[StringName] = []
## A boss is spawned only by a special round, never by the normal mix.
@export var boss: bool = false

@export_group("Body")
@export_range(0.1, 20.0, 0.05, "or_greater", "suffix:x") var health_multiplier: float = 1.0
## Extra health for each player after the first, as a fraction (0.5 is +50% per extra player), so a
## boss keeps up with the crowd that comes with more players.
@export_range(0.0, 2.0, 0.05, "or_greater") var health_per_extra_player: float = 0.0
@export_range(0.1, 5.0, 0.05, "or_greater", "suffix:x") var speed_multiplier: float = 1.0
## How hard it is to land a shot on it: 1 is a walker, below 1 sizes down the hit zones of a
## zombie that stands. A crawler's zones are fitted to its body on the ground, not shrunk by it.
@export_range(0.0, 1.0, 0.01) var hit_chance: float = 1.0
## A hit in the `weak` zone (the lit bulb of the headliner) does this many times the damage.
@export_range(0.1, 5.0, 0.05, "or_greater", "suffix:x") var weak_multiplier: float = 1.0
## What a zombie of this type becomes when a blast takes its legs (`zombie_crippled`); empty
## means it is only slowed.
@export var crawls_into: StringName = &""

@export_group("Attack")
## Health a landed blow takes from a player.
@export_range(0.0, 500.0, 1.0, "or_greater") var damage: float = 20.0
## Metres a landed blow throws the player back.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var knockback: float = 0.0
## Seconds the blow is shown coming (a wind-up the player can read and dodge). 0 is the walker's
## ordinary swing.
@export_range(0.0, 3.0, 0.05, "or_greater", "suffix:s") var telegraph_seconds: float = 0.0
## Barrier boards come off this many times faster than a walker pulls them.
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:x") var barrier_speed: float = 1.0

@export_group("Pay")
## Multiplies what a hit and the kill pay.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:x") var points_multiplier: float = 1.0
## Most hits that pay before the kill; 0 uses the economy's number.
@export_range(0, 20, 1, "or_greater") var max_paid_hits: int = 0

@export_group("Spawning")
## First round it can appear in (the base type: 1).
@export_range(1, 100, 1, "or_greater") var first_round: int = 1
## Exactly this many arrive on the first round, so the player meets each type before it is common.
@export_range(1, 50, 1, "or_greater") var intro_count: int = 1
## Share of a round's zombies from `first_round`: start, plus `share_step` each round after, up to
## `share_max`. The base type takes what the others leave.
@export_range(0.0, 1.0, 0.01) var share_start: float = 0.0
@export_range(0.0, 1.0, 0.005) var share_step: float = 0.0
@export_range(0.0, 1.0, 0.01) var share_max: float = 0.0


func share_at(round_number: int) -> float:
	if round_number < first_round or boss:
		return 0.0
	return minf(share_start + share_step * float(round_number - first_round), share_max)


## The model for a spawn, chosen by a roll the rules own.
func look_for(roll: int) -> StringName:
	if looks.is_empty():
		return id
	return looks[(roll >> 8) % looks.size()]
