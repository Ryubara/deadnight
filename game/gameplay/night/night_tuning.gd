class_name NightTuning
extends Resource
## The numbers of the night that belong to neither the rules, the zombies nor the weapons: what a
## player starts with, how far a hand reaches, where the barrel is. (Health and how it mends are
## the rules': `PlayerTuning`.) The shipped values are in `night_tuning_default.tres`: edit that
## file in the inspector; `NightTuning.shipped()` is how the night and the tests read it.

const SHIPPED_PATH := "res://gameplay/night/night_tuning_default.tres"

@export_group("Commands")
## Fixed steps a player's last command stays in force without a new one. After that the player
## stands, the trigger is released and only the view angles are kept (a stalled client does not walk
## into the dead). Half a second at the 60 Hz step.
@export_range(1, 600, 1, "suffix:steps") var command_ticks: int = 30

@export_group("Hands")
## Metres from the player's feet to a door slab (or a board) that it can be used from.
@export_range(0.5, 10.0, 0.05, "suffix:m") var use_reach: float = 3.2
## Seconds between two boards put back: the first at the press, then one every interval while the
## button stays down.
@export_range(0.1, 5.0, 0.05, "suffix:s") var repair_interval: float = 1.0
## Whether holding use at a breach keeps putting boards back (off: one board a press).
@export var repair_hold: bool = true
## Seconds before the same hand can throw a breaker again (a held key does not flicker the lights).
@export_range(0.0, 5.0, 0.05, "suffix:s") var switch_interval: float = 0.5

## Metres from a fuel can spot that a can can be bought from: the spot is stood at, so a wall's far
## side is out of reach.
@export_range(0.5, 10.0, 0.05, "suffix:m") var fuel_reach: float = 2.0
## Seconds before the same hand can buy another can (a held key does not empty the purse).
@export_range(0.0, 5.0, 0.05, "suffix:s") var fuel_interval: float = 0.5

@export_group("Grenades")
## Metres in front of the player, along the aim, that a grenade leaves the hand from (the server
## keeps it within `GrenadeDef.hand_reach` of the hand it knows).
@export_range(0.0, 2.0, 0.01, "suffix:m") var grenade_hand_reach: float = 0.35
## Seconds from the button coming up to the grenade leaving the hand, for an overarm throw: the
## Soldier's throw clip reaches its release frame then (`Grenade_Throw` frame 9 at 24 fps,
## `assets/characters/soldier/grenade/clips.json`), so the grenade flies as the hand opens.
@export_range(0.0, 2.0, 0.001, "suffix:s") var grenade_release_over: float = 0.375
## The same for an underarm toss (`Grenade_Toss` frame 10 at 24 fps).
@export_range(0.0, 2.0, 0.001, "suffix:s") var grenade_release_under: float = 0.4167

@export_group("Shots")
## The barrel, relative to the player's feet and facing (x right, -z forward).
@export var muzzle_offset: Vector3 = Vector3(0.3, 1.45, -0.4)
## A shot's origin farther than this from the shooter's head is pulled back to it.
@export_range(0.0, 10.0, 0.1, "suffix:m") var origin_slack: float = 3.0
## Metres from the feet to the head the server judges a shot's origin against.
@export_range(0.5, 2.5, 0.01, "suffix:m") var eye_height: float = 1.55

@export_group("Revive")
## Metres (on the ground) between two players that one can raise the other from.
@export_range(0.5, 10.0, 0.1, "or_greater", "suffix:m") var revive_reach: float = 2.0

@export_group("Aim")
## A shot whose direction differs from where the shooter's view points (`motion.yaw` and `pitch`)
## by more than this many degrees is refused: a person's shot follows the camera, so only a client
## that shoots one way and looks another is turned away.
@export_range(0.0, 90.0, 0.5, "or_greater", "suffix:deg") var aim_slack_degrees: float = 10.0

@export_group("Pings")
## Metres from the player that a place can be marked.
@export_range(1.0, 300.0, 1.0, "or_greater", "suffix:m") var ping_range: float = 70.0
## Metres from a marked ammunition spot that counts as the spot.
@export_range(0.0, 30.0, 0.5, "or_greater", "suffix:m") var ping_snap: float = 4.0
## Seconds a mark stays up, and seconds before the same player can place another.
@export_range(1.0, 120.0, 1.0, "or_greater", "suffix:s") var ping_seconds: float = 20.0
@export_range(0.0, 10.0, 0.1, "or_greater", "suffix:s") var ping_gap: float = 1.0

@export_group("Spectator camera")
## Where the bot's camera hangs, relative to the bot (metres): above and behind it, so a recording
## reads. Used when the autopilot plays without its own shoulder camera.
@export var spectator_offset: Vector3 = Vector3(0.0, 11.0, 8.0)
## What the bot's camera looks at, relative to the bot (metres).
@export var spectator_look_at: Vector3 = Vector3(0.0, 1.0, -3.0)
## The bot's camera field of view, in degrees.
@export_range(20.0, 120.0, 1.0, "suffix:°") var spectator_fov: float = 60.0


## A private copy of the shipped table (`night_tuning_default.tres`): a test or a night may change
## it without touching the file or another night.
static func shipped() -> NightTuning:
	return (load(SHIPPED_PATH) as NightTuning).duplicate(true) as NightTuning
