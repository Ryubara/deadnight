class_name BotRetreat
extends RefCounted
## The heading a bot takes when it steps out of a fight (`BotFightBrain._step_away` decides when):
## chosen among twelve on the walking mesh (`BotSteering`), with a pull toward the people (or the
## hold's spot, or home) and away from every dead it believes in and every live grenade.

## How much of the way to the people (or home) bends a retreat (so it circles the field, not a
## corner).
const HOME_BEND := 0.9
## A bot following a person that has got far from them (a pack on its heels led it away) bends its
## retreat toward them more the farther it is: from `FAR_BEND_FROM` metres (the gate of the soak is
## 25) the pull grows to `FAR_BEND` for each dead the steering feels at `FAR_BEND_FULL`. It is per
## dead because the steering adds up what each one pushes (a pull of 8 does not turn the flight of a
## bot with eight on its heels). The retreat never takes a heading that closes on the dead
## (`BotSteering.BOXED_IN`), so the pull only turns the flight round the pack, and the pack is led
## to the person instead of away from them (#784).
const FAR_BEND_FROM := 16.0
const FAR_BEND_FULL := 36.0
const FAR_BEND := 4.0
## The weight of the room ahead in a Safe bot's retreat, against `BotSteering.W_ROOM`.
const SAFE_ROOM_WEIGHT := 1.8

## The last heading chosen (zero for none): the steering keeps to it so a retreat does not flicker.
var last := Vector3.ZERO

var _profile: BotProfile
var _level: BotLevel
var _steering: BotSteering


func _init(profile: BotProfile, level: BotLevel) -> void:
	_profile = profile
	_level = level
	_steering = BotSteering.new(level)


## Forgets the last heading (the bot is no longer retreating).
func forget() -> void:
	last = Vector3.ZERO


## A heading away from what the bot knows of, with a pull toward `anchor` (or home). `blasts` are
## the live grenades it stands in reach of; `holding` and `following` are the order in force. Zero
## when it knows of nothing or is boxed in.
func heading(
	here: Vector3,
	beliefs: BotBeliefs,
	anchor: Vector3,
	play: BotPlayState,
	blasts: Array[Vector3],
	holding: bool,
	following: bool
) -> Vector3:
	var threats: Array[Dictionary] = []
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if not beliefs.is_believed(contact):
			continue
		var speed := Vector2(contact["velocity"].x, contact["velocity"].z).length()
		threats.append(
			{"position": beliefs.guess(contact, _profile.memory_seconds), "speed": speed}
		)
	# A grenade about to go off is a threat that stands still (its blast is what to keep out of).
	for point in blasts:
		threats.append({"position": point, "speed": 0.0})
	if threats.is_empty():
		last = Vector3.ZERO
		return Vector3.ZERO
	var toward := Vector3.ZERO
	var pull := _pull(here, beliefs, anchor, play, holding)
	_steering.room_weight = SAFE_ROOM_WEIGHT if play.prefers_open_ground() else BotSteering.W_ROOM
	if pull != Vector3.INF:
		var bend := HOME_BEND
		if following:
			var felt := 0
			for threat in threats:
				if _flat(here, threat["position"]) <= BotSteering.THREAT_RANGE:
					felt += 1
			bend = far_bend(_flat(here, pull), mini(felt, BotSteering.THREATS_KEPT))
		toward = Vector3(pull.x - here.x, 0.0, pull.z - here.z).normalized() * bend
	last = _steering.pick(here, threats, toward, last)
	return last


## How hard a retreat bends toward the person it follows, `distance` metres away with `felt` dead
## pushing the flight: `HOME_BEND` up to `FAR_BEND_FROM`, `FAR_BEND` for each of them (at least one)
## from `FAR_BEND_FULL`, and between in a line.
static func far_bend(distance: float, felt: int) -> float:
	var far := clampf((distance - FAR_BEND_FROM) / (FAR_BEND_FULL - FAR_BEND_FROM), 0.0, 1.0)
	return lerpf(HOME_BEND, FAR_BEND * float(maxi(felt, 1)), far)


## Where a retreat bends toward: the people (or the hold's spot), else home. A Safe bot with no one
## to stay with heads for its teammates, and a Safe holder is not pulled to the spot it backs from.
func _pull(
	here: Vector3, beliefs: BotBeliefs, anchor: Vector3, play: BotPlayState, holding: bool
) -> Vector3:
	if play.prefers_open_ground():
		if holding:
			return here
		if anchor == Vector3.INF:
			var mates_at := _nearest_mate(beliefs, here)
			if mates_at != Vector3.INF:
				return mates_at
	return anchor if anchor != Vector3.INF else _level.home


## Where the nearest teammate that is up stands, or `Vector3.INF`.
func _nearest_mate(beliefs: BotBeliefs, here: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_apart := INF
	for id in beliefs.teammates:
		var mate: Dictionary = beliefs.teammates[id]
		if id == beliefs.me or mate.get("downed", false) or mate.get("dead", false):
			continue
		var apart := _flat(here, mate["pos"])
		if apart < best_apart:
			best_apart = apart
			best = mate["pos"]
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
