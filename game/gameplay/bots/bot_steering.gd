class_name BotSteering
extends RefCounted
## Reflex movement that never leaves the walking mesh. A dodge, a retreat or a kite picks among
## `HEADINGS` directions round the bot, rates each by what a person weighs without thinking, and
## projects the end of the best one onto the mesh, so a bot in a panic cannot run off a ledge or
## into a wall (the shipped games' "panicky" steering did; `docs/research/bots.md#movement`).
##
## A heading is rated by: how much farther it takes the bot from each threat (a faster one
## weighs more), how far it goes toward the goal if the bot has one, how much room there is ahead
## (the open length of a ray at knee height), whether the ground it ends on is lit, whether it
## goes round the nearest loop, and whether it keeps the heading of the last choice (so a kite does
## not flicker). A heading whose end is off the mesh, or that a wall stops short, is not a
## candidate.

const HEADINGS := 12
## Metres the end of a candidate heading is placed ahead, and the room looked at.
const STEP := 2.5
const ROOM_LIMIT := 8.0
## A candidate whose end is farther than this from the mesh is dropped (metres), and one that a
## wall stops within this distance.
const OFF_MESH := 0.45
const WALL_STOP := 1.4
## The weights of the terms.
const W_AWAY := 1.0
const W_GOAL := 1.0
const W_ROOM := 0.6
const W_LIT := 0.25
const W_KEEP := 0.35
const W_LOOP := 0.4
## Metres a threat is felt from, and the speed (m/s) at which its weight doubles.
const THREAT_RANGE := 14.0
## The most threats a rating looks at (the nearest ones): a crowd is a direction, not a list.
const THREATS_KEPT := 8
## The metres of net approach (summed over the threats felt) beyond which the best heading is no
## way out.
const BOXED_IN := 0.5
const THREAT_SPEED := 4.0

var _level: BotLevel


func _init(level: BotLevel) -> void:
	_level = level


## The best heading as a flat unit vector, or zero when none is a candidate (the bot is boxed in).
## `threats` are `{position, speed}`; `goal_dir` is a flat unit vector toward where the bot would
## like to go (zero for none); `previous` is the last choice (zero for none). The headings are rated
## on the flat ground first and the best are put on the mesh in turn, because a mesh query costs
## far more than a rating: the first whose end is on the mesh wins.
func pick(
	here: Vector3, threats: Array[Dictionary], goal_dir: Vector3, previous: Vector3
) -> Vector3:
	for entry in _rated(here, threats, goal_dir, previous):
		# A heading that takes the bot closer to what it flees is no way out; if every one does, it is
		# boxed in.
		if entry["gain"] > -BOXED_IN and _on_mesh(entry):
			return entry["heading"]
	return Vector3.ZERO


## Every candidate heading with its score and projected end: `{heading, end, score, gain}`, best
## first.
## The ones that are not candidates are left out.
func rate(
	here: Vector3, threats: Array[Dictionary], goal_dir: Vector3, previous: Vector3
) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for entry in _rated(here, threats, goal_dir, previous):
		if _on_mesh(entry):
			kept.append(entry)
	return kept


## The headings a wall does not stop at once, rated, best first; the end of each is not yet on the
## mesh (`aimed`).
func _rated(
	here: Vector3, threats: Array[Dictionary], goal_dir: Vector3, previous: Vector3
) -> Array[Dictionary]:
	var near := _nearest_threats(here, threats)
	var rated: Array[Dictionary] = []
	for i in HEADINGS:
		var heading := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, TAU * float(i) / HEADINGS)
		var open := _level.room(here, heading, ROOM_LIMIT)
		if open < WALL_STOP:
			continue
		var aimed := here + heading * minf(STEP, open - 0.3)
		(
			rated
			. append(
				{
					"heading": heading,
					"aimed": aimed,
					"end": aimed,
					"score": _score(here, aimed, heading, open, near, goal_dir, previous),
					"gain": _gain(here, aimed, near),
				}
			)
		)
	rated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return rated


## Whether the end of a rated heading is on the mesh; its `end` becomes the projected point.
func _on_mesh(entry: Dictionary) -> bool:
	var aimed: Vector3 = entry["aimed"]
	var end := _level.project(aimed)
	entry["end"] = end
	return Vector2(end.x - aimed.x, end.z - aimed.z).length() <= OFF_MESH


## The threats that are felt, the nearest `THREATS_KEPT` of them.
func _nearest_threats(here: Vector3, threats: Array[Dictionary]) -> Array[Dictionary]:
	var felt: Array[Dictionary] = []
	for threat in threats:
		var apart := _flat(here, threat["position"])
		if apart <= THREAT_RANGE:
			felt.append(
				{"position": threat["position"], "speed": threat.get("speed", 0.0), "d": apart}
			)
	if felt.size() > THREATS_KEPT:
		felt.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
		felt.resize(THREATS_KEPT)
	return felt


## Metres the end takes the bot away from the threats it feels, the nearest weighing most.
func _gain(here: Vector3, end: Vector3, threats: Array[Dictionary]) -> float:
	var total := 0.0
	for threat in threats:
		total += _flat(end, threat["position"]) - _flat(here, threat["position"])
	return total


func _score(
	here: Vector3,
	end: Vector3,
	heading: Vector3,
	open: float,
	threats: Array[Dictionary],
	goal_dir: Vector3,
	previous: Vector3
) -> float:
	var score := 0.0
	for threat in threats:
		var at: Vector3 = threat["position"]
		var before := _flat(here, at)
		if before > THREAT_RANGE:
			continue
		var gained := _flat(end, at) - before
		var weight := 1.0 + float(threat.get("speed", 0.0)) / THREAT_SPEED
		# Near threats count for more: the gain is the same metres, the danger is not.
		score += W_AWAY * weight * gained / (1.0 + before / 5.0)
	if goal_dir.length() > 0.01:
		score += W_GOAL * heading.dot(goal_dir)
	score += W_ROOM * minf(open / ROOM_LIMIT, 1.0)
	if _level.lit.is_valid() and _level.lit.call(end):
		score += W_LIT
	if previous.length() > 0.01 and heading.dot(previous) > 0.95:
		score += W_KEEP
	score += W_LOOP * _loop_pull(here, heading)
	return score


## 1 for a heading that goes round the nearest loop (its tangent), 0 away from any loop. The sense
## in which the loop is circled is the one the heading itself picks.
func _loop_pull(here: Vector3, heading: Vector3) -> float:
	var best := 0.0
	for loop in _level.loops:
		var near := _nearest_on(loop, here)
		if near["distance"] > BotLevel.LOOP_REACH:
			continue
		var tangent: Vector3 = near["tangent"]
		var along := absf(heading.dot(tangent))
		var closeness: float = 1.0 - float(near["distance"]) / BotLevel.LOOP_REACH
		best = maxf(best, along * closeness)
	return best


## The point of a closed polyline nearest to `at`: `{distance, tangent}`.
static func _nearest_on(loop: PackedVector3Array, at: Vector3) -> Dictionary:
	var best := INF
	var tangent := Vector3.ZERO
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var near := BotPath._distance_to_segment(at, a, b)
		if near < best:
			best = near
			tangent = Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	return {"distance": best, "tangent": tangent}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
