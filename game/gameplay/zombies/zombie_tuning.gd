class_name ZombieTuning
extends Resource
## How a zombie behaves, apart from what the round does to it (speed and spawn pacing live in
## RoundTuning). Every number the simulation uses is here, so one place changes. The shipped values
## are in `zombie_tuning_default.tres`: edit that file in the inspector; `ZombieTuning.shipped()` is
## how the simulation, the client and the tests read it.

const SHIPPED_PATH := "res://gameplay/zombies/zombie_tuning_default.tres"

@export_group("Crowd")
## Zombies standing at once, whatever the rules ask for. The crowds spike's ceiling (kit docs,
## godot/crowds.md): beyond it the web build misses its budget.
@export_range(1, 200, 1, "suffix:zombies") var hard_cap: int = 40
## Seconds between a zombie's path queries; each zombie starts at a random phase.
@export_range(0.02, 2.0, 0.01, "suffix:s") var repath_interval: float = 0.25
## A zombie farther than this (metres) from its target asks for its path this many times less
## often: the way to a target across the lot hardly changes in a quarter of a second, and in a big
## crowd most of the dead are far.
@export_range(1.0, 100.0, 1.0, "suffix:m") var repath_far_distance: float = 14.0
@export_range(1.0, 8.0, 0.25) var repath_far_factor: float = 2.0
## Seconds between a zombie checking whether another player is the nearer one.
@export_range(0.05, 5.0, 0.05, "suffix:s") var retarget_interval: float = 0.5
## A new target must be this many metres nearer than the current one, so zombies do not flip-flop.
@export_range(0.0, 10.0, 0.1, "suffix:m") var retarget_margin: float = 2.0
## A waypoint this close counts as reached.
@export_range(0.05, 3.0, 0.05, "suffix:m") var waypoint_reach: float = 0.4

@export_group("Lure")
## Metres from a lure at which a zombie stops and stands about it (inside the attack's `reach`
## it would swing at nothing).
@export_range(0.0, 10.0, 0.1, "suffix:m") var lure_gather_distance: float = 2.5
## Whether a zombie in the middle of a swing at a player drops it at once for a lure (true), or
## finishes the swing first (false).
@export var lure_breaks_swings: bool = false
## Whether a zombie that is tearing a barricade's boards leaves them for a lure.
@export var lure_pulls_gate_zombies: bool = false
## Whether a boss goes to a lure.
@export var lure_pulls_bosses: bool = false

@export_group("Body")
## Two zombies closer than this (metres) push each other apart.
@export_range(0.0, 3.0, 0.05, "suffix:m") var separation_radius: float = 0.8
## Metres per second of push at zero distance.
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var separation_speed: float = 2.0
## Metres per second the pushes on one zombie may add up to: a pile cannot throw a zombie.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var separation_max_speed: float = 4.0
## Zombies this far apart in height (metres) do not push each other: one on a ramp is not in the
## way of one on the floor under it.
@export_range(0.1, 5.0, 0.05, "suffix:m") var separation_height: float = 1.0
## Metres per second a zombie rises or falls to the floor its path runs on (a stair, a ramp).
@export_range(0.5, 30.0, 0.5, "suffix:m/s") var climb_speed: float = 6.0
## Radians per second a zombie turns toward where it is going.
@export_range(0.5, 40.0, 0.5, "suffix:rad/s") var turn_rate: float = 9.0

@export_group("Fence")
## Metres short of the boards at which a zombie stops and starts tearing them off.
@export_range(0.0, 5.0, 0.05, "suffix:m") var board_stop: float = 0.9
## A zombie this close to the stop line (metres) is at the boards and works on them.
@export_range(0.0, 2.0, 0.05, "suffix:m") var board_slack: float = 0.25

@export_group("Attack")
## Metres from the zombie's feet to the player's at which it starts a swing.
@export_range(0.2, 5.0, 0.05, "suffix:m") var reach: float = 1.4
## A zombie this far above or below its target (metres) cannot reach it: the one under the roost
## does not swing at the person standing over its head.
@export_range(0.5, 10.0, 0.1, "suffix:m") var reach_height: float = 2.0
## The blow lands this many seconds into a swing.
@export_range(0.05, 3.0, 0.01, "suffix:s") var windup_seconds: float = 0.45
## A whole swing, windup and recovery, in seconds. A type with a longer windup (its telegraph)
## keeps the same recovery after the blow.
@export_range(0.1, 5.0, 0.01, "suffix:s") var swing_seconds: float = 1.2
## Metres past `reach` at which a landing blow still connects (the player may step back).
@export_range(0.0, 3.0, 0.05, "suffix:m") var strike_slack: float = 0.4
## Health a blow takes from the player.
@export_range(0.0, 200.0, 1.0, "suffix:health") var strike_damage: float = 20.0

@export_group("Marks")
## The last this many zombies of a round (those still to spawn count) are outlined through walls on
## every client, so the players can find them. 0 turns the outline off.
@export_range(0, 40, 1, "suffix:zombies") var mark_last: int = 3

@export_group("Reactions")
## Seconds a zombie rises from the ground after it spawns.
@export_range(0.0, 5.0, 0.05, "suffix:s") var emerge_seconds: float = 0.7
## Seconds a hit staggers a zombie (it stops and loses its swing).
@export_range(0.0, 3.0, 0.05, "suffix:s") var stagger_seconds: float = 0.4
## Seconds a boss stands roaring where it appeared before it comes (its entrance; the length of
## the `Boss_Roar` clip, assets/characters/zombie_boss/clips.json).
@export_range(0.0, 10.0, 0.05, "suffix:s") var boss_entrance_seconds: float = 2.75
## Seconds a hit on a boss's weak spot staggers it (the length of `Boss_Stagger`).
@export_range(0.0, 10.0, 0.05, "suffix:s") var boss_stagger_seconds: float = 1.42
## Seconds after a stagger in which another weak-spot hit does not stagger it again: a rifle that
## hits the lamp every shot must not hold the boss still for ever.
@export_range(0.0, 30.0, 0.1, "suffix:s") var boss_stagger_cooldown: float = 6.0
## The fastest a blast may throw a zombie (m/s), and how fast the throw slows down (m/s per second):
## at the grenade's 7 m/s a zombie in the middle of a blast slides 1.75 m.
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var push_max_speed: float = 8.0
@export_range(0.1, 60.0, 0.1, "suffix:m/s²") var push_decay: float = 14.0
## Seconds a dead zombie stays down before it is cleared.
@export_range(0.0, 10.0, 0.05, "suffix:s") var death_seconds: float = 2.5


## Seconds after the blow before the zombie can swing again.
func recovery_seconds() -> float:
	return maxf(swing_seconds - windup_seconds, 0.0)


## A private copy of the shipped table (`zombie_tuning_default.tres`): a test or a night may change
## it without touching the file or another night.
static func shipped() -> ZombieTuning:
	return (load(SHIPPED_PATH) as ZombieTuning).duplicate(true) as ZombieTuning
