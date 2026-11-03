class_name BotFightBrain
extends BotBrain
## The brain of phases 1 to 5: the fight, staying with the people, the errands and the revive
## (`BotRevive`: a downed teammate comes before an errand and, once the hold has begun, before the
## fight too). It picks the zombie to shoot by a utility (`BotCombat`),
## backs away from anything that gets inside the profile's margin (a heading chosen on the walking
## mesh, `BotSteering`) and steps out of a blow it saw start (`BotDodge`), keeps the headliner at
## arm's length, looks toward a blow it felt or a sound it heard, handles its weapons (`BotArsenal`:
## reloads, swaps, the crowbar when the guns are dry, never into a pack), throws a grenade at a
## pack when no teammate is near the blast (`BotGrenadier`), holds a choke in the stampede
## (`BotStance`), and otherwise walks to a place near the people (`BotFollow`) and stands there.

## A chase with the crowbar: from how near it starts (the swing reaches the rest), how far it goes,
## the speed (m/s) toward the bot under which a zombie counts as not coming, and where it stops.
const CHASE_FROM_NEAR := 1.6
const CHASE_UP_TO := 8.0
const CHASE_IDLE_SPEED := 0.3
const CHASE_STOP := 1.2
## A full health, as the frame counts it.
const FULL_HEALTH := 100.0
## Metres from its choke at which a bot holding the stampede counts itself there.
const HOLD_RADIUS := 1.0
## Seconds between two swaps.
const SWAP_EVERY := 0.8
## Metres to the nearest dead inside which an ordered throw is given up.
const THROW_ABORT_NEAR := 3.0
## Seconds a grenade order is watched over: the longest a turn, the pin and the swing take.
const THROW_WATCH := 2.5
## How much of the way to the people (or home) bends a retreat (so it circles the field, not a
## corner).
const HOME_BEND := 0.9
## Metres from the nearest dead within which the bot counts itself in a fight (the follow band is
## the closer one), and the seconds between two looks at where to stand.
const FIGHT_RANGE := 12.0
const REPLAN_EVERY := 0.5
## Metres the people may have moved before the place is chosen again.
const ANCHOR_MOVED := 2.0
## Metres beyond the follow band at which a bot hurries (runs) to catch up, if nothing is near.
const LAG := 0.5
const RUN_SAFE := 4.0
## Rays a think may have cast and still plan a place, and the longest a plan is put off (seconds).
const BUSY_LOOK := 2
const PLAN_PATIENCE := 1.2
## Seconds of a teammate's walk counted into the place it will be.
const PREDICT_SECONDS := 1.0

## The legs the bot walks on, set by the client: the brain asks them which places are blocked.
var legs: BotLegs
## What the bots of the night share (the claims on downed players), and where this bot reports.
var team: BotTeam:
	set(value):
		team = value
		revive.team = value
var telemetry: BotTelemetry:
	set(value):
		telemetry = value
		revive.telemetry = value
## What the bot does about a downed teammate (`BotRevive`).
var revive: BotRevive
## Whether the last think was an errand (shopping, boards, the generator), for the metrics.
var on_errand := false

var _profile: BotProfile
var _level: BotLevel
var _follow: BotFollow
var _steering: BotSteering
var _spot := Vector3.INF
var _planned_at := -INF
var _planned_anchor := Vector3.INF
var _was_fighting := false
var _last_reflex := Vector3.ZERO
var _combat: BotCombat
var _dodge: BotDodge
var _grenadier: BotGrenadier
var _stance: BotStance
var _errands: BotErrands
var _swapped_at := -SWAP_EVERY
var _order: BotGrenadier.Throw
var _ordered_at := -INF


func _init(profile: BotProfile, level: BotLevel, dodge_seed: int = 1) -> void:
	_profile = profile
	_level = level
	_follow = BotFollow.new(level)
	_steering = BotSteering.new(level)
	_combat = BotCombat.new(profile)
	_dodge = BotDodge.new(profile, dodge_seed)
	_grenadier = BotGrenadier.new(level)
	_stance = BotStance.new(level)
	revive = BotRevive.new(profile)
	revive.rounds = level.rounds
	if level.shop != null and profile.errands:
		_errands = BotErrands.new(level.shop, profile)


func think(beliefs: BotBeliefs, state: ClientState) -> BotIntent:
	var intent := BotIntent.new()
	on_errand = false
	var me := state.me()
	if me.is_empty() or me.get("downed", true):
		revive.reset()
		return intent
	var here: Vector3 = me["pos"]
	var held := _held(me)
	var kind := BotStance.of(beliefs.special)
	var mates := _mates(beliefs, state.player_id)
	var targets := beliefs.targets(here)
	intent.target_id = _combat.choose(
		targets, here, held, mates, beliefs.now, _blow_age(beliefs), _health(me)
	)
	var rescue := revive.run(
		intent, beliefs, me, held, state.round_number(), 1.0 / float(_profile.think_hz)
	)
	if rescue == BotRevive.Mode.HOLD:
		# Both hands on the revive: no shot, no step, no swap until it is done or let go of.
		intent.throw_abort = _order != null
		_order = null
		return intent
	var preferred := revive.prefer(targets, beliefs, here, intent.target_id)
	if preferred >= 0:
		intent.target_id = preferred
	var threat := beliefs.nearest_threat(here, _profile.memory_seconds)
	var people := _people(beliefs, state.player_id)
	var anchor := BotFollow.anchor_of(people)
	var plan := BotArsenal.plan(me, held, _distance_to(beliefs, intent.target_id, here), threat)
	var pack := BotCombat.near_count(beliefs, here, _profile.memory_seconds)
	intent.melee_ok = BotCombat.may_melee(pack, plan.dry)
	intent.quick_melee_ok = plan.dry and held != null and not held.is_melee()
	var ordered := _throw(intent, beliefs, here, targets, mates, threat, kind)
	if not _step_away(intent, beliefs, here, anchor, held, threat, kind, pack, plan.dry, ordered):
		_last_reflex = Vector3.ZERO
		if ordered:
			intent.note = "throw"
		elif rescue != BotRevive.Mode.NONE:
			pass  # `BotRevive` set the goal and the note.
		elif _chase(intent, beliefs, here, held, mates, pack, plan.dry):
			intent.note = "chase"
		elif _errand(intent, beliefs, state, threat):
			on_errand = true
			intent.note = intent.note if intent.note != "" else "errand"
		elif kind == BotStance.Kind.HOLD:
			_hold(intent, beliefs, here, anchor)
		else:
			_walk_to_people(intent, here, beliefs, people, anchor, threat)
	if intent.target_id < 0:
		intent.look_yaw = _glance(beliefs, here)
	_handle_weapon(intent, plan, beliefs.now)
	if intent.note == "":
		intent.note = "fight" if intent.target_id >= 0 else "hold"
	return intent


## Gives the intent a heading away from the dead when the bot should not stand where it is: a blow
## it saw start and can still step out of, the headliner nearer than the profile's `boss_keep`, or a
## zombie inside the profile's margin. Nothing in the stampede (running from runners is no use) but
## the boss's blow; a melee bot stands to fight except in front of a pack. True when it did.
func _step_away(
	intent: BotIntent,
	beliefs: BotBeliefs,
	here: Vector3,
	anchor: Vector3,
	held: WeaponDef,
	threat: float,
	kind: BotStance.Kind,
	pack: int,
	dry: bool,
	throwing: bool
) -> bool:
	var swings := _dodge.swings(beliefs, here)
	var boss_blow := false
	for swing in swings:
		boss_blow = boss_blow or beliefs.contact(swing["id"]).get("look", &"") == &"headliner"
	var dodge := not swings.is_empty() and (kind != BotStance.Kind.HOLD or boss_blow)
	var keeps_off := _boss_distance(beliefs, here) < _profile.boss_keep and not throwing
	var margin := maxf(_profile.retreat_margin, revive.kite_margin())
	# A bot with no round left stands to fight with the quick melee as one with a bat does.
	var melee := (held != null and held.is_melee()) or dry
	var backs := threat < margin and kind != BotStance.Kind.HOLD
	if (melee and BotCombat.may_melee(pack, dry)) or throwing:
		backs = false
	if not (dodge or keeps_off or backs):
		return false
	intent.reflex = _retreat(here, beliefs, anchor)
	intent.run = true
	intent.note = "dodge" if dodge else "retreat"
	_last_reflex = intent.reflex
	return true


## A heading away from what the bot knows of, chosen among twelve on the walking mesh, with a pull
## toward the people (or home) and toward the lot's loops. Zero when it knows of nothing or is
## boxed in.
func _retreat(here: Vector3, beliefs: BotBeliefs, anchor: Vector3) -> Vector3:
	var threats: Array[Dictionary] = []
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if not beliefs.is_believed(contact):
			continue
		var speed := Vector2(contact["velocity"].x, contact["velocity"].z).length()
		threats.append(
			{"position": beliefs.guess(contact, _profile.memory_seconds), "speed": speed}
		)
	if threats.is_empty():
		return Vector3.ZERO
	var toward := Vector3.ZERO
	var pull := anchor if anchor != Vector3.INF else _level.home
	if pull != Vector3.INF:
		toward = Vector3(pull.x - here.x, 0.0, pull.z - here.z).normalized() * HOME_BEND
	return _steering.pick(here, threats, toward, _last_reflex)


## The people the bot stays with, as the teammates' entries: the humans, or the other bots when
## there are none (so a team of bots stays together).
func _people(beliefs: BotBeliefs, me: int) -> Array[Dictionary]:
	var humans: Array[Dictionary] = []
	var bots: Array[Dictionary] = []
	for id in beliefs.teammates:
		if id == me:
			continue
		var mate: Dictionary = beliefs.teammates[id]
		if mate.get("dead", false):
			continue
		(bots if mate.get("bot", false) else humans).append(mate)
	return humans if not humans.is_empty() else bots


## Sets the goal: a place near the people, chosen again now and then, or nowhere when the bot is
## well placed.
func _walk_to_people(
	intent: BotIntent,
	here: Vector3,
	beliefs: BotBeliefs,
	people: Array[Dictionary],
	anchor: Vector3,
	threat: float
) -> void:
	if anchor == Vector3.INF or not _profile.follows:
		_spot = Vector3.INF
		return
	var fighting := threat < FIGHT_RANGE
	var now := beliefs.now
	var blocked := _spot != Vector3.INF and legs != null and legs.path.is_blocked(_spot, now)
	var due := (
		now - _planned_at >= REPLAN_EVERY
		or fighting != _was_fighting
		or blocked
		or (_planned_anchor != Vector3.INF and _flat(anchor, _planned_anchor) > ANCHOR_MOVED)
	)
	# A think that already cast most of its rays leaves the choice of a place for the next one (a
	# place is not urgent; the think's cost is, see the page's cost section), but not for long.
	if due and beliefs.rays > BUSY_LOOK and now - _planned_at < PLAN_PATIENCE:
		due = false
	if due:
		_planned_at = now
		_planned_anchor = anchor
		_was_fighting = fighting
		var avoid := Callable()
		if legs != null:
			avoid = Callable(legs.path, &"is_blocked").bind(now)
		_spot = _follow.plan(
			here,
			people,
			_bot_places(beliefs),
			_threat_places(beliefs),
			fighting,
			_spot,
			avoid,
			_slot(beliefs)
		)
	if _spot != Vector3.INF:
		intent.goal = _spot
		intent.goal_radius = 1.0
		var band := BotFollow.FIGHT_BAND if fighting else BotFollow.CALM_BAND
		intent.run = _flat(here, anchor) > band.y + LAG and threat > RUN_SAFE
		intent.note = "follow"


## Where the other bots are going to be in a moment: where they stand and a second of the way they
## walk (a bot cannot see where a teammate means to go, only that it is moving).
func _bot_places(beliefs: BotBeliefs) -> Array[Vector3]:
	var places: Array[Vector3] = []
	for id in beliefs.teammates:
		var mate: Dictionary = beliefs.teammates[id]
		if mate.get("bot", false) and id != beliefs.me:
			places.append(mate["pos"] + mate["velocity"] * PREDICT_SECONDS)
	return places


## The bot's slot behind a person: the bots of the team (the roster labels them) take their turns in
## the order of their seats, spread `BotFollow.SLOT_SPREAD` apart round straight behind.
func _slot(beliefs: BotBeliefs) -> float:
	var seats: Array[int] = []
	for id in beliefs.teammates:
		if beliefs.teammates[id].get("bot", false):
			seats.append(id)
	seats.sort()
	var rank := seats.find(beliefs.me)
	if rank < 0:
		return 0.0
	return (float(rank) - float(seats.size() - 1) * 0.5) * BotFollow.SLOT_SPREAD


func _threat_places(beliefs: BotBeliefs) -> Array[Vector3]:
	var places: Array[Vector3] = []
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if beliefs.is_believed(contact):
			places.append(beliefs.guess(contact, _profile.memory_seconds))
	return places


## Where to turn when nothing is in sight: a blow, else a sound, else a remembered zombie.
func _glance(beliefs: BotBeliefs, here: Vector3) -> float:
	if not beliefs.blows.is_empty():
		return beliefs.blows.back()["yaw"]
	if not beliefs.heard.is_empty():
		return beliefs.heard[0]["yaw"]
	for contact in beliefs.remembered():
		var at := beliefs.guess(contact, _profile.memory_seconds) - here
		return atan2(-at.x, -at.z)
	return NAN


func _handle_weapon(intent: BotIntent, plan: BotArsenal.Plan, now: float) -> void:
	intent.reload = plan.reload
	if plan.swap and not intent.keep_weapon and now - _swapped_at >= SWAP_EVERY:
		intent.swap = true
		_swapped_at = now


## Meters to the target the bot means to shoot, or INF for none.
static func _distance_to(beliefs: BotBeliefs, target_id: int, here: Vector3) -> float:
	var contact := beliefs.contact(target_id)
	return _flat(here, contact["position"]) if not contact.is_empty() else INF


## Seconds since the last blow the bot took (INF for none lately).
static func _blow_age(beliefs: BotBeliefs) -> float:
	return beliefs.now - float(beliefs.blows.back()["at"]) if not beliefs.blows.is_empty() else INF


## The other players as the beliefs keep them.
static func _mates(beliefs: BotBeliefs, me: int) -> Array[Dictionary]:
	var mates: Array[Dictionary] = []
	for id in beliefs.teammates:
		if id != me:
			mates.append(beliefs.teammates[id])
	return mates


## Metres to the nearest headliner the bot believes in, or INF.
static func _boss_distance(beliefs: BotBeliefs, here: Vector3) -> float:
	var best := INF
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if ZombieModels.is_boss(contact.get("look", ZombieModels.DEFAULT)):
			if beliefs.is_believed(contact):
				best = minf(best, _flat(here, contact["position"]))
	return best


## Orders a grenade at a pack when the throw is safe, and watches an order given a moment ago:
## the bot stands still for it, and takes it back if a teammate walks into the blast. True while an
## order is in force.
func _throw(
	intent: BotIntent,
	beliefs: BotBeliefs,
	here: Vector3,
	targets: Array[Dictionary],
	mates: Array[Dictionary],
	threat: float,
	kind: BotStance.Kind
) -> bool:
	var now := beliefs.now
	if _order != null and now - _ordered_at < THROW_WATCH:
		if threat < THROW_ABORT_NEAR or not _grenadier.is_safe(_order.landing, here, mates):
			intent.throw_abort = true
			_order = null
			return false
		return true
	_order = null
	if beliefs.grenades <= 0 or threat < BotGrenadier.SAFE_FROM_SELF or targets.is_empty():
		return false
	var throw := _grenadier.plan(
		here, targets, mates, beliefs.grenades, now, kind == BotStance.Kind.LOW
	)
	if throw == null:
		return false
	intent.throw_style = throw.style
	intent.throw_yaw = throw.yaw
	intent.throw_pitch = throw.pitch
	_order = throw
	_ordered_at = now
	_grenadier.last_throw = now
	intent.note = "throw"
	return true


## The errands of a lull (fuel, breakers, shopping, boards), when the level gave the bot a shop and
## nothing is near. A refusal the server told the bot about leaves the item alone for a while.
func _errand(intent: BotIntent, beliefs: BotBeliefs, state: ClientState, threat: float) -> bool:
	if _errands == null:
		return false
	_errands.legs = legs
	for denial in beliefs.denials:
		_errands.back_off(denial["item"], beliefs.now)
	beliefs.denials.clear()
	if intent.target_id >= 0:
		return false
	return _errands.run(intent, beliefs, state, threat)


## A bot with a crowbar in hand walks up to a zombie that is not coming to it (one tearing boards,
## held by a hit or by a blast), when the swing is a good idea (`BotCombat.may_melee`) and the
## leash allows the walk (`BotCombat.leash_allows`). A zombie that is coming is waited for.
func _chase(
	intent: BotIntent,
	beliefs: BotBeliefs,
	here: Vector3,
	held: WeaponDef,
	mates: Array[Dictionary],
	pack: int,
	dry: bool
) -> bool:
	var target := beliefs.contact(intent.target_id)
	if held == null or not held.is_melee() or target.is_empty():
		return false
	var apart := _flat(here, target["position"])
	if apart <= CHASE_FROM_NEAR or apart > CHASE_UP_TO:
		return false
	if (
		BotCombat.closing_speed(target, here) > CHASE_IDLE_SPEED
		or not BotCombat.may_melee(pack, dry)
	):
		return false
	var humans: Array[Vector3] = []
	var bots: Array[Vector3] = []
	var downed: Array[Vector3] = []
	for mate in mates:
		if mate.get("dead", false):
			continue
		if mate.get("downed", false):
			downed.append(mate["pos"])
		else:
			(bots if mate.get("bot", false) else humans).append(mate["pos"])
	var people := humans if not humans.is_empty() else bots
	if not BotCombat.leash_allows(target["position"], here, people, downed):
		return false
	intent.goal = target["position"]
	intent.goal_radius = CHASE_STOP
	intent.run = false
	return true


## The stampede: stand at a choke near the people (walls about it) and not run from the runners.
func _hold(intent: BotIntent, beliefs: BotBeliefs, here: Vector3, anchor: Vector3) -> void:
	var centre := anchor if anchor != Vector3.INF else here
	var spot := _stance.choke(here, centre, beliefs.now)
	if spot == Vector3.INF or _flat(here, spot) < HOLD_RADIUS:
		return
	intent.goal = spot
	intent.goal_radius = HOLD_RADIUS
	intent.run = false


## The bot's own health as a share of a full one.
static func _health(me: Dictionary) -> float:
	return float(me.get("health", 100.0)) / FULL_HEALTH


static func _held(me: Dictionary) -> WeaponDef:
	var id: StringName = me.get("weapon", &"")
	return WeaponCatalog.get_def(id) if id != &"" else null


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
