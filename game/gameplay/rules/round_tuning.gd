class_name RoundTuning
extends Resource
## How the night gets harder: every number that scales with the round, and the functions that apply
## them.
##
## Pure: the same inputs give the same outputs, and the only randomness is a generator the caller
## passes in. The reasoning behind each default is in docs/design/rounds.md.

@export_group("Count")
## Zombies in round 1 for one player.
@export var count_base: float = 6.0
## Zombies added per round (a straight climb).
@export var count_linear: float = 2.4
## Extra zombies added per round squared (the climb steepens).
@export var count_quadratic: float = 0.12
## Each player after the first adds this fraction of the solo count.
@export var count_per_extra_player: float = 0.6

@export_group("Health")
@export var health_base: float = 60.0
## Health added per round up to the knee.
@export var health_step: float = 18.0
## The last round of the straight climb.
@export var health_knee_round: int = 8
## After the knee health grows by this factor each round.
@export var health_growth: float = 1.07

@export_group("Speed")
## Walking speed of a zombie in round 1, metres per second: its pace under the lights. The
## round-by-round pace follows the original games' speed tiers (docs/research/movement-speeds.md).
@export var speed_base: float = 1.2
@export var speed_step: float = 0.16
## No zombie is faster than this under the lights: a hair above the player's run, so running alone
## does not shake the fastest, but a sprinting player can always get away.
@export var speed_cap: float = 5.0
## Each zombie's speed is varied by up to this fraction either way.
@export var speed_jitter: float = 0.12
## A zombie on ground that is not lit (a circuit off, or the generator dry) moves at this multiple
## of its speed: the dark makes the dead faster, and the light only keeps them at their round's
## pace. Times `speed_cap` it must stay under the player's sprint.
@export var dark_speed_multiplier: float = 1.25

@export_group("Spawning")
## Seconds between spawns in round 1 for one player.
@export var spawn_interval_start: float = 2.4
@export var spawn_interval_decay: float = 0.92
@export var spawn_interval_min: float = 0.5
## Each extra player makes spawns this much faster (fraction).
@export var spawn_rate_per_extra_player: float = 0.5
## Zombies alive at once in round 1, for one player.
@export var alive_cap_start: float = 10.0
@export var alive_cap_step: float = 1.5
@export var alive_cap_max: float = 28.0
@export var alive_cap_per_extra_player: float = 6.0
## The most zombies the rules ever allow alive at once, whatever the round and the players: the
## crowd the lot stands (`ZombieTuning.hard_cap`, the web ceiling; see docs/design/zombies.md).
## A cap above it would only queue the rest in the director, never on the lot.
@export var alive_cap_ceiling: int = 40
## Seconds from the start of a round to its first spawn.
@export var first_spawn_delay: float = 1.5

@export_group("Breaks")
## The wait before round 1.
@export var intro_seconds: float = 12.0
## The break after each round.
@export var break_seconds: float = 5.0

@export_group("Night")
## Ambient light level in round 1 (0 dark, 1 day), read by the world (`NightLight`).
@export var ambient_start: float = 0.6
@export var ambient_step: float = 0.035
@export var ambient_min: float = 0.15


func zombies_for_round(round_number: int, players: int) -> int:
	var n := float(maxi(round_number - 1, 0))
	var solo := count_base + count_linear * n + count_quadratic * n * n
	var crowd := 1.0 + count_per_extra_player * float(maxi(players - 1, 0))
	return maxi(1, roundi(solo * crowd))


func health_for_round(round_number: int) -> float:
	var r := maxi(round_number, 1)
	if r <= health_knee_round:
		return health_base + health_step * float(r - 1)
	var at_knee := health_base + health_step * float(health_knee_round - 1)
	return at_knee * pow(health_growth, float(r - health_knee_round))


func speed_for_round(round_number: int) -> float:
	var walking := speed_base + speed_step * float(maxi(round_number - 1, 0))
	return minf(walking, speed_cap)


## One zombie's speed: the round's walking speed times its type's multiplier, jittered. Draws from
## `rng`. (Sprinters are the runner type now: see `ZombieType`.)
func roll_speed(
	round_number: int, rng: RandomNumberGenerator, type_multiplier: float = 1.0
) -> float:
	var speed := speed_for_round(round_number) * type_multiplier
	speed *= 1.0 + rng.randf_range(-speed_jitter, speed_jitter)
	return minf(speed, speed_cap)


## The speed a zombie really moves at, given whether it stands on lit ground.
func speed_on_ground(speed: float, lit: bool) -> float:
	return speed if lit else speed * dark_speed_multiplier


func spawn_interval(round_number: int, players: int) -> float:
	var n := float(maxi(round_number - 1, 0))
	var solo := maxf(spawn_interval_start * pow(spawn_interval_decay, n), spawn_interval_min)
	return solo / (1.0 + spawn_rate_per_extra_player * float(maxi(players - 1, 0)))


func alive_cap(round_number: int, players: int) -> int:
	var n := float(maxi(round_number - 1, 0))
	var solo := minf(alive_cap_start + alive_cap_step * n, alive_cap_max)
	var wanted := roundi(solo + alive_cap_per_extra_player * float(maxi(players - 1, 0)))
	return mini(wanted, alive_cap_ceiling)


func ambient_for_round(round_number: int) -> float:
	var n := float(maxi(round_number - 1, 0))
	return maxf(ambient_start - ambient_step * n, ambient_min)
