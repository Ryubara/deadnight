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
@export_range(0.0, 10.0, 0.05, "suffix:deg") var track_error: float = 1.8
## Share of contacts the bot aims at the head of, when the target is slow and near.
@export_range(0.0, 1.0, 0.01) var head_rate: float = 0.12
## Seconds, at most, between two shots on top of the weapon's own interval.
@export_range(0.0, 1.0, 0.01, "suffix:s") var fire_jitter: float = 0.08

@export_group("Movement")
## Whether the bot walks to stay near the people. Off, it holds where it stands (a test that must
## not walk: a body the physics engine moves does not repeat to the last bit).
@export var follows: bool = true

@export_group("Thinking")
## How many times a second the brain decides; the motor runs every tick.
@export_range(1, 30, 1, "suffix:Hz") var think_hz: int = 8
## Metres of margin before a zombie reaches the bot at which it starts to back away.
@export_range(0.0, 20.0, 0.5, "suffix:m") var retreat_margin: float = 7.0
## How much risk a revive may take, 0 (none) to 1 (any); used from phase 5.
@export_range(0.0, 1.0, 0.05) var revive_eagerness: float = 0.5
## Brain failures (a thought that comes back empty or broken) after which the brain is switched off
## and the motor goes on alone.
@export_range(1, 10, 1) var brain_failure_limit: int = 1


static func rookie() -> BotProfile:
	var profile := BotProfile.new()
	profile.title = "Rookie"
	profile.reaction_seconds = 0.55
	profile.max_aim_speed = 240.0
	profile.aim_stiffness = 9.0
	profile.track_error = 3.0
	profile.head_rate = 0.05
	profile.fire_jitter = 0.15
	profile.think_hz = 5
	profile.retreat_margin = 5.0
	profile.revive_eagerness = 0.25
	return profile


static func regular() -> BotProfile:
	return BotProfile.new()


static func veteran() -> BotProfile:
	var profile := BotProfile.new()
	profile.title = "Veteran"
	profile.reaction_seconds = 0.25
	profile.max_aim_speed = 540.0
	profile.aim_stiffness = 20.0
	profile.track_error = 1.0
	profile.head_rate = 0.20
	profile.fire_jitter = 0.04
	profile.think_hz = 10
	profile.retreat_margin = 9.0
	profile.revive_eagerness = 0.5
	return profile


## The old bot: everything it did before the host, run unfiltered and unchanged.
static func autopilot() -> BotProfile:
	var profile := BotProfile.new()
	profile.title = "Autopilot"
	profile.filtered = false
	profile.think_hz = 60
	return profile
