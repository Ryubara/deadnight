class_name BotFollow
extends RefCounted
## Where a bot stands to stay with the people, after Ellie in The Last of Us (Game AI Pro 2,
## chapter 35): a ring of candidate places round the group, each rated, the best one kept until
## another is clearly better, and "close enough" is enough (no stepping about for a better place).
##
## The anchor is the centre of the people the bot follows, weighted toward the one who needs help
## (a downed one counts three). A candidate is rated by
## - its distance from the anchor against a band (3 to 7 m in a fight, 4 to 10 m outside one),
## - the walk to it (the cheapest place first, so four bots take four different places),
## - the leader's facing: behind or beside, never in front, outside the line of fire,
## - the leader's side of the threats (never nearer to them than the leader), and out of the
##   leader's line to the nearest one,
## - the other bots' places (2.5 m apart at least),
## - light, distance from the fence's breaches, and not standing in a gap.
## The cheap terms rate every candidate; the costly ones (a ray or two, a mesh projection) only the
## best few. All of it is arithmetic on positions: nothing random, so the same trace gives the same
## place.

const FIGHT_BAND := Vector2(3.0, 7.0)
const CALM_BAND := Vector2(4.0, 10.0)
const SPACING := 2.5
## Candidates on the ring: this many directions at each of two radii in the band.
const DIRECTIONS := 12
const RADII := 2
## The best this many by the cheap terms are looked at closely.
const SHORTLIST := 4
## A place held beats a better one by less than this.
const KEEP_BONUS := 0.7
## Points of rating.
const W_BAND := 1.5
const W_TRAVEL := 0.06
const W_FRONT := 4.0
const W_BEHIND := 0.3
const W_THREAT_SIDE := 1.5
const W_LINE := 2.0
const W_SPACING := 1.2
const W_LIT := 0.6
const W_BREACH := 0.5
const W_PASSAGE := 4.0
const W_PASS_THROUGH := 1.0
## Metres: the breach range, the leader's line, the leader's body.
const BREACH_RANGE := 5.0
const LINE_WIDTH := 1.5
const LEADER_BODY := 1.0
## The least dot product of the direction from the leader with where the leader faces that counts
## as being in front.
const FRONT_DOT := 0.3
## Metres a candidate may move when put on the mesh.
const MESH_SLACK := 0.8

var _level: BotLevel


func _init(level: BotLevel) -> void:
	_level = level


## The anchor of the people to follow: the weighted centre of `people` (`{pos, downed, health}`),
## or `Vector3.INF` when there are none. A downed one counts three, a hurt one a little more.
static func anchor_of(people: Array[Dictionary]) -> Vector3:
	var total := 0.0
	var sum := Vector3.ZERO
	for person in people:
		var weight := 1.0
		if person.get("downed", false):
			weight += 2.0
		weight += 1.0 - clampf(float(person.get("health", 100.0)) / 100.0, 0.0, 1.0)
		sum += (person["pos"] as Vector3) * weight
		total += weight
	return sum / total if total > 0.0 else Vector3.INF


## The person nearest the anchor: whose facing and line the place is rated against.
static func leader_of(people: Array[Dictionary], anchor: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for person in people:
		var apart := _flat(person["pos"], anchor)
		if apart < best_d:
			best_d = apart
			best = person
	return best


## The place to stand, or `Vector3.INF` when the bot is well placed where it is.
## - `here`: the bot; `people`: who it follows; `others`: the places of the other bots (where they
##   stand or are going); `threats`: where the dead are; `fighting`: whether any is near;
##   `current`: the place it holds now (`Vector3.INF` for none); `avoid`: `Callable(spot) -> bool`
##   for places not to take (the ones it could not reach or got stuck going to).
func plan(
	here: Vector3,
	people: Array[Dictionary],
	others: Array[Vector3],
	threats: Array[Vector3],
	fighting: bool,
	current: Vector3,
	avoid: Callable = Callable()
) -> Vector3:
	var anchor := anchor_of(people)
	if anchor == Vector3.INF:
		return Vector3.INF
	var leader := leader_of(people, anchor)
	var band := FIGHT_BAND if fighting else CALM_BAND
	var context := {
		"here": here,
		"anchor": anchor,
		"leader": leader["pos"],
		"forward": Vector3(-sin(leader.get("facing", 0.0)), 0.0, -cos(leader.get("facing", 0.0))),
		"others": others,
		"threat": _nearest(leader["pos"], threats),
		"band": band,
	}
	if _well_placed(here, context):
		return Vector3.INF
	var shortlist := _shortlist(context, current, avoid)
	var best := Vector3.INF
	var best_score := -INF
	for entry in shortlist:
		var spot: Vector3 = entry["spot"]
		var detail := _close_look(spot, context)
		if detail == Vector3.INF:
			continue
		var score: float = entry["score"] + _lit_and_gap(detail)
		if current != Vector3.INF and _flat(spot, current) < 1.0:
			score += KEEP_BONUS
		if score > best_score:
			best_score = score
			best = detail
	return best


## The rating of a place by the cheap terms: higher is better. Public so a test reads the terms.
func rate(spot: Vector3, context: Dictionary) -> float:
	var anchor: Vector3 = context["anchor"]
	var band: Vector2 = context["band"]
	var distance := _flat(spot, anchor)
	var score := -W_BAND * maxf(maxf(band.x - distance, distance - band.y), 0.0)
	score -= W_TRAVEL * _flat(spot, context["here"])
	var leader: Vector3 = context["leader"]
	var from_leader := Vector3(spot.x - leader.x, 0.0, spot.z - leader.z)
	if from_leader.length() > 0.01:
		var dot := from_leader.normalized().dot(context["forward"])
		if dot > FRONT_DOT:
			score -= W_FRONT * (dot - FRONT_DOT)
		elif dot < -0.2:
			score += W_BEHIND
	var threat: Vector3 = context["threat"]
	if threat != Vector3.INF:
		if _flat(spot, threat) < _flat(leader, threat) - 0.5:
			score -= W_THREAT_SIDE
		if BotPath._distance_to_segment(spot, leader, threat) < LINE_WIDTH:
			score -= W_LINE
	for other: Vector3 in context["others"]:
		var apart := _flat(spot, other)
		if apart < SPACING:
			score -= W_SPACING * (SPACING - apart)
	for breach in _level.breaches:
		var apart := _flat(spot, breach)
		if apart < BREACH_RANGE:
			score -= W_BREACH * (BREACH_RANGE - apart)
	if BotPath._distance_to_segment(leader, context["here"], spot) < LEADER_BODY:
		score -= W_PASS_THROUGH
	return score


## Whether standing here is good enough to stay: inside the band, not in front of the leader, not
## on top of another bot, not in a gap.
func _well_placed(here: Vector3, context: Dictionary) -> bool:
	var band: Vector2 = context["band"]
	var distance := _flat(here, context["anchor"])
	if distance < band.x - 0.5 or distance > band.y:
		return false
	for other: Vector3 in context["others"]:
		if _flat(here, other) < SPACING * 0.6:
			return false
	var leader: Vector3 = context["leader"]
	var from_leader := Vector3(here.x - leader.x, 0.0, here.z - leader.z)
	if from_leader.length() > 0.01 and from_leader.normalized().dot(context["forward"]) > 0.6:
		return false
	return not _level.in_passage(here)


## The best `SHORTLIST` candidates by the cheap terms: `{spot, score}`, best first.
func _shortlist(context: Dictionary, current: Vector3, avoid: Callable) -> Array[Dictionary]:
	var anchor: Vector3 = context["anchor"]
	var band: Vector2 = context["band"]
	var scored: Array[Dictionary] = []
	var spots: Array[Vector3] = []
	for r in RADII:
		var radius := lerpf(band.x + 0.5, band.y - 0.5, float(r) / float(RADII - 1))
		for i in DIRECTIONS:
			var heading := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, TAU * float(i) / DIRECTIONS)
			spots.append(anchor + heading * radius)
	if current != Vector3.INF:
		spots.append(current)
	for spot in spots:
		if avoid.is_valid() and avoid.call(spot):
			continue
		scored.append({"spot": spot, "score": rate(spot, context)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return scored.slice(0, SHORTLIST)


## The candidate on the mesh and in sight of the leader's side of the world, or `Vector3.INF`.
func _close_look(spot: Vector3, context: Dictionary) -> Vector3:
	var on_mesh := _level.project(spot)
	if _flat(on_mesh, spot) > MESH_SLACK:
		return Vector3.INF
	var leader: Vector3 = context["leader"]
	var eye := Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)
	if not _level.clear(leader + eye, on_mesh + eye):
		return Vector3.INF
	return on_mesh


func _lit_and_gap(spot: Vector3) -> float:
	var extra := 0.0
	if _level.lit.is_valid() and _level.lit.call(spot):
		extra += W_LIT
	if _level.in_passage(spot):
		extra -= W_PASSAGE
	return extra


static func _nearest(from: Vector3, points: Array[Vector3]) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for point in points:
		var apart := _flat(from, point)
		if apart < best_d:
			best_d = apart
			best = point
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
