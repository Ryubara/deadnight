class_name BotFightBrain
extends BotBrain
## The brain of phases 1 and 2: the fight and staying with the people (the errands, the revive and
## the rest come with the later phases). It shoots the nearest believed zombie in sight and keeps
## to it while it stays a fair choice, backs away from anything that gets inside the profile's
## margin (a heading chosen on the walking mesh, `BotSteering`), looks toward a blow it felt or a
## sound it heard, reloads when the magazine is dry or low in a quiet moment, swaps to a weapon
## that has rounds when its own is spent, and otherwise walks to a place near the people
## (`BotFollow`) and stands there.

## Metres a committed target may be farther than the nearest before the bot changes its mind.
const COMMITMENT := 3.0
## Metres from a zombie inside which a tactical reload waits.
const RELOAD_SAFE := 8.0
## Share of a magazine under which a quiet moment is used to reload.
const LOW_MAGAZINE := 0.3
## Ticks between two swaps.
const SWAP_EVERY := 20
## How much of the way to the people (or home) bends a retreat (so it circles the field, not a
## corner).
const HOME_BEND := 0.35
## Metres from the nearest dead within which the bot counts itself in a fight (the follow band is
## the closer one), and the seconds between two looks at where to stand.
const FIGHT_RANGE := 12.0
const REPLAN_EVERY := 0.8
## Metres the people may have moved before the place is chosen again.
const ANCHOR_MOVED := 3.0
## Metres beyond the follow band at which a bot hurries (runs) to catch up, if nothing is near.
const LAG := 0.5
const RUN_SAFE := 4.0

## The legs the bot walks on, set by the client: the brain asks them which places are blocked.
var legs: BotLegs

var _profile: BotProfile
var _level: BotLevel
var _follow: BotFollow
var _steering: BotSteering
var _spot := Vector3.INF
var _planned_at := -INF
var _planned_anchor := Vector3.INF
var _was_fighting := false
var _last_reflex := Vector3.ZERO
var _committed := -1
var _thinks := 0
var _swapped_at := -SWAP_EVERY


func _init(profile: BotProfile, level: BotLevel) -> void:
	_profile = profile
	_level = level
	_follow = BotFollow.new(level)
	_steering = BotSteering.new(level)


func think(beliefs: BotBeliefs, state: ClientState) -> BotIntent:
	_thinks += 1
	var intent := BotIntent.new()
	var me := state.me()
	if me.is_empty() or me.get("downed", true):
		return intent
	var here: Vector3 = me["pos"]
	var held := _held(me)
	var targets := beliefs.targets(here)
	intent.target_id = _choose(targets, here)
	_committed = intent.target_id
	var threat := beliefs.nearest_threat(here, _profile.memory_seconds)
	var people := _people(beliefs, state.player_id)
	var anchor := BotFollow.anchor_of(people)
	if threat < _profile.retreat_margin and (held == null or not held.is_melee()):
		intent.reflex = _retreat(here, beliefs, anchor)
		intent.run = true
		intent.note = "retreat"
		_last_reflex = intent.reflex
	else:
		_last_reflex = Vector3.ZERO
		_walk_to_people(intent, here, beliefs, people, anchor, threat)
	if intent.target_id < 0:
		intent.look_yaw = _glance(beliefs, here)
	_handle_weapon(intent, me, held, threat)
	if intent.note == "":
		intent.note = "fight" if intent.target_id >= 0 else "hold"
	return intent


## The target to shoot: the nearest in sight, kept once chosen unless another is clearly nearer.
func _choose(targets: Array[Dictionary], here: Vector3) -> int:
	var best := -1
	var best_score := INF
	for contact in targets:
		var score := (
			Vector2(contact["position"].x - here.x, contact["position"].z - here.z).length()
		)
		if contact["id"] == _committed:
			score -= COMMITMENT
		if score < best_score:
			best_score = score
			best = contact["id"]
	return best


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
	if due:
		_planned_at = now
		_planned_anchor = anchor
		_was_fighting = fighting
		var avoid := Callable()
		if legs != null:
			avoid = Callable(legs.path, &"is_blocked").bind(now)
		_spot = _follow.plan(
			here, people, _bot_places(beliefs), _threat_places(beliefs), fighting, _spot, avoid
		)
	if _spot != Vector3.INF:
		intent.goal = _spot
		intent.goal_radius = 1.0
		var band := BotFollow.FIGHT_BAND if fighting else BotFollow.CALM_BAND
		intent.run = _flat(here, anchor) > band.y + LAG and threat > RUN_SAFE
		intent.note = "follow"


func _bot_places(beliefs: BotBeliefs) -> Array[Vector3]:
	var places: Array[Vector3] = []
	for id in beliefs.teammates:
		var mate: Dictionary = beliefs.teammates[id]
		if mate.get("bot", false) and id != beliefs.me:
			places.append(mate["pos"])
	return places


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


func _handle_weapon(intent: BotIntent, me: Dictionary, held: WeaponDef, threat: float) -> void:
	if held == null:
		return
	var reloading: bool = me.get("reloading", false)
	var ammo: int = me.get("ammo", 0)
	var reserve: int = me.get("reserve", 0)
	if not held.is_melee() and not reloading and reserve > 0:
		var dry := ammo <= 0
		var low := float(ammo) < float(held.magazine_size) * LOW_MAGAZINE
		intent.reload = dry or (low and threat > RELOAD_SAFE)
	if _thinks - _swapped_at >= SWAP_EVERY and _wants_swap(me, held):
		intent.swap = true
		_swapped_at = _thinks


## Swap away from a melee weapon or an empty gun to one that has rounds; from an empty gun to the
## melee weapon when nothing else can shoot.
func _wants_swap(me: Dictionary, held: WeaponDef) -> bool:
	var arms: Dictionary = me.get("arms", {})
	if arms.size() < 2:
		return false
	if not held.is_melee() and _rounds(arms, held.id) > 0:
		return false
	var other_has_rounds := false
	for id: StringName in arms:
		if id != held.id and not WeaponCatalog.get_def(id).is_melee() and _rounds(arms, id) > 0:
			other_has_rounds = true
	return other_has_rounds if held.is_melee() else true


static func _rounds(arms: Dictionary, weapon_id: StringName) -> int:
	var counts: Array = arms.get(weapon_id, [0, 0])
	return int(counts[0]) + int(counts[1])


static func _held(me: Dictionary) -> WeaponDef:
	var id: StringName = me.get("weapon", &"")
	return WeaponCatalog.get_def(id) if id != &"" else null


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
