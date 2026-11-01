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
@export var health_multiplier: float = 1.0
## Extra health for each player after the first, as a fraction (0.5 is +50% per extra player), so a
## boss keeps up with the crowd that comes with more players.
@export var health_per_extra_player: float = 0.0
@export var speed_multiplier: float = 1.0
## How hard it is to land a shot on it: 1 is a walker, below 1 is harder (a crawler is low).
@export var hit_chance: float = 1.0
## A hit in the `weak` zone (the lit bulb of the headliner) does this many times the damage.
@export var weak_multiplier: float = 1.0
## A `limb` hit that leaves this fraction of its health or less turns the zombie into
## `crawls_into`. 0 means never.
@export var crawls_at: float = 0.0
@export var crawls_into: StringName = &""

@export_group("Attack")
## Health a landed blow takes from a player.
@export var damage: float = 20.0
## Metres a landed blow throws the player back.
@export var knockback: float = 0.0
## Seconds the blow is shown coming (a wind-up the player can read and dodge). 0 is the walker's
## ordinary swing.
@export var telegraph_seconds: float = 0.0
## Barrier boards come off this many times faster than a walker pulls them.
@export var barrier_speed: float = 1.0

@export_group("Pay")
## Multiplies what a hit and the kill pay.
@export var points_multiplier: float = 1.0
## Most hits that pay before the kill; 0 uses the economy's number.
@export var max_paid_hits: int = 0

@export_group("Spawning")
## First round it can appear in (the base type: 1).
@export var first_round: int = 1
## Exactly this many arrive on the first round, so the player meets each type before it is common.
@export var intro_count: int = 1
## Share of a round's zombies from `first_round`: start, plus `share_step` each round after, up to
## `share_max`. The base type takes what the others leave.
@export var share_start: float = 0.0
@export var share_step: float = 0.0
@export var share_max: float = 0.0


func share_at(round_number: int) -> float:
	if round_number < first_round or boss:
		return 0.0
	return minf(share_start + share_step * float(round_number - first_round), share_max)


## The model for a spawn, chosen by a roll the rules own.
func look_for(roll: int) -> StringName:
	if looks.is_empty():
		return id
	return looks[(roll >> 8) % looks.size()]
