class_name BotFightBrain
extends BotBrain
## The brain of phases 1 to 5: the fight, staying with the people, the errands and the revive
## (`BotRevive`: a downed teammate comes before an errand and, once the hold has begun, before the
## fight too). It picks the zombie to shoot by a utility (`BotCombat`),
## backs away from anything that gets inside the profile's margin (a heading chosen on the walking
## mesh, `BotSteering`) and steps out of a blow it saw start (`BotDodge`), keeps the headliner at
## arm's length, looks toward a blow it felt or a sound it heard, handles its weapons (`BotArsenal`:
## reloads, swaps, the crowbar when the guns are dry, never into a pack), throws a grenade at a
## pack (`BotGrenadier`), holds a choke in the stampede
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
## The order `HOLD`: the bots of a team stand this far from the spot round it (a lone bot stands on
## it), arrive within `HOLD_ARRIVE` metres of their place and walk back when `HOLD_LEAVE` metres
## away. The ring is wide enough that two neighbours' leave zones do not overlap (4 bots: 2.3 m
## apart), and the farthest a bot may stand is 2.6 m from the spot: inside the 3 m the order
## promises.
const ORDER_RING := 1.6
const HOLD_ARRIVE := 0.5
const HOLD_LEAVE := 1.0
## Metres from a held place beyond which a bot hurries (runs) to it, if nothing is near.
const HOLD_RUN_FROM := 8.0
## The `ROAM` order: how near counts as at a place, for the legs.
const ROAM_RADIUS := 1.0
## The flank: seconds between two looks for its place, and the metres the people may move before it
## is looked for again.
const FLANK_REPLAN := 3.0
const FLANK_MOVED := 3.0
## Metres the walk to the flank's place may end short of it: the place is on the mesh, so the walk
## reaches it, and one that ends further off is a patch the lot's ground does not join (the slab
## beyond the fence).
const FLANK_REACH_SHORT := 0.5

## The legs the bot walks on, set by the client: the brain asks them which places are blocked.
var legs: BotLegs
## What the bots of the night share (the claims on downed players), and where this bot reports.
var team: BotTeam:
	set(value):
		team = value
		revive.team = value
		if _errands != null and value != null:
			_errands.links = value.links
var telemetry: BotTelemetry:
	set(value):
		telemetry = value
		revive.telemetry = value
## What the bot does about a downed teammate (`BotRevive`).
var revive: BotRevive
## How boldly the bot plays, from its health (`BotPlayState`).
var play: BotPlayState
## What the bot is for at the moment (`BotRoles`).
var role := BotRoles.Role.ANCHOR
## A bot with no way out (`BotTrapped`).
var trapped := BotTrapped.new()
## What the bot says (`BotCallouts`).
var callouts := BotCallouts.new()
## Whether the last think was an errand (shopping, boards, the generator), for the metrics.
var on_errand := false

var _profile: BotProfile
var _level: BotLevel
var _follow: BotFollow
var _roam: BotRoam
## Whether the order in force is `HOLD` (set each think; `_step_away` reads it).
var _holding := false
## Whether the order in force is `FOLLOW` and the anchor is a person (set each think).
var _following := false
## The flank's place, when it was chosen, and the centre of the people it was chosen for.
var _flank_spot := Vector3.INF
var _flank_at := -INF
var _flank_centre := Vector3.INF
## Whether the bot has reached its place of the `HOLD` order and stands there.
var _at_hold := false
var _retreat: BotRetreat
var _spot := Vector3.INF
var _planned_at := -INF
var _planned_anchor := Vector3.INF
var _was_fighting := false
var _was_safe := false
var _play_changes := 0
var _combat: BotCombat
var _dodge: BotDodge
var _grenadier: BotGrenadier
var _stance: BotStance
var _errands: BotErrands
var _swapped_at := -SWAP_EVERY
var _order: BotGrenadier.Throw
var _ordered_at := -INF
## The look for the last zombies of the round (`BotHunt`).
var _hunter := BotHunt.new()


func _init(profile: BotProfile, level: BotLevel, dodge_seed: int = 1) -> void:
	_profile = profile
	_level = level
	_follow = BotFollow.new(level)
	_roam = BotRoam.new(level, dodge_seed ^ 0x40A3)
	_retreat = BotRetreat.new(profile, level)
	_combat = BotCombat.new(profile)
	_dodge = BotDodge.new(profile, dodge_seed)
	_grenadier = BotGrenadier.new(level)
	_stance = BotStance.new(level)
	play = BotPlayState.new(profile)
	revive = BotRevive.new(profile)
	revive.rounds = level.rounds
	revive.level = level
	if level.shop != null and profile.errands:
		_errands = BotErrands.new(level.shop, profile)


func think(beliefs: BotBeliefs, state: ClientState) -> BotIntent:
	var intent := BotIntent.new()
	on_errand = false
	var me := state.me()
	if me.is_empty() or me.get("downed", true):
		revive.reset()
		play.reset()
		if not me.is_empty():
			intent.say = callouts.downed(beliefs, me)
		return intent
	callouts.up()
	var here: Vector3 = me["pos"]
	var held := _held(me)
	var kind := BotStance.of(beliefs.special)
	var mates := _mates(beliefs, state.player_id)
	var targets := beliefs.targets(here)
	intent.target_id = _combat.choose(
		targets, here, held, mates, beliefs.now, _blow_age(beliefs), _health(me)
	)
	var humans := _take_role(beliefs, here)
	var threat := beliefs.nearest_threat(here, _profile.memory_seconds)
	_read_play_state(beliefs, me, here, threat)
	var marks := BotPings.marks(state.frame, beliefs.teammates)
	revive.pinged = BotPings.downed(marks)
	var rescue := revive.run(
		intent, beliefs, me, held, state.round_number(), 1.0 / float(_profile.think_hz)
	)
	if rescue == BotRevive.Mode.HOLD:
		# Both hands on the revive: no shot, no step, no swap until it is done or let go of.
		intent.throw_abort = _order != null
		_order = null
		intent.say = _callouts_plan(beliefs, me, true, false)
		return intent
	var preferred := revive.prefer(targets, beliefs, here, intent.target_id)
	if preferred >= 0:
		intent.target_id = preferred
	var marked := BotPings.enemy(marks, targets)
	if marked >= 0 and rescue == BotRevive.Mode.NONE:
		intent.target_id = marked
	var order := _standing_order(beliefs)
	_holding = order == BotOrders.HOLD
	_following = order == BotOrders.FOLLOW
	_hunter.watch(beliefs)
	var people := _people(beliefs, order)
	var anchor := BotFollow.anchor_of(people)
	if _holding:
		anchor = beliefs.order["at"]
	var plan := BotArsenal.plan(me, held, _distance_to(beliefs, intent.target_id, here), threat)
	var pack := BotCombat.near_count(beliefs, here, _profile.memory_seconds)
	intent.melee_ok = BotCombat.may_melee(pack, plan.dry or plan.cornered)
	intent.quick_melee_ok = (plan.dry or plan.unloaded) and held != null and not held.is_melee()
	# A flare ordered (`BotRevive`) holds the bot still, like a throw, and takes the weapon's handling.
	var flaring := rescue == BotRevive.Mode.LURE
	var ordered := not flaring and _throw(intent, beliefs, here, targets, threat, kind)
	intent.keep_out = _live_blast_near(here, beliefs)
	intent.keep_out_reach = _grenadier.step_out_reach()
	var stepped := _step_away(
		intent,
		beliefs,
		here,
		anchor,
		held,
		threat,
		kind,
		pack,
		plan.dry or plan.cornered,
		ordered or flaring
	)
	_check_trapped(intent, beliefs, here, stepped and intent.reflex == Vector3.ZERO)
	if not stepped:
		_retreat.forget()
		if ordered:
			intent.note = "throw"
		elif rescue != BotRevive.Mode.NONE:
			pass  # `BotRevive` set the goal and the note.
		elif not _live_blast_near(here, beliefs, BotGrenadier.WAIT_RANGE).is_empty():
			intent.note = "blast_wait"  # stands and fights; no walk toward its own grenade.
		elif _hold_ping(intent, beliefs, marks, here):
			pass
		elif (
			order == BotOrders.FOLLOW
			and role == BotRoles.Role.FLANK
			and _flank(intent, beliefs, here, humans)
		):
			pass
		elif (
			not _holding
			and play.may_push()
			and _chase(intent, beliefs, here, held, mates, pack, plan.dry, order)
		):
			intent.note = "chase"
		elif plan.dry and _dash(intent, beliefs, state, threat):
			# Out of rounds with points to spend: run for them (`BotErrands.DASH_FROM`).
			on_errand = true
		elif _hunt(intent, beliefs, here, order, anchor, plan.dry):
			pass  # The last of the dead are out there: go and look (`BotHunt`).
		elif _errand(
			intent, beliefs, state, threat, order, anchor, _holding and not _pinged_door(state)
		):
			on_errand = true
			intent.note = intent.note if intent.note != "" else "errand"
		elif kind == BotStance.Kind.HOLD:
			_hold(intent, beliefs, here, anchor)
		else:
			_by_order(intent, beliefs, here, order, people, anchor, threat)
	if intent.target_id < 0:
		var glance := _glance(beliefs, here)
		# A roaming bot looking about keeps its own look unless it has something to glance at.
		if not is_nan(glance) or is_nan(intent.look_yaw):
			intent.look_yaw = glance
	_handle_weapon(intent, plan, beliefs.now)
	intent.say = _callouts_plan(beliefs, me, false, intent.reload)
	if intent.note == "":
		intent.note = "fight" if intent.target_id >= 0 else "hold"
	return intent


## The bot's play state for this think (`BotPlayState`): its health and the dead within the
## pressure range, and what that asks of a revive. A change is counted for the report.
func _read_play_state(beliefs: BotBeliefs, me: Dictionary, here: Vector3, threat: float) -> void:
	var pressure := 0
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if beliefs.is_believed(contact):
			var at := beliefs.guess(contact, _profile.memory_seconds)
			if _flat(here, at) <= _profile.pressure_range:
				pressure += 1
	var own := {"health": me.get("health", beliefs.max_health), "max_health": beliefs.max_health}
	play.update(own, pressure, beliefs.now)
	if play.changes != _play_changes:
		_play_changes = play.changes
		if telemetry != null:
			telemetry.count(&"play_state_changes")
	revive.retreating = play.gives_up_revive(threat, false)


## The name of the bot's play state, for the reports.
func play_state_name() -> StringName:
	return play.state_name()


## Reads the team's roles for this moment and takes this bot's. Returns the people up (the ones the
## flank is placed by): `{pos, velocity, facing}`.
func _take_role(beliefs: BotBeliefs, here: Vector3) -> Array[Dictionary]:
	var bots: Array[Dictionary] = [{"id": beliefs.me, "pos": here}]
	var humans: Array[Dictionary] = []
	for id in beliefs.teammates:
		var mate: Dictionary = beliefs.teammates[id]
		if id == beliefs.me or mate.get("downed", false) or mate.get("dead", false):
			continue
		if mate.get("bot", false):
			bots.append({"id": id, "pos": mate["pos"]})
		else:
			humans.append(mate)
	if team != null:
		var maintainer := team.turn.holder
		team.roles.update(beliefs.now, bots, humans, maintainer)
		role = team.roles.role_of(beliefs.me)
	return humans


## The flank: a choke to the side of the people's heading (8 to 10 m, at most 10 from them), held
## and fought from while the people stand; while they walk the bot follows with the rest. The place
## is ground the bot can walk to (`_flank_place`): with none, the bot follows with the rest.
func _flank(
	intent: BotIntent, beliefs: BotBeliefs, here: Vector3, humans: Array[Dictionary]
) -> bool:
	if humans.is_empty() or BotRoles.speed_of(humans) > BotRoles.FLANK_STILL:
		_flank_spot = Vector3.INF
		return false
	var now := beliefs.now
	var centre := BotRoles.flank_centre(humans)
	var choke := _stance.choke(here, centre, now)
	# A place is kept (a bot that changes its mind walks back and forth between two) until the people
	# move on, or it is marked blocked; with none, the look is repeated every `FLANK_REPLAN` seconds.
	var due := false
	if _flank_spot == Vector3.INF:
		due = now - _flank_at >= FLANK_REPLAN
	else:
		due = _blocked(_flank_spot, now) or _flat(centre, _flank_centre) > FLANK_MOVED
	if due:
		_flank_at = now
		_flank_centre = centre
		_flank_spot = _flank_place(here, humans, choke, now)
	if _flank_spot == Vector3.INF:
		return false
	intent.note = "flank"
	if _flat(here, _flank_spot) < HOLD_RADIUS * 1.5:
		return true
	intent.goal = _flank_spot
	intent.goal_radius = HOLD_RADIUS * 1.5
	intent.run = false
	return true


## The first place for the flank that the bot can walk to: the choke the walls offer, then the
## places `BotRoles.flank_choices` names, each brought in to the limit from the people and put on
## the walking mesh. A place the walk does not reach (behind a fence, past a prop the mesh runs
## through, on the slab beyond the lot), or one marked blocked, is passed over. `Vector3.INF` for
## none.
func _flank_place(here: Vector3, humans: Array[Dictionary], choke: Vector3, now: float) -> Vector3:
	var wanted: Array[Vector3] = []
	if choke != Vector3.INF:
		wanted.append(choke)
	wanted.append_array(BotRoles.flank_choices(humans))
	for place in wanted:
		var spot := _level.project(BotRoles.within_limit(place, humans))
		if _level.in_passage(spot) or _blocked(spot, now):
			continue
		if legs == null or legs.path.probe(here, spot, now, FLANK_REACH_SHORT):
			return spot
	return Vector3.INF


## Whether the legs have marked `spot` as a place they cannot walk to.
func _blocked(spot: Vector3, now: float) -> bool:
	return legs != null and legs.path.is_blocked(spot, now)


## A person's "hold here": the bot nearest to the mark goes and stays by it while it stands.
func _hold_ping(
	intent: BotIntent, beliefs: BotBeliefs, marks: Array[Dictionary], here: Vector3
) -> bool:
	var free: Array[Dictionary] = []
	for id in beliefs.teammates:
		var mate: Dictionary = beliefs.teammates[id]
		if id != beliefs.me and mate.get("bot", false):
			if not mate.get("downed", false) and not mate.get("dead", false):
				free.append(mate)
	var place := BotPings.hold_place(marks, beliefs.me, here, free)
	if place == Vector3.INF:
		return false
	intent.goal = place
	intent.goal_radius = BotPings.HOLD_STAND
	intent.run = false
	intent.note = "hold_ping"
	return true


## Whether the bot has found no way out for long enough (`BotTrapped`): it reports it once and, if
## a place to jump from is near, goes there and jumps. It goes on fighting either way.
func _check_trapped(intent: BotIntent, beliefs: BotBeliefs, here: Vector3, boxed: bool) -> void:
	if trapped.update(boxed, beliefs.now):
		beliefs.moments.append({"kind": &"trapped"})
		if telemetry != null:
			telemetry.event(&"bot_trapped", roundi(beliefs.now * 60.0), {"position": here})
	if not trapped.trapped:
		return
	intent.trapped = true
	intent.note = "trapped"
	var link := BotTrapped.nearest_link(here, _level.links)
	if link != null:
		intent.goal = link.from
		intent.goal_radius = 0.5


## The line to call out this think, or none (`BotCallouts`).
func _callouts_plan(
	beliefs: BotBeliefs, me: Dictionary, holding: bool, reloading: bool
) -> Dictionary:
	var lowest := true
	for id in beliefs.teammates:
		if beliefs.teammates[id].get("bot", false) and id < beliefs.me:
			lowest = false
	return callouts.plan(beliefs, me, _profile, holding, reloading, lowest)


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
	# A holder keeps off a boss only a few metres from its spot (`BotProfile.hold_back`, as a Safe
	# one backs off): the spot is the order, and a bot that runs the length of the lot from the
	# boss and walks back to it is not holding anything (#769).
	var leashed := _holding and _flat(here, anchor) >= _profile.hold_back
	var keeps_off := (
		beliefs.boss_distance(here) < _profile.boss_keep and not throwing and not leashed
	)
	var blast := not throwing and not _live_blast_near(here, beliefs).is_empty()  # steps out
	var margin := play.margin(maxf(_profile.retreat_margin, revive.kite_margin()))
	# A bot with no round left stands to fight with the quick melee as one with a bat does.
	var melee := (held != null and held.is_melee()) or dry
	# A holder backs off its spot only when low on health, and only a few metres.
	var may_back := not _holding or play.may_back_off_hold(_flat(here, anchor))
	var backs := threat < margin and kind != BotStance.Kind.HOLD and may_back
	var stands_to_swing := melee and BotCombat.may_melee(pack, dry)
	if (stands_to_swing and not play.prefers_open_ground()) or throwing:
		backs = false
	if not (dodge or keeps_off or backs or blast):
		return false
	intent.reflex = _retreat.heading(
		here,
		beliefs,
		anchor,
		play,
		_live_blast_near(here, beliefs),
		_grenadier.step_out_reach(),
		_holding,
		_following
	)
	intent.run = true
	intent.note = "dodge" if dodge else "retreat"
	return true


## Where the bot's own live grenades are within `reach` metres (by default where it steps out,
## `BotGrenadier.step_out_reach`). Only its own: a grenade hurts its thrower alone (#856).
func _live_blast_near(here: Vector3, beliefs: BotBeliefs, reach := -1.0) -> Array[Vector3]:
	if team == null:
		return [] as Array[Vector3]
	var within := reach if reach >= 0.0 else _grenadier.step_out_reach()
	return team.blasts_near(here, within, beliefs.now, beliefs.me)


## The order the bot lives by: the team's (`BotOrders`), where a follow whose person is gone or
## dead, and a hold with no place, are a roam.
func _standing_order(beliefs: BotBeliefs) -> StringName:
	var order: StringName = beliefs.order.get("order", BotOrders.DEFAULT)
	if order == BotOrders.FOLLOW:
		var issuer: Dictionary = beliefs.teammates.get(int(beliefs.order.get("issuer_id", 0)), {})
		if issuer.is_empty() or issuer.get("dead", false) or int(issuer["id"]) == beliefs.me:
			return BotOrders.ROAM
	elif order == BotOrders.HOLD:
		var at: Vector3 = beliefs.order.get("at", Vector3.INF)
		if not at.is_finite():
			return BotOrders.ROAM
	return order if BotOrders.is_order(order) else BotOrders.DEFAULT


## The people the bot stays with, as the teammates' entries: only under the order `FOLLOW`, and then
## the person who gave it. A roaming or holding bot stays with nobody.
func _people(beliefs: BotBeliefs, order: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if order == BotOrders.FOLLOW:
		found.append(beliefs.teammates[int(beliefs.order["issuer_id"])])
	return found


## The standing order's stance: walk with the person (`FOLLOW`), stand at the spot (`HOLD`), or go
## about the lot (`ROAM`).
func _by_order(
	intent: BotIntent,
	beliefs: BotBeliefs,
	here: Vector3,
	order: StringName,
	people: Array[Dictionary],
	anchor: Vector3,
	threat: float
) -> void:
	if order != BotOrders.ROAM:
		_roam.drop()
		_forget_roam(beliefs)
	match order:
		BotOrders.FOLLOW:
			_walk_to_people(intent, here, beliefs, people, anchor, threat)
		BotOrders.HOLD:
			_stand_at_spot(intent, beliefs, here, threat)
		_:
			if play.may_wander():
				_roam_about(intent, beliefs, here)
			else:
				_rest(intent, beliefs)


## A roaming bot that is low on health stays where it is (and fights) until it is better.
func _rest(intent: BotIntent, beliefs: BotBeliefs) -> void:
	_spot = Vector3.INF
	_roam.drop()
	_forget_roam(beliefs)
	intent.note = "fight" if intent.target_id >= 0 else "safe"


## `HOLD`: be at the spot the order was given, a place of the ring about it by seat, and fight from
## there. Back to it when a dodge or a revive took the bot away.
func _stand_at_spot(intent: BotIntent, beliefs: BotBeliefs, here: Vector3, threat: float) -> void:
	_spot = Vector3.INF
	if not _profile.follows:
		return
	var place := _level.project(
		(beliefs.order["at"] as Vector3) + _ring_offset(beliefs, ORDER_RING)
	)
	var apart := _flat(here, place)
	_at_hold = apart <= (HOLD_LEAVE if _at_hold else HOLD_ARRIVE)
	intent.note = "hold_order"
	if _at_hold:
		return
	# A low holder stays where its retreat took it (a few metres off the spot) until it is better.
	if play.stays_off_hold(_flat(here, beliefs.order["at"])):
		intent.note = "hold_back"
		return
	# A holder that kept off a boss does not walk back into it: it stands and fights from where it
	# is, and goes back to its place when the boss is not at it (#769).
	if beliefs.boss_distance(place) < _profile.boss_keep:
		intent.note = "hold_back"
		return
	intent.goal = place
	intent.goal_radius = HOLD_ARRIVE
	intent.run = apart > HOLD_RUN_FROM and threat > RUN_SAFE


## `ROAM`: walk to a place across the lot, look about from it, go on to another. A bot with a zombie
## in its sights stands and fights, and takes up the walk afterwards.
func _roam_about(intent: BotIntent, beliefs: BotBeliefs, here: Vector3) -> void:
	_spot = Vector3.INF
	if not _profile.follows:
		return
	if intent.target_id >= 0:
		intent.note = "fight"
		return
	var humans: Array[Vector3] = []
	for id in beliefs.teammates:
		var mate: Dictionary = beliefs.teammates[id]
		if id != beliefs.me and not mate.get("bot", false) and not mate.get("dead", false):
			humans.append(mate["pos"])
	var claimed: Array[Vector3] = []
	if team != null:
		for bot_id: int in team.roam:
			if bot_id != beliefs.me:
				claimed.append(team.roam[bot_id])
	var avoid := Callable()
	var reach := Callable()
	var mesh := 0
	var short_of := Vector3.INF
	if legs != null:
		avoid = Callable(legs.path, &"is_blocked").bind(beliefs.now)
		reach = Callable(legs.path, &"probe").bind(beliefs.now)
		_roam.exact = Callable(legs.path, &"probe").bind(beliefs.now, BotRoam.EXACT_SHORT)
		mesh = legs.path.iteration()
		short_of = legs.stopped_short_of
	var goal := _roam.plan(
		here,
		beliefs.now,
		humans,
		_bot_places(beliefs),
		claimed,
		_threat_places(beliefs),
		avoid,
		reach,
		mesh,
		short_of
	)
	if goal == Vector3.INF:
		_forget_roam(beliefs)
		if _roam.rejoin.is_finite():
			# Cut off from the rest of the walking mesh: no path starts here, so the way back is
			# a straight walk to the spot it chose from (#1041).
			intent.reflex = (_roam.rejoin - here) * Vector3(1.0, 0.0, 1.0)
			intent.run = false
			intent.note = "rejoin"
			return
		if _roam.dwelling:
			intent.look_yaw = _roam.look_yaw
			intent.note = "roam_look"
		return
	if team != null:
		team.roam[beliefs.me] = goal
	intent.goal = goal
	intent.goal_radius = ROAM_RADIUS
	intent.run = false
	intent.note = "roam"


func _forget_roam(beliefs: BotBeliefs) -> void:
	if team != null:
		team.roam.erase(beliefs.me)


## Where bot `me` stands in the ring of the bots about a held spot: a lone bot on it, the others
## spread by seat order `radius` metres out.
func _ring_offset(beliefs: BotBeliefs, radius: float) -> Vector3:
	var seats: Array[int] = []
	for id in beliefs.teammates:
		var mate: Dictionary = beliefs.teammates[id]
		if mate.get("bot", false) and not mate.get("dead", false):
			seats.append(id)
	seats.sort()
	var rank := seats.find(beliefs.me)
	if seats.size() < 2 or rank < 0:
		return Vector3.ZERO
	return Vector3(0.0, 0.0, -radius).rotated(Vector3.UP, TAU * float(rank) / float(seats.size()))


## Whether a person has a door pinged: the one errand a holding bot goes on, as a ping pulls it.
func _pinged_door(state: ClientState) -> bool:
	var board: Dictionary = state.frame.get("pings", {})
	for from: int in board:
		if board[from].get("kind", &"") == PingBoard.DOOR:
			return true
	return false


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
	var band_override := play.follow_band()
	var safe := band_override != Vector2.ZERO
	var now := beliefs.now
	var blocked := _spot != Vector3.INF and legs != null and legs.path.is_blocked(_spot, now)
	var due := (
		now - _planned_at >= REPLAN_EVERY
		or fighting != _was_fighting
		or safe != _was_safe
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
		_was_safe = safe
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
			_slot(beliefs),
			band_override
		)
	if _spot != Vector3.INF:
		intent.goal = _spot
		intent.goal_radius = 1.0
		var band := BotFollow.FIGHT_BAND if fighting else BotFollow.CALM_BAND
		if safe:
			band = band_override
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
	if intent.ordering_flare():
		return  # `BotRevive` swaps and reloads for the flare.
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


## Orders a grenade at a pack when the throw is safe, and watches an order given a moment ago:
## the bot stands still for it, and takes it back while the view still turns if a zombie comes
## within `THROW_ABORT_NEAR`. True while an order is in force.
func _throw(
	intent: BotIntent,
	beliefs: BotBeliefs,
	here: Vector3,
	targets: Array[Dictionary],
	threat: float,
	kind: BotStance.Kind
) -> bool:
	var now := beliefs.now
	if _order != null and now - _ordered_at < THROW_WATCH:
		if threat < THROW_ABORT_NEAR or not _grenadier.is_safe(_order.landing, here):
			intent.throw_abort = true
			_order = null
			return false
		return true
	_order = null
	if (
		not _profile.throws_grenades
		or beliefs.grenades <= 0
		or threat < BotGrenadier.NEAR_ZOMBIE
		or targets.is_empty()
	):
		return false
	# A walking bot slides a few decimetres before it stands to throw: plan from where it stops.
	var mine: Dictionary = beliefs.teammates.get(beliefs.me, {})
	var stop := BotGrenadier.stop_point(here, mine.get("velocity", Vector3.ZERO))
	var throw := _grenadier.plan(stop, targets, beliefs.grenades, now, kind == BotStance.Kind.LOW)
	if throw == null:
		return false
	intent.throw_style = throw.style
	intent.throw_yaw = throw.yaw
	intent.throw_pitch = throw.pitch
	_order = throw
	_ordered_at = now
	_grenadier.last_throw = now
	if team != null:
		team.add_blast(throw.landing, now + _grenadier.def.fuse + BotTeam.BLAST_SLACK, beliefs.me)
	intent.note = "throw"
	return true


## The errands of a lull (fuel, breakers, shopping, boards), when the level gave the bot a shop and
## nothing is near. A refusal the server told the bot about leaves the item alone for a while.
## A bot that holds a spot (`needs_only`) leaves it only for a person's ping and for what its
## needs allow (`BotNeeds`): rounds when its reserve is under a magazine.
func _errand(
	intent: BotIntent,
	beliefs: BotBeliefs,
	state: ClientState,
	threat: float,
	order: StringName,
	anchor: Vector3,
	needs_only: bool
) -> bool:
	if _errands == null:
		return false
	_errands.legs = legs
	_errands.order = order
	_errands.anchor = anchor
	# A Safe bot (`BotPlayState`) keeps its distance: only a person's ping and an empty gun move it.
	_errands.keeps_distance = not play.may_wander()
	for denial in beliefs.denials:
		_errands.back_off(denial["item"], beliefs.now)
	beliefs.denials.clear()
	if intent.target_id >= 0:
		return false
	# One bot at a time goes (the maintainer): the others wait for their turn, except to buy a link
	# the team holds for them (`BotErrands` link job).
	var may_go := (
		team == null or not team.one_errand_at_a_time or team.turn.may_go(beliefs.me, beliefs.now)
	)
	var went := _errands.run(intent, beliefs, state, threat, needs_only, may_go)
	if went and may_go and team != null and not _errands.linking:
		team.turn.took(beliefs.me, beliefs.now)
	return went


## The last zombies of a round are marked on every screen and a person walks to them; this bot goes
## to look for the nearest one it holds the claim on when it is free to (`BotHunt`). True when it
## set the goal.
func _hunt(
	intent: BotIntent,
	beliefs: BotBeliefs,
	here: Vector3,
	order: StringName,
	anchor: Vector3,
	dry: bool
) -> bool:
	var free := (
		_profile.follows
		and order != BotOrders.HOLD
		and not dry
		and intent.target_id < 0
		and play.may_wander()
	)
	var going := _hunter.run(
		intent,
		beliefs,
		here,
		free,
		order == BotOrders.FOLLOW,
		anchor,
		legs,
		team,
		_level,
		_profile.memory_seconds
	)
	if going:
		_roam.drop()
		_forget_roam(beliefs)
		_spot = Vector3.INF
	return going


## The supply dash of a bot with no round left (see `BotErrands.dash`).
func _dash(intent: BotIntent, beliefs: BotBeliefs, state: ClientState, threat: float) -> bool:
	if _errands == null:
		return false
	_errands.legs = legs
	_errands.order = _standing_order(beliefs)
	return _errands.dash(intent, beliefs, state, threat)


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
	dry: bool,
	order: StringName
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
	# Only a bot under `FOLLOW` is leashed to its people; a roaming one to where it stands.
	if order == BotOrders.ROAM:
		people = []
	if not BotCombat.leash_allows(target["position"], here, people, downed):
		return false
	intent.goal = target["position"]
	intent.goal_radius = CHASE_STOP
	intent.run = false
	return true


## The stampede: stand at a choke near the people (walls about it) and not run from the runners.
func _hold(intent: BotIntent, beliefs: BotBeliefs, here: Vector3, anchor: Vector3) -> void:
	var centre := anchor if anchor != Vector3.INF else here
	intent.note = "choke"
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
	if id == &"":
		return null
	var counts: Array = (me.get("arms", {}) as Dictionary).get(id, [])
	return WeaponCatalog.get_def_at(id, int(counts[2]) if counts.size() > 2 else 0)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
