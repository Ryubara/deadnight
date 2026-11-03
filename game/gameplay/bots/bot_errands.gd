class_name BotErrands
extends RefCounted
## The errands of a bot in a lull: look after the generator (a fuel can when the tank runs low, the
## breakers for the areas people are in), spend points (`BotEconomy`), and put boards back across a
## breach in a break. It is the one place that knows a person's claim on a door, the bots' turns and
## the back-off after a refused buy; the economy only ranks what to buy.
##
## What it never does: go while a zombie is near (`CLEAR_FROM`), buy a door while a teammate is
## down or hurt, buy a door a person holding the price stands at before the grace has passed,
## buy what the rules refused for `BACK_OFF` seconds, put boards where a person is working, or
## let two bots do the same team job at once: a job has one bot whose turn it is (the nearest that
## can do it), and the turn moves on to the next every `TURN_SECONDS` the job stays undone
## (`docs/research/bots.md#economy`).
##
## A need of the bot's own (rounds, `BotNeeds`) is let through only as the standing order allows: a
## roaming bot goes freely, one that follows goes when the stand is near the person (or its gun is
## empty), one that holds goes when its reserve is under a magazine. A bot held back says so once
## (`NEED_HELD_BACK`). The rule is the table of `BotNeeds`, not a branch here.
##
## It reads the frame the bot is shown (the players, their points, the prompt, the circuits, the
## tank, the boards, the doors, the pings) and the shop it was given; nothing of the rules.

## What `_shopping` may pick: anything on the list, only the rounds a person marked, or only what a
## bot that holds a spot may leave for (the marked rounds and its own need for rounds).
enum Scope { ALL, MARKED, NEEDS }

## The frame's `phase` for a break and for a round (a bot names no rules class; a test holds these
## to the rules' phase enum).
const BREAK_PHASE := 1
const ACTIVE_PHASE := 2
## Metres to the nearest dead inside which no errand is begun or kept.
const CLEAR_FROM := 12.0
## Seconds a refused item is left alone.
const BACK_OFF := 30.0
## Seconds a bot that holds a door's price waits for a person at the door who holds it too.
const CLAIM_GRACE := 20.0
## Seconds a bot waits for the person who pinged a door to buy it themselves.
const PING_DEFER := 10.0
## Metres from a door within which a person holding the price has the first claim.
const CLAIM_RADIUS := 15.0
## Health share under which a teammate is in trouble (no door is bought while one is).
const HURT_SHARE := 0.5
## Fraction of the tank above the low line at which fuel buying stops.
const FILL_MARGIN := 0.15
## Seconds a job waits for the bot whose turn it is before the next bot's turn comes.
const TURN_SECONDS := 40.0
## Metres from a breach within which a person has the boards, and a zombie ends a repair.
const PERSON_AT_BREACH := 10.0
## Metres from a lamp (past its reach) within which a person counts as in the circuit's area, and
## the seconds an area stays empty before its circuit goes off.
const AREA_MARGIN := 3.0
const AREA_EMPTY := 15.0
## Metres from a stand at which a bot counts itself arrived, for a stand in the open and a door (a
## door's stand is 1.5 m from the slab and a hand reaches 3.2 m, so it must come closer than 1.7).
const ARRIVE := 1.0
const ARRIVE_DOOR := 0.8
## Seconds at a stand with nothing to press before the item is left alone for a while, and the
## longest an errand may take.
const AT_STAND_PATIENCE := 3.0
const ERRAND_LIMIT := 60.0
## Seconds a stand the legs found no way to is left alone (a new door, which changes the mesh,
## clears the list).
const UNREACHABLE_BACK_OFF := 180.0
## Seconds without a sight or a sound of the dead that make a lull in a round.
const LULL_SECONDS := 10.0
## The share of a round's dead that, once only this many are left, makes a lull to go shopping in.
const CALM_SHARE := 0.25
## Seconds between two looks at what to buy.
const PLAN_EVERY := 0.5
## Seconds between two swaps asked for at a locker.
const SWAP_GAP := 1.0
## Seconds a walk to a stand is remembered, before the legs are asked again.
const WALK_KEEP := 3.0
## The moment a bot held back from a need puts in its beliefs (the callouts say it).
const NEED_HELD_BACK := &"need_held_back"

## The legs the bot walks on (set by the brain): their word that a stand cannot be reached.
var legs: BotLegs
## The standing order of the bot (`BotOrders`) and the place its people are at (the person it
## follows, or the spot it holds; `Vector3.INF` for none): set by the brain each think, read by the
## table of needs.
var order: StringName = BotOrders.ROAM
var anchor := Vector3.INF
## What the bot decided last, for the ring buffer, and how many of each kind it began.
var note := ""
var counts: Dictionary = {}
## The longest the bot has held more than twice the price of the next thing on its list (seconds).
var longest_glut := 0.0
## Seconds in each round (by round number) the bot held more than twice that price.
var glut_by_round: Dictionary = {}

var _shop: BotShop
var _profile: BotProfile
var _economy: BotEconomy
## Item id (or a job's key) to the clock when it may be tried again.
var _denied: Dictionary = {}
## Door id to the clock when the bot first held its price; ping to when it was first seen.
var _held_since: Dictionary = {}
var _ping_seen: Dictionary = {}
## The marked locker a bot set out for, kept until `_ammo_until` when the mark runs out on the way.
var _ammo_kept := Vector3.INF
var _ammo_until := -INF
## A job's key to the clock when it first waited, for the rotation of turns.
var _waiting_since: Dictionary = {}
## Circuit id to the clock when its area was first found empty.
var _empty_since: Dictionary = {}
var _fuelling := false
var _last_item: StringName = &""
var _begun := 0.0
var _clock := 0.0
## A stand's key to the clock until which the bot leaves it alone (it found no way there).
var _unreachable: Dictionary = {}
var _door_count := -1
## A stand's key to `{length, until}`: the metres of walk to it, asked of the legs.
var _walks: Dictionary = {}
var _walk_mesh := -1
## The ammunition stand the bot is walking to for rounds of its own, and whether the callout for a
## need it was held back from has been given since it last was free.
var _heading := Vector3.INF
var _announced := false
## A stand's key to whether a walk reaches it on the mesh as it is (asked once for each new mesh).
var _probed: Dictionary = {}
var _mesh := -1
var _here := Vector3.ZERO
var _round := -1
var _seen_at := -INF
var _round_at := 0.0
var _lull_round := -1
var _lull := false
var _peak := 0
var _committed: StringName = &""
var _committed_until := -INF
var _found: Array[BotEconomy.Buy] = []
var _planned_at := -INF
var _next_price := 0
var _glut_since := -1.0
var _arrived_at := -1.0
var _post_arrived := -1.0
var _swap_at := -INF


func _init(shop: BotShop, profile: BotProfile) -> void:
	_shop = shop
	_profile = profile
	_economy = BotEconomy.new(shop, profile)


## The items the last look found the bot wants and can pay for, and the price of the next thing on
## its list (for the metrics).
func wants_now() -> Dictionary:
	var items: Array[String] = []
	for buy in _found:
		items.append("%s(%s)" % [buy.item, buy.why])
	return {"found": items, "next_price": _next_price}


## The economy's chooser (for the metrics).
func economy() -> BotEconomy:
	return _economy


## Leaves the item alone for `BACK_OFF` seconds (a refused purchase).
func back_off(item_id: StringName, now: float) -> void:
	_denied[item_id] = now + BACK_OFF
	_planned_at = -INF
	counts["refused"] = int(counts.get("refused", 0)) + 1


## Sets the intent for an errand and returns true, or returns false when the bot has none (or is
## in a fight). `threat` is the metres to the nearest dead it knows of. With `needs_only` (a bot
## that holds a spot) only what a person's ping names and the bot's own need for rounds are looked
## at: the rest of the errands wait for an order that lets the bot go.
func run(
	intent: BotIntent, beliefs: BotBeliefs, state: ClientState, threat: float, needs_only := false
) -> bool:
	var me := state.me()
	if me.is_empty() or me.get("downed", false) or not state.has_frame():
		return false
	var now := beliefs.now
	var frame := state.frame
	_clock = now
	_here = me["pos"]
	_watch(frame, threat, now)
	var doors: int = frame.get("doors", []).size()
	if doors != _door_count:
		_door_count = doors
		_unreachable.clear()
		_planned_at = -INF
	if now - _planned_at >= PLAN_EVERY or beliefs.purchased_at > _planned_at:
		_plan(beliefs, state, me, frame)
	if threat < CLEAR_FROM:
		_last_item = &""
		_heading = Vector3.INF
		_arrived_at = -1.0
		return false
	var crane := _crane_wait(intent, me, frame, state.player_id)
	if crane:
		return true
	var jobs: Array[StringName] = [&"marked", &"fuel", &"circuits", &"shopping", &"repairs"]
	if needs_only:
		jobs = [&"marked", &"needs"]
	for job in jobs:
		var took := false
		match job:
			&"marked":
				took = _shopping(intent, beliefs, state, me, frame, Scope.MARKED)
			&"needs":
				took = _shopping(intent, beliefs, state, me, frame, Scope.NEEDS)
			&"fuel":
				took = _fuel(intent, beliefs, state, me, frame)
			&"circuits":
				took = _circuits(intent, beliefs, state, me, frame)
			&"shopping":
				took = _shopping(intent, beliefs, state, me, frame, Scope.ALL)
			&"repairs":
				took = _repairs(intent, beliefs, state, me, frame)
		if took:
			counts[job] = int(counts.get(job, 0)) + 1
			return true
	_last_item = &""
	_heading = Vector3.INF
	_arrived_at = -1.0
	_post_arrived = -1.0
	note = ""
	_forget_old(now)
	return false


# --- The crane ---


## The bot's own crane play is running: it stays at the glass and takes the prize when it is held
## out (a prize it would not take is left to fade).
func _crane_wait(intent: BotIntent, me: Dictionary, frame: Dictionary, me_id: int) -> bool:
	var crane: Dictionary = frame.get("crane", {})
	if crane.get("buyer", -1) != me_id:
		return false
	var stage: int = crane.get("stage", CraneState.Stage.READY)
	if stage != CraneState.Stage.SPIN and stage != CraneState.Stage.GRAB:
		return false
	var prompt: Dictionary = me.get("prompt", {})
	intent.note = "crane"
	intent.keep_weapon = true
	if prompt.get("kind", &"") == &"crane_take":
		var view := BotEconomy.View.new()
		view.arms = me.get("arms", {})
		view.held = me.get("weapon", &"")
		if BotEconomy.worth_taking(view, WeaponCatalog.catalog_id(prompt.get("weapon", &""))):
			intent.use = true
	return true


# --- Money ---


func _shopping(
	intent: BotIntent,
	beliefs: BotBeliefs,
	state: ClientState,
	me: Dictionary,
	frame: Dictionary,
	scope: Scope
) -> bool:
	var now := beliefs.now
	var pick: BotEconomy.Buy = null
	var held_back := false
	for buy in _found:
		if scope == Scope.MARKED and buy.why != BotEconomy.AMMO_PING:
			continue
		if scope == Scope.NEEDS and buy.why != BotEconomy.AMMO_PING and not _is_ammo_need(buy):
			continue
		if _is_ammo_need(buy):
			var verdict := _verdict(buy, me)
			held_back = held_back or verdict == BotNeeds.Verdict.STAY_AND_SAY
			if verdict != BotNeeds.Verdict.GO:
				continue
		if _team_turn(buy, beliefs, frame, state.player_id):
			if buy.item == _last_item:
				pick = buy
				break
			if pick == null:
				pick = buy
	if scope != Scope.MARKED:
		_announce(beliefs, held_back)
	if pick == null:
		return false
	if pick.item != _last_item:
		_last_item = pick.item
		_begun = now
		_arrived_at = -1.0
	if pick.why == BotEconomy.PING:
		_committed = pick.item
		_committed_until = now + ERRAND_LIMIT
	if pick.why == BotEconomy.AMMO_PING:
		_ammo_kept = pick.stand
		_ammo_until = now + ERRAND_LIMIT
	_heading = pick.stand if pick.prompt == &"ammo" else Vector3.INF
	note = "buy %s (%s)" % [pick.item, pick.why]
	return _carry_out(intent, pick, me, now)


## Whether `buy` is rounds the bot wants for itself: not a person's ping (which sits above the
## orders) but a need or a top-off. A top-off of a gun the bot is short of is that gun's need.
func _is_ammo_need(buy: BotEconomy.Buy) -> bool:
	return buy.prompt == &"ammo" and buy.why != BotEconomy.AMMO_PING


## What the table of needs says about this purchase of rounds under the standing order. A trip
## begun is given a little more leash.
func _verdict(buy: BotEconomy.Buy, me: Dictionary) -> BotNeeds.Verdict:
	var level := BotNeeds.ammo_level(me.get("arms", {}), _profile.ammo_floor_mags)
	var slack := BotNeeds.UNDERWAY_SLACK if _flat(_heading, buy.stand) < 1.0 else 0.0
	var near := BotNeeds.is_near(buy.stand, _here, anchor, slack)
	return BotNeeds.verdict(BotNeeds.Need.AMMO, order, level, near)


## A bot held back from its need says so once, and again only after it has been free of the hold.
func _announce(beliefs: BotBeliefs, held_back: bool) -> void:
	if held_back and not _announced:
		beliefs.moments.append({"kind": NEED_HELD_BACK})
		counts["held_back"] = int(counts.get("held_back", 0)) + 1
	_announced = held_back


## Looks at the shop again: what the bot would buy now, and how long it has held more than twice
## the next thing on its list.
func _plan(beliefs: BotBeliefs, state: ClientState, me: Dictionary, frame: Dictionary) -> void:
	var now := beliefs.now
	var view := _view(beliefs, state, me, frame)
	_found = _economy.candidates(view)
	_next_price = _economy.last_next
	_planned_at = now
	if _next_price > 0 and view.points > BotEconomy.GLUT * _next_price:
		if _glut_since < 0.0:
			_glut_since = now
		longest_glut = maxf(longest_glut, now - _glut_since)
		var round_number := int(frame.get("round", 1))
		glut_by_round[round_number] = float(glut_by_round.get(round_number, 0.0)) + PLAN_EVERY
	else:
		_glut_since = -1.0


## Walks to where `pick` is sold and presses use when the prompt there sells it. An errand that
## takes too long, or a stand with no prompt for it, leaves the item alone for a while.
func _carry_out(intent: BotIntent, pick: BotEconomy.Buy, me: Dictionary, now: float) -> bool:
	var prompt: Dictionary = me.get("prompt", {})
	var here: Vector3 = me["pos"]
	if _sells(prompt, pick) and _at_marked(pick, here):
		var wrong := _hands_wrong(pick, prompt, me)
		intent.keep_weapon = wrong or pick.prompt in [&"ammo", &"weapon", &"crane"]
		if not wrong:
			intent.use = true
		elif now - _swap_at >= SWAP_GAP:
			intent.swap = true
			_swap_at = now
		intent.note = note
		_arrived_at = now
		return true
	if now - _begun > ERRAND_LIMIT:
		back_off(pick.item, now)
		return false
	var radius := ARRIVE_DOOR if pick.prompt == &"door" else ARRIVE
	if _flat(here, pick.stand) <= radius + 0.5:
		if _arrived_at < 0.0:
			_arrived_at = now
		intent.keep_weapon = pick.prompt == &"ammo"
		if _wants_swap(pick, me) and now - _swap_at >= SWAP_GAP:
			intent.swap = true
			_swap_at = now
		elif now - _arrived_at > AT_STAND_PATIENCE:
			back_off(pick.item, now)
			return false
		intent.note = note
		return true
	if _cannot_reach(pick.stand, now):
		return false
	intent.goal = pick.stand
	intent.goal_radius = radius
	intent.run = false
	intent.note = note
	return true


## Whether the bot is where `pick` is to be bought when a person marked the place: any locker sells
## the same rounds, but a mark is an order for that one, so a bot at another locker walks on.
func _at_marked(pick: BotEconomy.Buy, here: Vector3) -> bool:
	return pick.why != BotEconomy.AMMO_PING or _flat(here, pick.stand) <= _shop.use_reach


## Notes a stand the legs found no way to, so the plan looks elsewhere. True when it is one.
func _cannot_reach(stand: Vector3, now: float) -> bool:
	if legs != null and legs.path.is_blocked(stand, now):
		_unreachable[_key(stand)] = now + UNREACHABLE_BACK_OFF
		_planned_at = -INF
		_last_item = &""
		return true
	return false


func _avoided(stand: Vector3) -> bool:
	var key := _key(stand)
	if _unreachable.get(key, -INF) > _clock:
		return true
	if legs == null:
		return false
	if legs.path.iteration() != _mesh:
		_mesh = legs.path.iteration()
		_probed.clear()
	if not _probed.has(key):
		_probed[key] = legs.path.probe(_here, stand, _clock)
	return not _probed[key]


## The metres of walk to `stand` (`INF` for none), asked of the legs and kept for `WALK_KEEP`
## seconds; the answers go with the mesh.
func _walk_to(stand: Vector3) -> float:
	if legs.path.iteration() != _walk_mesh:
		_walk_mesh = legs.path.iteration()
		_walks.clear()
	var key := _key(stand)
	var kept: Dictionary = _walks.get(key, {})
	if kept.is_empty() or float(kept["until"]) <= _clock:
		kept = {"length": legs.path.walk_length(_here, stand, _clock), "until": _clock + WALK_KEEP}
		_walks[key] = kept
	return float(kept["length"])


static func _key(stand: Vector3) -> Vector2i:
	return Vector2i(roundi(stand.x * 2.0), roundi(stand.z * 2.0))


## Whether the prompt shown is the sale of `pick` and the bot can pay.
func _sells(prompt: Dictionary, pick: BotEconomy.Buy) -> bool:
	if _denied.get(pick.item, -INF) > _clock:
		return false
	if prompt.get("kind", &"") != pick.prompt:
		return false
	if prompt.get("id", &"") != pick.item:
		return false
	return true


## Whether buying `pick` would give up a weapon other than the weakest one carried (full hands give
## up the one in hand), so the bot should put the weakest in hand first.
func _hands_wrong(pick: BotEconomy.Buy, prompt: Dictionary, me: Dictionary) -> bool:
	if pick.prompt != &"weapon" and pick.prompt != &"crane":
		return false
	var arms: Dictionary = me.get("arms", {})
	if arms.size() < WeaponCatalog.CARRY_LIMIT:
		return false
	var held: StringName = me.get("weapon", &"")
	var replaced: StringName = prompt.get("replaces", held)
	return replaced != &"" and replaced != BotEconomy.weakest_of(arms)


## At a locker with a blade in hand and the gun to feed in the pack: the rounds are sold for the
## weapon in hand, so put the blade away.
func _wants_swap(pick: BotEconomy.Buy, me: Dictionary) -> bool:
	if pick.prompt != &"ammo" or pick.weapon == me.get("weapon", &""):
		return false
	return me.get("arms", {}).has(pick.weapon)


## The dead left at or under which a round has a lull: five, or a quarter of the most the bot has
## seen in this round.
func calm_at(frame: Dictionary) -> int:
	var round_number := int(frame.get("round", 1))
	var remaining := int(frame.get("remaining", 0))
	if round_number != _round or remaining > _peak:
		_peak = remaining if round_number != _round else maxi(_peak, remaining)
		_round = round_number
	return maxi(BotEconomy.CALM_REMAINING, ceili(float(_peak) * CALM_SHARE))


## Whether the frame shows a break or a lull in a round.
func _calm(frame: Dictionary) -> bool:
	return (
		frame.get("phase", ACTIVE_PHASE) == BREAK_PHASE
		or _lull
		or int(frame.get("remaining", 0)) <= calm_at(frame)
	)


## Notes when the bot last saw or heard a zombie, and whether a round has gone quiet for it: nothing
## seen or heard for `LULL_SECONDS` since the round began.
func _watch(frame: Dictionary, threat: float, now: float) -> void:
	var round_number := int(frame.get("round", 1))
	if round_number != _lull_round:
		_lull_round = round_number
		_round_at = now
	if threat < INF:
		_seen_at = now
	_lull = now - maxf(_seen_at, _round_at) >= LULL_SECONDS


func _view(
	beliefs: BotBeliefs, state: ClientState, me: Dictionary, frame: Dictionary
) -> BotEconomy.View:
	var view := BotEconomy.View.new()
	var now := beliefs.now
	view.points = state.points()
	view.round_number = int(frame.get("round", 1))
	view.in_break = frame.get("phase", ACTIVE_PHASE) == BREAK_PHASE
	view.remaining = int(frame.get("remaining", 0))
	view.calm_at = calm_at(frame)
	view.lull = _lull
	view.here = me["pos"]
	view.arms = me.get("arms", {})
	view.held = me.get("weapon", &"")
	view.grenades = beliefs.grenades
	view.doors_open = frame.get("doors", [])
	view.bought = state.bought
	var crane: Dictionary = frame.get("crane", {})
	view.crane_spot = int(crane.get("spot", 0))
	view.crane_ready = int(crane.get("stage", CraneState.Stage.READY)) == CraneState.Stage.READY
	view.denied = _denied
	view.now = now
	view.avoid = Callable(self, &"_avoided")
	if legs != null:
		view.walk = Callable(self, &"_walk_to")
	view.heading = _heading
	_etiquette(view, beliefs, frame, state.player_id)
	return view


## The door manners: which doors the bot holds back from, and which a person asked it to buy.
func _etiquette(view: BotEconomy.View, beliefs: BotBeliefs, frame: Dictionary, me_id: int) -> void:
	var now := beliefs.now
	var players: Dictionary = frame.get("players", {})
	var trouble := false
	for id: int in players:
		var player: Dictionary = players[id]
		if id == me_id or player.get("dead", false):
			continue
		if player.get("downed", false) or float(player.get("health", 100.0)) < 100.0 * HURT_SHARE:
			trouble = true
	for door_id in _shop.unlocked_doors(view.doors_open):
		var price := _shop.economy.item(door_id).price_at(view.round_number)
		if view.points >= price:
			if not _held_since.has(door_id):
				_held_since[door_id] = now
		else:
			_held_since.erase(door_id)
		if trouble:
			view.blocked[door_id] = true
			continue
		var stand := BotEconomy.nearest_to(_shop.door_stands.get(door_id, []), view.here)
		var held_for: float = now - float(_held_since.get(door_id, now))
		var claimed := false
		for id: int in players:
			if id == me_id or beliefs.teammates.get(id, {}).get("bot", false):
				continue
			var person: Dictionary = players[id]
			if person.get("dead", false) or person.get("downed", false):
				continue
			if (
				int(person.get("points", 0)) >= price
				and _flat(person["pos"], stand) <= CLAIM_RADIUS
			):
				claimed = true
		if claimed and held_for < CLAIM_GRACE:
			view.blocked[door_id] = true
	_pings(view, beliefs, frame, me_id)
	_ammo_mark(view, beliefs, frame)


## The locker a person marked for rounds. A bot that set out for it keeps going when the mark runs
## out on the way (for at most `ERRAND_LIMIT`).
func _ammo_mark(view: BotEconomy.View, beliefs: BotBeliefs, frame: Dictionary) -> void:
	view.ammo_marked = BotPings.ammo(BotPings.marks(frame, beliefs.teammates))
	if not view.ammo_marked.is_finite() and beliefs.now < _ammo_until:
		view.ammo_marked = _ammo_kept


## A person's ping on a door asks the bot to buy it. The person gets `PING_DEFER` seconds to buy it
## themselves when they can pay.
func _pings(view: BotEconomy.View, beliefs: BotBeliefs, frame: Dictionary, me_id: int) -> void:
	var now := beliefs.now
	var players: Dictionary = frame.get("players", {})
	var seen: Array[StringName] = []
	var marks: Dictionary = frame.get("pings", {})
	for id: int in marks:
		var mark: Dictionary = marks[id]
		if id == me_id or mark.get("kind", &"") != &"door":
			continue
		if beliefs.teammates.get(id, {}).get("bot", false):
			continue
		var door_id: StringName = StringName(str(mark.get("subject", "")))
		if not _shop.doors.has(door_id):
			continue
		seen.append(door_id)
		if not _ping_seen.has(door_id):
			_ping_seen[door_id] = now
		var item := _shop.economy.item(door_id)
		var pinger: Dictionary = players.get(id, {})
		var able := int(pinger.get("points", 0)) >= item.price_at(view.round_number)
		if able and now - float(_ping_seen[door_id]) < PING_DEFER:
			view.blocked[door_id] = true
		view.pinged = door_id
	for door_id in _ping_seen.keys():
		if not seen.has(door_id):
			_ping_seen.erase(door_id)
	# A bot that set out for a pinged door keeps going when the ping runs out on the way.
	if view.pinged == &"" and _committed != &"" and now < _committed_until:
		if not view.doors_open.has(_committed):
			view.pinged = _committed


## Whether it is this bot's turn to do the job `buy` stands for: a door, which any bot may buy, goes
## to the nearest bot that can pay; anything else is the bot's own business.
func _team_turn(buy: BotEconomy.Buy, beliefs: BotBeliefs, frame: Dictionary, me_id: int) -> bool:
	if buy.prompt != &"door":
		return true
	return _turn("door:%s" % buy.item, buy.stand, beliefs, frame, me_id, buy.price)


# --- The generator ---


func _fuel(
	intent: BotIntent, beliefs: BotBeliefs, state: ClientState, me: Dictionary, frame: Dictionary
) -> bool:
	var price := _can_price(beliefs, state, frame)
	var stand := _nearest_open_fuel(me["pos"], frame) if price > 0 else Vector3.INF
	if stand == Vector3.INF or not _turn("fuel", stand, beliefs, frame, state.player_id, price):
		return false
	var prompt: Dictionary = me.get("prompt", {})
	note = "fuel"
	intent.note = note
	if prompt.get("kind", &"") == &"fuel":
		intent.use = float(prompt.get("units", 0.0)) > 0.0
		return true
	if _cannot_reach(stand, beliefs.now):
		return false
	intent.goal = stand
	intent.goal_radius = ARRIVE
	return true


## What a can costs when the bot wants one now (the tank is at the low line, or it is filling up
## from there) and can pay for it; 0 for no.
func _can_price(beliefs: BotBeliefs, state: ClientState, frame: Dictionary) -> int:
	var price := 0
	if _shop.fuel_item != null and not _shop.fuel_stands.is_empty():
		var capacity := _shop.fuel.capacity
		var fraction := float(frame.get("fuel", capacity)) / capacity
		var low := _shop.fuel.low_fraction
		if fraction <= low:
			_fuelling = true
		elif fraction > low + FILL_MARGIN:
			_fuelling = false
		if _fuelling and _denied.get(_shop.fuel_item.id, -INF) <= beliefs.now:
			var space := capacity - float(frame.get("fuel", capacity))
			price = _shop.fuel_item.fuel_offer(int(frame.get("round", 1)), space)["price"]
	if price <= 0 or state.points() < price:
		_waiting_since.erase("fuel")
		return 0
	return price


func _nearest_open_fuel(here: Vector3, frame: Dictionary) -> Vector3:
	var best := Vector3.INF
	var best_apart := INF
	for id in _shop.fuel_stands:
		var door: StringName = _shop.fuel_doors.get(id, &"")
		if door != &"" and not frame.get("doors", []).has(door):
			continue
		if _avoided(_shop.fuel_stands[id]):
			continue
		var apart := _flat(here, _shop.fuel_stands[id])
		if apart < best_apart:
			best_apart = apart
			best = _shop.fuel_stands[id]
	return best


## Keeps the field's circuit on, and the circuit of an area on while people are in it and the tank
## is over the line; throws it off when everyone has left (for `AREA_EMPTY` seconds) or the tank
## runs low. The bot nearest to the breaker does it.
func _circuits(
	intent: BotIntent, beliefs: BotBeliefs, state: ClientState, me: Dictionary, frame: Dictionary
) -> bool:
	var circuits: Dictionary = frame.get("circuits", {})
	var prompt: Dictionary = me.get("prompt", {})
	var now := beliefs.now
	var best_id: StringName = &""
	var best_apart := INF
	for circuit_id: StringName in _shop.circuit_stands:
		var on_now: bool = circuits.get(circuit_id, false)
		var want := _wants_circuit(circuit_id, on_now, beliefs, frame, state.player_id)
		if want == on_now or _denied.get("circuit:%s" % circuit_id, -INF) > now:
			_waiting_since.erase("circuit:%s" % circuit_id)
			continue
		var stand := _shop.circuit_stands[circuit_id]
		if _avoided(stand):
			continue
		if not _turn("circuit:%s" % circuit_id, stand, beliefs, frame, state.player_id, 0):
			continue
		var apart := _flat(me["pos"], stand)
		if apart < best_apart:
			best_apart = apart
			best_id = circuit_id
	if best_id == &"":
		return false
	note = "breaker %s" % best_id
	if prompt.get("kind", &"") == &"circuit" and prompt.get("id", &"") == best_id:
		intent.use = true
		intent.note = note
		return true
	if best_apart <= ARRIVE + 0.5:
		# At the post but the prompt names another (a door or a spot is nearer): give it a moment.
		if _post_arrived < 0.0:
			_post_arrived = now
		if now - _post_arrived > AT_STAND_PATIENCE:
			_denied["circuit:%s" % best_id] = now + BACK_OFF
			_post_arrived = -1.0
			return false
		return true
	if _cannot_reach(_shop.circuit_stands[best_id], now):
		return false
	intent.goal = _shop.circuit_stands[best_id]
	intent.goal_radius = ARRIVE
	intent.note = note
	return true


## Whether the bot wants `circuit_id` on. The field's stays on; an area's is on while a person is in
## it and the tank has fuel above the line (a higher line to light it again than to keep it).
func _wants_circuit(
	circuit_id: StringName, on_now: bool, beliefs: BotBeliefs, frame: Dictionary, me_id: int
) -> bool:
	var door: StringName = _shop.circuit_doors.get(circuit_id, &"")
	var capacity := _shop.fuel.capacity
	var fraction := float(frame.get("fuel", capacity)) / capacity
	if door == &"":
		return fraction > 0.0 or on_now
	if not frame.get("doors", []).has(door):
		return false
	var line := _shop.fuel.low_fraction + (0.0 if on_now else FILL_MARGIN)
	if fraction < line:
		return false
	if _people_in_area(circuit_id, frame, beliefs, me_id):
		_empty_since.erase(circuit_id)
		return true
	if not on_now:
		return false
	if not _empty_since.has(circuit_id):
		_empty_since[circuit_id] = beliefs.now
	return beliefs.now - float(_empty_since[circuit_id]) < AREA_EMPTY


## Whether a person (a bot, when no person is up) is within a lamp's reach of the circuit.
func _people_in_area(
	circuit_id: StringName, frame: Dictionary, beliefs: BotBeliefs, me_id: int
) -> bool:
	var players: Dictionary = frame.get("players", {})
	var humans: Array[Vector3] = []
	var bots: Array[Vector3] = []
	for id: int in players:
		var player: Dictionary = players[id]
		if player.get("dead", false) or player.get("downed", false):
			continue
		var is_bot: bool = id == me_id or beliefs.teammates.get(id, {}).get("bot", false)
		(bots if is_bot else humans).append(player["pos"])
	var people := humans if not humans.is_empty() else bots
	var reach := _shop.lamp_reach + AREA_MARGIN
	for at in people:
		for lamp: Vector3 in _shop.circuit_lamps.get(circuit_id, []):
			if _flat(at, lamp) <= reach:
				return true
	return false


# --- Boards ---


func _repairs(
	intent: BotIntent, beliefs: BotBeliefs, state: ClientState, me: Dictionary, frame: Dictionary
) -> bool:
	if not _calm(frame):
		return false
	var boards: Dictionary = frame.get("barricades", {})
	var players: Dictionary = frame.get("players", {})
	var here: Vector3 = me["pos"]
	var best_id: StringName = &""
	var best_apart := INF
	for id: StringName in _shop.repair_stands:
		if int(boards.get(id, _shop.boards)) >= _shop.boards:
			_waiting_since.erase("repair:%s" % id)
			continue
		var centre := _shop.repair_centres[id]
		if _person_near(players, beliefs, state.player_id, centre, PERSON_AT_BREACH):
			continue
		if _zombie_near(beliefs, centre, PERSON_AT_BREACH):
			continue
		var stand := _shop.repair_stands[id]
		if _avoided(stand):
			continue
		if not _turn("repair:%s" % id, stand, beliefs, frame, state.player_id, 0):
			continue
		var apart := _flat(here, stand)
		if apart < best_apart:
			best_apart = apart
			best_id = id
	if best_id == &"":
		return false
	note = "boards %s" % best_id
	var prompt: Dictionary = me.get("prompt", {})
	if prompt.get("kind", &"") == &"repair" and prompt.get("id", &"") == best_id:
		intent.use = true
		intent.use_held = true
		intent.note = note
		return true
	if _cannot_reach(_shop.repair_stands[best_id], beliefs.now):
		return false
	intent.goal = _shop.repair_stands[best_id]
	intent.goal_radius = ARRIVE
	intent.note = note
	return true


## Whether a person (not a bot) other than the bot is within `reach` metres of `at`.
func _person_near(
	players: Dictionary, beliefs: BotBeliefs, me_id: int, at: Vector3, reach: float
) -> bool:
	for id: int in players:
		if id == me_id or beliefs.teammates.get(id, {}).get("bot", false):
			continue
		var player: Dictionary = players[id]
		if player.get("dead", false) or player.get("downed", false):
			continue
		if _flat(player["pos"], at) <= reach:
			return true
	return false


## Whether the bot believes in a zombie within `reach` metres of `at`.
func _zombie_near(beliefs: BotBeliefs, at: Vector3, reach: float) -> bool:
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if beliefs.is_believed(contact):
			if _flat(beliefs.guess(contact, _profile.memory_seconds), at) <= reach:
				return true
	return false


# --- Turns ---


## Whether it is this bot's turn at the job `key`: of the bots that are up and (for a job with a
## price) can pay it, the nearest to `at` goes first, and the next takes over for each
## `TURN_SECONDS` the job has waited. A team of one bot is always its own turn.
func _turn(
	key: String, at: Vector3, beliefs: BotBeliefs, frame: Dictionary, me_id: int, price: int
) -> bool:
	if not _waiting_since.has(key):
		_waiting_since[key] = beliefs.now
	var players: Dictionary = frame.get("players", {})
	var ranked: Array[Vector2] = []
	for id: int in players:
		var player: Dictionary = players[id]
		var is_bot: bool = id == me_id or beliefs.teammates.get(id, {}).get("bot", false)
		if not is_bot or player.get("dead", false) or player.get("downed", false):
			continue
		if int(player.get("points", 0)) < price:
			continue
		ranked.append(Vector2(_flat(player["pos"], at), float(id)))
	if ranked.size() <= 1:
		return true
	ranked.sort()
	var waited := beliefs.now - float(_waiting_since[key])
	var index := int(waited / TURN_SECONDS) % ranked.size()
	return int(ranked[index].y) == me_id


func _forget_old(now: float) -> void:
	for key in _denied.keys():
		if _denied[key] < now - 1.0:
			_denied.erase(key)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
