class_name BotLegs
extends RefCounted
## The legs of a bot: every tick it turns what the brain wants (a goal to walk to, or a reflex
## heading to take) into the way to walk now, and sees to it that the bot gets there.
##
## - A goal is walked to along a cached path (`BotPath`: a look-ahead point, a query budget, doors
##   and unreachable goals); a reflex heading is walked as it is (it was chosen on the mesh).
## - A person who walks at the bot is given way: the bot steps out of the line at the last moment
##   (inside 1.2 m, or closing in a gap), picking the heading with room as a reflex does.
## - A bot that is commanded to walk and does not get anywhere climbs the stuck ladder
##   (`BotStuck`): sidestep, repath to a jittered goal, jump (and sprint if nothing is near), drop
##   the goal, walk back along its breadcrumbs, and at last report itself (`report`). It never
##   teleports.
##
## It sets `wish`, `sprint` and `jump`; the motor turns them into the stick. Time is the step it is
## given, chance is the bot's own stream.

## The speeds the stuck detector expects (metres a second): a run and a sprint.
const RUN_SPEED := 4.8
const SPRINT_SPEED := 7.0
## Metres from a goal at which a bot counts as there, unless the brain says otherwise.
const ARRIVED := 1.0
## A person this close is given way; or this close and closing in a gap.
const YIELD_CLOSE := 1.2
const YIELD_NEAR := 2.5
## Closing speed (m/s) that counts as walking at the bot.
const CLOSING := 0.4
## Seconds a step out of the way lasts, a sidestep of the ladder, and the gap between two jumps.
const YIELD_HOLD := 0.6
const SIDESTEP_SECONDS := 0.6
const JUMP_EVERY := 0.4
## Metres of jitter given to a goal at the repath rung.
const JITTER := 1.5
## Breadcrumbs kept, the least apart (metres) two are, and how near one counts as reached.
const CRUMBS := 10
const CRUMB_APART := 1.5
const CRUMB_REACHED := 0.8
## Metres from the bot within which the dead make a sprint unwise.
const SPRINT_SAFE := 4.0
## Decisions put into a stuck report.
const REPORT_DECISIONS := 20
## Seconds a dropped goal stays dropped.
const DROP_SECONDS := 10.0
## Seconds between two looks at whether the bot stands in a gap, and how near a person must be.
const GAP_EVERY := 0.25
const GAP_PEOPLE := 8.0

## What the legs ask of the motor this tick.
var wish := Vector3.ZERO
var sprint := false
var jump := false
var path: BotPath
var stuck := BotStuck.new()
var steering: BotSteering
## Filled when the ladder reaches its last rung: `{position, goal, path, rungs}`. The owner reads it
## and clears it (`take_report`); a callable would tie this object to its owner.
var report: Dictionary = {}
## Seconds spent giving way, and seconds standing in a gap.
var yielded_seconds := 0.0
var blocking_seconds := 0.0
## The goals the ladder dropped, newest last (for the brain to see it must choose another).
var dropped: Array[Vector3] = []

var _level: BotLevel
var _rng: RandomNumberGenerator
var _last_here := Vector3.INF
var _crumbs: Array[Vector3] = []
var _side := 1.0
var _yield_left := 0.0
var _yield_dir := Vector3.ZERO
var _rung_seen := 0
var _jitter := Vector3.ZERO
var _goal_seen := Vector3.INF
var _may_query := true
var _gap_timer := 0.0
var _in_gap := false


func _init(level: BotLevel, rng: RandomNumberGenerator) -> void:
	_level = level
	_rng = rng
	path = BotPath.new(level.map)
	steering = BotSteering.new(level)


## The report of a stuck bot, once; empty when there is none.
func take_report() -> Dictionary:
	var out := report
	report = {}
	return out


## The doors the frame shows open (a change drops the cache, see `BotPath.note_doors`).
func note_doors(count: int, now: float) -> void:
	path.note_doors(count, now)


## One tick. `me` is the bot's entry of the frame, `intent` what the brain wants, `crew` the other
## players as `{pos, velocity, bot, downed}`, `threat` how far the nearest thing it believes in is.
func step(
	delta: float,
	now: float,
	me: Dictionary,
	intent: BotIntent,
	crew: Array[Dictionary],
	threat: float,
	may_query: bool = true
) -> void:
	_may_query = may_query
	wish = Vector3.ZERO
	sprint = false
	jump = false
	var here: Vector3 = me.get("pos", Vector3.ZERO)
	if me.get("downed", false) or me.is_empty():
		_idle(here)
		return
	var base := _base_direction(here, intent, now)
	_watch_the_gap(delta, here, base, crew)
	# Giving way to a person who walks at the bot.
	var given := _give_way(delta, here, crew)
	var direction := given if given != Vector3.ZERO else base
	var progress := 0.0
	if _last_here != Vector3.INF and base != Vector3.ZERO and given == Vector3.ZERO:
		var gone := here - _last_here
		progress = Vector2(gone.x, gone.z).dot(Vector2(base.x, base.z))
	_last_here = here
	var run_wanted := intent.run
	var walking := base != Vector3.ZERO and given == Vector3.ZERO
	var rung := stuck.feed(
		delta, (SPRINT_SPEED if run_wanted else RUN_SPEED) if walking else 0.0, progress
	)
	if rung > 0:
		direction = _climb(delta, now, here, intent, base)
		# The third rung sprints when nothing is near.
		run_wanted = run_wanted or (rung == 3 and threat > SPRINT_SAFE)
	else:
		_rung_seen = 0
		_note_crumb(here, base, progress)
	if direction != Vector3.ZERO:
		wish = direction
		sprint = run_wanted


## Time spent standing in a gap with a person about, counted every quarter second: the rays that
## tell a gap are too many to cast every tick.
func _watch_the_gap(delta: float, here: Vector3, base: Vector3, crew: Array[Dictionary]) -> void:
	_gap_timer -= delta
	if _gap_timer > 0.0:
		blocking_seconds += delta if _in_gap else 0.0
		return
	_gap_timer = GAP_EVERY
	_in_gap = false
	if base != Vector3.ZERO:
		return
	for other in crew:
		if not other.get("bot", false) and _flat(here, other["pos"]) < GAP_PEOPLE:
			_in_gap = _level.in_passage(here)
			return


# --- Where to go ---


## The way the bot would walk with nothing in the way: along its path to the goal, or the reflex
## heading, or zero.
func _base_direction(here: Vector3, intent: BotIntent, now: float) -> Vector3:
	if intent.reflex.length() > 0.01:
		return Vector3(intent.reflex.x, 0.0, intent.reflex.z).normalized()
	if intent.goal == Vector3.INF:
		path.forget()
		return Vector3.ZERO
	if intent.goal != _goal_seen:
		if _goal_seen == Vector3.INF or _goal_seen.distance_to(intent.goal) > BotPath.GOAL_MOVED:
			_jitter = Vector3.ZERO
			stuck.reset()
		_goal_seen = intent.goal
	var radius := intent.goal_radius if intent.goal_radius > 0.0 else ARRIVED
	if _flat(here, intent.goal) <= radius:
		return Vector3.ZERO
	var status := path.ask(here, intent.goal + _jitter, now, false, _may_query)
	if status != BotPath.Status.OK:
		return Vector3.ZERO
	if path.arrived(here, radius):
		return Vector3.ZERO
	return path.direction(here)


# --- Giving way ---


## A heading out of the way of a person walking at the bot, or zero. Held for `YIELD_HOLD`.
func _give_way(delta: float, here: Vector3, crew: Array[Dictionary]) -> Vector3:
	if _yield_left > 0.0:
		_yield_left -= delta
		yielded_seconds += delta
		return _yield_dir
	for other in crew:
		if other.get("bot", false) or other.get("downed", false):
			continue
		var at: Vector3 = other["pos"]
		var apart := _flat(here, at)
		if apart > YIELD_NEAR:
			continue
		var velocity: Vector3 = other.get("velocity", Vector3.ZERO)
		var toward := Vector3(here.x - at.x, 0.0, here.z - at.z)
		if toward.length() < 0.01:
			continue
		var closing := velocity.dot(toward.normalized())
		var in_gap := apart <= YIELD_NEAR and closing > CLOSING and _level.in_passage(here)
		if (apart <= YIELD_CLOSE and closing > CLOSING) or in_gap:
			var threats: Array[Dictionary] = [{"position": at, "speed": velocity.length()}]
			var heading := steering.pick(here, threats, Vector3.ZERO, Vector3.ZERO)
			if heading != Vector3.ZERO:
				_yield_dir = heading
				_yield_left = YIELD_HOLD
				return _yield_dir
	return Vector3.ZERO


# --- The ladder ---


func _climb(delta: float, now: float, here: Vector3, intent: BotIntent, base: Vector3) -> Vector3:
	var rung := stuck.rung
	var entered := rung != _rung_seen
	_rung_seen = rung
	if entered and rung == 1:
		_side = -_side
	var way := base
	match rung:
		1:
			# Sidestep, to alternating sides on each climb, then try the way again.
			if stuck.rung_age < SIDESTEP_SECONDS and base != Vector3.ZERO:
				way = base.rotated(Vector3.UP, PI * 0.5 * _side)
		2:
			if entered:
				_repath(here, intent, now)
			if base == Vector3.ZERO:
				way = _base_direction(here, intent, now)
		3:
			jump = fmod(stuck.rung_age, JUMP_EVERY) < delta * 2.0
		4:
			if entered:
				_drop(intent, now)
			way = Vector3.ZERO
		5:
			way = _back_along_crumbs(here)
		_:
			if entered:
				report = {
					"position": here,
					"goal": intent.goal,
					"path": path.points.duplicate(),
					"rungs": stuck.climbed.duplicate(),
					"episode": stuck.episode_seconds,
				}
	return way


## Repath from scratch: from the nearest mesh point, to a goal moved a little by the bot's own
## stream (or, with no path, the heading turned a little).
func _repath(here: Vector3, intent: BotIntent, now: float) -> void:
	path.forget()
	if intent.goal == Vector3.INF:
		return
	_jitter = Vector3(_rng.randf_range(-JITTER, JITTER), 0.0, _rng.randf_range(-JITTER, JITTER))
	path.ask(here, intent.goal + _jitter, now, true)


## Drops the goal: it is marked blocked for a while and the brain is told to take another.
func _drop(intent: BotIntent, now: float) -> void:
	if intent.goal == Vector3.INF:
		return
	path.block(intent.goal, now, DROP_SECONDS)
	path.forget()
	dropped.append(intent.goal)
	if dropped.size() > CRUMBS:
		dropped.pop_front()


## Back along the places where it last made progress, newest first.
func _back_along_crumbs(here: Vector3) -> Vector3:
	while not _crumbs.is_empty() and _flat(here, _crumbs.back()) < CRUMB_REACHED:
		_crumbs.pop_back()
	if _crumbs.is_empty():
		return Vector3.ZERO
	var to: Vector3 = _crumbs.back() - here
	to.y = 0.0
	return to.normalized()


func _note_crumb(here: Vector3, base: Vector3, progress: float) -> void:
	if base == Vector3.ZERO or progress <= 0.0:
		return
	if _crumbs.is_empty() or _flat(here, _crumbs.back()) >= CRUMB_APART:
		_crumbs.append(here)
		if _crumbs.size() > CRUMBS:
			_crumbs.pop_front()


func _idle(here: Vector3) -> void:
	_last_here = here
	stuck.reset()
	_rung_seen = 0
	_yield_left = 0.0


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
