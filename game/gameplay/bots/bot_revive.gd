class_name BotRevive
extends RefCounted
## What a bot does about a downed teammate (bots plan, phase 5, `docs/research/bots.md#revives`).
## It uses the game's own revive (the held `use` beside the body, `ReviveChannel`); this class only
## decides when to go, when to fight first and when to let go.
##
## Each think it looks at the downed players in order of need (a person before a bot, the least time
## left first, the nearest) and for each asks the risk function (`BotReviveRisk`) whether the hold
## is safe. Then:
## - the bot the claim table names (`BotClaims`: the nearest, a 3 s lease) is the *reviver*:
##   `GO` when the risk is clear, `HOLD` beside the body, `CLEAR` (fight from near the body, the
##   zombies nearest the body first) when the dead that can reach it can be killed in time;
## - the other bots *cover* (`COVER`): they stand within a few metres of the body and fight, the
##   zombies nearest the body first;
## - the last one standing, with the risk not clear, *survives* (`SURVIVE`): it does not go, it
##   kites (a wide retreat margin), because a downed player gets up when the round ends;
## - a risk that is too much for any (`UNSAFE`) sends nobody; the bot goes on as before.
##
## Commit and abort have hysteresis: once the hold has begun only the abort rule lets go of it (more
## than one zombie on the bot and 20 health lost in a second, or under 30% health; past 60% of the
## hold only the health). A bot that lets go goes to `CLEAR` and tries again after a pause. The
## walk there is held to a looser risk than the start (`COMMIT_BOOST`), so a zombie that shows
## up on the way does not turn it round at once.
##
## It reads the bot's beliefs (the teammates' entries carry `bleed`, `reviver`, `revive`) and never
## the frame; it writes only into the intent.

enum Mode { NONE, GO, HOLD, CLEAR, COVER, SURVIVE }

## The hold's length and the reach, as the game has them (`HealthTuning.revive_seconds`,
## `NightTuning.revive_reach`; a test holds the two together).
const REVIVE_SECONDS := 3.5
const REVIVE_REACH := 2.0
## Metres from the body at which the hold begins (inside the reach), and the radius of the walk.
const HOLD_FROM := 1.6
const STAND := 1.0
## Metres from the body a clearing bot goes to, and a covering one, and how far from the body a
## covering bot stands before it walks back.
const STANDOFF := 7.0
const COVER_STAND := 4.0
const COVER_FROM := 7.5
## A bot farther than this from the body leaves it to the others and goes on as before.
const COVER_RANGE := 30.0
## Metres from the body within which a zombie is shot first.
const BIAS_RADIUS := 7.0
## Share of full health (0 to 1) under which a hold is let go of, whatever the progress; and the
## share of the hold after which only that rule applies.
const ABORT_HEALTH := 0.3
const COMMITTED_PROGRESS := 0.6
## Health lost in `ABORT_WINDOW` seconds with `ABORT_ATTACKERS` zombies within `ON_SELF` metres.
const ABORT_LOSS := 20.0
const ABORT_WINDOW := 1.0
const ABORT_ATTACKERS := 2
const ON_SELF := 2.5
## The retreat margin (metres) a bot that survives keeps from the dead.
const KITE_MARGIN := 5.0
## Seconds a bot that let go waits before it tries again.
const RETRY_PAUSE := 1.5
## Added to the profile's eagerness while the bot is on its way, so the walk is judged more loosely
## than the start.
const COMMIT_BOOST := 0.35
## A full health, as the frame counts it.
const FULL_HEALTH := 100.0

## Set by the brain.
var team: BotTeam
var telemetry: BotTelemetry
var rounds: RoundTuning

## The downed player a person pinged (`BotPings.downed`), raised first; 0 for none.
var pinged := 0

## What the bot is doing about whom, and the verdict that led to it.
var mode := Mode.NONE
var victim := 0
var verdict: BotReviveRisk.Verdict
## Seconds a clearing bot was at it, for the metrics.
var clear_seconds := 0.0

var _profile: BotProfile
var _retry_at := -INF
var _health_log: Array[Vector2] = []


func _init(profile: BotProfile) -> void:
	_profile = profile


## Decides this think and fills the intent for it; returns the mode (NONE leaves the intent to the
## rest of the brain). `held` is the weapon in hand and `round_number` the round, for the risk
## function.
func run(
	intent: BotIntent,
	beliefs: BotBeliefs,
	me: Dictionary,
	held: WeaponDef,
	round_number: int,
	step: float
) -> Mode:
	var now := beliefs.now
	var here: Vector3 = me["pos"]
	_note_health(now, float(me.get("health", FULL_HEALTH)))
	var me_id := beliefs.me
	var down := _downed(beliefs, here)
	if team != null and victim != 0 and not _still_down(beliefs, victim):
		team.claims.release_victim(victim)
	if down.is_empty() or team == null:
		return _end(Mode.NONE, 0)
	var last := _last_standing(beliefs, me_id)
	var threats := _threats(beliefs, round_number)
	var cover_for := 0
	for mate: Dictionary in down:
		var id: int = mate["id"]
		var holder := int(mate.get("reviver", 0))
		if holder != 0 and holder != me_id:
			cover_for = cover_for if cover_for != 0 else id
			continue
		var owned := team.claims.held_by(me_id, now)
		if owned != 0 and owned != id:
			continue
		var holding := mode == Mode.HOLD and victim == id
		var judged := _judge(mate, here, threats, held, round_number)
		if judged.kind == BotReviveRisk.Kind.LATE and not holding:
			continue
		if judged.kind == BotReviveRisk.Kind.UNSAFE and not holding:
			if last:
				return _survive(intent, id, judged)
			continue
		var apart := _flat(here, mate["pos"])
		if not team.claims.request(id, me_id, apart, now, holding):
			cover_for = cover_for if cover_for != 0 else id
			continue
		return _claimant(intent, beliefs, me, mate, judged, last, step)
	if cover_for != 0:
		return _cover(intent, beliefs.teammates[cover_for], here)
	return _end(Mode.NONE, 0)


## The bot went down (or the night began again): nothing is in hand.
func reset() -> void:
	mode = Mode.NONE
	victim = 0
	verdict = null
	_health_log.clear()


## The id of the zombie to shoot first among `targets` (believed, in sight) while the bot guards a
## body: the one nearest the body within `BIAS_RADIUS` of it, unless `current` already is one or a
## zombie is on the bot. -1 for no change.
func prefer(targets: Array[Dictionary], beliefs: BotBeliefs, here: Vector3, current: int) -> int:
	if mode == Mode.NONE or mode == Mode.HOLD or not beliefs.teammates.has(victim):
		return -1
	var body: Vector3 = beliefs.teammates[victim]["pos"]
	var best := -1
	var best_apart := BIAS_RADIUS
	for contact in targets:
		if _flat(here, contact["position"]) <= ON_SELF:
			return -1
		var apart := _flat(body, contact["position"])
		if contact["id"] == current and apart <= BIAS_RADIUS:
			return -1
		if apart < best_apart:
			best_apart = apart
			best = contact["id"]
	return best


## The retreat margin (metres) the brain keeps while this bot survives, or 0 for none.
func kite_margin() -> float:
	return KITE_MARGIN if mode == Mode.SURVIVE else 0.0


# --- Deciding ---


func _claimant(
	intent: BotIntent,
	beliefs: BotBeliefs,
	me: Dictionary,
	mate: Dictionary,
	judged: BotReviveRisk.Verdict,
	last: bool,
	step: float
) -> Mode:
	var now := beliefs.now
	var id: int = mate["id"]
	var body: Vector3 = mate["pos"]
	var here: Vector3 = me["pos"]
	var apart := _flat(here, body)
	verdict = judged
	if mode == Mode.HOLD and victim == id and apart <= HOLD_FROM + 0.5:
		if _should_let_go(beliefs, me, mate):
			_retry_at = now + RETRY_PAUSE
			if telemetry != null:
				telemetry.count(&"revive_aborts")
			return _clear(intent, id, body, apart, step)
		return _hold(intent, id, body)
	if now < _retry_at or judged.kind != BotReviveRisk.Kind.SAFE:
		if last:
			return _survive(intent, id, judged)
		return _clear(intent, id, body, apart, step)
	if apart <= HOLD_FROM:
		return _hold(intent, id, body)
	return _go(intent, id, body)


func _go(intent: BotIntent, id: int, body: Vector3) -> Mode:
	intent.goal = body
	intent.goal_radius = STAND
	intent.run = true
	intent.note = "revive_go"
	return _end(Mode.GO, id)


func _hold(intent: BotIntent, id: int, body: Vector3) -> Mode:
	intent.goal = body
	intent.goal_radius = STAND
	intent.run = false
	intent.use_held = true
	intent.target_id = -1
	intent.melee_ok = false
	intent.quick_melee_ok = false
	intent.reload = false
	intent.swap = false
	intent.keep_weapon = true
	intent.look_yaw = NAN
	intent.note = "revive_hold"
	return _end(Mode.HOLD, id)


func _clear(intent: BotIntent, id: int, body: Vector3, apart: float, step: float) -> Mode:
	if apart > STANDOFF:
		intent.goal = body
		intent.goal_radius = STANDOFF - 1.0
		intent.run = false
	intent.note = "revive_clear"
	clear_seconds += step
	return _end(Mode.CLEAR, id)


func _survive(intent: BotIntent, id: int, judged: BotReviveRisk.Verdict) -> Mode:
	verdict = judged
	intent.note = "survive"
	return _end(Mode.SURVIVE, id)


func _cover(intent: BotIntent, mate: Dictionary, here: Vector3) -> Mode:
	var body: Vector3 = mate["pos"]
	var apart := _flat(here, body)
	if apart > COVER_RANGE:
		return _end(Mode.NONE, 0)
	if apart > COVER_FROM:
		intent.goal = body
		intent.goal_radius = COVER_STAND
		intent.run = false
	intent.note = "cover"
	return _end(Mode.COVER, int(mate["id"]))


func _end(next: Mode, for_victim: int) -> Mode:
	mode = next
	victim = for_victim
	if next == Mode.NONE:
		verdict = null
	return next


## The risk of the hold on `mate`, from the bot's place (the walk, the dead that come, the bleed).
func _judge(
	mate: Dictionary,
	here: Vector3,
	threats: Array[BotReviveRisk.Threat],
	held: WeaponDef,
	round_number: int
) -> BotReviveRisk.Verdict:
	var health := 0.0
	for threat in threats:
		health += threat.health
	var average := health / float(maxi(threats.size(), 1))
	var rate := BotReviveRisk.kill_rate_of(
		held, average if average > 0.0 else _walker(round_number)
	)
	var eager := _profile.revive_eagerness
	if mode == Mode.GO and victim == int(mate["id"]):
		eager = minf(eager + COMMIT_BOOST, 1.0)
	return BotReviveRisk.assess(
		mate["pos"],
		here,
		threats,
		REVIVE_SECONDS,
		REVIVE_REACH,
		rate,
		float(mate.get("bleed", 0.0)),
		eager
	)


func _walker(round_number: int) -> float:
	return BotReviveRisk.health_of(&"walker", round_number, rounds)


## Whether the hold in progress should be let go of: the health rule, and the pack rule before the
## hold is far along.
func _should_let_go(beliefs: BotBeliefs, me: Dictionary, mate: Dictionary) -> bool:
	var share := float(me.get("health", FULL_HEALTH)) / FULL_HEALTH
	if share < ABORT_HEALTH:
		return true
	if float(mate.get("revive", 0.0)) > COMMITTED_PROGRESS:
		return false
	return (
		_lost_lately(beliefs.now) >= ABORT_LOSS
		and _attackers(beliefs, me["pos"]) >= ABORT_ATTACKERS
	)


## The zombies on the bot: the believed ones within `ON_SELF` metres, or the ones heard very near
## (a bot at the revive faces the body, so what hits it from behind is only heard), whichever is
## more.
func _attackers(beliefs: BotBeliefs, here: Vector3) -> int:
	var seen := 0
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if not beliefs.is_believed(contact):
			continue
		if contact["mode"] == ZombieBody.Mode.DYING:
			continue
		if _flat(here, contact["position"]) <= ON_SELF:
			seen += 1
	var heard := 0
	for sound in beliefs.heard:
		if sound["range_class"] == BotBeliefs.VERY_NEAR:
			heard += 1
	return maxi(seen, heard)


func _note_health(now: float, health: float) -> void:
	_health_log.append(Vector2(now, health))
	while _health_log.size() > 1 and now - _health_log[0].x > ABORT_WINDOW * 2.0:
		_health_log.pop_front()


## Health lost in the last `ABORT_WINDOW` seconds (the most it dropped from its highest point).
func _lost_lately(now: float) -> float:
	var highest := -INF
	var latest := 0.0
	for entry in _health_log:
		if now - entry.x <= ABORT_WINDOW:
			highest = maxf(highest, entry.y)
		latest = entry.y
	return maxf(highest - latest, 0.0) if highest > -INF else 0.0


# --- What the bot knows ---


## The downed teammates who are not dead, in order of need: a person before a bot, the least time
## left, the nearest, the lowest id.
func _downed(beliefs: BotBeliefs, here: Vector3) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id in beliefs.teammates:
		var mate: Dictionary = beliefs.teammates[id]
		if id != beliefs.me and mate.get("downed", false) and not mate.get("dead", false):
			found.append(mate)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if (int(a["id"]) == pinged) != (int(b["id"]) == pinged):
				return int(a["id"]) == pinged
			var a_bot: bool = a.get("bot", false)
			var b_bot: bool = b.get("bot", false)
			if a_bot != b_bot:
				return b_bot
			var a_left := float(a.get("bleed", 0.0))
			var b_left := float(b.get("bleed", 0.0))
			if not is_equal_approx(a_left, b_left):
				return a_left < b_left
			var a_apart := _flat(here, a["pos"])
			var b_apart := _flat(here, b["pos"])
			if not is_equal_approx(a_apart, b_apart):
				return a_apart < b_apart
			return int(a["id"]) < int(b["id"])
	)
	return found


func _still_down(beliefs: BotBeliefs, id: int) -> bool:
	var mate: Dictionary = beliefs.teammates.get(id, {})
	return not mate.is_empty() and mate.get("downed", false) and not mate.get("dead", false)


## Whether every other player is down or dead (and one is down who can still be raised).
func _last_standing(beliefs: BotBeliefs, me_id: int) -> bool:
	var raisable := false
	for id in beliefs.teammates:
		if id == me_id:
			continue
		var mate: Dictionary = beliefs.teammates[id]
		if mate.get("dead", false):
			continue
		if not mate.get("downed", false):
			return false
		raisable = true
	return raisable


## The zombies the bot believes in (seen, or remembered for the memory's length), as the risk
## function wants them.
func _threats(beliefs: BotBeliefs, round_number: int) -> Array[BotReviveRisk.Threat]:
	var found: Array[BotReviveRisk.Threat] = []
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if not beliefs.is_believed(contact):
			continue
		var mode_now: int = contact["mode"]
		if mode_now == ZombieBody.Mode.DYING:
			continue
		var look: StringName = contact.get("look", ZombieModels.DEFAULT)
		found.append(
			BotReviveRisk.Threat.make(
				beliefs.guess(contact, _profile.memory_seconds),
				BotReviveRisk.speed_of(look, round_number, rounds),
				BotReviveRisk.health_of(look, round_number, rounds)
			)
		)
	return found


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
