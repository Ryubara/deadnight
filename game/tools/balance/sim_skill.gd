class_name SimSkill
extends RefCounted
## How a modelled player plays. Three levels, each a handful of numbers, not a brain: the simulator
## asks "how many of its shots land, where, how often does it avoid a blow, how well does it
## spend", never "what would a person do". The numbers are assumptions, written down here so a
## change is a reviewed change; docs/design/rounds.md says what they stand for.

const WEAK := &"weak"
const AVERAGE := &"average"
const STRONG := &"strong"
const ALL: Array[StringName] = [WEAK, AVERAGE, STRONG]

var id: StringName = AVERAGE
## Share of shots that land on a walker (before the type's own `hit_chance`).
var accuracy: float = 0.65
## Of the shots that land: the share that hit the head, the limbs, and (against a boss) the weak
## spot.
var head_rate: float = 0.15
var limb_rate: float = 0.1
var weak_spot_rate: float = 0.45
## Share of time spent actually shooting (the rest is moving, reloading, looking).
var uptime: float = 0.85
## Chance a plain blow misses the player (kiting, backing off, a step aside).
var dodge: float = 0.3
## How well a telegraphed blow is read: the chance a blow lands is multiplied by
## `exp(-telegraph_seconds * read)`.
var read: float = 0.5
## Share of the approach spent on lit ground (the zombies keep their round's pace there, and on the
## rest of the approach they are faster) when every circuit the player keeps on has fuel. Each
## circuit burns fuel, so this is bought, not free.
var light_use: float = 0.35
## The generator circuits the player keeps switched on for the whole night.
var circuits: Array[StringName] = [&"screen_lot", &"concession"]
## Whether the player changes weapon to suit the target in front of them (a shotgun at the door, a
## rifle at range) and not only when one runs dry.
var swaps: bool = true
## Magazines of reserve a player keeps for each weapon worth shooting before they spend on anything
## else, and the share of a weapon's reserve limit they top it up to with what is left over.
var ammo_floor_mags: int = 3
var ammo_topoff: float = 1.0
## What the player buys, first to last.
var shopping: Array[StringName] = []


## The same player on another night: every number moved by up to `spread` either way (a good night,
## a bad night), so a level is a spread of nights and not one fixed outcome.
func jittered(rng: RandomNumberGenerator, spread: float) -> SimSkill:
	var copy := SimSkill.new()
	copy.id = id
	copy.shopping = shopping
	copy.circuits = circuits
	copy.swaps = swaps
	copy.ammo_floor_mags = ammo_floor_mags
	copy.ammo_topoff = ammo_topoff
	copy.accuracy = _wobble(accuracy, rng, spread)
	copy.head_rate = _wobble(head_rate, rng, spread)
	copy.limb_rate = limb_rate
	copy.weak_spot_rate = _wobble(weak_spot_rate, rng, spread)
	copy.uptime = _wobble(uptime, rng, spread)
	copy.dodge = _wobble(dodge, rng, spread)
	copy.read = _wobble(read, rng, spread)
	copy.light_use = _wobble(light_use, rng, spread)
	return copy


## The same player on a touch screen with the aim assist at `strength` (0 to 1): the misses the
## assist wins back are added to the accuracy (`AimAssist.assisted_accuracy`, which is what
## `test_aim_assist_bot.gd` measured). Nothing else about the player moves.
func with_touch_assist(strength: float) -> SimSkill:
	accuracy = AimAssist.assisted_accuracy(accuracy, strength, AimAssistTuning.new())
	return self


static func _wobble(value: float, rng: RandomNumberGenerator, spread: float) -> float:
	return minf(value * rng.randf_range(1.0 - spread, 1.0 + spread), 0.95)


static func named(skill_id: StringName) -> SimSkill:
	var skill := SimSkill.new()
	skill.id = skill_id
	match skill_id:
		WEAK:
			skill.accuracy = 0.45
			skill.head_rate = 0.06
			skill.limb_rate = 0.12
			skill.weak_spot_rate = 0.2
			skill.uptime = 0.75
			skill.dodge = 0.12
			skill.read = 0.25
			skill.light_use = 0.1
			skill.swaps = false
			skill.ammo_floor_mags = 2
			skill.ammo_topoff = 0.5
			skill.circuits.assign([&"screen_lot"])
			(
				skill
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
					]
				)
			)
		STRONG:
			skill.accuracy = 0.82
			skill.head_rate = 0.3
			skill.limb_rate = 0.08
			skill.weak_spot_rate = 0.75
			skill.uptime = 0.92
			skill.dodge = 0.5
			skill.read = 0.9
			skill.light_use = 0.55
			skill.ammo_topoff = 1.0
			skill.circuits.assign([&"screen_lot", &"concession", &"booth"])
			(
				skill
				. shopping
				. assign(
					[
						&"weapon_shotgun",
						&"weapon_rifle",
						&"door_concession",
						&"door_booth",
						&"crane_play",
						&"door_back_lot",
					]
				)
			)
		_:
			(
				skill
				. shopping
				. assign(
					[
						&"weapon_shotgun",
						&"door_concession",
						&"weapon_rifle",
						&"door_booth",
						&"crane_play",
						&"door_back_lot",
					]
				)
			)
	return skill
