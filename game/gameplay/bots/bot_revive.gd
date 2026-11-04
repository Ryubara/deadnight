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
## - a risk that is too much for any (`UNSAFE`) sends nobody to the hold, but the nearest bot that
##   is not the last one up *stages* (`STAGE`): it keeps `STAGE_FROM` metres from the body (never
##   farther), shooting the zombies nearest the body first, so that when the pack has gone or been
##   killed it is a short walk away and the body has time left (#673); the others go on as before.
## - the reviver that carries a flare and finds the dead at the body too many to clear in time fires
##   it at a spot far from the body (`BotFlare`, mode `LURE`): the dead within the flare's radius
##   walk to it for its seconds, the risk check counts them as far away, and the revive goes on.
##   The flare goes through the claim table like the revive: only the claimant fires.
##
## Commit and abort have hysteresis: once the hold has begun only the abort rule lets go of it (more
## than one zombie on the bot and 20 health lost in a second, or under 30% health; past 60% of the
## hold only the health). A bot that lets go goes to `CLEAR` and tries again after a pause. The
## walk there is held to a looser risk than the start (`COMMIT_BOOST`), so a zombie that shows
## up on the way does not turn it round at once.
##
## It reads the bot's beliefs (the teammates' entries carry `bleed`, `reviver`, `revive`) and never
## the frame; it writes only into the intent.

enum Mode { NONE, GO, HOLD, CLEAR, COVER, SURVIVE, LURE, STAGE }

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
## Metres from a body judged unsafe at which the nearest bot waits, and the radius of the walk
## there. The walk from there is `STAGE_FROM * DETOUR / WALK_SPEED`, about 5 s of the 45.
const STAGE_FROM := 14.0
const STAGE_STAND := 3.0
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
## A claimant on its way (`GO`) that has come no nearer than `STALL_GAIN` metres in `STALL_SECONDS`
## is stuck: it gives the claim up and stays out of the body for `STALL_PAUSE` seconds, so the next
## bot takes it (a bot wedged three metres from a body held the claim, and the others only covered,
## for 30 s).
const STALL_SECONDS := 5.0
const STALL_GAIN := 0.5
const STALL_PAUSE := 20.0
## Seconds a bot that let go waits before it tries again.
const RETRY_PAUSE := 1.5
## Added to the profile's eagerness while the bot is on its way, so the walk is judged more loosely
## than the start.
const COMMIT_BOOST := 0.35
## A full health, as the frame counts it.
const FULL_HEALTH := 100.0
## The fewest zombies a flare must draw off to be fired (one or two are shot).
const MIN_LURED := 2
## Metres to the nearest dead within which a flare is not begun, or an order given up (the turn and
## the shot take a second or two).
const FLARE_NEAR := 3.0
## Seconds an order is kept before it is given up (the swap, a reload of 2 s, the turn, the shot),
## and the wait after a flare is fired before the next.
const FLARE_WATCH := 5.0
const FLARE_GAP := 4.0
## Seconds before the next look for a spot after a look that found none.
const PLAN_RETRY := 1.0
## Seconds from the order to the flare's burst, counted into when the dead are drawn off.
const FLARE_LEAD := 1.5
## Seconds between two swaps asked for.
const SWAP_PAUSE := 0.8

## Switches for the soak's A/B runs (`--no-stage`, `--no-stall`); both on in the game.
static var stage_on := true
static var stall_on := true

## Set by the brain.
var team: BotTeam
var telemetry: BotTelemetry
var rounds: RoundTuning
var level: BotLevel

## The downed player a person pinged (`BotPings.downed`), raised first; 0 for none.
var pinged := 0

## What the bot is doing about whom, and the verdict that led to it.
var mode := Mode.NONE
var victim := 0
var verdict: BotReviveRisk.Verdict
## Seconds a clearing bot was at it, for the metrics.
var clear_seconds := 0.0

## The brain's word that the bot is low on health with the dead near (`BotPlayState`): it does not
## go for a body, and lets go of the walk to one, unless it is the last one up.
var retreating := false

## For each downed player the bot looked at in its last think: why it did or did not go (`why`),
## the verdict, the metres to the body and who holds the claim, so a bleed-out can say why nobody
## came (the revive soak prints it).
var account: Dictionary[int, Dictionary] = {}

var _profile: BotProfile
var _retry_at := -INF
var _best_apart := INF
var _best_at := 0.0
var _stalled_until := -INF
var _stalled_victim := 0
var _health_log: Array[Vector2] = []
var _flare := BotFlare.new()
## The flare ordered and when, the clock before which none is ordered, and the last swap asked for.
var _order: BotFlare.Shot
var _ordered_at := -INF
var _flare_ready_at := -INF
var _armed := false
var _swapped_at := -INF


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
	account.clear()
	if team != null and victim != 0 and not _still_down(beliefs, victim):
		team.claims.release_victim(victim)
	var last := _last_standing(beliefs, me_id)
	# A low bot with the dead near leaves the body to the others (`BotPlayState`), unless it is the
	# last one up or has the hold begun.
	var giving_up := retreating and not last and mode != Mode.HOLD and team != null
	if giving_up:
		for mate: Dictionary in down:
			_account(int(mate["id"]), "retreating", null, _flat(here, mate["pos"]), 0)
		if victim != 0:
			team.claims.release_victim(victim)
	if down.is_empty() or team == null or giving_up:
		_order = null
		return _end(Mode.NONE, 0)
	var threats := _threats(beliefs, round_number)
	var gun := _gun(me, held)
	var cover_for := 0
	var stage_for := 0
	for mate: Dictionary in down:
		var id: int = mate["id"]
		var holder := int(mate.get("reviver", 0))
		var apart := _flat(here, mate["pos"])
		if holder != 0 and holder != me_id:
			cover_for = cover_for if cover_for != 0 else id
			_account(id, "holder_is_reviving", null, apart, holder)
			continue
		var owned := team.claims.held_by(me_id, now)
		if owned != 0 and owned != id:
			_account(id, "claim_on_other", null, apart, me_id)
			continue
		var holding := mode == Mode.HOLD and victim == id
		var judged := _judge(mate, here, threats, gun, round_number)
		if judged.kind == BotReviveRisk.Kind.LATE and not holding:
			_account(id, "late", judged, apart, team.claims.holder_of(id, now))
			continue
		var shot: BotFlare.Shot = null
		var claimed_by_another := team.claims.holder_of(id, now) not in [0, me_id]
		if not holding and not claimed_by_another and judged.kind != BotReviveRisk.Kind.SAFE:
			shot = _flare_shot(beliefs, me, mate, judged, threats, gun, round_number)
		if judged.kind == BotReviveRisk.Kind.UNSAFE and not holding and shot == null:
			_account(id, "unsafe", judged, apart, team.claims.holder_of(id, now))
			if last:
				return _survive(intent, id, judged)
			if stage_on and stage_for == 0 and _nearest_bot(beliefs, mate["pos"], here) == me_id:
				stage_for = id
			continue
		if stall_on and _stalled(now, id, apart, holding):
			team.claims.release(me_id)
			cover_for = cover_for if cover_for != 0 else id
			_account(id, "stalled", judged, apart, team.claims.holder_of(id, now))
			continue
		if not team.claims.request(id, me_id, apart, now, holding):
			_order = null
			cover_for = cover_for if cover_for != 0 else id
			_account(id, "claim_lost", judged, apart, team.claims.holder_of(id, now))
			continue
		_account(id, "claimant", judged, apart, me_id)
		return _claimant(intent, beliefs, me, mate, judged, last, step, shot)
	_order = null
	if cover_for != 0:
		return _cover(intent, beliefs.teammates[cover_for], here)
	if stage_for != 0:
		return _stage(intent, beliefs.teammates[stage_for], here)
	return _end(Mode.NONE, 0)


## The bot went down (or the night began again): nothing is in hand.
func reset() -> void:
	_stalled_until = -INF
	_best_apart = INF
	mode = Mode.NONE
	victim = 0
	verdict = null
	_order = null
	_health_log.clear()


## The id of the zombie to shoot first among `targets` (believed, in sight) while the bot guards a
## body: the one nearest the body within `BIAS_RADIUS` of it, unless `current` already is one or a
## zombie is on the bot. -1 for no change.
func prefer(targets: Array[Dictionary], beliefs: BotBeliefs, here: Vector3, current: int) -> int:
	if mode == Mode.NONE or mode == Mode.HOLD or mode == Mode.LURE:
		return -1
	if not beliefs.teammates.has(victim):
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
	return KITE_MARGIN if mode == Mode.SURVIVE and _profile.kites_when_last else 0.0


# --- Deciding ---


func _claimant(
	intent: BotIntent,
	beliefs: BotBeliefs,
	me: Dictionary,
	mate: Dictionary,
	judged: BotReviveRisk.Verdict,
	last: bool,
	step: float,
	shot: BotFlare.Shot
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
		return _not_yet(intent, me, mate, judged, last, step, shot, now)
	if apart <= HOLD_FROM:
		return _hold(intent, id, body)
	return _go(intent, id, body)


## The reviver when the hold is not to begin yet: the flare when one is ordered, else (the last
## one up) survive, else clear the dead from the body.
func _not_yet(
	intent: BotIntent,
	me: Dictionary,
	mate: Dictionary,
	judged: BotReviveRisk.Verdict,
	last: bool,
	step: float,
	shot: BotFlare.Shot,
	now: float
) -> Mode:
	var id: int = mate["id"]
	if shot != null:
		return _lure(intent, me, shot, id, now)
	if last:
		return _survive(intent, id, judged)
	var body: Vector3 = mate["pos"]
	return _clear(intent, id, body, _flat(me["pos"], body), step)


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


## The flare ordered: the bot stands where it is, puts the flare gun in hand (reloading it first if
## its round is spent), turns to the shot's view and fires; the motor does the last two.
func _lure(intent: BotIntent, me: Dictionary, shot: BotFlare.Shot, id: int, now: float) -> Mode:
	intent.flare_yaw = shot.yaw
	intent.flare_pitch = shot.pitch
	intent.target_id = -1
	intent.melee_ok = false
	intent.quick_melee_ok = false
	intent.keep_weapon = true
	intent.note = "flare"
	if me.get("weapon", &"") != BotFlare.WEAPON:
		if now - _swapped_at >= SWAP_PAUSE:
			intent.swap = true
			_swapped_at = now
	elif int(me.get("ammo", 0)) <= 0 and not me.get("reloading", false):
		intent.reload = true
	return _end(Mode.LURE, id)


func _survive(intent: BotIntent, id: int, judged: BotReviveRisk.Verdict) -> Mode:
	verdict = judged
	intent.note = "survive"
	return _end(Mode.SURVIVE, id)


func _cover(intent: BotIntent, mate: Dictionary, here: Vector3) -> Mode:
	var body: Vector3 = mate["pos"]
	var apart := _flat(here, body)
	if apart > COVER_RANGE:
		if account.has(int(mate["id"])):
			account[int(mate["id"])]["why"] = "cover_out_of_range"
		return _end(Mode.NONE, 0)
	if apart > COVER_FROM:
		intent.goal = body
		intent.goal_radius = COVER_STAND
		intent.run = false
	intent.note = "cover"
	return _end(Mode.COVER, int(mate["id"]))


## Whether the bot is to stay off body `id`: it is in its pause, or it was on its way and has come
## no nearer for `STALL_SECONDS` (this starts the pause).
func _stalled(now: float, id: int, apart: float, holding: bool) -> bool:
	if now < _stalled_until and _stalled_victim == id:
		return true
	if holding or mode != Mode.GO or victim != id:
		_best_apart = apart
		_best_at = now
		return false
	if apart < _best_apart - STALL_GAIN:
		_best_apart = apart
		_best_at = now
		return false
	if now - _best_at < STALL_SECONDS:
		return false
	_stalled_until = now + STALL_PAUSE
	_stalled_victim = id
	if telemetry != null:
		telemetry.count(&"revive_stalls")
	return true


func _account(
	id: int, why: String, judged: BotReviveRisk.Verdict, apart: float, claim: int
) -> void:
	account[id] = {
		"why": why,
		"verdict": BotReviveRisk.Kind.keys()[judged.kind] if judged != null else "-",
		"apart": snappedf(apart, 0.1),
		"claim": claim,
		"count": judged.count if judged != null else 0,
		"kill_s": snappedf(judged.kill_seconds, 0.1) if judged != null else 0.0,
	}


## Waits for the pack to go: nearer than `STAGE_FROM` the bot stays where it is (its own fight and
## retreat rules move it), farther it walks to the ring.
func _stage(intent: BotIntent, mate: Dictionary, here: Vector3) -> Mode:
	var body: Vector3 = mate["pos"]
	var apart := _flat(here, body)
	if apart > STAGE_FROM + STAGE_STAND:
		intent.goal = body
		intent.goal_radius = STAGE_FROM
		intent.run = apart > STAGE_FROM * 2.0
	intent.note = "revive_stage"
	return _end(Mode.STAGE, int(mate["id"]))


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
	var lures: Array[Dictionary] = []
	if team != null:
		lures = team.active_lures(beliefs.now)
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if not beliefs.is_believed(contact):
			continue
		var mode_now: int = contact["mode"]
		if mode_now == ZombieBody.Mode.DYING:
			continue
		var look: StringName = contact.get("look", ZombieModels.DEFAULT)
		var at := beliefs.guess(contact, _profile.memory_seconds)
		var lurable := not ZombieModels.is_boss(look) and mode_now != ZombieBody.Mode.ATTACK
		var delay := 0.0
		if lurable:
			# A flare burning has drawn it: it starts for the people when the lure goes out.
			for lure in lures:
				if _flat(lure["point"], at) <= float(lure["radius"]):
					at = lure["point"]
					delay = maxf(float(lure["until"]) - beliefs.now, 0.0)
					break
		found.append(
			BotReviveRisk.Threat.make(
				at,
				BotReviveRisk.speed_of(look, round_number, rounds),
				BotReviveRisk.health_of(look, round_number, rounds),
				delay,
				lurable
			)
		)
	return found


## The id of the bot nearest `body` among the bots up (this one at `here`), the lowest id on a tie.
func _nearest_bot(beliefs: BotBeliefs, body: Vector3, here: Vector3) -> int:
	var best := beliefs.me
	var best_apart := _flat(here, body)
	for id in beliefs.teammates:
		var mate: Dictionary = beliefs.teammates[id]
		if id == beliefs.me or not mate.get("bot", false):
			continue
		if mate.get("downed", false) or mate.get("dead", false):
			continue
		var apart := _flat(mate["pos"], body)
		if apart < best_apart or (is_equal_approx(apart, best_apart) and id < best):
			best = id
			best_apart = apart
	return best


# --- The flare ---


## The weapon the bot fights with: the one in hand, or (the flare gun being a tool for one shot) the
## best loaded firearm it carries.
func _gun(me: Dictionary, held: WeaponDef) -> WeaponDef:
	if held == null or not held.is_lure():
		return held
	var arms: Dictionary = me.get("arms", {})
	var other := BotArsenal.best_loaded(arms, held, 0.0)
	return WeaponCatalog.get_def(other) if other != &"" else held


## The shot to fire for `mate`'s body now, or null: the order in force, or a new one when the
## verdict is not safe, the bot carries a flare with a round, no flare is burning or just fired, the
## dead are not yet on the bot, enough of the dead at the body can be drawn off, drawing them off
## would make the revive better (safe, or clearable when it was not), and `BotFlare` finds a spot.
func _flare_shot(
	beliefs: BotBeliefs,
	me: Dictionary,
	mate: Dictionary,
	judged: BotReviveRisk.Verdict,
	threats: Array[BotReviveRisk.Threat],
	gun: WeaponDef,
	round_number: int
) -> BotFlare.Shot:
	var here: Vector3 = me["pos"]
	if not team.flares or not _carries_flare(me):
		_order = null
		return null
	if beliefs.nearest_threat(here, _profile.memory_seconds) < FLARE_NEAR:
		_order = null
		return null
	var mates := _others(beliefs)
	if _order != null:
		return _kept_order(beliefs.now, me, mates)
	return _new_order(beliefs, me, mate, judged, threats, gun, round_number, mates)


## The order in force, or null when it is done (the round that was in the gun is gone: the flare
## flew, and the lure is heard when it bursts a moment later), has run out or a player walked
## near its landing. An order that ends holds the next off for `FLARE_GAP`.
func _kept_order(now: float, me: Dictionary, mates: Array[Dictionary]) -> BotFlare.Shot:
	var counts: Array = (me.get("arms", {}) as Dictionary).get(BotFlare.WEAPON, [0, 0, 0])
	if int(counts[0]) > 0:
		_armed = true
	var gone := int(counts[0]) <= 0 and _armed
	var fit := (
		now - _ordered_at < FLARE_WATCH
		and team.active_lures(now).is_empty()
		and _flare.is_clear_of_mates(_order.landing, mates)
	)
	if fit and not gone:
		return _order
	_order = null
	_flare_ready_at = now + FLARE_GAP
	return null


## A new order, or null.
func _new_order(
	beliefs: BotBeliefs,
	me: Dictionary,
	mate: Dictionary,
	judged: BotReviveRisk.Verdict,
	threats: Array[BotReviveRisk.Threat],
	gun: WeaponDef,
	round_number: int,
	mates: Array[Dictionary]
) -> BotFlare.Shot:
	var now := beliefs.now
	var here: Vector3 = me["pos"]
	if now < _flare_ready_at or not team.active_lures(now).is_empty():
		return null
	var lured: Array[Vector3] = []
	for index in judged.danger:
		var threat := threats[index]
		if threat.lurable and threat.delay <= 0.0:
			lured.append(threat.position)
	if lured.size() < MIN_LURED:
		return null
	if not _would_help(mate, here, threats, gun, round_number, judged.kind):
		return null
	var shot := _flare.plan(here, mate["pos"], lured, mates, level, _dead_by_id(beliefs))
	# A place that cannot be shot at is not looked for again at once.
	_flare_ready_at = now + (0.0 if shot != null else PLAN_RETRY)
	if telemetry != null:
		telemetry.count(&"flares_wanted")
		if shot == null:
			telemetry.count(&"flares_no_spot")
	if shot != null:
		_order = shot
		_ordered_at = now
		_armed = false
	return shot


## The zombies the bot believes in as the weapons code takes targets (`{id: {pos, yaw, scale}}`).
func _dead_by_id(beliefs: BotBeliefs) -> Dictionary:
	var found := {}
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if not beliefs.is_believed(contact) or contact["mode"] == ZombieBody.Mode.DYING:
			continue
		var look: StringName = contact.get("look", ZombieModels.DEFAULT)
		found[id] = {
			"pos": beliefs.guess(contact, _profile.memory_seconds),
			"yaw": float(contact.get("yaw", 0.0)),
			"scale": ZombieModels.height_of(look),
			"pose": ZombiePose.hit_set(look, contact["mode"]),
		}
	return found


## Whether the bot has a flare gun with a round in it or in reserve.
static func _carries_flare(me: Dictionary) -> bool:
	var arms: Dictionary = me.get("arms", {})
	if not arms.has(BotFlare.WEAPON):
		return false
	var counts: Array = arms[BotFlare.WEAPON]
	return int(counts[0]) + int(counts[1]) > 0


## Whether the revive would be judged better with every zombie a flare can draw standing at the
## lure's place (the lure lasts, and they start for the body again from 12 m away): safe, or at
## least clearable when it was not.
func _would_help(
	mate: Dictionary,
	here: Vector3,
	threats: Array[BotReviveRisk.Threat],
	gun: WeaponDef,
	round_number: int,
	now_kind: BotReviveRisk.Kind
) -> bool:
	var body: Vector3 = mate["pos"]
	var away := Vector3(body.x - here.x, 0.0, body.z - here.z)
	away = away.normalized() if away.length() > 0.5 else Vector3.RIGHT
	var spot := body + away * BotFlare.MIN_FROM_BODY
	var after: Array[BotReviveRisk.Threat] = []
	for threat in threats:
		if threat.lurable and threat.delay <= 0.0:
			after.append(
				BotReviveRisk.Threat.make(
					spot, threat.speed, threat.health, FLARE_LEAD + _flare.def.lure_seconds, true
				)
			)
		else:
			after.append(threat)
	var judged := _judge(mate, here, after, gun, round_number)
	if judged.kind == BotReviveRisk.Kind.SAFE:
		return true
	return now_kind == BotReviveRisk.Kind.UNSAFE and judged.kind == BotReviveRisk.Kind.CLEAR


## The other players, as the beliefs keep them.
func _others(beliefs: BotBeliefs) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id in beliefs.teammates:
		if id != beliefs.me:
			found.append(beliefs.teammates[id])
	return found


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
