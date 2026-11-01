class_name ZombieTuning
extends Resource
## How a zombie behaves, apart from what the round does to it (speed and spawn pacing live in
## RoundTuning). Every number the simulation uses is here, so one place changes.

@export_group("Crowd")
## Zombies standing at once, whatever the rules ask for. The crowds spike's ceiling (kit docs,
## godot/crowds.md): beyond it the web build misses its budget.
@export var hard_cap: int = 40
## Seconds between a zombie's path queries; each zombie starts at a random phase.
@export var repath_interval: float = 0.25
## Seconds between a zombie checking whether another player is the nearer one.
@export var retarget_interval: float = 0.5
## A new target must be this many metres nearer than the current one, so zombies do not flip-flop.
@export var retarget_margin: float = 2.0
## A waypoint this close counts as reached.
@export var waypoint_reach: float = 0.4

@export_group("Body")
## Two zombies closer than this (metres) push each other apart.
@export var separation_radius: float = 0.8
## Metres per second of push at zero distance.
@export var separation_speed: float = 2.0
## Metres per second the pushes on one zombie may add up to: a pile cannot throw a zombie.
@export var separation_max_speed: float = 4.0
## Radians per second a zombie turns toward where it is going.
@export var turn_rate: float = 9.0

@export_group("Attack")
## Metres from the zombie's feet to the player's at which it starts a swing.
@export var reach: float = 1.4
## The blow lands this many seconds into a swing.
@export var windup_seconds: float = 0.45
## A whole swing, windup and recovery, in seconds. A type with a longer windup (its telegraph)
## keeps the same recovery after the blow.
@export var swing_seconds: float = 1.2
## Metres past `reach` at which a landing blow still connects (the player may step back).
@export var strike_slack: float = 0.4
## Health a blow takes from the player.
@export var strike_damage: float = 20.0

@export_group("Reactions")
## Seconds a zombie rises from the ground after it spawns.
@export var emerge_seconds: float = 0.7
## Seconds a hit staggers a zombie (it stops and loses its swing).
@export var stagger_seconds: float = 0.4
## Seconds a boss stands roaring where it appeared before it comes (its entrance; the length of
## the `Boss_Roar` clip, assets/characters/zombie_boss/clips.json).
@export var boss_entrance_seconds: float = 2.75
## Seconds a hit on a boss's weak spot staggers it (the length of `Boss_Stagger`).
@export var boss_stagger_seconds: float = 1.42
## Seconds after a stagger in which another weak-spot hit does not stagger it again: a rifle that
## hits the lamp every shot must not hold the boss still for ever.
@export var boss_stagger_cooldown: float = 6.0
## Seconds a dead zombie stays down before it is cleared.
@export var death_seconds: float = 2.5


## Seconds after the blow before the zombie can swing again.
func recovery_seconds() -> float:
	return maxf(swing_seconds - windup_seconds, 0.0)
