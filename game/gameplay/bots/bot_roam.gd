class_name BotRoam
extends RefCounted
## Where a bot goes when it is free to do its own thing (the `ROAM` order, the default): a place
## across the lot, picked among `BotLevel.roam_spots`, walked to, looked about from for a few
## seconds, and then another. A place is rated by
## - how far it is from the people (a roaming bot spreads away from the person, it does not shadow
##   them), up to `FAR_FROM_PEOPLE`,
## - how far it is from the other bots' places and from the places they are walking to
##   (`BotTeam.roam`), so the team fans out over the map,
## - the walk to it (the nearer first, but never a place under `MIN_LEG`),
## - the dead near it, and the places the bot was at lately.
## A place the legs could not reach is left alone until the walking mesh changes (a door bought),
## and a place is asked about (`reach`) before the bot sets out, a few at a think, so a bot never
## spends its time trying the places behind a shut door. The only chance is the bot's own
## seeded stream, so the same trace gives the same walk.
##
## A bot can end on a piece of the walking mesh that nothing joins to the rest (a step out of
## another bot's way, a blow, a place that lies on a polygon cut for a barricade): then every place
## is refused and, banned for ten minutes, none would be tried again from anywhere. Told apart from
## a place behind a shut door by the spot the bot last made a choice from, which the bot can no
## longer reach (`exact`), it takes the refusals back and walks straight back to that spot
## (`rejoin`), and chooses again from there (#1041).
##
## Pure data and arithmetic: the level, the clock and the stream are the caller's.

## Metres from the people beyond which a place is no better for being farther.
const FAR_FROM_PEOPLE := 20.0
## Metres from another bot beyond which a place is no better for being farther.
const FAR_FROM_BOTS := 16.0
## Metres: the shortest walk worth taking, and the walk at which the cost is a full point.
const MIN_LEG := 6.0
const LEG_COST := 35.0
## Metres within which the dead make a place bad, and within which a place counts as lately seen.
const DEAD_NEAR := 9.0
const VISITED_NEAR := 8.0
## Places remembered as visited.
const VISITED := 5
## Seconds a place is left alone after the legs found no way to it, if the mesh does not change.
const BAN_SECONDS := 600.0
## Places asked about at one choice (each is a path query).
const PROBES := 4
## Points of rating.
const W_AWAY := 1.0
const W_SPREAD := 1.3
const W_LEG := 0.8
const W_DEAD := 2.0
const W_VISITED := 1.5
const W_JITTER := 0.35
## Seconds the bot looks about at a place, shortest and longest, and the turn between two looks
## (radians) and the seconds each look lasts.
const DWELL := Vector2(2.0, 5.0)
const LOOK_TURN := 1.9
const LOOK_SECONDS := 1.3
## Metres from a place at which the bot counts itself there.
const ARRIVE := 1.5
## Metres from the spot it last chose from within which a bot that can reach no place walks back to
## that spot, and the seconds the walk back is given.
const REJOIN_RANGE := 6.0
const REJOIN_SECONDS := 8.0
## Metres a path may end short of a point and still reach it, when asking whether the bot is
## joined to the spot it chose from (`exact`).
const EXACT_SHORT := 0.5
## A bot with no place of the level to go to wanders: candidates at these radii (metres), this
## many directions at each.
const WANDER_RINGS: Array[float] = [9.0, 15.0]
const WANDER_DIRECTIONS := 8

## The place the bot walks to, or `Vector3.INF` when it has none (it is looking about, or nothing
## was found).
var spot := Vector3.INF
## Whether the bot is at a place and looking about.
var dwelling := false
## Where the bot looks while it looks about (a view yaw).
var look_yaw := 0.0
## The places walked to, newest last.
var visited: Array[Vector3] = []
## The spot the stranded bot walks straight back to, or `Vector3.INF` when it is not stranded.
var rejoin := Vector3.INF
## Times the bot found itself cut off from the rest of the mesh.
var strandings := 0
## `Callable(here, spot) -> bool`: whether a walk gets from `here` to the spot, ending within
## `EXACT_SHORT` of it (`reach` allows more). Whether the bot is joined to the spot it chose from;
## without it a bot is never taken for cut off.
var exact := Callable()

var _level: BotLevel
var _rng := RandomNumberGenerator.new()
var _dwell_until := -INF
var _look_until := -INF
var _banned: Dictionary = {}
var _refused: Array[Vector2i] = []
var _free := Vector3.INF
var _rejoin_until := -INF
var _mesh := -1


func _init(level: BotLevel, bot_seed: int) -> void:
	_level = level
	_rng.seed = bot_seed
	look_yaw = _rng.randf_range(-PI, PI)


## The place to walk to this think, or `Vector3.INF` while the bot looks about.
## - `here`: the bot, `now`: its clock;
## - `people`: where the people (on their feet) are; `others`: where the other bots stand or will
##   stand in a moment, and `claimed`: the places they are walking to;
## - `threats`: where the dead are believed to be;
## - `blocked`: `Callable(spot) -> bool` for a place the legs found no way to;
## - `reach`: `Callable(here, spot) -> bool` whether a walk gets there on the mesh as it is (a path
##   query), and `mesh` the mesh's number (a place found unreachable is asked again after it moves);
## - `stopped_short_of`: the goal the legs stood at the end of the path to without being near it
##   (`BotLegs.stopped_short_of`): the mesh ends short of the place, the bot is as near as it gets
##   and counts itself there.
## While `rejoin` is finite the bot is walking back to the spot it chose from and no place is
## returned.
func plan(
	here: Vector3,
	now: float,
	people: Array[Vector3],
	others: Array[Vector3],
	claimed: Array[Vector3],
	threats: Array[Vector3],
	blocked: Callable = Callable(),
	reach: Callable = Callable(),
	mesh: int = 0,
	stopped_short_of := Vector3.INF
) -> Vector3:
	if mesh != _mesh:
		_mesh = mesh
		_banned.clear()
	_refused.clear()
	if rejoin.is_finite():
		if not _joined(here, now):
			return Vector3.INF
		rejoin = Vector3.INF
	if dwelling:
		if now < _dwell_until:
			_look_about(now)
			return Vector3.INF
		dwelling = false
	if spot != Vector3.INF:
		if blocked.is_valid() and blocked.call(spot):
			_ban(spot, now)
			spot = Vector3.INF
		elif _flat(here, spot) <= ARRIVE or _is_short(spot, stopped_short_of):
			_arrive(here, now)
			return Vector3.INF
		elif not _worth_keeping(spot, threats):
			spot = Vector3.INF
	if spot == Vector3.INF:
		var spread: Array[Vector3] = others.duplicate()
		spread.append_array(claimed)
		spot = _choose(here, now, people, spread, threats, reach)
		if spot != Vector3.INF:
			_free = here
		elif _is_stranded(here):
			_strand(now)
	return spot


## Whether the bot is back on the part of the mesh the spot it left is on. A walk that has had its
## time (a wall in the way) forgets the spot: the bot is not helped by it, and goes back to choosing
## among the places, refusals and all.
func _joined(here: Vector3, now: float) -> bool:
	if now >= _rejoin_until:
		_free = Vector3.INF
		return true
	if _flat(here, _free) <= ARRIVE * 0.5:
		return true
	return exact.is_valid() and exact.call(here, _free)


## Whether every place was refused because the bot is cut off, not because the places are: it
## chose from a spot close by, and no walk gets back to that spot.
func _is_stranded(here: Vector3) -> bool:
	if _refused.is_empty() or not _free.is_finite() or not exact.is_valid():
		return false
	var apart := _flat(here, _free)
	return apart > ARRIVE * 0.5 and apart <= REJOIN_RANGE and not exact.call(here, _free)


## Takes back the refusals of this think (a bot that cannot get anywhere says nothing of the places)
## and sets out to walk back to the spot it chose from.
func _strand(now: float) -> void:
	for key in _refused:
		_banned.erase(key)
	rejoin = _free
	_rejoin_until = now + REJOIN_SECONDS
	strandings += 1


## Whether the legs stopped short of this very place.
static func _is_short(point: Vector3, stopped_short_of: Vector3) -> bool:
	return stopped_short_of.is_finite() and point.is_equal_approx(stopped_short_of)


## Forgets the place held (a fight, an errand or a revive took the bot away from it).
func drop() -> void:
	spot = Vector3.INF
	dwelling = false


## Whether the place is still a good one to walk to: the dead have not taken it.
func _worth_keeping(point: Vector3, threats: Array[Vector3]) -> bool:
	for threat in threats:
		if _flat(point, threat) < DEAD_NEAR * 0.5:
			return false
	return true


func _arrive(here: Vector3, now: float) -> void:
	_free = here
	visited.append(spot)
	if visited.size() > VISITED:
		visited.pop_front()
	dwelling = true
	_dwell_until = now + _rng.randf_range(DWELL.x, DWELL.y)
	_look_until = now
	spot = Vector3.INF


func _look_about(now: float) -> void:
	if now >= _look_until:
		_look_until = now + LOOK_SECONDS
		look_yaw = wrapf(look_yaw + LOOK_TURN * (1.0 if _rng.randf() < 0.5 else -1.0), -PI, PI)


func _ban(point: Vector3, now: float) -> void:
	_banned[_key(point)] = now + BAN_SECONDS
	_refused.append(_key(point))


func _is_banned(point: Vector3, now: float) -> bool:
	return float(_banned.get(_key(point), -INF)) > now


func _choose(
	here: Vector3,
	now: float,
	people: Array[Vector3],
	others: Array[Vector3],
	threats: Array[Vector3],
	reach: Callable
) -> Vector3:
	var found := _pick(_level.roam_spots, here, now, people, others, threats, reach)
	# With none of the level's places worth the walk (the rest are behind shut doors, or under six
	# metres away), the bot wanders: a ring of places about it on the walking mesh.
	if found == Vector3.INF:
		found = _pick(_ring(here), here, now, people, others, threats, reach)
	return found


## The best of `places` by the rating, the first of the best few the walking mesh gets to.
func _pick(
	places: Array[Vector3],
	here: Vector3,
	now: float,
	people: Array[Vector3],
	others: Array[Vector3],
	threats: Array[Vector3],
	reach: Callable
) -> Vector3:
	var rated: Array[Vector3] = []
	var scores: Dictionary = {}
	for candidate in places:
		if _is_banned(candidate, now):
			continue
		var leg := _flat(here, candidate)
		if leg < MIN_LEG:
			continue
		var score := W_AWAY * minf(_nearest(candidate, people), FAR_FROM_PEOPLE) / FAR_FROM_PEOPLE
		score += W_SPREAD * minf(_nearest(candidate, others), FAR_FROM_BOTS) / FAR_FROM_BOTS
		score -= W_LEG * leg / LEG_COST
		if _nearest(candidate, threats) < DEAD_NEAR:
			score -= W_DEAD
		if _nearest(candidate, visited) < VISITED_NEAR:
			score -= W_VISITED
		score += W_JITTER * _rng.randf()
		scores[candidate] = score
		rated.append(candidate)
	rated.sort_custom(func(a: Vector3, b: Vector3) -> bool: return scores[a] > scores[b])
	var asked := 0
	for candidate in rated:
		if not reach.is_valid():
			return candidate
		if asked >= PROBES:
			break
		asked += 1
		if reach.call(here, candidate):
			return candidate
		_ban(candidate, now)
	return Vector3.INF


## A ring of places round the bot on the walking mesh.
func _ring(here: Vector3) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for ring in WANDER_RINGS:
		for i in WANDER_DIRECTIONS:
			var heading := Vector3(0.0, 0.0, -1.0).rotated(
				Vector3.UP, TAU * float(i) / float(WANDER_DIRECTIONS)
			)
			found.append(_level.project(here + heading * ring))
	return found


## Metres to the nearest of `points` (a far number for none).
static func _nearest(point: Vector3, points: Array[Vector3]) -> float:
	var best := 1000.0
	for other in points:
		best = minf(best, _flat(point, other))
	return best


static func _key(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x * 2.0), roundi(point.z * 2.0))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
