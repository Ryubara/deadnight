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
## The best this many (of the best `LOOKS`) by the cheap terms pass the close look.
const SHORTLIST := 3
## The most candidates looked at closely to find that many that pass.
const LOOKS := 6
## The tries of the walk toward the people, and the metres each moves the place nearer them.
const FALLBACK_TRIES := 3
const FALLBACK_STEP := 1.5
## A place held beats a better one by less than this.
const KEEP_BONUS := 0.7
## Points of rating.
## Seconds of a person's walk the anchor leads by, and the most it leads (metres).
const LEAD_SECONDS := 0.8
const LEAD_LIMIT := 4.0
const W_BAND := 1.5
const W_MIDDLE := 0.2
const W_TRAVEL := 0.06
const W_FRONT := 4.0
const W_BEHIND := 0.3
const W_THREAT_SIDE := 1.5
const W_LINE := 2.0
const W_SPACING := 1.2
const W_LIT := 0.6
const W_BREACH := 0.5
const W_PASSAGE := 4.0
const W_SLOT := 1.2
## The turn between the slots of two neighbouring bots (radians).
const SLOT_SPREAD := 0.7
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
		# Where they will be in a moment: the places are for the person, not for where they were.
		var ahead: Vector3 = (person.get("velocity", Vector3.ZERO) as Vector3) * LEAD_SECONDS
		sum += ((person["pos"] as Vector3) + ahead.limit_length(LEAD_LIMIT)) * weight
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
##   for places not to take (the ones it could not reach or got stuck going to); `slot`: the turn
##   (radians) from straight behind the leader at which this bot would like to stand, so that the
##   bots of one team fan out behind a person instead of piling onto the same place.
func plan(
	here: Vector3,
	people: Array[Dictionary],
	others: Array[Vector3],
	threats: Array[Vector3],
	fighting: bool,
	current: Vector3,
	avoid: Callable = Callable(),
	slot := 0.0,
	band_override := Vector2.ZERO
) -> Vector3:
	var anchor := anchor_of(people)
	if anchor == Vector3.INF:
		return Vector3.INF
	var leader := leader_of(people, anchor)
	var band := FIGHT_BAND if fighting else CALM_BAND
	if band_override != Vector2.ZERO:
		band = band_override
	var context := {
		"here": here,
		"anchor": anchor,
		"leader": leader["pos"],
		"forward": Vector3(-sin(leader.get("facing", 0.0)), 0.0, -cos(leader.get("facing", 0.0))),
		"others": others,
		"threat": _nearest(leader["pos"], threats),
		"band": band,
		"slot": slot,
	}
	if _well_placed(here, context):
		return Vector3.INF
	var best := Vector3.INF
	var best_score := -INF
	var looked := 0
	var seen := 0
	for entry in _shortlist(context, current, avoid):
		if seen >= SHORTLIST or looked >= LOOKS:
			break
		# The candidates come best first: when what is left cannot beat the best found even with
		# every bonus the close look adds, the rest are not looked at.
		if best_score > entry["score"] + W_LIT + KEEP_BONUS:
			break
		looked += 1
		var spot: Vector3 = entry["spot"]
		var detail := _close_look(spot, context)
		if detail == Vector3.INF:
			continue
		seen += 1
		var score: float = entry["score"] + _lit_and_gap(detail)
		if current != Vector3.INF and _flat(spot, current) < 1.0:
			score += KEEP_BONUS
		if score > best_score:
			best_score = score
			best = detail
	return best if best != Vector3.INF else _toward_the_people(here, anchor, band, avoid)


## No place on the ring is on the mesh and in the leader's sight (a room of walls and props): walk
## toward the people to the edge of the band, wherever the mesh puts it.
func _toward_the_people(here: Vector3, anchor: Vector3, band: Vector2, avoid: Callable) -> Vector3:
	var away := Vector3(here.x - anchor.x, 0.0, here.z - anchor.z)
	if away.length() <= band.y:
		return Vector3.INF
	var radius := band.y - 1.0
	for _try in FALLBACK_TRIES:
		var spot := _level.project(anchor + away.normalized() * radius)
		if not _level.in_passage(spot) and not (avoid.is_valid() and avoid.call(spot)):
			return spot
		# Not in a gap, and not where it has been: a little nearer the people.
		radius -= FALLBACK_STEP
	return Vector3.INF


## The rating of a place by the cheap terms: higher is better. Public so a test reads the terms.
func rate(spot: Vector3, context: Dictionary) -> float:
	var anchor: Vector3 = context["anchor"]
	var band: Vector2 = context["band"]
	var distance := _flat(spot, anchor)
	var score := -W_BAND * maxf(maxf(band.x - distance, distance - band.y), 0.0)
	# Inside the band the middle is best: a bot at its far edge is a step from being too far.
	score -= W_MIDDLE * absf(distance - (band.x + band.y) * 0.5)
	score -= W_TRAVEL * _flat(spot, context["here"])
	var leader: Vector3 = context["leader"]
	var from_leader := Vector3(spot.x - leader.x, 0.0, spot.z - leader.z)
	if from_leader.length() > 0.01:
		var dot := from_leader.normalized().dot(context["forward"])
		if dot > FRONT_DOT:
			score -= W_FRONT * (dot - FRONT_DOT)
		elif dot < -0.2:
			score += W_BEHIND
	if from_leader.length() > 0.01:
		var wanted: Vector3 = (-context["forward"] as Vector3).rotated(
			Vector3.UP, context.get("slot", 0.0)
		)
		score -= W_SLOT * (1.0 - from_leader.normalized().dot(wanted))
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


## The best `LOOKS` candidates by the cheap terms: `{spot, score}`, best first.
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
	return scored.slice(0, LOOKS)


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
