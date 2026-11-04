class_name BotGrenadier
extends RefCounted
## When and where a bot throws its grenade. It looks for a pack the blast would take (the dead
## within `CLUSTER_RADIUS` of each other, as they will stand when the fuse runs out: they keep
## coming), and throws only when
## - the blast would land where it does not reach the bot: at least `SAFE_FROM_SELF` metres from
##   it. A blast hurts a player by `PlayerBlast`, all the way out to the blast radius, so "not
##   reach" is the distance where it takes `HARMLESS_SHARE` of their health (`harmless_apart`),
##   which the number is at least (a test holds it to it). Only the thrower takes a grenade's
##   damage (#856), so no teammate is looked at (`docs/research/grenades.md`, "Only the thrower");
## - the way to it is open: the arc is clear of walls, and of the dead that would stop the grenade
##   short, nearer the bot than `SAFE_FROM_SELF`, to lie at its own feet (#872);
## - the pack is big enough (`MIN_PACK`; the crawlers of Crawl Space, which are hard to hit with a
##   gun, count from `MIN_PACK_LOW`), and the bot has waited out the last throw (`COOLDOWN`).
##
## The pitch comes from a table of flights made once with the real `GrenadeArc` on flat ground
## (`landings`): the grenade hops and rolls on, and what counts is where it lies when the fuse runs
## out. The tests fly the real arc again and measure where it ends.
## Pure: positions in, a `Throw` out, or null. The motor does the throwing (`BotMotor`).

const DEF_PATH := "res://gameplay/grenades/defs/frag.tres"
## The blast must be this far from the bot (metres): the rule is that it takes under
## `HARMLESS_SHARE` of the bot's health there (`harmless_apart`, 5.8 m), and the grenade lands a
## metre or so from where it was aimed (hops, view not quite on), so the bot is planned a metre
## further off: a blast that lands exactly there takes 2% of its health.
const SAFE_FROM_SELF := 7.0
## A zombie nearer than this (metres) keeps the bot from throwing: it is busy with it. Not
## `SAFE_FROM_SELF`, which is about where the blast lands.
const NEAR_ZOMBIE := 6.0
## The share of a player's health a blast may take at the bot's spot and still not "reach" it: 10%,
## a graze that mends in seconds.
const HARMLESS_SHARE := 0.1
const THROW_MARGIN := 1.5
## Metres from its own live grenade within which a bot does not walk on (follow, chase, errand): a
## runner covers the 10 metres from the blast's edge to its middle in the 2 s the fuse has left,
## so only standing and fighting until it goes off keeps the bot out (#872).
const WAIT_RANGE := 20.0
## Metres across a pack, and the zombies that make one.
const CLUSTER_RADIUS := 3.0
const MIN_PACK := 3
const MIN_PACK_LOW := 2
## The farthest and nearest a throw is aimed (metres from the bot).
const RANGE_MAX := 12.0
const RANGE_MIN := 3.0
## Seconds between two throws.
const COOLDOWN := 6.0
## The hand's reach in front of the body (`NightTuning.grenade_hand_reach`), and the seconds from
## the button coming up to the grenade leaving the hand (`grenade_release_over`, `_under`) and the
## pin held before that: the fuse that is left for the flight is what remains.
const HAND_REACH := 0.35
const RELEASE_OVER := 0.375
const RELEASE_UNDER := 0.4167
const COOK_SECONDS := 0.04
## Pitches tried for the table of flights, in radians: from this to that in steps, flown at this
## step.
const PITCH_LOW := -0.6
const PITCH_HIGH := 1.45
const PITCH_STEP := 0.03
const FLIGHT_STEP := 1.0 / 60.0
## Metres by which the shortest throw in the table may overshoot a goal that is nearer still.
const REACH_SLACK := 1.0
## The farthest an underarm toss is used for (metres); beyond it, overarm. The heavy underarm toss
## lies 4.5 m out at most (a blast that close is never planned: `SAFE_FROM_SELF`).
const UNDERARM_UP_TO := 4.0
## Samples of the arc checked for walls.
const ARC_SAMPLES := 6

## The tables of flights by style (shared: the grenade is the same for every bot).
static var _tables := {}

var def: GrenadeDef
## The clock (seconds) of the last throw ordered.
var last_throw := -INF

var _level: BotLevel


## What to do: throw `style` (`over` or `under`) looking along `yaw` and `pitch`, to land the blast
## at `landing`.
class Throw:
	extends RefCounted
	var style: StringName = &"over"
	var yaw := 0.0
	var pitch := 0.0
	var landing := Vector3.ZERO
	var pack := 0


func _init(level: BotLevel) -> void:
	_level = level
	def = load(DEF_PATH) as GrenadeDef
	landings(&"over")
	landings(&"under")


## A throw to make now, or null. `contacts` are the believed zombies in sight, `left` the grenades
## carried.
func plan(
	here: Vector3, contacts: Array[Dictionary], left: int, now: float, low_pack: bool = false
) -> Throw:
	if left <= 0 or now - last_throw < COOLDOWN or contacts.size() < _need(low_pack):
		return null
	var cluster := best_cluster(contacts, here, _need(low_pack))
	if cluster.is_empty():
		return null
	var landing: Vector3 = cluster["centre"]
	if not is_safe(landing, here):
		return null
	var apart := _flat(here, landing)
	var style := &"under" if apart <= UNDERARM_UP_TO else &"over"
	var pitch := solve_pitch(apart, style)
	if is_nan(pitch):
		style = &"over"
		pitch = solve_pitch(apart, style)
	if is_nan(pitch):
		return null
	var offset := landing - here
	var throw := Throw.new()
	throw.style = style
	throw.yaw = atan2(-offset.x, -offset.z)
	throw.pitch = pitch
	throw.landing = landing
	throw.pack = int(cluster["count"])
	if not arc_is_open(here, throw, contacts):
		return null
	return throw


## The densest group of at least `need` contacts, as `{centre, count}` (centre: where they will
## stand when the fuse runs out, flat), or empty. A group is the zombies within `CLUSTER_RADIUS`
## of one of them; ties go to the nearer to the bot.
func best_cluster(contacts: Array[Dictionary], here: Vector3, need: int) -> Dictionary:
	var ahead: Array[Vector3] = []
	for contact in contacts:
		ahead.append(_where_then(contact))
	var best := {}
	var best_count := need - 1
	var best_apart := INF
	for i in ahead.size():
		var count := 0
		var sum := Vector3.ZERO
		for j in ahead.size():
			if _flat(ahead[i], ahead[j]) <= CLUSTER_RADIUS:
				count += 1
				sum += ahead[j]
		if count < need:
			continue
		var centre := sum / float(count)
		var apart := _flat(here, centre)
		if apart < RANGE_MIN or apart > RANGE_MAX:
			continue
		if count > best_count or (count == best_count and apart < best_apart):
			best_count = count
			best_apart = apart
			best = {"centre": centre, "count": count}
	return best


## Whether a blast at `landing` is clear of the bot.
func is_safe(landing: Vector3, here: Vector3) -> bool:
	return _flat(landing, here) >= SAFE_FROM_SELF


## The distance from a blast beyond which it takes under `HARMLESS_SHARE` of a player's health
## (`PlayerBlast`): the least `SAFE_FROM_SELF` may be.
func harmless_apart() -> float:
	return PlayerBlast.distance_for(HARMLESS_SHARE, def.player_full_radius, def.blast_radius)


## The metres from its own live grenade at which a bot steps out: the harmless distance and the
## throw margin, a little before the blast's edge.
func step_out_reach() -> float:
	return harmless_apart() + THROW_MARGIN


## Where a contact will stand when the fuse runs out: it walks on at its speed, and stops a body's
## width from the bot (it is at its feet by then, and that is not a place to aim at).
func _where_then(contact: Dictionary) -> Vector3:
	var now_at: Vector3 = contact["position"]
	var then: Vector3 = now_at + (contact["velocity"] as Vector3) * def.fuse
	then.y = now_at.y
	return then


## The view pitch at which a throw of `style` ends `distance` metres from the bot when the fuse runs
## out, or NAN when no pitch reaches it. A grenade bounces and rolls on from where it first touches
## the ground (a flat throw lies 9 to 13 m out, the heavy grenade hardly rolls), so a short throw is
## a lob: the answer is the highest pitch that reaches the distance (the far side of the longest
## throw). The server lifts the throw by the style's own angle above the view. Read from a table of
## flights, `landings`, made once with the real arc.
func solve_pitch(distance: float, style: StringName) -> float:
	var table: Array[Vector2] = landings(style)
	var goal := distance - HAND_REACH
	for i in range(table.size() - 1, -1, -1):
		if table[i].y < goal:
			continue
		if i == table.size() - 1:
			return table[i].x if table[i].y <= goal + REACH_SLACK else NAN
		var span := maxf(table[i].y - table[i + 1].y, 0.0001)
		return lerpf(table[i + 1].x, table[i].x, clampf((goal - table[i + 1].y) / span, 0.0, 1.0))
	return NAN


## Pitch against the metres from the hand's drop at which the grenade is when the fuse runs out, on
## flat ground, for one style: the real `GrenadeArc` flown once per pitch (the table is shared by
## every bot of the process), from the lowest pitch to the highest.
func landings(style: StringName) -> Array[Vector2]:
	var key := String(style)
	if _tables.has(key):
		return _tables[key]
	var table: Array[Vector2] = []
	var under := style == &"under"
	var flight := def.fuse - (RELEASE_UNDER if under else RELEASE_OVER) - COOK_SECONDS
	var pitch := PITCH_LOW
	while pitch <= PITCH_HIGH:
		var aim := Basis.from_euler(Vector3(pitch, 0.0, 0.0)) * Vector3.FORWARD
		var result := GrenadeArc.predict(
			def,
			Vector3(0.0, def.hand_height, 0.0),
			aim,
			Vector3.ZERO,
			under,
			_floor,
			FLIGHT_STEP,
			flight
		)
		var at: Vector3 = result["landing"]
		table.append(Vector2(pitch, Vector2(at.x, at.z).length()))
		pitch += PITCH_STEP
	_tables[key] = table
	return table


## The flat ground at y = 0 as the grenade's world.
static func _floor(from: Vector3, to: Vector3) -> Dictionary:
	if from.y < 0.0 or to.y >= 0.0:
		return {}
	return {"distance": from.distance_to(to) * from.y / (from.y - to.y), "normal": Vector3.UP}


## Whether the walls leave the arc alone, and so do the dead that would stop it short: a few
## samples of the flight, each joined to the next. A zombie in the way (`ZombieBump`, where it will
## stand as the grenade passes) that the grenade meets nearer the bot than `SAFE_FROM_SELF` drops it
## there, at the bot's own feet; one met farther off only lands it among the dead (#872).
func arc_is_open(here: Vector3, throw: Throw, contacts: Array[Dictionary] = []) -> bool:
	var under := throw.style == &"under"
	var angle := throw.pitch + deg_to_rad(def.under_lift_deg if under else def.over_lift_deg)
	var speed := def.under_speed if under else def.over_speed
	var heading := Vector3(-sin(throw.yaw), 0.0, -cos(throw.yaw))
	var vx := speed * cos(angle)
	var vy := speed * sin(angle)
	var fall := (vy + sqrt(vy * vy + 2.0 * def.gravity * def.hand_height)) / def.gravity
	var from := here + Vector3(0.0, def.hand_height, 0.0) + heading * HAND_REACH
	for i in range(1, ARC_SAMPLES + 1):
		var t := fall * float(i) / float(ARC_SAMPLES)
		var to := (
			here
			+ heading * (HAND_REACH + vx * t)
			+ Vector3(0.0, maxf(def.hand_height + vy * t - 0.5 * def.gravity * t * t, 0.05), 0.0)
		)
		if not _level.clear(from, to):
			return false
		if not contacts.is_empty() and _stopped_short(here, from, to, t, contacts):
			return false
		from = to
	return true


## Whether a zombie stops the grenade on the segment `from` to `to` (flown by `time`) nearer the
## bot than `SAFE_FROM_SELF`.
func _stopped_short(
	here: Vector3, from: Vector3, to: Vector3, time: float, contacts: Array[Dictionary]
) -> bool:
	var bodies := {}
	for contact in contacts:
		var at: Vector3 = contact["position"] + (contact["velocity"] as Vector3) * time
		at.y = (contact["position"] as Vector3).y
		bodies[int(contact["id"])] = {"pos": at}
	var bump := ZombieBump.nearest(from, to, bodies)
	if bump.is_empty():
		return false
	var dir := (to - from).normalized()
	return _flat(from + dir * float(bump["distance"]), here) < SAFE_FROM_SELF


func _need(low_pack: bool) -> int:
	return MIN_PACK_LOW if low_pack else MIN_PACK


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
