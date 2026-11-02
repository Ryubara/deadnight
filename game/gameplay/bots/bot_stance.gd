class_name BotStance
extends RefCounted
## How a bot stands in a special round, read from what the screen announces (`round_started`'s
## `special_id`):
##
## - Midnight Stampede (runners only, 1.4 times faster than the bot's sprint): running is no use,
##   so the bot holds a choke instead, a place with walls at its back and sides where only a few
##   can come at once, and shoots; it never sprints away (`HOLD`).
## - Crawl Space (crawlers only, slow): they lie low, so the aim goes low (the aim already follows
##   the look); the bot keeps its distance as in any round, and a grenade needs a smaller pack
##   (`LOW`).
## - Double Feature (a headliner among escorts): the bot keeps the boss 6 m away, dodges its
##   telegraphed blow and aims at its weak spot (`BOSS`).
##
## `choke` rates places round the bot by the walls about them (eight rays of `COVER_REACH` metres:
## a blocked one is a wall) and keeps the best seen so far, two candidates a think, so a place costs
## sixteen rays spread over eight thinks.

enum Kind { NORMAL, HOLD, LOW, BOSS }

const STAMPEDE := &"stampede"
const CRAWL_SPACE := &"crawl_space"
const DOUBLE_FEATURE := &"double_feature"
## Rays about a place, and how far each reaches (metres).
const COVER_RAYS := 8
const COVER_REACH := 2.5
## Candidates at these radii (metres) round the bot, this many directions each.
const RINGS: Array[float] = [2.5, 4.5]
const DIRECTIONS := 8
## Candidates rated in one think.
const PER_THINK := 2
## Points of rating: a wall about the place, a metre of walk to it.
const W_WALL := 1.0
const W_WALK := 0.2
## Fewest walls about a place for it to be a choke at all.
const MIN_WALLS := 3
## Seconds a sweep of the candidates lasts before the place is chosen again, the metres the group
## may move before the search starts over round it, and the walls a new place needs over the one
## held to be worth the walk.
const SWEEP_SECONDS := 8.0
const RECENTRE := 5.0
const WALLS_TO_MOVE := 1

var spot := Vector3.INF
var spot_walls := 0

var _level: BotLevel
var _centre := Vector3.INF
var _next := 0
var _best := Vector3.INF
var _best_score := -INF
var _best_walls := 0
var _swept_at := -INF


func _init(level: BotLevel) -> void:
	_level = level


static func of(special: StringName) -> Kind:
	match special:
		STAMPEDE:
			return Kind.HOLD
		CRAWL_SPACE:
			return Kind.LOW
		DOUBLE_FEATURE:
			return Kind.BOSS
	return Kind.NORMAL


## Walls about `point`: how many of eight compass rays meet something within `COVER_REACH`.
func walls_about(point: Vector3) -> int:
	var count := 0
	for i in COVER_RAYS:
		var heading := Vector3(0.0, 0.0, -1.0).rotated(
			Vector3.UP, TAU * float(i) / float(COVER_RAYS)
		)
		if _level.room(point, heading, COVER_REACH) < COVER_REACH:
			count += 1
	return count


## Rates the next candidates round `centre` (the bot, or the group it holds with). Once all of
## them are rated, the best is the place (`spot`) if it has `MIN_WALLS`; until then `spot` is the
## last one chosen, or `Vector3.INF`. `here` is where the bot stands: a walk costs. A sweep starts
## again `SWEEP_SECONDS` after the last began.
func choke(here: Vector3, centre: Vector3, now: float) -> Vector3:
	if (
		_centre == Vector3.INF
		or Vector2(centre.x - _centre.x, centre.z - _centre.z).length() > RECENTRE
	):
		_centre = centre
		spot = Vector3.INF
		spot_walls = 0
		_swept_at = -INF
	if now - _swept_at > SWEEP_SECONDS:
		_swept_at = now
		_next = 0
		_best = Vector3.INF
		_best_score = -INF
		_best_walls = 0
	var total := RINGS.size() * DIRECTIONS
	for _i in PER_THINK:
		if _next >= total:
			break
		var ring: float = RINGS[_next / DIRECTIONS]
		var heading := Vector3(0.0, 0.0, -1.0).rotated(
			Vector3.UP, TAU * float(_next % DIRECTIONS) / float(DIRECTIONS)
		)
		_next += 1
		var point := _level.project(_centre + heading * ring)
		var walls := walls_about(point)
		var walk := Vector2(point.x - here.x, point.z - here.z).length()
		var score := W_WALL * float(walls) - W_WALK * walk
		# The gap test costs more rays, so only a place that would be the best is asked.
		if score > _best_score and not _level.in_passage(point):
			_best_score = score
			_best = point
			_best_walls = walls
	if _next >= total and _best_walls >= MIN_WALLS and _best != spot:
		if spot == Vector3.INF or _best_walls >= spot_walls + WALLS_TO_MOVE:
			spot = _best
			spot_walls = _best_walls
	return spot
