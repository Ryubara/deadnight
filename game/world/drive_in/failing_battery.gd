class_name FailingBattery
extends RefCounted
## How the back lot's lights burn: dimmed, and struggling to stay on like a dying battery
## (Deadnight #851). A pure function of the time and the lamp's number, so a recording, a test and
## every client see the same lights (no clock, no random draw: the "random" is an integer hash of
## the seed, the cycle and the lamp).
##
## The shape, from slow to quick:
##   - the base: `LightTuning.failing_base`, with a slow wander of a few seconds (a drifting sag);
##   - a cycle (`failing_cycle` seconds) holds at most one event, picked for every lamp together
##     (the battery is one): nothing, a slow sag, a stutter (two quick dips) or a dropout (out for
##     a third of a second, then a stumbling recovery). A lamp's own depth, delay (up to
##     `LAMP_DELAY`) and a one-in-four chance of sitting an event out make the lamps differ without
##     adding events.
##
## Not a strobe, and kept safe on purpose: the dips of one cycle are at least `REST_SECONDS` away
## from the next cycle's, a cycle has at most two dips, so no second holds more than two flashes
## (the common guidance for photosensitivity is three, WCAG 2.3.1 "Three Flashes or Below
## Threshold"), and the dips never reach black: the lights stay on (`visible`) the whole time, so a
## Compatibility mesh never changes its set of lights.
##
## The same shape is the tank's warning (`brownout`): when the generator's tank is in its last
## tenth, the lamps that follow it sag and dip in these events, the deeper the lower the tank, so
## the flicker says "running out" without ever being a strobe.
##
## A sign follows the flicker by following a lamp of the group (`LightFollower`, as `LotNeonSign`
## does): the level of the lamp it follows is this function's, scaled by its circuit and the tank.
## A node that is not a lamp asks `level` directly with the same `seconds` and a `lamp` number.

## What a cycle holds.
enum Kind { CALM, SAG, STUTTER, DROPOUT }

## The most a lamp's own clock is late against the battery's, in seconds.
const LAMP_DELAY := 0.05
## Where an event starts in its cycle: this long after the cycle begins, plus up to the jitter.
const EVENT_LEAD := 0.3
const EVENT_JITTER := 0.4
## The shortest quiet between the end of one cycle's last event and the start of the next's.
const REST_SECONDS := 1.5
## The chance that a lamp takes part in the cycle's event.
const PARTICIPATION := 0.75
## How deep a lamp's dip goes, from the shallowest lamp to the deepest (1 is the floor).
const DEPTH_SHALLOW := 0.6
## The slow wander's two periods, in seconds.
const WANDER_SLOW := 5.3
const WANDER_FAST := 2.1
## The chances of the kinds in a cycle, as the upper bounds of the roll: calm, sag, stutter, then
## dropout for the rest.
const CHANCE_CALM := 0.3
const CHANCE_SAG := 0.55
const CHANCE_STUTTER := 0.8
## The kinds' shapes: [seconds from the event's start, how much of the dip is applied (0 none, 1
## all)], smoothed between the points.
const SAG_SHAPE: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.45, 0.55), Vector2(0.9, 0.0)]
const STUTTER_SHAPE: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(0.08, 1.0),
	Vector2(0.16, 1.0),
	Vector2(0.3, 0.0),
	Vector2(0.42, 0.0),
	Vector2(0.5, 0.8),
	Vector2(0.56, 0.8),
	Vector2(0.74, 0.0),
]
const DROPOUT_SHAPE: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(0.08, 1.0),
	Vector2(0.45, 1.0),
	Vector2(0.57, 0.35),
	Vector2(0.65, 0.8),
	Vector2(0.73, 0.8),
	Vector2(1.1, 0.0),
]
## The hash's salts: one per thing that is rolled.
const _SALT_KIND := 1
const _SALT_START := 2
const _SALT_TAKES_PART := 3
const _SALT_DEPTH := 4
const _SALT_DELAY := 5
const _SALT_WANDER := 6


## The share of its own light lamp number `lamp` gives at `seconds`: the base with the wander and
## the cycle's event. Always above 0 (the lights never go out), at most `failing_base` plus the
## wander.
static func level(seconds: float, lamp: int, seed_value: int = -1) -> float:
	var tuning := LightTuning.current()
	var chosen := tuning.failing_seed if seed_value < 0 else seed_value
	var phase_a := _roll(chosen, lamp, _SALT_WANDER)
	var phase_b := _roll(chosen, lamp, _SALT_WANDER + 100)
	var wander := (
		0.6 * sin(TAU * (seconds / WANDER_SLOW + phase_a))
		+ 0.4 * sin(TAU * (seconds / WANDER_FAST + phase_b))
	)
	var base := tuning.failing_base + tuning.failing_wander * wander
	return base * (1.0 - dip(seconds, lamp, chosen) * (1.0 - tuning.failing_floor))


## The share of its light a lamp of the generator gives while the tank is low (`power_level` from
## 1, healthy, to 0, dry; 0 and below is out): the tank's sag, and the cycle's event on top of it,
## deeper the lower the tank (the square root of how far it has fallen, so the warning shows from
## the first drop). Healthy, 1. The same events as the failing battery, so no second holds more
## than three flashes at any level of the tank.
static func brownout(seconds: float, lamp: int, power_level: float, seed_value: int = -1) -> float:
	if power_level <= 0.0:
		return 0.0
	if power_level >= 1.0:
		return 1.0
	var tuning := LightTuning.current()
	var chosen := tuning.failing_seed if seed_value < 0 else seed_value
	var sag := lerpf(tuning.sag_floor, 1.0, power_level)
	var severity := sqrt(1.0 - power_level)
	return sag * (1.0 - severity * dip(seconds, lamp, chosen) * (1.0 - tuning.failing_floor))


## How much of its dip the lamp is in at `seconds`: 0 steady, 1 at the floor.
static func dip(seconds: float, lamp: int, seed_value: int) -> float:
	var tuning := LightTuning.current()
	var delay := LAMP_DELAY * _roll(seed_value, lamp, _SALT_DELAY)
	var shifted := seconds - delay
	var cycle := floori(shifted / tuning.failing_cycle)
	var into := shifted - float(cycle) * tuning.failing_cycle
	var starts := EVENT_LEAD + EVENT_JITTER * _roll(seed_value, cycle, _SALT_START)
	var shape := shape_of(kind_of(cycle, seed_value))
	if shape.is_empty() or _roll(seed_value + lamp, cycle, _SALT_TAKES_PART) >= PARTICIPATION:
		return 0.0
	var depth := lerpf(DEPTH_SHALLOW, 1.0, _roll(seed_value + lamp, cycle, _SALT_DEPTH))
	return depth * _sample(shape, into - starts)


## The event the battery has in cycle number `cycle`.
static func kind_of(cycle: int, seed_value: int) -> Kind:
	var roll := _roll(seed_value, cycle, _SALT_KIND)
	if roll < CHANCE_CALM:
		return Kind.CALM
	if roll < CHANCE_SAG:
		return Kind.SAG
	if roll < CHANCE_STUTTER:
		return Kind.STUTTER
	return Kind.DROPOUT


static func shape_of(kind: Kind) -> Array[Vector2]:
	match kind:
		Kind.SAG:
			return SAG_SHAPE
		Kind.STUTTER:
			return STUTTER_SHAPE
		Kind.DROPOUT:
			return DROPOUT_SHAPE
	return []


## The shape at `at` seconds from its start: 0 before and after it, smoothed between its points.
static func _sample(shape: Array[Vector2], at: float) -> float:
	if at <= shape[0].x or at >= shape[shape.size() - 1].x:
		return 0.0
	for i in range(1, shape.size()):
		if at <= shape[i].x:
			var from := shape[i - 1]
			var to := shape[i]
			return lerpf(from.y, to.y, smoothstep(from.x, to.x, at))
	return 0.0


## A repeatable number in 0 to 1 from three integers: a 32-bit integer hash ("lowbias32"), the same
## on every machine.
static func _roll(a: int, b: int, salt: int) -> float:
	var x := (a * 73856093 + b * 19349663 + salt * 83492791) & 0xFFFFFFFF
	x = x ^ (x >> 16)
	x = (x * 0x7FEB352D) & 0xFFFFFFFF
	x = x ^ (x >> 15)
	x = (x * 0x846CA68B) & 0xFFFFFFFF
	x = x ^ (x >> 16)
	return float(x) / 4294967296.0
