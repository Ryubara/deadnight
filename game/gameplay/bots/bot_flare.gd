class_name BotFlare
extends RefCounted
## Where a bot fires its flare to draw the dead off a downed teammate's body (bots plan, phase 5,
## `docs/research/bots.md#revives`; the lure is `docs/research/flare-lure.md`). A flare burns for
## `lure_seconds` and every walker within `lure_radius` of it goes there instead of to a player, so
## the dead that stand about a body are taken to a spot far from it, and the revive goes on.
##
## The spot is a point on the ground that
## - is at least `MIN_FROM_BODY` metres from the body and `MIN_FROM_MATE` from every other player
##   (the dead stand about the flare for the whole burn: the rule is never within 4 m of a
##   teammate, and the rest is the way the flare lands a little off), and `FIRE_MIN` to
##   `FIRE_MAX` from the bot;
## - has every zombie to be drawn within the lure's reach (with a margin);
## - is off the line to the reviver: the dead walk to it without filing past the bot, and the spot
##   does not lie on the reviver's side of the body (the angle at the body between the way to the
##   spot and the way to the bot is at least `BEHIND_DEGREES`).
##
## The shot is the view the bot looks along. A flare leaves the barrel toward what the view meets
## (`AimResolver.aim_direction`) and falls (`projectile_gravity`), so the pitch comes from a table
## of flights made once with the real projectile on flat ground, to find the lines worth trying.
## Each is then flown in the bot's own world (the walls the level can see, the dead it knows of)
## and the rules are asked of where the flare really lands, and of where it lands with the view
## turned a little to each side, so a car in the way does not spoil a shot that lands well anyway.
## Pure: positions in, a `Shot` out, or null. The motor turns and fires (`BotMotor`); the brain
## decides when (`BotRevive`).

const WEAPON := &"flare_gun"
## The nearest the spot may be to the body, to another player and to the bot, and the farthest from
## the bot (metres).
const MIN_FROM_BODY := 12.0
const MIN_FROM_MATE := 6.0
const FIRE_MIN := 8.0
const FIRE_MAX := 24.0
## The landing, flown in the bot's world, must keep these distances (the rule is 4 m from a
## teammate; the rest is a margin for a bounce or a body that moved).
const LANDED_FROM_MATE := 5.0
const LANDED_FROM_BODY := 10.0
## Metres by which the lure's reach is shortened for a zombie that must be drawn.
const REACH_MARGIN := 3.0
## Metres by which a zombie's walk to the spot may come to the bot (a zombie nearer than this to
## start with is held to how near it is).
const PATH_CLEAR := 2.5
## Degrees at the body between the way to the spot and the way to the bot: the spot lies no nearer
## the bot's side than this.
const BEHIND_DEGREES := 60.0
## The share of the distance aimed at under which a flare that landed counts as taken by something
## on the way.
const SHORT_SHARE := 0.7
## Headings and distances (from the bot) of the spots tried.
const HEADINGS := 24
const RINGS: Array[float] = [10.0, 13.0, 16.0, 19.0, 22.0]
## The turns of the view (radians: yaw, pitch) the chosen shot is flown again with: the motor fires
## within a degree of the order, and a low flare lands metres off for a hair of pitch.
const WOBBLES: Array[Vector2] = [
	Vector2(0.03, 0.0), Vector2(-0.03, 0.0), Vector2(0.0, 0.02), Vector2(0.0, -0.02)
]
## Spots flown for real in one plan, best first.
const FLOWN_AT_MOST := 8
## Radians either side of a heading that failed in which no other spot is flown for (a wall in the
## way of one shot is in the way of its neighbours).
const BLOCKED_ARC := 0.15
## A spot is rated by its distance from the body up to this far.
const BODY_RATED_TO := 16.0
## Seconds ahead a player is taken to stand for the distances to the spot.
const MATE_LOOKAHEAD := 2.0
## Pitches of the table of flights, in radians, and the step of the flights (seconds).
const PITCH_LOW := -0.7
const PITCH_HIGH := 0.5
const PITCH_STEP := 0.01
const FLIGHT_STEP := 1.0 / 60.0

## Pitch against the metres from the bot's feet at which the flare lands on flat ground (shared:
## the flare is the same for every bot).
static var _table: Array[Vector2] = []

## The flare gun.
var def: WeaponDef = WeaponCatalog.get_def(WEAPON)


## What to do: look along `yaw` and `pitch` and fire. `landing` is where the flight ends in the
## bot's world (`spot` is the same, kept for the callers that read it).
class Shot:
	extends RefCounted
	var yaw := 0.0
	var pitch := 0.0
	var landing := Vector3.ZERO
	var spot := Vector3.ZERO


## A shot that draws `lured` (the zombies' places) off `body` from where the bot stands at `here`,
## or null. `mates` are the other players (`pos`, `velocity`, `dead`); `level` is the bot's world;
## `dead` the zombies the bot believes in as `{id: {pos, yaw, scale}}`: a flare bursts on the first
## one it meets, so a shot through them is not taken.
func plan(
	here: Vector3,
	body: Vector3,
	lured: Array[Vector3],
	mates: Array[Dictionary],
	level: BotLevel,
	dead: Dictionary = {}
) -> Shot:
	var rated: Array[Dictionary] = []
	for h in HEADINGS:
		var heading := TAU * float(h) / float(HEADINGS)
		var way := Vector3(-sin(heading), 0.0, -cos(heading))
		for ring in RINGS:
			var spot := here + way * ring
			if is_fit(spot, here, body, lured, mates):
				var score := minf(_flat(spot, body), BODY_RATED_TO) - 0.25 * ring
				rated.append({"spot": spot, "score": score})
	rated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var blocked: Array[float] = []
	var flown := 0
	var world := Callable(BotFlare, &"_floor")
	if level != null and level.sight.is_valid():
		world = level.sight
	for entry in rated:
		var spot: Vector3 = entry["spot"]
		var heading := atan2(here.x - spot.x, here.z - spot.z)
		var shut := false
		for wall in blocked:
			shut = shut or absf(angle_difference(heading, wall)) < BLOCKED_ARC
		if shut:
			continue
		flown += 1
		var pitch := pitch_for(_flat(here, spot))
		var landing := fly(here, heading, pitch, world, dead)
		if _flat(here, landing) < _flat(here, spot) * SHORT_SHARE:
			# Something took the flare on the way (a car, a wall): its neighbours are shut too.
			blocked.append(heading)
		elif _lands_fit(landing, here, body, lured, mates):
			var shot := _steady(here, heading, pitch, landing, body, lured, mates, world, dead)
			if shot != null:
				return shot
		if flown >= FLOWN_AT_MOST:
			break
	return null


## Whether a flare that really landed at `landing` keeps the rules: far from the body and from every
## player, and the dead to be drawn are within its reach.
func _lands_well(
	landing: Vector3, body: Vector3, lured: Array[Vector3], mates: Array[Dictionary]
) -> bool:
	if _flat(landing, body) < LANDED_FROM_BODY:
		return false
	if not _far_from_mates(landing, mates, LANDED_FROM_MATE):
		return false
	var reach := def.lure_radius - 1.0
	for at in lured:
		if _flat(at, landing) > reach:
			return false
	return true


## Whether a flare landing at `spot` suits the rules above, from the pure positions alone.
func is_fit(
	spot: Vector3, here: Vector3, body: Vector3, lured: Array[Vector3], mates: Array[Dictionary]
) -> bool:
	var apart := _flat(spot, here)
	var placed := _flat(spot, body) >= MIN_FROM_BODY and apart >= FIRE_MIN and apart <= FIRE_MAX
	if not placed or is_nan(pitch_for(apart)):
		return false
	if not _far_from_mates(spot, mates, MIN_FROM_MATE) or _behind_the_reviver(spot, here, body):
		return false
	var reach := def.lure_radius - REACH_MARGIN
	for at in lured:
		if _flat(at, spot) > reach:
			return false
		if not _walks_clear(at, spot, here):
			return false
	return true


## The view pitch at which a flare fired on flat ground lands `distance` metres from the bot's
## feet, or NAN when none does (the table's range is the view from straight down to a little above
## the horizon).
func pitch_for(distance: float) -> float:
	var table := landings()
	if table.is_empty() or distance < table[0].y or distance > table[table.size() - 1].y:
		return NAN
	for i in range(1, table.size()):
		if table[i].y >= distance:
			var span := maxf(table[i].y - table[i - 1].y, 0.0001)
			return lerpf(
				table[i - 1].x, table[i].x, clampf((distance - table[i - 1].y) / span, 0.0, 1.0)
			)
	return NAN


## Pitch against landing distance on flat ground, from the lowest pitch to the highest: the real
## projectile and the real aim correction flown once per pitch. A flight that ends in the air
## (the burn of its own lifetime) counts as landing where it ended.
func landings() -> Array[Vector2]:
	if not _table.is_empty():
		return _table
	var made: Array[Vector2] = []
	var pitch := PITCH_LOW
	var floor_at := Callable(BotFlare, &"_floor")
	while pitch <= PITCH_HIGH:
		var end := fly(Vector3.ZERO, 0.0, pitch, floor_at)
		made.append(Vector2(pitch, Vector2(end.x, end.z).length()))
		pitch += PITCH_STEP
	# Keep it increasing so a lookup can search it: a pitch that lands nearer than the one below
	# it is dropped.
	var kept: Array[Vector2] = []
	for entry in made:
		if kept.is_empty() or entry.y > kept[kept.size() - 1].y:
			kept.append(entry)
	_table = kept
	return _table


## Where a flare fired from a bot standing at `here`, looking along `yaw` and `pitch`, ends: the
## server's own projectile from the barrel the motor sets, with the aim correction, in the world
## `world_ray` answers for (`world_ray(from, to)` is the distance to the first wall, or -1.0) and
## among `targets` (as the server's `{id: {pos, yaw, scale}}`).
func fly(
	here: Vector3, yaw: float, pitch: float, world_ray: Callable, targets: Dictionary = {}
) -> Vector3:
	var eye := here + Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)
	var view := Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD
	var muzzle := here + Basis(Vector3.UP, yaw) * BotMotor.MUZZLE
	var aim := AimResolver.aim_direction(def, eye, view, muzzle, targets, world_ray)
	var flare := ProjectileState.new(0, 0, def, muzzle, aim * def.projectile_speed)
	var steps := ceili(def.projectile_lifetime / FLIGHT_STEP) + 2
	for _i in steps:
		var result := flare.step(FLIGHT_STEP, targets, world_ray)
		if not result.is_empty():
			return result["point"]
	return flare.position


# --- Checking a shot ---


## The shot, when the flare lands well from the order and from the turns of the view a little to
## each side (the motor fires within a degree of the order, and a corner a hand's breadth off the
## line is the end of a flare), or null.
func _steady(
	here: Vector3,
	yaw: float,
	pitch: float,
	landing: Vector3,
	body: Vector3,
	lured: Array[Vector3],
	mates: Array[Dictionary],
	world: Callable,
	dead: Dictionary
) -> Shot:
	for wobble: Vector2 in WOBBLES:
		var off := fly(here, yaw + wobble.x, pitch + wobble.y, world, dead)
		if _flat(here, off) < FIRE_MIN or not _lands_well(off, body, lured, mates):
			return null
	var shot := Shot.new()
	shot.yaw = yaw
	shot.pitch = pitch
	shot.landing = landing
	shot.spot = landing
	return shot


## Whether a flare that really landed at `landing` is a good one: far enough from the bot, far from
## the body and from every player, the dead to be drawn within its reach, not on the reviver's side
## of the body, and the dead not drawn past the bot.
func _lands_fit(
	landing: Vector3, here: Vector3, body: Vector3, lured: Array[Vector3], mates: Array[Dictionary]
) -> bool:
	if _flat(here, landing) < FIRE_MIN or not _lands_well(landing, body, lured, mates):
		return false
	if _behind_the_reviver(landing, here, body):
		return false
	for at in lured:
		if not _walks_clear(at, landing, here):
			return false
	return true


## Whether `spot` is at least `least` metres from every living player, where each stands and where
## each will be shortly.
func _far_from_mates(spot: Vector3, mates: Array[Dictionary], least: float) -> bool:
	for mate in mates:
		if mate.get("dead", false):
			continue
		var at: Vector3 = mate["pos"]
		if _flat(spot, at) < least:
			return false
		var then: Vector3 = at + (mate.get("velocity", Vector3.ZERO) as Vector3) * MATE_LOOKAHEAD
		if _flat(spot, then) < least:
			return false
	return true


## Whether a flare that landed at `landing` is `LANDED_FROM_MATE` metres or more from every living
## player (the order is given up when a player walks that near before the shot).
func is_clear_of_mates(landing: Vector3, mates: Array[Dictionary]) -> bool:
	return _far_from_mates(landing, mates, LANDED_FROM_MATE)


## Whether the spot lies on the bot's side of the body: the angle at the body between the way to
## the spot and the way to the bot is under `BEHIND_DEGREES`. A bot at the body has no side.
func _behind_the_reviver(spot: Vector3, here: Vector3, body: Vector3) -> bool:
	var to_bot := Vector2(here.x - body.x, here.z - body.z)
	if to_bot.length() < PATH_CLEAR:
		return false
	var to_spot := Vector2(spot.x - body.x, spot.z - body.z)
	return absf(rad_to_deg(to_bot.angle_to(to_spot))) < BEHIND_DEGREES


## Whether a zombie at `at` walking straight to `spot` keeps away from the bot (as far as it was to
## start with, at most `PATH_CLEAR`): the dead drawn off do not file past the one who fires.
func _walks_clear(at: Vector3, spot: Vector3, here: Vector3) -> bool:
	var start := _flat(at, here)
	return _segment_distance(at, spot, here) >= minf(PATH_CLEAR, start) - 0.3


## Metres from `point` to the segment `from` to `to`, on the ground.
static func _segment_distance(from: Vector3, to: Vector3, point: Vector3) -> float:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var p := Vector2(point.x, point.z)
	var along := b - a
	var length_squared := along.length_squared()
	if length_squared < 0.0001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(along) / length_squared, 0.0, 1.0)
	return (a + along * t).distance_to(p)


## The flat ground at the feet's height (y = 0) as the flare's world.
static func _floor(from: Vector3, to: Vector3) -> float:
	if from.y < 0.0 or to.y >= 0.0:
		return -1.0
	return from.distance_to(to) * from.y / (from.y - to.y)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
