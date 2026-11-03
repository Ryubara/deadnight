class_name BotReviveRisk
extends RefCounted
## Whether a revive is safe to begin, as a pure function a test pins one case at a time (bots plan,
## phase 5, `docs/research/bots.md#revives`). The revive takes `revive_seconds` of a held button
## during which the reviver neither shoots nor moves, so a zombie that arrives inside the hold is a
## free blow on the reviver. For every zombie the bot knows of it estimates the time to reach the
## victim or the reviver (the path as the crow flies, stretched a little, over its speed) and
## compares it with the window: the walk there, the hold and a margin.
##
## - `SAFE`: nobody can arrive inside the window. Go and hold.
## - `CLEAR`: somebody can, but the bot can kill the ones that can in a time it can afford (their
##   health over the held weapon's sustained damage). Fight first, look again.
## - `UNSAFE`: too many or too tough to clear (a pack, a boss). Do not go; the bot fights from
##   where it is and, as the last one standing, kites.
## - `LATE`: the victim bleeds out before the bot can walk there. Go on without.
##
## Everything is read from what a client is told: positions, speeds (the public formula of the
## round, `RoundTuning.speed_for_round`), health (`health_for_round` times the type's share), the
## held weapon. Nothing here sends a command or reads the rules.

enum Kind { SAFE, CLEAR, UNSAFE, LATE }

## A zombie's health against the round's, and its speed against the round's, by look (the roster's
## `health_multiplier` and `speed_multiplier`; a test holds the two tables together).
const HEALTH_BY_LOOK := {&"runner": 0.55, &"brute": 2.5, &"crawler": 0.7, &"headliner": 16.25}
const SPEED_BY_LOOK := {&"runner": 1.4, &"brute": 0.4, &"crawler": 0.4, &"headliner": 0.45}
## The night's dark speed-up, assumed in full (the bot is careful).
const DARK_SPEED := 1.25
## A walk is longer than the straight line by this much.
const DETOUR := 1.2
## Metres a zombie must still close to strike (the body's width and the arm).
const STRIKE_REACH := 1.1
## Metres a second a bot is assumed to cover to the victim (a little under `run_speed`).
const WALK_SPEED := 4.2
## Share of a weapon's sustained damage that lands in a fight (a bot turns, misses and reloads).
const HIT_SHARE := 0.55
## Seconds of margin added to the window at no eagerness and at full eagerness.
const MARGIN_CAUTIOUS := 2.0
const MARGIN_BOLD := 0.6
## The longest a bot will spend killing what stands in the way, and the most zombies in the way,
## at no eagerness and at full eagerness.
const CLEAR_CAUTIOUS := 7.0
const CLEAR_BOLD := 16.0
const MOST_CAUTIOUS := 5
const MOST_BOLD := 12
## Seconds before the bleed-out under which a walk is not tried.
const BLEED_SLACK := 0.5


## A zombie the bot knows of: where it is (or will be), how fast it comes, how much health it has.
class Threat:
	extends RefCounted
	var position := Vector3.ZERO
	var speed := 0.0
	var health := 0.0

	static func make(at: Vector3, p_speed: float, p_health: float) -> Threat:
		var threat := Threat.new()
		threat.position = at
		threat.speed = p_speed
		threat.health = p_health
		return threat


## The verdict: its kind, seconds the bot needs to kill the zombies that threaten the window, the
## seconds until the first of them arrives (INF for none), how many threaten, and the window.
class Verdict:
	extends RefCounted
	var kind := Kind.SAFE
	var kill_seconds := 0.0
	var first_arrival := INF
	var count := 0
	var window := 0.0
	## The ids (indexes into the list given) of the zombies that threaten, nearest arrival first.
	var danger: Array[int] = []


## Judges a revive. `victim` and `reviver` are flat positions; `threats` the zombies known;
## `revive_seconds` the hold (`HealthTuning.revive_seconds`), `reach` how near the reviver must
## stand (`NightTuning.revive_reach`), `kill_rate` health a second the bot kills (already scaled by
## `HIT_SHARE`), `bleed` the victim's seconds left, `eagerness` the profile's 0 to 1.
static func assess(
	victim: Vector3,
	reviver: Vector3,
	threats: Array[Threat],
	revive_seconds: float,
	reach: float,
	kill_rate: float,
	bleed: float,
	eagerness: float
) -> Verdict:
	var out := Verdict.new()
	var walk := walk_seconds(reviver, victim, reach)
	if walk + BLEED_SLACK >= bleed:
		out.kind = Kind.LATE
		return out
	var margin := lerpf(MARGIN_CAUTIOUS, MARGIN_BOLD, clampf(eagerness, 0.0, 1.0))
	out.window = walk + revive_seconds + margin
	var arrivals: Array[Vector2] = []
	var health := 0.0
	for i in threats.size():
		var threat := threats[i]
		var arrive := minf(_arrival(threat, victim), _arrival(threat, reviver))
		if arrive < out.window:
			arrivals.append(Vector2(arrive, float(i)))
			health += threat.health
	if arrivals.is_empty():
		return out
	arrivals.sort()
	out.count = arrivals.size()
	out.first_arrival = arrivals[0].x
	for pair in arrivals:
		out.danger.append(int(pair.y))
	out.kill_seconds = health / maxf(kill_rate, 0.001)
	var budget := lerpf(CLEAR_CAUTIOUS, CLEAR_BOLD, clampf(eagerness, 0.0, 1.0))
	var most := roundi(lerpf(float(MOST_CAUTIOUS), float(MOST_BOLD), clampf(eagerness, 0.0, 1.0)))
	out.kind = Kind.CLEAR if out.kill_seconds <= budget and out.count <= most else Kind.UNSAFE
	return out


## Seconds a bot at `from` needs to stand within `reach` of `victim`.
static func walk_seconds(from: Vector3, victim: Vector3, reach: float) -> float:
	return maxf(_flat(from, victim) * DETOUR - reach, 0.0) / WALK_SPEED


## Seconds a zombie needs to be within striking distance of `point`.
static func _arrival(threat: Threat, point: Vector3) -> float:
	var apart := maxf(_flat(threat.position, point) - STRIKE_REACH, 0.0)
	return apart / maxf(threat.speed, 0.05)


## What a zombie of `look` has for health in `round_number`, from the round's public formula.
static func health_of(look: StringName, round_number: int, rounds: RoundTuning) -> float:
	var base := rounds.health_for_round(round_number) if rounds != null else 100.0
	return base * float(HEALTH_BY_LOOK.get(look, 1.0))


## How fast a zombie of `look` walks in `round_number`, the dark's speed-up in.
static func speed_of(look: StringName, round_number: int, rounds: RoundTuning) -> float:
	var base := rounds.speed_for_round(round_number) if rounds != null else 2.0
	return base * float(SPEED_BY_LOOK.get(look, 1.0)) * DARK_SPEED


## Health a second the bot kills with `held` against zombies of `health` (the weapon's sustained
## damage, shots landing whole, scaled by the share that lands). Zero with no weapon.
static func kill_rate_of(held: WeaponDef, health: float) -> float:
	if held == null:
		return 0.0
	return WeaponWorth.of(held, health) * HIT_SHARE


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
