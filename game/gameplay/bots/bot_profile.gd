class_name BotProfile
extends Resource
## Who a bot is as a player: how fast it reacts, how far and how steadily it turns, how well it
## aims, how often it thinks. Difficulty is this and nothing else: zombies, damage, points and
## ammunition never change with a bot's skill (`docs/research/bots.md#aim-and-difficulty`).
## `rookie()`, `regular()` and `veteran()` are the three shipped skills; `autopilot()` is the old
## bot (`Autopilot`), which keeps its own senses and aim and only borrows the host.

## No profile reacts faster than this (seconds): the floor of a person's visual reaction.
const REACTION_FLOOR := 0.20

@export var title: String = "Regular"
## False for the `Autopilot`: it reads the whole frame and aims perfectly, as it always did, and
## the host runs it without a perception filter or an aim model.
@export var filtered: bool = true

@export_group("Senses")
## Degrees of the horizontal view cone, centred on where the bot looks.
@export_range(40.0, 180.0, 1.0, "suffix:deg") var view_degrees: float = 110.0
## Seconds a seen zombie is remembered after it was last seen. A remembered zombie is never shot at.
@export_range(0.0, 10.0, 0.1, "suffix:s") var memory_seconds: float = 3.0
## Metres within which a zombie out of sight is heard (a bearing and a range class, no position).
@export_range(0.0, 20.0, 0.5, "suffix:m") var hearing_range: float = 4.0
## Rays a think may cast, the closest candidates first.
@export_range(1, 16, 1) var rays_per_think: int = 6

@export_group("Reaction")
## Mean seconds from a zombie's first clear ray to the bot believing it is there.
@export_range(0.2, 2.0, 0.01, "suffix:s") var reaction_seconds: float = 0.35
## Spread of the reaction between contacts (coefficient of variation of a log-normal).
@export_range(0.0, 1.0, 0.01) var reaction_spread: float = 0.2
## Seconds to look to the next zombie after a kill: a flick, not a snap (the shortest and longest).
@export_range(0.0, 1.0, 0.01, "suffix:s") var retarget_min: float = 0.12
@export_range(0.0, 1.0, 0.01, "suffix:s") var retarget_max: float = 0.25

@export_group("Aim")
## Degrees a second the view may turn at most, over any window.
@export_range(30.0, 1440.0, 1.0, "suffix:deg/s") var max_aim_speed: float = 360.0
## Natural frequency of the turning spring (radians a second): higher closes the gap faster.
@export_range(1.0, 60.0, 0.5, "suffix:rad/s") var aim_stiffness: float = 14.0
## Degrees of tracking error, one sigma, on a target 15 m away that stands still.
@export_range(0.0, 20.0, 0.05, "suffix:deg") var track_error: float = 4.0
## Share of contacts the bot aims at the head of, when the target is slow and near.
@export_range(0.0, 1.0, 0.01) var head_rate: float = 0.3
## How many times wider than the weapon's hit cone the view may be off the target when the bot pulls
## the trigger: a rookie fires when it is roughly on, a veteran waits to be on.
@export_range(1.0, 8.0, 0.05) var fire_slop: float = 3.0
## Share of shots pulled without waiting to be on target (the view only has to be roughly there):
## the nerves of a bot that fires at what is coming at it.
@export_range(0.0, 1.0, 0.01) var panic_rate: float = 0.0
## Chance that the bot makes out a telegraphed blow (the boss's) at all: the simulator's `read`, as
## a rookie misses most of them. A blow it makes out is stepped out of after the reaction time.
@export_range(0.0, 1.0, 0.01) var telegraph_read: float = 1.0
## Share of the headliner's contacts the bot aims at the weak spot (the lit lens) of, when it
## faces the bot: the simulator's `weak_spot_rate` of the matching skill.
@export_range(0.0, 1.0, 0.01) var weak_spot_rate: float = 0.5
## Seconds, at most, between two shots on top of the weapon's own interval.
@export_range(0.0, 1.0, 0.01, "suffix:s") var fire_jitter: float = 0.08

@export_group("Movement")
## Whether the bot walks to stay near the people. Off, it holds where it stands (a test that must
## not walk: a body the physics engine moves does not repeat to the last bit).
@export var follows: bool = true

@export_group("Shopping")
## Whether the bot goes on errands (shopping, boards, the generator) when the level gives it a shop.
@export var errands: bool = true
## What the bot buys, first to last: the player model of the balance simulator's matching level
## (`SimSkill.shopping`; a test holds the two together). Doors the list lacks are bought after it,
## in the shop table's order.
@export var shopping: Array[StringName] = [
	&"weapon_shotgun",
	&"door_concession",
	&"weapon_rifle",
	&"door_booth",
	&"crane_play",
	&"upgrade_weapon",
	&"tonic_hearty",
	&"door_back_lot",
]
## Items on that list the bot saves for: while one is not yet affordable, nothing after it is
## bought.
@export var saves_for: Array[StringName] = [&"upgrade_weapon", &"tonic_hearty"]
## Magazines of reserve the bot keeps for each gun worth shooting before it spends on anything else,
## and the share of a gun's reserve limit it tops up to with what is left over (`SimSkill`).
@export_range(1, 6, 1) var ammo_floor_mags: int = 3
@export_range(0.0, 1.0, 0.05) var ammo_topoff: float = 1.0
## Grenades under which the bot buys more at a rack when it has points to spare (0: never).
@export_range(0, 5, 1) var grenades_wanted: int = 2
## How many weapons the bot re-cuts in a night.
@export_range(0, 4, 1) var re_cuts: int = 1

@export_group("Thinking")
## How many times a second the brain decides; the motor runs every tick.
@export_range(1, 30, 1, "suffix:Hz") var think_hz: int = 8
## Metres of margin before a zombie reaches the bot at which it starts to back away.
@export_range(0.0, 20.0, 0.5, "suffix:m") var retreat_margin: float = 1.25
## Metres the headliner is kept away (a boss nearer than this makes the bot back off, whatever the
## margin above says). 0 turns it off: a bot that is pinned has nowhere to back to.
@export_range(0.0, 20.0, 0.5, "suffix:m") var boss_keep: float = 6.0
## How much risk a revive may take, 0 (none) to 1 (any); used from phase 5.
@export_range(0.0, 1.0, 0.05) var revive_eagerness: float = 0.5
## Brain failures (a thought that comes back empty or broken) after which the brain is switched off
## and the motor goes on alone.
@export_range(1, 10, 1) var brain_failure_limit: int = 1


static func rookie() -> BotProfile:
	var profile := BotProfile.new()
	profile.title = "Rookie"
	profile.reaction_seconds = 0.55
	profile.view_degrees = 80.0
	profile.max_aim_speed = 240.0
	profile.aim_stiffness = 9.0
	profile.track_error = 14.0
	profile.fire_slop = 6.0
	profile.head_rate = 0.0
	profile.weak_spot_rate = 0.25
	profile.telegraph_read = 0.0
	profile.boss_keep = 0.0
	profile.fire_jitter = 0.15
	profile.think_hz = 5
	profile.retreat_margin = 0.0
	profile.revive_eagerness = 0.25
	profile.ammo_floor_mags = 2
	profile.ammo_topoff = 0.5
	profile.saves_for.clear()
	(
		profile
		. shopping
		. assign(
			[
				&"door_concession",
				&"crane_play",
				&"weapon_shotgun",
				&"door_booth",
				&"crane_play",
				&"weapon_rifle",
				&"door_back_lot",
				&"upgrade_weapon",
				&"tonic_hearty",
			]
		)
	)
	return profile


static func regular() -> BotProfile:
	return BotProfile.new()  # The field defaults are the regular bot's.


static func veteran() -> BotProfile:
	var profile := BotProfile.new()
	profile.title = "Veteran"
	profile.reaction_seconds = 0.25
	profile.max_aim_speed = 540.0
	profile.aim_stiffness = 20.0
	profile.track_error = 2.0
	profile.fire_slop = 1.8
	profile.head_rate = 0.75
	profile.weak_spot_rate = 0.8
	profile.fire_jitter = 0.04
	profile.think_hz = 10
	profile.retreat_margin = 1.5
	profile.revive_eagerness = 0.5
	profile.re_cuts = 2
	(
		profile
		. shopping
		. assign(
			[
				&"weapon_shotgun",
				&"weapon_rifle",
				&"door_concession",
				&"door_booth",
				&"crane_play",
				&"upgrade_weapon",
				&"tonic_hearty",
				&"door_back_lot",
			]
		)
	)
	return profile


## The old bot: everything it did before the host, run unfiltered and unchanged.
static func autopilot() -> BotProfile:
	var profile := BotProfile.new()
	profile.title = "Autopilot"
	profile.filtered = false
	profile.think_hz = 60
	return profile
